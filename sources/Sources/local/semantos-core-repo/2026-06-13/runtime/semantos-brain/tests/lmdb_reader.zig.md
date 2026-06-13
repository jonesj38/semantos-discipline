---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/lmdb_reader.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.209777+00:00
---

# runtime/semantos-brain/tests/lmdb_reader.zig

```zig
// M1.9 — LMDB crash-recovery conformance: reader helper binary.
//
// Opens an LMDB env read-only, counts all records in the default (anonymous)
// database, and prints the count on stdout.
//
// Usage:
//   lmdb-reader <db_path>
//
// Exit codes:
//   0 — success (count printed on stdout)
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

    if (args.len < 2) {
        std.debug.print("usage: lmdb-reader <db_path>\n", .{});
        std.process.exit(1);
    }

    const db_path = args[1];

    var env = lmdb.Env.open(db_path, .{
        .map_size = lmdb_config.LmdbConfig.default.map_size,
        .max_dbs = lmdb_config.LmdbConfig.default.max_dbs,
        .open_flags = lmdb_config.LmdbConfig.prod_flags | lmdb.EnvFlags.RDONLY,
        .mode = lmdb_config.LmdbConfig.default.mode,
    }) catch |e| {
        std.debug.print("env open: {s}\n", .{@errorName(e)});
        std.process.exit(2);
    };
    defer env.close();

    const txn = env.beginTxn(.read_only) catch |e| {
        std.debug.print("beginTxn: {s}\n", .{@errorName(e)});
        std.process.exit(2);
    };
    defer txn.abort();

    const dbi = txn.openDb(null, .{ .create = false }) catch |e| {
        std.debug.print("openDb: {s}\n", .{@errorName(e)});
        std.process.exit(2);
    };

    var cursor = txn.openCursor(dbi) catch |e| {
        std.debug.print("openCursor: {s}\n", .{@errorName(e)});
        std.process.exit(2);
    };
    defer cursor.close();

    var count: usize = 0;
    while (try cursor.next()) |_| {
        count += 1;
    }

    var buf: [32]u8 = undefined;
    const line = std.fmt.bufPrint(&buf, "{d}\n", .{count}) catch unreachable;
    _ = std.fs.File.stdout().write(line) catch {};
}

```
