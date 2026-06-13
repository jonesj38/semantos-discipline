---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/migrate_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.203372+00:00
---

# runtime/semantos-brain/tests/migrate_conformance.zig

```zig
// M1.8 — migrate conformance tests (TDD scaffold — starts red).
//
// Tests:
//   M1.8-T-header-import  — write 3 header JSONL records to a temp dir, run
//                           brain-migrate, read back from LMDB → all 3 present
//   M1.8-T-idempotent     — run brain-migrate twice on same dir → second run
//                           succeeds, no duplicates, same 3 records
//   M1.8-T-dry-run        — --dry-run flag → no LMDB env created/modified
//   M1.8-T-corrupt-skip   — introduce a malformed JSONL line → tool logs
//                           error + continues + remaining records imported
//
// These tests invoke the Semantos Brain-migrate binary as a child process (exec-based
// integration test), which is the only way to test a standalone CLI binary
// that writes LMDB while the test harness may also be using LMDB.  The
// binary path is injected at build time via the migrate_opts module.

const std = @import("std");
const lmdb = @import("lmdb");
const header_store_lmdb = @import("header_store_lmdb");
const migrate_opts = @import("migrate_opts");

// ── Helpers ────────────────────────────────────────────────────────────────

/// Return the Semantos Brain-migrate binary path baked in at build time.
fn migrateBin(allocator: std.mem.Allocator) ![]u8 {
    return allocator.dupe(u8, migrate_opts.migrate_bin);
}

/// Write a minimal `headers.jsonl` in `data_dir`.
///
/// JSON format (one record per line):
///   {
///     "height": <u32>,
///     "version": <u32>,
///     "prev_hash": "<64 hex chars>",
///     "merkle_root": "<64 hex chars>",
///     "timestamp": <u32>,
///     "bits": <u32>,
///     "nonce": <u32>,
///     "hash": "<64 hex chars>"
///   }
fn writeHeadersJsonl(data_dir: []const u8, records: []const HeaderRec) !void {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/headers.jsonl", .{data_dir});
    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    for (records) |r| {
        try file.deprecatedWriter().print(
            \\{{"height":{d},"version":{d},"prev_hash":"{s}","merkle_root":"{s}","timestamp":{d},"bits":{d},"nonce":{d},"hash":"{s}"}}
            \\
        , .{
            r.height,
            r.version,
            &hexBuf(&r.prev_hash),
            &hexBuf(&r.merkle_root),
            r.timestamp,
            r.bits,
            r.nonce,
            &hexBuf(&r.hash),
        });
    }
}

const HeaderRec = struct {
    height: u32,
    version: u32,
    prev_hash: [32]u8,
    merkle_root: [32]u8,
    timestamp: u32,
    bits: u32,
    nonce: u32,
    hash: [32]u8,
};

fn hexBuf(bytes: *const [32]u8) [64]u8 {
    var out: [64]u8 = undefined;
    const hex = "0123456789abcdef";
    for (bytes, 0..) |b, i| {
        out[i * 2] = hex[(b >> 4) & 0xf];
        out[i * 2 + 1] = hex[b & 0xf];
    }
    return out;
}

/// Build three deterministic test header records (no PoW required — the
/// migrator doesn't validate PoW, it just transfers bytes).
fn threeHeaders() [3]HeaderRec {
    var recs: [3]HeaderRec = undefined;
    var prev: [32]u8 = [_]u8{0} ** 32;
    for (0..3) |i| {
        const hash = blk: {
            var h: [32]u8 = undefined;
            h[0] = @intCast(i + 1);
            h[1..].* = [_]u8{@intCast(i)} ** 31;
            break :blk h;
        };
        recs[i] = .{
            .height = @intCast(i),
            .version = 1,
            .prev_hash = prev,
            .merkle_root = [_]u8{@intCast(i + 10)} ** 32,
            .timestamp = @intCast(1_700_000_000 + i * 600),
            .bits = 0x1d00ffff,
            .nonce = @intCast(i),
            .hash = hash,
        };
        prev = hash;
    }
    return recs;
}

/// Run brain-migrate with the given args. Returns exit code.
fn runMigrate(allocator: std.mem.Allocator, args: []const []const u8) !u8 {
    const bin = try migrateBin(allocator);
    defer allocator.free(bin);

    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);
    try argv.append(allocator, bin);
    for (args) |a| try argv.append(allocator, a);

    var child = std.process.Child.init(argv.items, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    try child.spawn();

    // Drain stdout/stderr so the child doesn't block on a full pipe.
    var buf: [4096]u8 = undefined;
    if (child.stdout) |out| {
        while (true) {
            const n = out.read(&buf) catch 0;
            if (n == 0) break;
        }
    }
    if (child.stderr) |err| {
        while (true) {
            const n = err.read(&buf) catch 0;
            if (n == 0) break;
        }
    }

    const result = try child.wait();
    return switch (result) {
        .Exited => |code| code,
        else => 1,
    };
}

/// Count header records in the LMDB env at `lmdb_dir`.
fn countLmdbHeaders(allocator: std.mem.Allocator, lmdb_dir: []const u8) !u32 {
    var env = try lmdb.Env.open(lmdb_dir, .{ .max_dbs = 8 });
    defer env.close();
    var store = try header_store_lmdb.LmdbHeaderStore.init(&env, allocator);
    defer store.deinit();
    const snap = try store.store().snapshot(allocator);
    defer allocator.free(snap);
    return @intCast(snap.len);
}

// ── Test cases ─────────────────────────────────────────────────────────────

test "M1.8-T-header-import: 3 headers → LMDB all 3 present" {
    const allocator = std.testing.allocator;

    // Create temp directories.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var data_dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &data_dir_buf);

    var lmdb_tmp = std.testing.tmpDir(.{});
    defer lmdb_tmp.cleanup();
    var lmdb_dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const lmdb_dir = try lmdb_tmp.dir.realpath(".", &lmdb_dir_buf);

    const headers = threeHeaders();
    try writeHeadersJsonl(data_dir, &headers);

    const data_arg = try std.fmt.allocPrint(allocator, "--data-dir={s}", .{data_dir});
    defer allocator.free(data_arg);
    const lmdb_arg = try std.fmt.allocPrint(allocator, "--lmdb-dir={s}", .{lmdb_dir});
    defer allocator.free(lmdb_arg);

    const exit_code = try runMigrate(allocator, &.{ data_arg, lmdb_arg });
    try std.testing.expectEqual(@as(u8, 0), exit_code);

    const count = try countLmdbHeaders(allocator, lmdb_dir);
    try std.testing.expectEqual(@as(u32, 3), count);
}

test "M1.8-T-idempotent: second run succeeds, same 3 records" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var data_dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &data_dir_buf);

    var lmdb_tmp = std.testing.tmpDir(.{});
    defer lmdb_tmp.cleanup();
    var lmdb_dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const lmdb_dir = try lmdb_tmp.dir.realpath(".", &lmdb_dir_buf);

    const headers = threeHeaders();
    try writeHeadersJsonl(data_dir, &headers);

    const data_arg = try std.fmt.allocPrint(allocator, "--data-dir={s}", .{data_dir});
    defer allocator.free(data_arg);
    const lmdb_arg = try std.fmt.allocPrint(allocator, "--lmdb-dir={s}", .{lmdb_dir});
    defer allocator.free(lmdb_arg);

    // First run.
    const exit1 = try runMigrate(allocator, &.{ data_arg, lmdb_arg });
    try std.testing.expectEqual(@as(u8, 0), exit1);

    // Second run — must also succeed (idempotent).
    const exit2 = try runMigrate(allocator, &.{ data_arg, lmdb_arg });
    try std.testing.expectEqual(@as(u8, 0), exit2);

    // Still exactly 3 records — no duplicates.
    const count = try countLmdbHeaders(allocator, lmdb_dir);
    try std.testing.expectEqual(@as(u32, 3), count);
}

test "M1.8-T-dry-run: --dry-run does not create LMDB env" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var data_dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &data_dir_buf);

    var lmdb_tmp = std.testing.tmpDir(.{});
    defer lmdb_tmp.cleanup();
    var lmdb_dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const lmdb_dir = try lmdb_tmp.dir.realpath(".", &lmdb_dir_buf);

    const headers = threeHeaders();
    try writeHeadersJsonl(data_dir, &headers);

    const data_arg = try std.fmt.allocPrint(allocator, "--data-dir={s}", .{data_dir});
    defer allocator.free(data_arg);
    const lmdb_arg = try std.fmt.allocPrint(allocator, "--lmdb-dir={s}", .{lmdb_dir});
    defer allocator.free(lmdb_arg);

    const exit_code = try runMigrate(allocator, &.{ data_arg, lmdb_arg, "--dry-run" });
    try std.testing.expectEqual(@as(u8, 0), exit_code);

    // No LMDB data file should have been created.
    var lmdb_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_mdb = try std.fmt.bufPrint(&lmdb_path_buf, "{s}/data.mdb", .{lmdb_dir});
    const exists = blk: {
        std.fs.cwd().access(data_mdb, .{}) catch break :blk false;
        break :blk true;
    };
    try std.testing.expect(!exists);
}

test "M1.8-T-corrupt-skip: malformed line skipped, good records imported" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var data_dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &data_dir_buf);

    var lmdb_tmp = std.testing.tmpDir(.{});
    defer lmdb_tmp.cleanup();
    var lmdb_dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const lmdb_dir = try lmdb_tmp.dir.realpath(".", &lmdb_dir_buf);

    // Write good record, corrupt line, two more good records.
    const headers = threeHeaders();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const jsonl_path = try std.fmt.bufPrint(&path_buf, "{s}/headers.jsonl", .{data_dir});
    {
        const file = try std.fs.cwd().createFile(jsonl_path, .{ .truncate = true });
        defer file.close();

        // First good record.
        try file.deprecatedWriter().print(
            \\{{"height":{d},"version":{d},"prev_hash":"{s}","merkle_root":"{s}","timestamp":{d},"bits":{d},"nonce":{d},"hash":"{s}"}}
            \\
        , .{
            headers[0].height, headers[0].version,
            &hexBuf(&headers[0].prev_hash), &hexBuf(&headers[0].merkle_root),
            headers[0].timestamp, headers[0].bits, headers[0].nonce,
            &hexBuf(&headers[0].hash),
        });

        // Malformed line.
        try file.deprecatedWriter().writeAll("{this is not valid json}\n");

        // Two more good records.
        for (headers[1..]) |r| {
            try file.deprecatedWriter().print(
                \\{{"height":{d},"version":{d},"prev_hash":"{s}","merkle_root":"{s}","timestamp":{d},"bits":{d},"nonce":{d},"hash":"{s}"}}
                \\
            , .{
                r.height, r.version,
                &hexBuf(&r.prev_hash), &hexBuf(&r.merkle_root),
                r.timestamp, r.bits, r.nonce,
                &hexBuf(&r.hash),
            });
        }
    } // file closed here

    const data_arg = try std.fmt.allocPrint(allocator, "--data-dir={s}", .{data_dir});
    defer allocator.free(data_arg);
    const lmdb_arg = try std.fmt.allocPrint(allocator, "--lmdb-dir={s}", .{lmdb_dir});
    defer allocator.free(lmdb_arg);

    // Tool must exit 0 (partial success) even with a corrupt line.
    const exit_code = try runMigrate(allocator, &.{ data_arg, lmdb_arg });
    try std.testing.expectEqual(@as(u8, 0), exit_code);

    // All 3 good records imported (corrupt line skipped).
    const count = try countLmdbHeaders(allocator, lmdb_dir);
    try std.testing.expectEqual(@as(u32, 3), count);
}

```
