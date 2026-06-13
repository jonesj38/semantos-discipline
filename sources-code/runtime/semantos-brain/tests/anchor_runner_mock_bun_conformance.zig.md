---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/anchor_runner_mock_bun_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.191713+00:00
---

# runtime/semantos-brain/tests/anchor_runner_mock_bun_conformance.zig

```zig
// Anchor-runner supervised-child conformance (mock-bun harness).
//
// PR #799 wired AnchorRunnerSupervisor to spawn `bun anchor-runner.ts
// --queue <path>` and restart it on exit. PR #810 closed the
// emitter → broker → queue-writer chain in-process. This file closes
// the remaining test gap: does the supervised child actually get the
// JSONL bytes the queue writer produced, with the argv shape the real
// runner expects?
//
// Approach: write a tiny shell script at test time that stands in for
// `anchor-runner.ts`. The mock:
//   1. Records its argv to a known file on first line.
//   2. Polls the queue file; on every change, copies it to a
//      `seen.jsonl` observation file and writes the line count to
//      `count.txt`.
//
// The supervisor is configured with bun_path="/bin/sh" + the mock
// script as script_path. /bin/sh runs the script with the rest of the
// argv (`--queue <path>` + optional `--poll-ms <N>`) as $1, $2, ...
//
// Tests then assert:
//   - The mock saw `--queue <queue_path>` (and `--poll-ms <N>` when
//     configured).
//   - After AnchorEmitter publishes N events through the broker, the
//     mock observes N lines in the queue file.
//   - The `seen.jsonl` content carries the cell_hash hex string,
//     proving the wire shape round-trips from emitter to consumer.
//
// Out of scope: ARC broadcast, BRC-42 derivation, BEEF assembly. The
// real `anchor-runner.ts` does those; this harness proves the bytes
// reach a bun-shaped consumer correctly. Real broadcast happens
// downstream of this gate — a separate operator-driven sanity run
// against Metanet Desktop produces an actual txid.

const std = @import("std");
const anchor_emitter = @import("anchor_emitter");
const anchor_queue_writer = @import("anchor_queue_writer");
const anchor_runner_supervisor = @import("anchor_runner_supervisor");
const helm_event_broker = @import("helm_event_broker");

const testing = std.testing;

// ─────────────────────────────────────────────────────────────────────
// Harness — mock-bun script writer + observation paths.
// ─────────────────────────────────────────────────────────────────────

const Paths = struct {
    queue: []const u8,
    obs_argv: []const u8,
    obs_count: []const u8,
    obs_seen: []const u8,
    script: []const u8,

    fn alloc(allocator: std.mem.Allocator, tmp_root: []const u8) !Paths {
        return .{
            .queue = try std.fs.path.join(allocator, &.{ tmp_root, "queue.jsonl" }),
            .obs_argv = try std.fs.path.join(allocator, &.{ tmp_root, "argv.txt" }),
            .obs_count = try std.fs.path.join(allocator, &.{ tmp_root, "count.txt" }),
            .obs_seen = try std.fs.path.join(allocator, &.{ tmp_root, "seen.jsonl" }),
            .script = try std.fs.path.join(allocator, &.{ tmp_root, "mock-bun.sh" }),
        };
    }

    fn free(self: Paths, allocator: std.mem.Allocator) void {
        allocator.free(self.queue);
        allocator.free(self.obs_argv);
        allocator.free(self.obs_count);
        allocator.free(self.obs_seen);
        allocator.free(self.script);
    }
};

/// Write the mock-bun shell script. Records `$*` to argv.txt then polls
/// the queue file for `iters` cycles of 100ms each, copying the queue
/// to seen.jsonl + writing the line count to count.txt whenever the
/// count changes.
fn writeMockScript(allocator: std.mem.Allocator, paths: Paths, iters: u32) !void {
    const body = try std.fmt.allocPrint(allocator,
        \\#!/bin/sh
        \\echo "$*" > {[obs_argv]s}
        \\PREV=0
        \\i=0
        \\while [ "$i" -lt {[iters]d} ]; do
        \\  if [ -f "{[queue]s}" ]; then
        \\    LINES=$(wc -l < "{[queue]s}" | tr -d ' ')
        \\    if [ "$LINES" != "$PREV" ] && [ "$LINES" != "0" ]; then
        \\      cp "{[queue]s}" {[obs_seen]s}
        \\      echo "$LINES" > {[obs_count]s}
        \\      PREV="$LINES"
        \\    fi
        \\  fi
        \\  sleep 0.1
        \\  i=$((i + 1))
        \\done
        \\
    , .{
        .obs_argv = paths.obs_argv,
        .queue = paths.queue,
        .obs_seen = paths.obs_seen,
        .obs_count = paths.obs_count,
        .iters = iters,
    });
    defer allocator.free(body);

    var f = try std.fs.cwd().createFile(paths.script, .{ .mode = 0o755 });
    defer f.close();
    try f.writeAll(body);
}

/// Poll for an observation file to contain the expected line count.
/// Returns the count actually observed (0 if file never appeared).
fn pollForCount(allocator: std.mem.Allocator, path: []const u8, expected: usize, deadline_ms: u64) usize {
    var elapsed: u64 = 0;
    while (elapsed < deadline_ms) : (elapsed += 50) {
        std.Thread.sleep(50 * std.time.ns_per_ms);
        const bytes = std.fs.cwd().readFileAlloc(allocator, path, 64) catch continue;
        defer allocator.free(bytes);
        const trimmed = std.mem.trim(u8, bytes, " \t\r\n");
        const n = std.fmt.parseInt(usize, trimmed, 10) catch continue;
        if (n >= expected) return n;
    }
    return 0;
}

/// Poll for a file to simply exist (used for argv observation).
fn pollForFile(path: []const u8, deadline_ms: u64) bool {
    var elapsed: u64 = 0;
    while (elapsed < deadline_ms) : (elapsed += 50) {
        std.Thread.sleep(50 * std.time.ns_per_ms);
        std.fs.cwd().access(path, .{}) catch continue;
        return true;
    }
    return false;
}

fn makeContext(byte: u8) anchor_emitter.AnchorContext {
    var ch: [32]u8 = undefined;
    @memset(&ch, byte);
    var th: [32]u8 = undefined;
    @memset(&th, byte ^ 0x55);
    return .{
        .cell_hash = ch,
        .type_hash = th,
        .entity_tag = 0x10,
    };
}

// ─────────────────────────────────────────────────────────────────────
// Pillar 1 — Supervised child receives correct argv shape.
// Mock script records $* on first line; test reads + asserts.
// ─────────────────────────────────────────────────────────────────────

test "Supervisor invokes child with --queue <queue_path>" {
    std.fs.cwd().access("/bin/sh", .{}) catch return error.SkipZigTest;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_root = try tmp.dir.realpath(".", &path_buf);

    const paths = try Paths.alloc(testing.allocator, tmp_root);
    defer paths.free(testing.allocator);

    try writeMockScript(testing.allocator, paths, 30); // ~3s lifetime

    var sup = anchor_runner_supervisor.Supervisor.init(testing.allocator, .{
        .bun_path = "/bin/sh",
        .script_path = paths.script,
        .queue_path = paths.queue,
    });
    try sup.start();
    defer sup.stop();

    // Wait for the child to record its argv.
    try testing.expect(pollForFile(paths.obs_argv, 2000));

    const argv_bytes = try std.fs.cwd().readFileAlloc(testing.allocator, paths.obs_argv, 4096);
    defer testing.allocator.free(argv_bytes);

    // The mock's `$*` is everything after $0 — i.e. positional args
    // passed by /bin/sh to the script. Supervisor argv =
    //   [/bin/sh, <script>, --queue, <queue_path>]
    // /bin/sh sees script_path as $0 + the rest as $1, $2 — so $*
    // should be "--queue <queue_path>".
    try testing.expect(std.mem.indexOf(u8, argv_bytes, "--queue") != null);
    try testing.expect(std.mem.indexOf(u8, argv_bytes, paths.queue) != null);
    // --poll-ms was NOT configured → must not appear.
    try testing.expect(std.mem.indexOf(u8, argv_bytes, "--poll-ms") == null);
}

// ─────────────────────────────────────────────────────────────────────
// Pillar 2 — --poll-ms gets forwarded when configured.
// ─────────────────────────────────────────────────────────────────────

test "Supervisor forwards --poll-ms <N> when configured" {
    std.fs.cwd().access("/bin/sh", .{}) catch return error.SkipZigTest;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_root = try tmp.dir.realpath(".", &path_buf);

    const paths = try Paths.alloc(testing.allocator, tmp_root);
    defer paths.free(testing.allocator);

    try writeMockScript(testing.allocator, paths, 30);

    var sup = anchor_runner_supervisor.Supervisor.init(testing.allocator, .{
        .bun_path = "/bin/sh",
        .script_path = paths.script,
        .queue_path = paths.queue,
        .poll_ms = 2500,
    });
    try sup.start();
    defer sup.stop();

    try testing.expect(pollForFile(paths.obs_argv, 2000));

    const argv_bytes = try std.fs.cwd().readFileAlloc(testing.allocator, paths.obs_argv, 4096);
    defer testing.allocator.free(argv_bytes);

    try testing.expect(std.mem.indexOf(u8, argv_bytes, "--poll-ms") != null);
    try testing.expect(std.mem.indexOf(u8, argv_bytes, "2500") != null);
}

// ─────────────────────────────────────────────────────────────────────
// Pillar 3 — Full chain: AnchorEmitter → broker → writer → supervised
// mock-bun reads the JSONL the writer produced.
//
// This is the test we can hold up as proof the bun runner can read
// what the brain writes. ARC broadcast is downstream of this gate.
// ─────────────────────────────────────────────────────────────────────

test "AnchorEmitter → queue file → supervised mock-bun observes JSONL with cell_hash" {
    std.fs.cwd().access("/bin/sh", .{}) catch return error.SkipZigTest;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_root = try tmp.dir.realpath(".", &path_buf);

    const paths = try Paths.alloc(testing.allocator, tmp_root);
    defer paths.free(testing.allocator);

    // Mock lifetime ~5s: enough for argv record + queue polls.
    try writeMockScript(testing.allocator, paths, 50);

    var broker = helm_event_broker.Broker.init(testing.allocator);
    defer broker.deinit();
    var writer = anchor_queue_writer.AnchorQueueWriter.init(
        testing.allocator,
        .{ .queue_path = paths.queue },
    );
    try writer.attach(&broker);
    defer writer.detach(&broker);

    var sup = anchor_runner_supervisor.Supervisor.init(testing.allocator, .{
        .bun_path = "/bin/sh",
        .script_path = paths.script,
        .queue_path = paths.queue,
    });
    try sup.start();
    defer sup.stop();

    // Wait for the child to be up + report its argv before publishing,
    // so we don't race the first emit ahead of the poll loop.
    try testing.expect(pollForFile(paths.obs_argv, 2000));

    var emitter = anchor_emitter.AnchorEmitter.initWithBroker(
        testing.allocator,
        .bsv,
        &broker,
    );

    // Three distinct emits → three lines in the queue.
    _ = emitter.emit(makeContext(0xA1));
    _ = emitter.emit(makeContext(0xA2));
    _ = emitter.emit(makeContext(0xA3));

    // Mock should observe 3 lines within ~3s.
    const observed = pollForCount(testing.allocator, paths.obs_count, 3, 3000);
    try testing.expectEqual(@as(usize, 3), observed);

    // Read seen.jsonl (the mock's snapshot of the queue file) and assert
    // wire shape: event type + each cell_hash hex string present.
    const seen_bytes = try std.fs.cwd().readFileAlloc(testing.allocator, paths.obs_seen, 64 * 1024);
    defer testing.allocator.free(seen_bytes);

    try testing.expect(std.mem.indexOf(u8, seen_bytes, "\"type\":\"cell.created\"") != null);

    // Each emit uses byte = 0xA1/0xA2/0xA3 → cell_hash hex of that
    // byte repeated 32 times = 64 chars of 'a1'/'a2'/'a3'.
    const a1_hex = "a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1";
    const a2_hex = "a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2";
    const a3_hex = "a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3a3";
    try testing.expect(std.mem.indexOf(u8, seen_bytes, a1_hex) != null);
    try testing.expect(std.mem.indexOf(u8, seen_bytes, a2_hex) != null);
    try testing.expect(std.mem.indexOf(u8, seen_bytes, a3_hex) != null);
}

```
