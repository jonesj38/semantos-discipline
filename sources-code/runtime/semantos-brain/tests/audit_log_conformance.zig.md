---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/audit_log_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.206491+00:00
---

# runtime/semantos-brain/tests/audit_log_conformance.zig

```zig
// Phase Brain 2 — Audit log conformance tests.

const std = @import("std");
const audit_log = @import("audit_log");

fn tempPath(name: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const dir = std.testing.tmpDir(.{});
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try dir.dir.realpath(".", &buf);
    return std.fs.path.join(allocator, &.{ real, name });
}

fn readAll(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const stat = try file.stat();
    const buf = try allocator.alloc(u8, stat.size);
    errdefer allocator.free(buf);
    const got = try file.readAll(buf);
    if (got != buf.len) return error.ShortRead;
    return buf;
}

var pinned_clock: i64 = 1_700_000_000;
fn fixedClock() i64 {
    return pinned_clock;
}

test "Brain 2 audit: record one ok line" {
    const path = try tempPath("audit-ok.log", std.testing.allocator);
    defer {
        std.fs.cwd().deleteFile(path) catch {};
        std.testing.allocator.free(path);
    }
    var log = audit_log.AuditLog.init();
    defer log.close();
    log.setClockFn(fixedClock);
    try log.open(path);

    try log.record(std.testing.allocator, .{
        .module = "wallet-engine",
        .op = "host_persist_cell",
        .result = .ok,
        .detail = "slot=42 len=1024",
    });
    log.close();

    const contents = try readAll(std.testing.allocator, path);
    defer std.testing.allocator.free(contents);
    try std.testing.expect(std.mem.indexOf(u8, contents, "\"module\":\"wallet-engine\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "\"op\":\"host_persist_cell\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "\"result\":\"ok\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "\"ts\":1700000000") != null);
}

test "Brain 2 audit: append accumulates lines (no truncate on reopen)" {
    const path = try tempPath("audit-append.log", std.testing.allocator);
    defer {
        std.fs.cwd().deleteFile(path) catch {};
        std.testing.allocator.free(path);
    }

    {
        var log = audit_log.AuditLog.init();
        log.setClockFn(fixedClock);
        try log.open(path);
        try log.record(std.testing.allocator, .{
            .module = "m1",
            .op = "op1",
            .result = .ok,
        });
        log.close();
    }
    {
        var log = audit_log.AuditLog.init();
        log.setClockFn(fixedClock);
        try log.open(path);
        try log.record(std.testing.allocator, .{
            .module = "m2",
            .op = "op2",
            .result = .denied,
        });
        log.close();
    }

    const contents = try readAll(std.testing.allocator, path);
    defer std.testing.allocator.free(contents);
    var line_count: usize = 0;
    for (contents) |c| {
        if (c == '\n') line_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), line_count);
    try std.testing.expect(std.mem.indexOf(u8, contents, "\"module\":\"m1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "\"module\":\"m2\"") != null);
}

test "Brain 2 audit: record on a closed log returns error.closed" {
    var log = audit_log.AuditLog.init();
    try std.testing.expectError(
        error.closed,
        log.record(std.testing.allocator, .{
            .module = "x",
            .op = "y",
            .result = .ok,
        }),
    );
}

test "Brain 2 audit: distinct result values appear in output" {
    const path = try tempPath("audit-results.log", std.testing.allocator);
    defer {
        std.fs.cwd().deleteFile(path) catch {};
        std.testing.allocator.free(path);
    }
    var log = audit_log.AuditLog.init();
    defer log.close();
    log.setClockFn(fixedClock);
    try log.open(path);

    try log.record(std.testing.allocator, .{ .module = "m", .op = "ok-op", .result = .ok });
    try log.record(std.testing.allocator, .{ .module = "m", .op = "denied-op", .result = .denied });
    try log.record(std.testing.allocator, .{ .module = "m", .op = "err-op", .result = .err });
    log.close();

    const contents = try readAll(std.testing.allocator, path);
    defer std.testing.allocator.free(contents);
    try std.testing.expect(std.mem.indexOf(u8, contents, "\"result\":\"ok\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "\"result\":\"denied\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, contents, "\"result\":\"error\"") != null);
}

```
