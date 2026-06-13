---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/anchor_runner_supervisor.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.264857+00:00
---

# runtime/semantos-brain/src/anchor_runner_supervisor.zig

```zig
// AnchorRunnerSupervisor — long-lived child-process supervisor for
// the `anchor-runner.ts` daemon.
//
// Background: the simple-anchor pipeline ships
// (AnchorEmitter.emitBsv → broker.publish("cell.created") →
// AnchorQueueWriter → JSONL queue file → anchor-runner.ts) but the
// runner has historically been operator-driven — someone runs `bun
// cartridges/wallet-headers/brain/scripts/anchor-runner.ts` by hand,
// or sets up a systemd unit. Without that, JSONL lines accumulate
// in the queue and never get broadcast.
//
// This supervisor closes the gap: when `BRAIN_ANCHOR_RUNNER=1` and
// `BRAIN_ANCHOR_QUEUE_PATH` are both set, the brain spawns the
// runner as a child process and respawns it on exit with bounded
// backoff. On `brain serve` shutdown the supervisor signals + joins
// the runner cleanly.
//
// Opt-in only — defaults preserve operator-driven deployment.
//
// Architecture:
//
//   brain serve
//     ├─ AnchorQueueWriter (subscribes broker, appends to JSONL)
//     ├─ AnchorRunnerSupervisor.start()
//     │    └─ supervisor thread
//     │         loop:
//     │           spawn `bun anchor-runner.ts --queue ...`
//     │           wait()                ← blocks until runner exits
//     │           if shutdown:  break
//     │           else: backoff, restart
//     └─ ... rest of serve
//
// Shutdown protocol:
//   1. main thread calls supervisor.stop()
//   2. stop() sets `shutdown_requested = true`
//   3. stop() sends SIGTERM to the current child (if any)
//   4. supervisor thread's child.wait() returns
//   5. supervisor thread checks shutdown flag, breaks out of loop
//   6. stop() joins the supervisor thread
//
// Logs: child stdout/stderr inherit the brain's, so runner logs
// flow through `flutter logs` / systemd journal / wherever the
// brain's stdout points.

const std = @import("std");

/// Tunables (compile-time defaults; future override path = JSON config).
pub const INITIAL_BACKOFF_MS: u64 = 500;
pub const MAX_BACKOFF_MS: u64 = 30_000;
pub const BACKOFF_MULTIPLIER: u64 = 2;

/// Minimum runtime before we reset the backoff. A child that ran for
/// at least this long before exiting is treated as a healthy long
/// session — the next restart starts from INITIAL_BACKOFF_MS again.
pub const HEALTHY_RUNTIME_MS: u64 = 30_000;

pub const Config = struct {
    /// Path to the bun binary. Defaults to "bun" (PATH lookup).
    bun_path: []const u8 = "bun",
    /// Absolute path to anchor-runner.ts.
    script_path: []const u8,
    /// Absolute path to the JSONL queue file (matches
    /// `BRAIN_ANCHOR_QUEUE_PATH`).
    queue_path: []const u8,
    /// Optional `--poll-ms <N>` value forwarded to the runner.
    poll_ms: ?u32 = null,
};

pub const Supervisor = struct {
    allocator: std.mem.Allocator,
    config: Config,
    thread: ?std.Thread = null,
    shutdown_requested: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    /// Holds the currently-running child so stop() can signal it.
    /// Guarded by `child_mu`. Null when no child is alive (between
    /// spawn attempts, or after final shutdown).
    current_child: ?*std.process.Child = null,
    child_mu: std.Thread.Mutex = .{},

    pub fn init(allocator: std.mem.Allocator, config: Config) Supervisor {
        return .{
            .allocator = allocator,
            .config = config,
        };
    }

    /// Spawn the supervisor thread. Returns immediately; the runner
    /// is up shortly after via the thread's loop.
    pub fn start(self: *Supervisor) !void {
        if (self.thread != null) return error.AlreadyStarted;
        self.thread = try std.Thread.spawn(.{}, supervisorLoop, .{self});
    }

    /// Signal shutdown + join the supervisor thread. Safe to call
    /// even if start() was never invoked.
    pub fn stop(self: *Supervisor) void {
        if (self.thread == null) return;
        self.shutdown_requested.store(true, .release);

        // Signal the current child (if any) to terminate. The
        // supervisor thread's child.wait() returns, the loop checks
        // shutdown flag, breaks out.
        self.child_mu.lock();
        if (self.current_child) |child| {
            // Best-effort SIGTERM. Errors are ignored — if the child
            // already exited or we lack permission, the wait() will
            // either have returned already or never (in which case
            // join() blocks; the operator deals with it).
            _ = std.posix.kill(child.id, std.posix.SIG.TERM) catch {};
        }
        self.child_mu.unlock();

        if (self.thread) |t| t.join();
        self.thread = null;
    }
};

fn supervisorLoop(self: *Supervisor) void {
    var backoff_ms: u64 = INITIAL_BACKOFF_MS;
    var restart_count: u64 = 0;

    std.log.info("[anchor_runner] supervisor starting; bun={s} script={s} queue={s}", .{
        self.config.bun_path,
        self.config.script_path,
        self.config.queue_path,
    });

    while (!self.shutdown_requested.load(.acquire)) {
        const spawn_start_ms = std.time.milliTimestamp();
        runOnce(self) catch |err| {
            std.log.err("[anchor_runner] runOnce error: {s}", .{@errorName(err)});
        };
        const runtime_ms: u64 = blk: {
            const elapsed = std.time.milliTimestamp() - spawn_start_ms;
            if (elapsed <= 0) break :blk 0;
            break :blk @intCast(elapsed);
        };

        if (self.shutdown_requested.load(.acquire)) break;

        if (runtime_ms >= HEALTHY_RUNTIME_MS) {
            // The child ran for a healthy long time before exiting;
            // reset backoff so we don't penalise stable supervised
            // sessions for occasional restarts.
            backoff_ms = INITIAL_BACKOFF_MS;
        }

        restart_count += 1;
        std.log.warn(
            "[anchor_runner] runner exited (runtime_ms={d}); restart #{d} in {d}ms",
            .{ runtime_ms, restart_count, backoff_ms },
        );

        std.Thread.sleep(backoff_ms * std.time.ns_per_ms);

        if (backoff_ms < MAX_BACKOFF_MS) {
            backoff_ms = @min(backoff_ms * BACKOFF_MULTIPLIER, MAX_BACKOFF_MS);
        }
    }

    std.log.info("[anchor_runner] supervisor loop exiting (shutdown requested)", .{});
}

/// One spawn → wait cycle. Errors propagate up so the loop can log;
/// the loop will backoff + retry regardless.
fn runOnce(self: *Supervisor) !void {
    // Build argv: bun <script> --queue <path> [--poll-ms <N>]
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(self.allocator);

    try argv.append(self.allocator, self.config.bun_path);
    try argv.append(self.allocator, self.config.script_path);
    try argv.append(self.allocator, "--queue");
    try argv.append(self.allocator, self.config.queue_path);

    var poll_buf: [16]u8 = undefined;
    if (self.config.poll_ms) |ms| {
        try argv.append(self.allocator, "--poll-ms");
        const s = try std.fmt.bufPrint(&poll_buf, "{d}", .{ms});
        try argv.append(self.allocator, s);
    }

    var child = std.process.Child.init(argv.items, self.allocator);
    // Runner logs to stdout/stderr; inherit so they flow through the
    // brain's parent streams (systemd journal, console, etc.).
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    try child.spawn();

    self.child_mu.lock();
    self.current_child = &child;
    self.child_mu.unlock();

    defer {
        self.child_mu.lock();
        self.current_child = null;
        self.child_mu.unlock();
    }

    const term = child.wait() catch |err| {
        std.log.err("[anchor_runner] child.wait failed: {s}", .{@errorName(err)});
        return err;
    };

    switch (term) {
        .Exited => |code| std.log.info("[anchor_runner] child exited with code {d}", .{code}),
        .Signal => |sig| std.log.info("[anchor_runner] child killed by signal {d}", .{sig}),
        .Stopped => |sig| std.log.warn("[anchor_runner] child stopped by signal {d} (unexpected)", .{sig}),
        .Unknown => |code| std.log.warn("[anchor_runner] child terminated unknown (code {d})", .{code}),
    }
}

// ─────────────────────────────────────────────────────────────────────
// Tests — supervisor lifecycle without an actual bun binary.
//
// We exercise start/stop and the shutdown signal path by pointing
// the supervisor at a no-op script that sleeps in a loop (via
// `/bin/sh -c "while true; do sleep 1; done"`), then call stop()
// and verify the thread joins cleanly.
// ─────────────────────────────────────────────────────────────────────

const testing = std.testing;

test "Supervisor.init constructs with valid config" {
    var s = Supervisor.init(testing.allocator, .{
        .script_path = "/dev/null",
        .queue_path = "/tmp/test-queue.jsonl",
    });
    try testing.expect(s.thread == null);
    try testing.expectEqual(false, s.shutdown_requested.load(.acquire));
}

test "Supervisor.start + stop round-trips cleanly with sleep-loop child" {
    // Skip on platforms without /bin/sh (e.g. some embedded CI). The
    // test exists to exercise the supervisor lifecycle, not to ship
    // /bin/sh as a hard dep — production uses `bun`.
    std.fs.cwd().access("/bin/sh", .{}) catch return error.SkipZigTest;

    var s = Supervisor.init(testing.allocator, .{
        .bun_path = "/bin/sh",
        .script_path = "-c",
        // The "queue" arg position is normally `--queue <path>`; here
        // /bin/sh treats it as args to the inline command. The
        // command itself is a sleep loop that ignores its args.
        .queue_path = "while true; do sleep 1; done",
    });
    try s.start();
    // Let the supervisor spawn at least once.
    std.Thread.sleep(200 * std.time.ns_per_ms);
    s.stop();
    try testing.expect(s.thread == null);
}

test "Supervisor.stop is safe when never started" {
    var s = Supervisor.init(testing.allocator, .{
        .script_path = "/dev/null",
        .queue_path = "/tmp/test-queue.jsonl",
    });
    s.stop();
    try testing.expect(s.thread == null);
}

test "Supervisor.start twice errors" {
    std.fs.cwd().access("/bin/sh", .{}) catch return error.SkipZigTest;

    var s = Supervisor.init(testing.allocator, .{
        .bun_path = "/bin/sh",
        .script_path = "-c",
        .queue_path = "while true; do sleep 1; done",
    });
    try s.start();
    defer s.stop();

    try testing.expectError(error.AlreadyStarted, s.start());
}

```
