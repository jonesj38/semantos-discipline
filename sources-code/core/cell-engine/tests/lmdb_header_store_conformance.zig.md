---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests/lmdb_header_store_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.958155+00:00
---

# core/cell-engine/tests/lmdb_header_store_conformance.zig

```zig
// M1.2 — LmdbHeaderStore conformance tests.
//
// TDD red phase: these tests are written before the implementation.
// They mirror header_store_conformance.zig but wire to LmdbHeaderStore.
//
// Test IDs: M1.2-T-append-get, M1.2-T-bad-prev-hash, M1.2-T-snapshot-replay,
//           M1.2-T-rollback, M1.2-T-height-out-of-order, M1.2-T-reorg-rollback.
//
// Run: zig build test-lmdb-header-store

const std = @import("std");
const lmdb = @import("lmdb");
const header_store = @import("header_store");
const headers = @import("headers");
const lmdb_header_store = @import("lmdb_header_store");

fn tmpDir(alloc: std.mem.Allocator) ![]u8 {
    var buf: [64]u8 = undefined;
    const name = try std.fmt.bufPrint(
        &buf,
        "/tmp/lmdb-hdr-test-{d}",
        .{std.time.nanoTimestamp()},
    );
    try std.fs.cwd().makePath(name);
    return alloc.dupe(u8, name);
}

fn mkChain(allocator: std.mem.Allocator, n: u32) ![]headers.Header {
    const chain = try allocator.alloc(headers.Header, n);
    var prev_hash = [_]u8{0} ** 32;
    var ts: u32 = 1_700_000_000;
    for (0..n) |i| {
        var h = headers.Header{
            .version = 1,
            .prev_hash = prev_hash,
            .merkle_root = [_]u8{0xab} ** 32,
            .timestamp = ts,
            .bits = headers.REGTEST_BITS,
            .nonce = 0,
        };
        ts += 600;
        var n_try: u32 = 0;
        while (n_try < 200_000) : (n_try += 1) {
            h.nonce = n_try;
            if (h.satisfiesProofOfWork()) break;
        }
        prev_hash = h.computeHash();
        chain[i] = h;
    }
    return chain;
}

// ── M1.2-T-append-get ────────────────────────────────────────────────

test "M1.2: append → get_by_height / get_by_hash / tip round-trip" {
    const allocator = std.testing.allocator;

    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var store_impl = try lmdb_header_store.LmdbHeaderStore.init(&env, allocator);
    defer store_impl.deinit();
    const store = store_impl.store();

    const chain = try mkChain(allocator, 5);
    defer allocator.free(chain);

    for (chain, 0..) |h, i| {
        try store.appendValidated(h, @intCast(i));
    }

    const got = store.getByHeight(2) orelse return error.TestFailed;
    try std.testing.expectEqual(@as(u32, 2), got.height);

    const tip = store.tip() orelse return error.TestFailed;
    try std.testing.expectEqual(@as(u32, 4), tip.height);

    const by_hash = store.getByHash(&tip.hash) orelse return error.TestFailed;
    try std.testing.expectEqual(@as(u32, 4), by_hash.height);
}

// ── M1.2-T-bad-prev-hash ─────────────────────────────────────────────

test "M1.2: appendValidated rejects bad prev_hash" {
    const allocator = std.testing.allocator;

    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var store_impl = try lmdb_header_store.LmdbHeaderStore.init(&env, allocator);
    defer store_impl.deinit();
    const store = store_impl.store();

    const chain = try mkChain(allocator, 2);
    defer allocator.free(chain);

    try store.appendValidated(chain[0], 0);

    var bad = chain[1];
    @memcpy(&bad.prev_hash, &([_]u8{0xff} ** 32));
    try std.testing.expectError(
        error.prev_hash_mismatch,
        store.appendValidated(bad, 1),
    );
}

// ── M1.2-T-snapshot-replay ───────────────────────────────────────────

test "M1.2: snapshot → replay reconstructs state" {
    const allocator = std.testing.allocator;

    const path_src = try tmpDir(allocator);
    defer allocator.free(path_src);
    defer std.fs.cwd().deleteTree(path_src) catch {};

    const path_dst = try tmpDir(allocator);
    defer allocator.free(path_dst);
    defer std.fs.cwd().deleteTree(path_dst) catch {};

    var env_src = try lmdb.Env.open(path_src, .{});
    defer env_src.close();
    var env_dst = try lmdb.Env.open(path_dst, .{});
    defer env_dst.close();

    var src_impl = try lmdb_header_store.LmdbHeaderStore.init(&env_src, allocator);
    defer src_impl.deinit();
    const src = src_impl.store();

    const chain = try mkChain(allocator, 4);
    defer allocator.free(chain);

    for (chain, 0..) |h, i| try src.appendValidated(h, @intCast(i));

    const snap = try src.snapshot(allocator);
    defer allocator.free(snap);

    var dst_impl = try lmdb_header_store.LmdbHeaderStore.init(&env_dst, allocator);
    defer dst_impl.deinit();
    const dst = dst_impl.store();
    try dst.replay(snap);

    const tip = dst.tip() orelse return error.TestFailed;
    try std.testing.expectEqual(@as(u32, 3), tip.height);
}

// ── M1.2-T-rollback ──────────────────────────────────────────────────

test "M1.2: rollback_from drops suffix" {
    const allocator = std.testing.allocator;

    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var store_impl = try lmdb_header_store.LmdbHeaderStore.init(&env, allocator);
    defer store_impl.deinit();
    const store = store_impl.store();

    const chain = try mkChain(allocator, 6);
    defer allocator.free(chain);

    for (chain, 0..) |h, i| try store.appendValidated(h, @intCast(i));

    const dropped = try store.rollbackFrom(4);
    try std.testing.expectEqual(@as(u32, 2), dropped);

    try std.testing.expect(store.getByHeight(4) == null);
    try std.testing.expect(store.getByHeight(3) != null);
    const tip = store.tip() orelse return error.TestFailed;
    try std.testing.expectEqual(@as(u32, 3), tip.height);
}

// ── M1.2-T-height-out-of-order ───────────────────────────────────────

test "M1.2: append rejects out-of-order height" {
    const allocator = std.testing.allocator;

    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var store_impl = try lmdb_header_store.LmdbHeaderStore.init(&env, allocator);
    defer store_impl.deinit();
    const store = store_impl.store();

    const chain = try mkChain(allocator, 3);
    defer allocator.free(chain);

    try store.appendValidated(chain[0], 0);
    try std.testing.expectError(
        error.height_out_of_order,
        store.appendValidated(chain[2], 5),
    );
}

// ── M1.2-T-reorg-rollback ────────────────────────────────────────────
// Load-bearing reorg test: write heights 1–10, rollback to height 5,
// verify heights 6–10 are gone and heights 1–5 survive.

test "M1.2: reorg rollback — heights 6-10 gone, 1-5 survive" {
    const allocator = std.testing.allocator;

    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var store_impl = try lmdb_header_store.LmdbHeaderStore.init(&env, allocator);
    defer store_impl.deinit();
    const store = store_impl.store();

    const chain = try mkChain(allocator, 10);
    defer allocator.free(chain);

    for (chain, 0..) |h, i| try store.appendValidated(h, @intCast(i));

    // Rollback from height 5 — drops heights 5..9 (5 records).
    const dropped = try store.rollbackFrom(5);
    try std.testing.expectEqual(@as(u32, 5), dropped);

    // Heights 0–4 survive.
    for (0..5) |i| {
        const r = store.getByHeight(@intCast(i)) orelse return error.TestFailed;
        try std.testing.expectEqual(@as(u32, @intCast(i)), r.height);
    }

    // Heights 5–9 are gone.
    for (5..10) |i| {
        try std.testing.expect(store.getByHeight(@intCast(i)) == null);
    }

    const tip = store.tip() orelse return error.TestFailed;
    try std.testing.expectEqual(@as(u32, 4), tip.height);
}

```
