---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests/lmdb_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.960071+00:00
---

# core/cell-engine/tests/lmdb_conformance.zig

```zig
// M1.1 — LMDB binding smoke tests (TDD red phase).
//
// Acceptance: one LMDB binding chosen; built; smoke test loads/stores one row.
// Per §5 TDD discipline: these tests are written before the implementation.
//
// Test IDs: M1.1-T-smoke-put-get, M1.1-T-smoke-not-found,
//           M1.1-T-smoke-delete, M1.1-T-smoke-overwrite,
//           M1.1-T-smoke-txn-abort-rollback, M1.1-T-smoke-cursor.
//
// Run: zig build test-lmdb (see build.zig)

const std = @import("std");
const lmdb = @import("lmdb");

// ── helpers ──────────────────────────────────────────────────────────

fn tmpDir(alloc: std.mem.Allocator) ![]u8 {
    var buf: [64]u8 = undefined;
    const name = try std.fmt.bufPrint(&buf, "/tmp/lmdb-test-{d}", .{std.time.nanoTimestamp()});
    try std.fs.cwd().makePath(name);
    return alloc.dupe(u8, name);
}

// ── M1.1-T-smoke-put-get ─────────────────────────────────────────────

test "M1.1: put then get returns same bytes" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const path = try tmpDir(alloc);
    defer alloc.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    {
        var txn = try env.beginTxn(.read_write);
        errdefer txn.abort();
        const db = try txn.openDb(null, .{});
        try txn.put(db, "hello", "world", .{});
        try txn.commit();
    }

    {
        var txn = try env.beginTxn(.read_only);
        defer txn.abort();
        const db = try txn.openDb(null, .{});
        const val = try txn.get(db, "hello");
        try std.testing.expectEqualSlices(u8, "world", val);
    }
}

// ── M1.1-T-smoke-not-found ───────────────────────────────────────────

test "M1.1: get missing key returns error.not_found" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const path = try tmpDir(alloc);
    defer alloc.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var txn = try env.beginTxn(.read_only);
    defer txn.abort();
    const db = try txn.openDb(null, .{});
    try std.testing.expectError(error.not_found, txn.get(db, "absent"));
}

// ── M1.1-T-smoke-delete ──────────────────────────────────────────────

test "M1.1: delete removes key" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const path = try tmpDir(alloc);
    defer alloc.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    {
        var txn = try env.beginTxn(.read_write);
        errdefer txn.abort();
        const db = try txn.openDb(null, .{});
        try txn.put(db, "k", "v", .{});
        try txn.commit();
    }

    {
        var txn = try env.beginTxn(.read_write);
        errdefer txn.abort();
        const db = try txn.openDb(null, .{});
        try txn.del(db, "k", null);
        try txn.commit();
    }

    {
        var txn = try env.beginTxn(.read_only);
        defer txn.abort();
        const db = try txn.openDb(null, .{});
        try std.testing.expectError(error.not_found, txn.get(db, "k"));
    }
}

// ── M1.1-T-smoke-overwrite ───────────────────────────────────────────

test "M1.1: second put overwrites first" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const path = try tmpDir(alloc);
    defer alloc.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    {
        var txn = try env.beginTxn(.read_write);
        errdefer txn.abort();
        const db = try txn.openDb(null, .{});
        try txn.put(db, "k", "first", .{});
        try txn.commit();
    }
    {
        var txn = try env.beginTxn(.read_write);
        errdefer txn.abort();
        const db = try txn.openDb(null, .{});
        try txn.put(db, "k", "second", .{});
        try txn.commit();
    }
    {
        var txn = try env.beginTxn(.read_only);
        defer txn.abort();
        const db = try txn.openDb(null, .{});
        const val = try txn.get(db, "k");
        try std.testing.expectEqualSlices(u8, "second", val);
    }
}

// ── M1.1-T-smoke-txn-abort-rollback ─────────────────────────────────

test "M1.1: aborted write transaction does not persist" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const path = try tmpDir(alloc);
    defer alloc.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    {
        var txn = try env.beginTxn(.read_write);
        const db = try txn.openDb(null, .{});
        try txn.put(db, "ghost", "never", .{});
        txn.abort(); // explicit abort — no commit
    }

    {
        var txn = try env.beginTxn(.read_only);
        defer txn.abort();
        const db = try txn.openDb(null, .{});
        try std.testing.expectError(error.not_found, txn.get(db, "ghost"));
    }
}

// ── M1.1-T-smoke-cursor ──────────────────────────────────────────────

test "M1.1: cursor iterates all keys in sorted order" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const path = try tmpDir(alloc);
    defer alloc.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    const keys = [_][]const u8{ "a", "b", "c", "d" };
    {
        var txn = try env.beginTxn(.read_write);
        errdefer txn.abort();
        const db = try txn.openDb(null, .{});
        for (keys) |k| try txn.put(db, k, "v", .{});
        try txn.commit();
    }

    {
        var txn = try env.beginTxn(.read_only);
        defer txn.abort();
        const db = try txn.openDb(null, .{});
        var cur = try txn.openCursor(db);
        defer cur.close();

        var i: usize = 0;
        while (try cur.next()) |entry| : (i += 1) {
            try std.testing.expectEqualSlices(u8, keys[i], entry.key);
        }
        try std.testing.expectEqual(keys.len, i);
    }
}

```
