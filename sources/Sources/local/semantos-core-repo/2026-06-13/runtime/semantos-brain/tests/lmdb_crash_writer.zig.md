---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/lmdb_crash_writer.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.211216+00:00
---

# runtime/semantos-brain/tests/lmdb_crash_writer.zig

```zig
// M1.9 — LMDB crash-recovery conformance: writer helper binary.
//
// Invoked by lmdb_crash_recovery.sh.  Writes N records to an LMDB env,
// then either exits cleanly or receives SIGKILL (from the test harness)
// depending on the BRAIN_CRASH_WRITER_UNCLEAN env var.
//
// Usage:
//   lmdb-crash-writer <db_path> <n_records> [nosync]
//
// Arguments:
//   db_path   — path to the LMDB directory (created if absent)
//   n_records — number of key/value pairs to write
//   nosync    — optional; if present, opens with NOSYNC flag (CI only)
//
// Exit codes:
//   0 — wrote all records and committed successfully (clean exit)
//   1 — argument error
//   2 — LMDB error

const std = @import("std");
const lmdb = @import("lmdb");
const lmdb_config = @import("lmdb_config");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 3) {
        std.debug.print("usage: lmdb-crash-writer <db_path> <n_records> [nosync]\n", .{});
        std.process.exit(1);
    }

    const db_path = args[1];
    const n_records = std.fmt.parseInt(usize, args[2], 10) catch {
        std.debug.print("n_records must be an integer\n", .{});
        std.process.exit(1);
    };

    // Determine flags: nosync arg → NOSYNC (CI only), else prod_flags.
    const use_nosync = args.len >= 4 and std.mem.eql(u8, args[3], "nosync");
    const flags: c_uint = if (use_nosync)
        lmdb_config.LmdbConfig.ci_flags
    else
        lmdb_config.LmdbConfig.prod_flags;

    // Ensure the directory exists.
    std.fs.makeDirAbsolute(db_path) catch |e| switch (e) {
        error.PathAlreadyExists => {},
        else => {
            std.debug.print("mkdir {s}: {s}\n", .{ db_path, @errorName(e) });
            std.process.exit(2);
        },
    };

    var env = lmdb.Env.open(db_path, .{
        .map_size = lmdb_config.LmdbConfig.default.map_size,
        .max_dbs = lmdb_config.LmdbConfig.default.max_dbs,
        .open_flags = flags,
        .mode = lmdb_config.LmdbConfig.default.mode,
    }) catch |e| {
        std.debug.print("env open: {s}\n", .{@errorName(e)});
        std.process.exit(2);
    };
    defer env.close();

    // Write records one per transaction so partial commits are possible.
    var i: usize = 0;
    while (i < n_records) : (i += 1) {
        const txn = env.beginTxn(.read_write) catch |e| {
            std.debug.print("beginTxn: {s}\n", .{@errorName(e)});
            std.process.exit(2);
        };
        const dbi = txn.openDb(null, .{ .create = true }) catch |e| {
            txn.abort();
            std.debug.print("openDb: {s}\n", .{@errorName(e)});
            std.process.exit(2);
        };

        var key_buf: [32]u8 = undefined;
        var val_buf: [64]u8 = undefined;
        const key = std.fmt.bufPrint(&key_buf, "key_{d:0>6}", .{i}) catch unreachable;
        const val = std.fmt.bufPrint(&val_buf, "value_{d:0>6}", .{i}) catch unreachable;

        txn.put(dbi, key, val, .{}) catch |e| {
            txn.abort();
            std.debug.print("put: {s}\n", .{@errorName(e)});
            std.process.exit(2);
        };
        txn.commit() catch |e| {
            std.debug.print("commit: {s}\n", .{@errorName(e)});
            std.process.exit(2);
        };
    }

    // Print confirmation so the test harness can verify the write completed.
    std.debug.print("wrote {d} records to {s}\n", .{ n_records, db_path });
}

```
