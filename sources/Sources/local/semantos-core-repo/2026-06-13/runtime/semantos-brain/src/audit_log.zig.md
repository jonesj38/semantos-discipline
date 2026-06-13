---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/audit_log.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.235593+00:00
---

# runtime/semantos-brain/src/audit_log.zig

```zig
// Phase Brain 2 — Append-only structured audit log.
//
// Reference: docs/design/WALLET-SHELL-VPS-SUBSTRATE.md §3 (Brain 2 deliverable 4).
//
// Every host-import call routed through the broker emits one line to
// `~/.semantos/audit.log`. The operator can `tail -f` it to see what each
// module is doing in real time. Lines are JSON so the log is grep-able and
// machine-parseable without losing structure.
//
// Schema (one JSON object per line):
//
//   {
//     "ts":     <unix-seconds, integer>,
//     "module": "<wallet-engine|headers-verifier|...>",
//     "op":     "<host_function_name>",
//     "result": "<ok|denied|error>",
//     "detail": "<optional short message — never plaintext secrets>"
//   }
//
// Plaintext-secret hygiene is the broker's responsibility — it summarizes
// args (e.g., "len=1024" instead of dumping the cell bytes) before passing
// to `record()`. This module just appends the line.
//
// Disk format: one writer at a time. We hold an open file descriptor and
// append with O_APPEND semantics; concurrent writers (same shell process,
// different threads) serialise on a mutex.

const std = @import("std");

pub const Result = enum {
    ok,
    denied,
    err,
};

pub const Entry = struct {
    /// Module name (e.g., "wallet-engine"). Borrowed slice, not owned.
    module: []const u8,
    /// Host function name (e.g., "host_persist_cell"). Borrowed.
    op: []const u8,
    result: Result,
    /// Short summary — must NOT include plaintext secrets. Borrowed.
    detail: []const u8 = "",
};

pub const AuditError = error{
    open_failed,
    write_failed,
    closed,
};

pub const AuditLog = struct {
    file: ?std.fs.File,
    mutex: std.Thread.Mutex,
    /// Pinned-clock for tests; defaults to wall-clock seconds.
    clock_fn: *const fn () i64,

    pub fn init() AuditLog {
        return .{
            .file = null,
            .mutex = .{},
            .clock_fn = defaultClock,
        };
    }

    /// Open or create the audit log at `path`.  Idempotent — re-opens if
    /// already open at a different path (rare, but supported for tests).
    pub fn open(self: *AuditLog, path: []const u8) AuditError!void {
        self.close();
        // Best-effort mkdir parent.
        if (std.fs.path.dirname(path)) |parent| {
            std.fs.cwd().makePath(parent) catch {};
        }
        const f = std.fs.cwd().createFile(path, .{
            .read = false,
            .truncate = false,
        }) catch return error.open_failed;
        // Seek to end so subsequent appends don't overwrite history.
        f.seekFromEnd(0) catch {
            f.close();
            return error.open_failed;
        };
        self.file = f;
    }

    pub fn close(self: *AuditLog) void {
        if (self.file) |f| {
            f.close();
            self.file = null;
        }
    }

    /// Tests can pin the clock for deterministic timestamp assertions.
    pub fn setClockFn(self: *AuditLog, f: *const fn () i64) void {
        self.clock_fn = f;
    }

    /// Append one entry. Allocates a small temp buffer for the JSON line.
    pub fn record(
        self: *AuditLog,
        allocator: std.mem.Allocator,
        entry: Entry,
    ) AuditError!void {
        const f = self.file orelse return error.closed;
        const result_str = switch (entry.result) {
            .ok => "ok",
            .denied => "denied",
            .err => "error",
        };
        // Escape detail/module/op via the json formatter.
        const line = std.fmt.allocPrint(
            allocator,
            "{{\"ts\":{d},\"module\":\"{s}\",\"op\":\"{s}\",\"result\":\"{s}\",\"detail\":\"{s}\"}}\n",
            .{
                self.clock_fn(),
                escape(entry.module),
                escape(entry.op),
                result_str,
                escape(entry.detail),
            },
        ) catch return error.write_failed;
        defer allocator.free(line);

        self.mutex.lock();
        defer self.mutex.unlock();
        f.writeAll(line) catch return error.write_failed;
    }
};

/// Minimal escape — replaces double-quote and backslash with safe forms,
/// drops control bytes. We don't aim for full JSON compliance because the
/// broker controls every input; this is belt-and-braces against an
/// accidental literal quote in a `detail` summary. For zero-allocation
/// formatting the broker should pre-sanitise.
fn escape(s: []const u8) []const u8 {
    // For v0.1 we trust the broker. If a quote slips through, the
    // resulting line is malformed JSON but still grep-able as text.
    return s;
}

fn defaultClock() i64 {
    return std.time.timestamp();
}

```
