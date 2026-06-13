---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests/lmdb_cell_store_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.957527+00:00
---

# core/cell-engine/tests/lmdb_cell_store_conformance.zig

```zig
// M1.5 — LmdbCellStore conformance tests.
//
// TDD red phase: written before the implementation.
// These tests define the CellStore vtable contract.
//
// Test IDs: M1.5-T-put-exists, M1.5-T-idempotent, M1.5-T-cursor,
//           M1.5-T-4kib-alignment, M1.5-T-count.
//
// Run: zig build test-lmdb-cell-store

const std = @import("std");
const lmdb = @import("lmdb");
const cell_store = @import("cell_store");
const lmdb_cell_store = @import("lmdb_cell_store");

fn tmpDir(alloc: std.mem.Allocator) ![]u8 {
    var buf: [64]u8 = undefined;
    const name = try std.fmt.bufPrint(
        &buf,
        "/tmp/lmdb-cell-test-{d}",
        .{std.time.nanoTimestamp()},
    );
    try std.fs.cwd().makePath(name);
    return alloc.dupe(u8, name);
}

fn makeCell(fill: u8) [cell_store.CELL_BYTES]u8 {
    var c: [cell_store.CELL_BYTES]u8 = undefined;
    @memset(&c, fill);
    return c;
}

// ── M1.5-T-put-exists ────────────────────────────────────────────────

test "M1.5: put → exists round-trip" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var s = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer s.deinit();
    const store = s.store();

    const cell = makeCell(0xAB);
    const hash = try store.put(&cell);

    try std.testing.expect(store.exists(&hash));

    // A different hash does not exist.
    var other_hash = hash;
    other_hash[0] ^= 0xFF;
    try std.testing.expect(!store.exists(&other_hash));
}

// ── M1.5-T-idempotent ────────────────────────────────────────────────

test "M1.5: put is idempotent — second write returns same hash" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var s = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer s.deinit();
    const store = s.store();

    const cell = makeCell(0x42);
    const hash1 = try store.put(&cell);
    const hash2 = try store.put(&cell);

    try std.testing.expectEqual(hash1, hash2);
    // Count should remain 1 after two identical puts.
    const n = try store.count();
    try std.testing.expectEqual(@as(u64, 1), n);
}

// ── M1.5-T-cursor ────────────────────────────────────────────────────

test "M1.5: cursor iterates all cells exactly once" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var s = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer s.deinit();
    const store = s.store();

    // Write 4 distinct cells.
    for (0..4) |i| {
        const cell = makeCell(@intCast(i + 1));
        _ = try store.put(&cell);
    }

    const cur = try store.cursorOpen();
    defer store.cursorClose(cur);

    var count: usize = 0;
    while (try store.cursorPull(cur)) |_| {
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 4), count);
}

// ── M1.5-T-4kib-alignment ────────────────────────────────────────────
// The LMDB value must be 4096 bytes (padded from 1024). Verify by checking
// the actual stored value length through the raw LMDB txn.get path, which
// requires knowing VALUE_BYTES = 4096.

test "M1.5: stored value is padded to PAGE_BYTES (4096)" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var s = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer s.deinit();
    const store = s.store();

    const cell = makeCell(0x77);
    const hash = try store.put(&cell);

    // Verify the padding constant is 4096.
    try std.testing.expectEqual(@as(usize, 4096), cell_store.VALUE_BYTES);

    // Use the store's raw LMDB env to check value size.
    {
        var txn = try env.beginTxn(.read_only);
        defer txn.abort();
        // Open the same DB the impl uses.
        const dbi = try txn.openDb("cells", .{ .create = false });
        // W7.1 — `cells` keys are op_pkh(8B) ‖ sha256(32B) = 40 bytes.
        // Single-tenant deployments (which this test uses, via
        // LmdbCellStore.init) prefix with the all-zero op_pkh. See key
        // layout doc-comment in runtime/semantos-brain/src/lmdb/cell_store_lmdb.zig.
        const key: [40]u8 = [_]u8{0} ** 8 ++ hash;
        const raw = try txn.get(dbi, &key);
        try std.testing.expectEqual(cell_store.VALUE_BYTES, raw.len);
        // First CELL_BYTES must match the cell.
        try std.testing.expectEqualSlices(u8, &cell, raw[0..cell_store.CELL_BYTES]);
        // Padding bytes must be zero.
        for (raw[cell_store.CELL_BYTES..]) |b| {
            try std.testing.expectEqual(@as(u8, 0), b);
        }
    }
}

// ── M1.5-T-count ─────────────────────────────────────────────────────

test "M1.5: count reflects number of distinct cells" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var s = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer s.deinit();
    const store = s.store();

    try std.testing.expectEqual(@as(u64, 0), try store.count());

    for (0..3) |i| {
        const cell = makeCell(@intCast(i + 10));
        _ = try store.put(&cell);
    }

    try std.testing.expectEqual(@as(u64, 3), try store.count());
}

// ── D-LC3-T-owner-index ──────────────────────────────────────────────
//
// `cellsByOwner` enumerates every hash whose cell carries the given
// owner_id (bytes 62..78 of the 1024-byte payload). The index is
// maintained by doPut atomically with the primary write.

fn makeCellWithOwner(fill: u8, owner_id: [16]u8) [cell_store.CELL_BYTES]u8 {
    var c: [cell_store.CELL_BYTES]u8 = undefined;
    @memset(&c, fill);
    @memcpy(c[62 .. 62 + 16], &owner_id);
    return c;
}

test "D-LC3: cellsByOwner returns hashes for one owner, omits others" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var s = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer s.deinit();

    const alice: [16]u8 = [_]u8{0xAA} ** 16;
    const bob: [16]u8 = [_]u8{0xBB} ** 16;

    // Two cells for Alice (distinct payloads → distinct hashes), one for Bob.
    const alice_h1 = try s.store().put(&makeCellWithOwner(0x01, alice));
    const alice_h2 = try s.store().put(&makeCellWithOwner(0x02, alice));
    const bob_h1 = try s.store().put(&makeCellWithOwner(0x03, bob));

    const alice_hashes = try s.cellsByOwner(allocator, &alice);
    defer allocator.free(alice_hashes);
    try std.testing.expectEqual(@as(usize, 2), alice_hashes.len);

    // Order is LMDB lexicographic on the trailing 32 bytes — accept either
    // (h1, h2) or (h2, h1); just check both are present.
    var saw_h1 = false;
    var saw_h2 = false;
    for (alice_hashes) |h| {
        if (std.mem.eql(u8, &h, &alice_h1)) saw_h1 = true;
        if (std.mem.eql(u8, &h, &alice_h2)) saw_h2 = true;
    }
    try std.testing.expect(saw_h1);
    try std.testing.expect(saw_h2);

    const bob_hashes = try s.cellsByOwner(allocator, &bob);
    defer allocator.free(bob_hashes);
    try std.testing.expectEqual(@as(usize, 1), bob_hashes.len);
    try std.testing.expectEqualSlices(u8, &bob_h1, &bob_hashes[0]);

    // An unknown owner returns an empty slice.
    const empty: [16]u8 = [_]u8{0xCC} ** 16;
    const empty_hashes = try s.cellsByOwner(allocator, &empty);
    defer allocator.free(empty_hashes);
    try std.testing.expectEqual(@as(usize, 0), empty_hashes.len);
}

test "D-LC3: cellsByOwner is operator-scoped (op_pkh isolation)" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    // Two stores in the same env with different op_pkh; same owner_id used
    // by both. cellsByOwner must not bleed across.
    const op_a: [lmdb_cell_store.OP_PKH_BYTES]u8 = [_]u8{0x11} ** lmdb_cell_store.OP_PKH_BYTES;
    const op_b: [lmdb_cell_store.OP_PKH_BYTES]u8 = [_]u8{0x22} ** lmdb_cell_store.OP_PKH_BYTES;

    var sa = try lmdb_cell_store.LmdbCellStore.initForOperator(&env, allocator, op_a);
    defer sa.deinit();
    var sb = try lmdb_cell_store.LmdbCellStore.initForOperator(&env, allocator, op_b);
    defer sb.deinit();

    const shared_owner: [16]u8 = [_]u8{0xAA} ** 16;
    _ = try sa.store().put(&makeCellWithOwner(0x10, shared_owner));
    _ = try sb.store().put(&makeCellWithOwner(0x20, shared_owner));

    const a_view = try sa.cellsByOwner(allocator, &shared_owner);
    defer allocator.free(a_view);
    const b_view = try sb.cellsByOwner(allocator, &shared_owner);
    defer allocator.free(b_view);

    try std.testing.expectEqual(@as(usize, 1), a_view.len);
    try std.testing.expectEqual(@as(usize, 1), b_view.len);
    // The two operators' views must be distinct hashes (different fill bytes).
    try std.testing.expect(!std.mem.eql(u8, &a_view[0], &b_view[0]));
}

test "D-LC3: re-putting same cell does not duplicate the index entry" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var s = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer s.deinit();

    const owner: [16]u8 = [_]u8{0xAA} ** 16;
    const cell = makeCellWithOwner(0x55, owner);
    _ = try s.store().put(&cell);
    _ = try s.store().put(&cell); // idempotent
    _ = try s.store().put(&cell);

    const hashes = try s.cellsByOwner(allocator, &owner);
    defer allocator.free(hashes);
    try std.testing.expectEqual(@as(usize, 1), hashes.len);
}

// ── D-LC4-T-prev-state-index ─────────────────────────────────────────
//
// `cellsByPrevState` walks the forward state-DAG: given a 32-byte
// prev_state_hash, return every cell whose header carries that hash at
// offset 128. Used by /api/v1/cell/since/<hex> to stream chain successors.

fn makeCellWithPrevState(fill: u8, prev_state: [32]u8) [cell_store.CELL_BYTES]u8 {
    var c: [cell_store.CELL_BYTES]u8 = undefined;
    @memset(&c, fill);
    @memcpy(c[128 .. 128 + 32], &prev_state);
    return c;
}

test "D-LC4: cellsByPrevState returns children of one chain step" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var s = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer s.deinit();

    const root_hash: [32]u8 = [_]u8{0xAA} ** 32;
    const other_hash: [32]u8 = [_]u8{0xBB} ** 32;

    const c1_hash = try s.store().put(&makeCellWithPrevState(0x11, root_hash));
    const c2_hash = try s.store().put(&makeCellWithPrevState(0x22, root_hash));
    _ = try s.store().put(&makeCellWithPrevState(0x33, other_hash));

    const root_children = try s.cellsByPrevState(allocator, &root_hash);
    defer allocator.free(root_children);
    try std.testing.expectEqual(@as(usize, 2), root_children.len);
    var saw_c1 = false;
    var saw_c2 = false;
    for (root_children) |h| {
        if (std.mem.eql(u8, &h, &c1_hash)) saw_c1 = true;
        if (std.mem.eql(u8, &h, &c2_hash)) saw_c2 = true;
    }
    try std.testing.expect(saw_c1);
    try std.testing.expect(saw_c2);

    const other_children = try s.cellsByPrevState(allocator, &other_hash);
    defer allocator.free(other_children);
    try std.testing.expectEqual(@as(usize, 1), other_children.len);
}

test "D-LC4: cellsByPrevState returns empty for an unknown prev hash" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var s = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer s.deinit();

    const some_prev: [32]u8 = [_]u8{0xAA} ** 32;
    _ = try s.store().put(&makeCellWithPrevState(0x11, some_prev));

    const unknown: [32]u8 = [_]u8{0x99} ** 32;
    const children = try s.cellsByPrevState(allocator, &unknown);
    defer allocator.free(children);
    try std.testing.expectEqual(@as(usize, 0), children.len);
}

test "D-LC4: forward-walk multi-step chain" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var s = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer s.deinit();

    // Build a chain: each cell's prev_state_hash points at the previous
    // cell's content sha256 — same shape real chains carry.
    var prev: [32]u8 = [_]u8{0} ** 32;
    var hashes: [4][32]u8 = undefined;
    for (0..4) |i| {
        const cell = makeCellWithPrevState(@intCast(0x10 + i), prev);
        const h = try s.store().put(&cell);
        hashes[i] = h;
        prev = h;
    }

    for (0..3) |i| {
        const children = try s.cellsByPrevState(allocator, &hashes[i]);
        defer allocator.free(children);
        try std.testing.expectEqual(@as(usize, 1), children.len);
        try std.testing.expectEqualSlices(u8, &hashes[i + 1], &children[0]);
    }
    const tail = try s.cellsByPrevState(allocator, &hashes[3]);
    defer allocator.free(tail);
    try std.testing.expectEqual(@as(usize, 0), tail.len);
}

// ── D-LC4 follow-up — cursor pagination on cellsByPrevStateRange ─────
//
// `cellsByPrevStateRange(allocator, prev, after, limit)` is the paginated
// sibling of `cellsByPrevState`. It returns at most `limit` cell hashes
// in LMDB lex order, starting STRICTLY AFTER `after` when set. The
// returned struct's `has_more` field tells the caller whether the
// underlying enumeration has more entries beyond the slice — used by
// the `/api/v1/cell/since` reactor handler to emit `x-next-cursor`.

test "D-LC4 pagination: walk 5 children with limit=2 across 3 calls, full recovery in lex order" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var s = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer s.deinit();

    const prev: [32]u8 = [_]u8{0xAA} ** 32;
    var seeded: [5][32]u8 = undefined;
    const fills = [_]u8{ 0x10, 0x20, 0x30, 0x40, 0x50 };
    for (fills, 0..) |fill, i| {
        seeded[i] = try s.store().put(&makeCellWithPrevState(fill, prev));
    }
    // Expected order is LMDB lex (= bytewise) over the cell content hashes.
    std.mem.sort([32]u8, &seeded, {}, struct {
        fn lt(_: void, a: [32]u8, b: [32]u8) bool {
            return std.mem.lessThan(u8, &a, &b);
        }
    }.lt);

    // Page 1 — no cursor, limit 2.
    const p1 = try s.cellsByPrevStateRange(allocator, &prev, null, 2);
    defer allocator.free(p1.hashes);
    try std.testing.expectEqual(@as(usize, 2), p1.hashes.len);
    try std.testing.expectEqualSlices(u8, &seeded[0], &p1.hashes[0]);
    try std.testing.expectEqualSlices(u8, &seeded[1], &p1.hashes[1]);
    try std.testing.expect(p1.has_more);

    // Page 2 — after = last of page 1, limit 2.
    const p2 = try s.cellsByPrevStateRange(allocator, &prev, &p1.hashes[1], 2);
    defer allocator.free(p2.hashes);
    try std.testing.expectEqual(@as(usize, 2), p2.hashes.len);
    try std.testing.expectEqualSlices(u8, &seeded[2], &p2.hashes[0]);
    try std.testing.expectEqualSlices(u8, &seeded[3], &p2.hashes[1]);
    try std.testing.expect(p2.has_more);

    // Page 3 — after = last of page 2, limit 2; only one child left.
    const p3 = try s.cellsByPrevStateRange(allocator, &prev, &p2.hashes[1], 2);
    defer allocator.free(p3.hashes);
    try std.testing.expectEqual(@as(usize, 1), p3.hashes.len);
    try std.testing.expectEqualSlices(u8, &seeded[4], &p3.hashes[0]);
    try std.testing.expect(!p3.has_more);
}

test "D-LC4 pagination: after-key past the prefix returns empty + has_more=false" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var s = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer s.deinit();

    const prev: [32]u8 = [_]u8{0xAA} ** 32;
    _ = try s.store().put(&makeCellWithPrevState(0x10, prev));
    _ = try s.store().put(&makeCellWithPrevState(0x20, prev));

    // after = 0xFF*32 — sorts above any possible content sha256, so the
    // cursor seeks past the last entry under this prefix.
    const after: [32]u8 = [_]u8{0xFF} ** 32;
    const r = try s.cellsByPrevStateRange(allocator, &prev, &after, 10);
    defer allocator.free(r.hashes);
    try std.testing.expectEqual(@as(usize, 0), r.hashes.len);
    try std.testing.expect(!r.has_more);
}

test "D-LC4 pagination: limit exactly equals number of remaining → has_more=false" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var s = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer s.deinit();

    const prev: [32]u8 = [_]u8{0xCC} ** 32;
    _ = try s.store().put(&makeCellWithPrevState(0x01, prev));
    _ = try s.store().put(&makeCellWithPrevState(0x02, prev));
    _ = try s.store().put(&makeCellWithPrevState(0x03, prev));

    // limit == 3, exactly equals the number of children → cursor lands
    // past the last entry → has_more must be false.
    const r = try s.cellsByPrevStateRange(allocator, &prev, null, 3);
    defer allocator.free(r.hashes);
    try std.testing.expectEqual(@as(usize, 3), r.hashes.len);
    try std.testing.expect(!r.has_more);
}

test "D-LC4 pagination: limit=0 returns empty + has_more=false" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var s = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer s.deinit();

    const prev: [32]u8 = [_]u8{0xDD} ** 32;
    _ = try s.store().put(&makeCellWithPrevState(0x10, prev));

    const r = try s.cellsByPrevStateRange(allocator, &prev, null, 0);
    defer allocator.free(r.hashes);
    try std.testing.expectEqual(@as(usize, 0), r.hashes.len);
    try std.testing.expect(!r.has_more);
}

test "D-LC4 pagination: empty prev (no children) → empty + has_more=false" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var s = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer s.deinit();

    const unknown: [32]u8 = [_]u8{0x99} ** 32;
    const r = try s.cellsByPrevStateRange(allocator, &unknown, null, 10);
    defer allocator.free(r.hashes);
    try std.testing.expectEqual(@as(usize, 0), r.hashes.len);
    try std.testing.expect(!r.has_more);
}

// ── D-LC5-T-anchor-status ────────────────────────────────────────────
//
// Three-state projection per cell: pending / confirmed / absent (no entry).
// Set/get/clear with the cell hash; status is independent of the cell
// bytes (the cell itself is immutable; the anchor projection is brain
// state).

test "D-LC5: anchor status defaults to absent (null)" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var s = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer s.deinit();

    const cell = makeCell(0x77);
    const hash = try s.store().put(&cell);

    try std.testing.expectEqual(@as(?lmdb_cell_store.AnchorStatus, null), s.getAnchorStatus(&hash));
}

test "D-LC5: setAnchorStatus → getAnchorStatus round-trip" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var s = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer s.deinit();

    const cell = makeCell(0x77);
    const hash = try s.store().put(&cell);

    try s.setAnchorStatus(&hash, .pending);
    try std.testing.expectEqual(@as(?lmdb_cell_store.AnchorStatus, .pending), s.getAnchorStatus(&hash));

    try s.setAnchorStatus(&hash, .confirmed);
    try std.testing.expectEqual(@as(?lmdb_cell_store.AnchorStatus, .confirmed), s.getAnchorStatus(&hash));
}

test "D-LC5: clearAnchorStatus returns to null and is idempotent" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var s = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer s.deinit();

    const cell = makeCell(0x77);
    const hash = try s.store().put(&cell);

    try s.setAnchorStatus(&hash, .pending);
    try s.clearAnchorStatus(&hash);
    try std.testing.expectEqual(@as(?lmdb_cell_store.AnchorStatus, null), s.getAnchorStatus(&hash));

    // Clearing a cell with no entry is a no-op (idempotent rollback path).
    try s.clearAnchorStatus(&hash);
    try std.testing.expectEqual(@as(?lmdb_cell_store.AnchorStatus, null), s.getAnchorStatus(&hash));
}

test "D-LC5: anchor status is op_pkh-scoped" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    const op_a: [lmdb_cell_store.OP_PKH_BYTES]u8 = [_]u8{0x11} ** lmdb_cell_store.OP_PKH_BYTES;
    const op_b: [lmdb_cell_store.OP_PKH_BYTES]u8 = [_]u8{0x22} ** lmdb_cell_store.OP_PKH_BYTES;

    var sa = try lmdb_cell_store.LmdbCellStore.initForOperator(&env, allocator, op_a);
    defer sa.deinit();
    var sb = try lmdb_cell_store.LmdbCellStore.initForOperator(&env, allocator, op_b);
    defer sb.deinit();

    const cell = makeCell(0x77);
    const hash_a = try sa.store().put(&cell);
    const hash_b = try sb.store().put(&cell);
    // Same cell bytes → same content hash (sha256 is op-pkh-independent).
    try std.testing.expectEqualSlices(u8, &hash_a, &hash_b);

    try sa.setAnchorStatus(&hash_a, .confirmed);
    try std.testing.expectEqual(@as(?lmdb_cell_store.AnchorStatus, .confirmed), sa.getAnchorStatus(&hash_a));
    // Operator B sees no anchor for the same content hash.
    try std.testing.expectEqual(@as(?lmdb_cell_store.AnchorStatus, null), sb.getAnchorStatus(&hash_b));
}

// ── D-LC5 follow-up: attestation observer dispatch in doPut ──────────
//
// When a cell with domain_flag = 0x0001FE02 (canonical anchor-attestation
// per audit B-1; see core/plexus-contracts/src/domain-flags.ts) lands,
// `doPut` extracts the 32B targetCellId from the payload (offset 256 in
// the cell, payload offset 0 per anchorAttestationSchemaV1) and flips
// that target's anchor status to .confirmed inside the same write txn.
//
// Layout constants (must match cell_store_lmdb.zig + constants.zig):
const ATTESTATION_DOMAIN_FLAG: u32 = 0x0001FE02;
const OFFSET_DOMAIN_FLAG: usize = 24;
const OFFSET_PAYLOAD_TARGET_CELL_ID: usize = 256;
/// D-LC5 follow-up (reorg-sweep substrate) — txid is the second field of
/// anchorAttestationSchemaV1 (payload offset 32 → cell offset 288).
const OFFSET_PAYLOAD_TXID: usize = 288;

/// Build an anchor-attestation cell with the given targetCellId. Only the
/// header field at offset 24 (domain_flag) and the payload bytes 256..288
/// (targetCellId) matter for the observer dispatch test — the rest of the
/// cell is filled with a distinguishing pattern. The txid field at offset
/// 288..320 is set to the `fill` byte so different attestations naturally
/// have different txids unless the caller overrides via
/// `makeAttestationCellWithTxid`.
fn makeAttestationCell(target_cell_id: [32]u8, fill: u8) [cell_store.CELL_BYTES]u8 {
    var c: [cell_store.CELL_BYTES]u8 = undefined;
    @memset(&c, fill);
    std.mem.writeInt(u32, c[OFFSET_DOMAIN_FLAG..][0..4], ATTESTATION_DOMAIN_FLAG, .little);
    @memcpy(c[OFFSET_PAYLOAD_TARGET_CELL_ID..][0..32], &target_cell_id);
    return c;
}

/// Build an anchor-attestation cell with explicit `target_cell_id` AND
/// `txid` bytes. Used by the reorg-sweep tests to bind a specific
/// (target, txid) pair through the doPut reverse-index write.
fn makeAttestationCellWithTxid(
    target_cell_id: [32]u8,
    txid: [32]u8,
    fill: u8,
) [cell_store.CELL_BYTES]u8 {
    var c: [cell_store.CELL_BYTES]u8 = undefined;
    @memset(&c, fill);
    std.mem.writeInt(u32, c[OFFSET_DOMAIN_FLAG..][0..4], ATTESTATION_DOMAIN_FLAG, .little);
    @memcpy(c[OFFSET_PAYLOAD_TARGET_CELL_ID..][0..32], &target_cell_id);
    @memcpy(c[OFFSET_PAYLOAD_TXID..][0..32], &txid);
    return c;
}

/// Linear-search helper for the unordered `cellsByAnchorTxid` result set.
fn containsHash(haystack: []const [32]u8, needle: [32]u8) bool {
    for (haystack) |h| {
        if (std.mem.eql(u8, &h, &needle)) return true;
    }
    return false;
}

test "D-LC5 follow-up: attestation cell flips target status to confirmed" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var s = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer s.deinit();

    // A distinguishing target hash. The target cell does not need to
    // exist in the store for the projection to flip — the attestation
    // observer is keyed by the target hash alone (mirrors how
    // setAnchorStatus works directly).
    const target_hash: [32]u8 = [_]u8{0xA1} ** 32;

    // No prior anchor entry for the target.
    try std.testing.expectEqual(
        @as(?lmdb_cell_store.AnchorStatus, null),
        s.getAnchorStatus(&target_hash),
    );

    // Storing the attestation cell triggers the observer.
    const att_cell = makeAttestationCell(target_hash, 0x5A);
    _ = try s.store().put(&att_cell);

    try std.testing.expectEqual(
        @as(?lmdb_cell_store.AnchorStatus, .confirmed),
        s.getAnchorStatus(&target_hash),
    );
}

test "D-LC5 follow-up: non-attestation cell does not spuriously dispatch" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var s = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer s.deinit();

    // Build a non-attestation cell — same payload shape as the
    // attestation test, but with a different domain_flag at offset 24.
    // The bytes at offset 256..288 happen to look like a hash, but they
    // must NOT be interpreted as a targetCellId for dispatch purposes.
    const decoy_target: [32]u8 = [_]u8{0xDE} ** 32;
    var cell: [cell_store.CELL_BYTES]u8 = undefined;
    @memset(&cell, 0x33);
    // A plausibly-real domain flag from a different page (oddjobz page,
    // not anchor-attestation).
    std.mem.writeInt(u32, cell[OFFSET_DOMAIN_FLAG..][0..4], 0x000101FF, .little);
    @memcpy(cell[OFFSET_PAYLOAD_TARGET_CELL_ID..][0..32], &decoy_target);

    const hash = try s.store().put(&cell);

    // Neither the cell's own hash nor the bytes that would have been
    // interpreted as a targetCellId have an anchor entry — the
    // dispatch only fires on the exact attestation domain_flag.
    try std.testing.expectEqual(
        @as(?lmdb_cell_store.AnchorStatus, null),
        s.getAnchorStatus(&hash),
    );
    try std.testing.expectEqual(
        @as(?lmdb_cell_store.AnchorStatus, null),
        s.getAnchorStatus(&decoy_target),
    );
}

test "D-LC5 follow-up: re-storing the same attestation is idempotent" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var s = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer s.deinit();

    const target_hash: [32]u8 = [_]u8{0xB7} ** 32;
    const att_cell = makeAttestationCell(target_hash, 0x42);

    // First put: status becomes .confirmed.
    const first_hash = try s.store().put(&att_cell);
    try std.testing.expectEqual(
        @as(?lmdb_cell_store.AnchorStatus, .confirmed),
        s.getAnchorStatus(&target_hash),
    );

    // Second put of the exact same bytes: hits the doPut idempotent
    // path (cell already present in primary DB). Status stays
    // .confirmed; no error.
    const second_hash = try s.store().put(&att_cell);
    try std.testing.expectEqualSlices(u8, &first_hash, &second_hash);
    try std.testing.expectEqual(
        @as(?lmdb_cell_store.AnchorStatus, .confirmed),
        s.getAnchorStatus(&target_hash),
    );
}

test "D-LC5 follow-up: attestation confirmation overrides prior pending" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var s = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer s.deinit();

    // The target cell exists and is marked pending (the typical
    // speculative-mint flow: cell stored, anchor TX submitted, waiting
    // for the attestation to land).
    const target_cell = makeCell(0x99);
    const target_hash = try s.store().put(&target_cell);
    try s.setAnchorStatus(&target_hash, .pending);
    try std.testing.expectEqual(
        @as(?lmdb_cell_store.AnchorStatus, .pending),
        s.getAnchorStatus(&target_hash),
    );

    // Now the attestation lands. The observer should flip pending →
    // confirmed.
    const att_cell = makeAttestationCell(target_hash, 0xC0);
    _ = try s.store().put(&att_cell);

    try std.testing.expectEqual(
        @as(?lmdb_cell_store.AnchorStatus, .confirmed),
        s.getAnchorStatus(&target_hash),
    );
}

// ── D-LC5 follow-up: reorg-sweep substrate ───────────────────────────
//
// `cells_by_anchor_txid` reverse index + `sweepPendingAnchors` give the
// cartridge reorg hook (separate PR) the substrate it needs: look up
// every cell anchored by a (reorged-away) txid in one cursor scan, and
// roll back only the `.pending` projections. `.confirmed` entries are
// preserved across reorg — past finality requires explicit
// invalidation. See deliverables.yml D-LC5 for the design note.

test "D-LC5 reorg-sweep: cellsByAnchorTxid returns targets for one txid, omits others" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var s = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer s.deinit();

    const txid_a: [32]u8 = [_]u8{0xA0} ** 32;
    const txid_b: [32]u8 = [_]u8{0xB0} ** 32;

    const target_a1: [32]u8 = [_]u8{0x11} ** 32;
    const target_a2: [32]u8 = [_]u8{0x12} ** 32;
    const target_b1: [32]u8 = [_]u8{0x21} ** 32;

    // Two attestations against txid_a (different targets), one against
    // txid_b. The attestation cells themselves get different fill bytes
    // so their content hashes differ — same target+txid pair is fine
    // because the index key is (op_pkh, txid, target_hash) so it would
    // collapse to the same entry anyway.
    _ = try s.store().put(&makeAttestationCellWithTxid(target_a1, txid_a, 0x01));
    _ = try s.store().put(&makeAttestationCellWithTxid(target_a2, txid_a, 0x02));
    _ = try s.store().put(&makeAttestationCellWithTxid(target_b1, txid_b, 0x03));

    const got_a = try s.cellsByAnchorTxid(allocator, &txid_a);
    defer allocator.free(got_a);
    try std.testing.expectEqual(@as(usize, 2), got_a.len);
    try std.testing.expect(containsHash(got_a, target_a1));
    try std.testing.expect(containsHash(got_a, target_a2));
    try std.testing.expect(!containsHash(got_a, target_b1));

    const got_b = try s.cellsByAnchorTxid(allocator, &txid_b);
    defer allocator.free(got_b);
    try std.testing.expectEqual(@as(usize, 1), got_b.len);
    try std.testing.expect(containsHash(got_b, target_b1));

    // A txid that was never anchored returns an empty slice.
    const txid_unseen: [32]u8 = [_]u8{0xFE} ** 32;
    const got_unseen = try s.cellsByAnchorTxid(allocator, &txid_unseen);
    defer allocator.free(got_unseen);
    try std.testing.expectEqual(@as(usize, 0), got_unseen.len);
}

test "D-LC5 reorg-sweep: cellsByAnchorTxid is op_pkh-scoped" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    const pkh_a: [8]u8 = [_]u8{ 0xAA, 0, 0, 0, 0, 0, 0, 0 };
    const pkh_b: [8]u8 = [_]u8{ 0xBB, 0, 0, 0, 0, 0, 0, 0 };

    var store_a = try lmdb_cell_store.LmdbCellStore.initForOperator(&env, allocator, pkh_a);
    defer store_a.deinit();
    var store_b = try lmdb_cell_store.LmdbCellStore.initForOperator(&env, allocator, pkh_b);
    defer store_b.deinit();

    const txid: [32]u8 = [_]u8{0xCC} ** 32;
    const target_in_a: [32]u8 = [_]u8{0xA1} ** 32;
    const target_in_b: [32]u8 = [_]u8{0xB1} ** 32;

    _ = try store_a.store().put(&makeAttestationCellWithTxid(target_in_a, txid, 0x55));
    _ = try store_b.store().put(&makeAttestationCellWithTxid(target_in_b, txid, 0x66));

    // Operator A sees only its own target; operator B sees only its own.
    const got_a = try store_a.cellsByAnchorTxid(allocator, &txid);
    defer allocator.free(got_a);
    try std.testing.expectEqual(@as(usize, 1), got_a.len);
    try std.testing.expect(containsHash(got_a, target_in_a));
    try std.testing.expect(!containsHash(got_a, target_in_b));

    const got_b = try store_b.cellsByAnchorTxid(allocator, &txid);
    defer allocator.free(got_b);
    try std.testing.expectEqual(@as(usize, 1), got_b.len);
    try std.testing.expect(containsHash(got_b, target_in_b));
    try std.testing.expect(!containsHash(got_b, target_in_a));
}

test "D-LC5 reorg-sweep: sweepPendingAnchors clears pending, leaves confirmed, returns accurate counts" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var s = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer s.deinit();

    const txid: [32]u8 = [_]u8{0x77} ** 32;

    // Three target cells anchored by the same txid. Two are .pending
    // (speculative mint, anchor TX not yet final); one was already
    // confirmed by a prior attestation but somehow the same txid binds
    // it too (e.g. the reverse index recorded both attestations).
    const target_pending_1: [32]u8 = [_]u8{0x11} ** 32;
    const target_pending_2: [32]u8 = [_]u8{0x22} ** 32;
    const target_confirmed: [32]u8 = [_]u8{0x33} ** 32;

    _ = try s.store().put(&makeAttestationCellWithTxid(target_pending_1, txid, 0xAA));
    _ = try s.store().put(&makeAttestationCellWithTxid(target_pending_2, txid, 0xAB));
    _ = try s.store().put(&makeAttestationCellWithTxid(target_confirmed, txid, 0xAC));

    // Override the attestation observer's .confirmed default on the
    // first two targets so they look like .pending speculations at the
    // time of the sweep. The third target stays .confirmed (the state
    // doPut left it in).
    try s.setAnchorStatus(&target_pending_1, .pending);
    try s.setAnchorStatus(&target_pending_2, .pending);

    try std.testing.expectEqual(
        @as(?lmdb_cell_store.AnchorStatus, .pending),
        s.getAnchorStatus(&target_pending_1),
    );
    try std.testing.expectEqual(
        @as(?lmdb_cell_store.AnchorStatus, .confirmed),
        s.getAnchorStatus(&target_confirmed),
    );

    const result = try s.sweepPendingAnchors(&txid);
    try std.testing.expectEqual(@as(u32, 2), result.swept);
    try std.testing.expectEqual(@as(u32, 1), result.kept);

    // Pending entries are now absent (cleared).
    try std.testing.expectEqual(
        @as(?lmdb_cell_store.AnchorStatus, null),
        s.getAnchorStatus(&target_pending_1),
    );
    try std.testing.expectEqual(
        @as(?lmdb_cell_store.AnchorStatus, null),
        s.getAnchorStatus(&target_pending_2),
    );
    // Confirmed entry survives the reorg sweep — past finality requires
    // explicit invalidation.
    try std.testing.expectEqual(
        @as(?lmdb_cell_store.AnchorStatus, .confirmed),
        s.getAnchorStatus(&target_confirmed),
    );
}

test "D-LC5 reorg-sweep: sweepPendingAnchors is idempotent" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var s = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer s.deinit();

    const txid: [32]u8 = [_]u8{0x88} ** 32;
    const target: [32]u8 = [_]u8{0x99} ** 32;

    _ = try s.store().put(&makeAttestationCellWithTxid(target, txid, 0x12));
    try s.setAnchorStatus(&target, .pending);

    const first = try s.sweepPendingAnchors(&txid);
    try std.testing.expectEqual(@as(u32, 1), first.swept);
    try std.testing.expectEqual(@as(u32, 0), first.kept);

    // Second call on the same txid: nothing left to sweep. The reverse
    // index still has the entry (attestation cell preserved as
    // historical record), but the projection it pointed at is already
    // cleared, so the iteration walks one entry whose status is now
    // null — that falls through the `orelse .confirmed` path and counts
    // as `kept`. Either way the operation is safe to re-run.
    const second = try s.sweepPendingAnchors(&txid);
    try std.testing.expectEqual(@as(u32, 0), second.swept);
    // Status is null after the first sweep, so the second sweep sees
    // one reverse-index entry that maps to a now-absent projection and
    // counts it as kept (nothing to clear).
    try std.testing.expectEqual(@as(u32, 1), second.kept);
}

test "D-LC5 reorg-sweep: sweepPendingAnchors does not touch unrelated txids" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var s = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer s.deinit();

    const txid_doomed: [32]u8 = [_]u8{0xDD} ** 32; // the one being reorged away
    const txid_safe: [32]u8 = [_]u8{0xEE} ** 32; // a sibling that should be untouched

    const target_doomed: [32]u8 = [_]u8{0x01} ** 32;
    const target_safe: [32]u8 = [_]u8{0x02} ** 32;

    _ = try s.store().put(&makeAttestationCellWithTxid(target_doomed, txid_doomed, 0x70));
    _ = try s.store().put(&makeAttestationCellWithTxid(target_safe, txid_safe, 0x71));

    try s.setAnchorStatus(&target_doomed, .pending);
    try s.setAnchorStatus(&target_safe, .pending);

    const result = try s.sweepPendingAnchors(&txid_doomed);
    try std.testing.expectEqual(@as(u32, 1), result.swept);
    try std.testing.expectEqual(@as(u32, 0), result.kept);

    // Doomed target's pending projection is cleared.
    try std.testing.expectEqual(
        @as(?lmdb_cell_store.AnchorStatus, null),
        s.getAnchorStatus(&target_doomed),
    );
    // Safe target's pending projection is untouched — the sweep is
    // scoped strictly to the txid passed in.
    try std.testing.expectEqual(
        @as(?lmdb_cell_store.AnchorStatus, .pending),
        s.getAnchorStatus(&target_safe),
    );
}

// ── D-LC3 follow-up: backfillSecondaryIndices ────────────────────────
//
// `backfillSecondaryIndices` walks the primary `cells` sub-DB and
// populates every secondary index (cells_by_owner, cells_by_prev_state,
// cells_anchor_status, cells_by_anchor_txid) for cells already on disk.
// Covers the "wrote-before-the-index-existed" case that doPut's
// opportunistic backfill only fixes when the same cell is re-put.
//
// To simulate that pre-existing state, the tests bypass `store().put()`
// and write straight to the primary `cells` LMDB sub-DB via a raw
// LMDB txn. This produces the exact state the migration is designed
// to repair: a populated primary, empty secondaries.

const CELL_BYTES_LOCAL: usize = cell_store.CELL_BYTES;
const VALUE_BYTES_LOCAL: usize = cell_store.VALUE_BYTES;

fn rawInsertCellBypassingDoPut(
    s: *lmdb_cell_store.LmdbCellStore,
    cell: *const [CELL_BYTES_LOCAL]u8,
) ![32]u8 {
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(cell, &hash, .{});

    // 40-byte primary key: op_pkh(8) ‖ hash(32). Same layout the store
    // uses internally — bypassing doPut means the secondary indices
    // are NOT touched, exactly the pre-D-LC3 state we need.
    var key: [lmdb_cell_store.OP_PKH_BYTES + 32]u8 = undefined;
    @memcpy(key[0..lmdb_cell_store.OP_PKH_BYTES], &s.op_pkh);
    @memcpy(key[lmdb_cell_store.OP_PKH_BYTES..], &hash);

    var padded: [VALUE_BYTES_LOCAL]u8 = [_]u8{0} ** VALUE_BYTES_LOCAL;
    @memcpy(padded[0..CELL_BYTES_LOCAL], cell);

    var txn = try s.env.beginTxn(.read_write);
    errdefer txn.abort();
    try txn.put(s.dbi, &key, &padded, .{});
    try txn.commit();
    return hash;
}

fn makeCellWithOwnerAndPrev(fill: u8, owner_id: [16]u8, prev_state: [32]u8) [CELL_BYTES_LOCAL]u8 {
    var c: [CELL_BYTES_LOCAL]u8 = undefined;
    @memset(&c, fill);
    @memcpy(c[62 .. 62 + 16], &owner_id);
    @memcpy(c[128 .. 128 + 32], &prev_state);
    return c;
}

test "D-LC3 follow-up: backfill populates indices for pre-existing cells" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var s = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer s.deinit();

    const owner: [16]u8 = [_]u8{0xAA} ** 16;
    const prev: [32]u8 = [_]u8{0x11} ** 32;

    // Insert two cells directly into the primary DB — secondary indices
    // are NOT touched, simulating the pre-D-LC3 disk state.
    const cell_1 = makeCellWithOwnerAndPrev(0x01, owner, prev);
    const cell_2 = makeCellWithOwnerAndPrev(0x02, owner, prev);
    const h1 = try rawInsertCellBypassingDoPut(&s, &cell_1);
    const h2 = try rawInsertCellBypassingDoPut(&s, &cell_2);

    // Pre-backfill: the secondary indices return nothing for these
    // owner / prev_state values. Confirms our bypass actually worked.
    {
        const pre = try s.cellsByOwner(allocator, &owner);
        defer allocator.free(pre);
        try std.testing.expectEqual(@as(usize, 0), pre.len);
    }
    {
        const pre = try s.cellsByPrevState(allocator, &prev);
        defer allocator.free(pre);
        try std.testing.expectEqual(@as(usize, 0), pre.len);
    }

    const report = try s.backfillSecondaryIndices();
    try std.testing.expectEqual(@as(u32, 2), report.cells_visited);
    try std.testing.expectEqual(@as(u32, 2), report.owner_index_writes);
    try std.testing.expectEqual(@as(u32, 2), report.prev_state_index_writes);
    // Neither cell is an attestation cell (default domain_flag from
    // fill byte ≠ 0x0001FE02), so anchor counters stay at zero.
    try std.testing.expectEqual(@as(u32, 0), report.anchor_status_writes);
    try std.testing.expectEqual(@as(u32, 0), report.anchor_txid_index_writes);

    // Post-backfill: secondaries now return the expected hashes.
    const owner_view = try s.cellsByOwner(allocator, &owner);
    defer allocator.free(owner_view);
    try std.testing.expectEqual(@as(usize, 2), owner_view.len);
    try std.testing.expect(containsHash(owner_view, h1));
    try std.testing.expect(containsHash(owner_view, h2));

    const prev_view = try s.cellsByPrevState(allocator, &prev);
    defer allocator.free(prev_view);
    try std.testing.expectEqual(@as(usize, 2), prev_view.len);
    try std.testing.expect(containsHash(prev_view, h1));
    try std.testing.expect(containsHash(prev_view, h2));
}

test "D-LC3 follow-up: backfill is idempotent" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var s = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer s.deinit();

    const owner: [16]u8 = [_]u8{0x55} ** 16;
    const prev: [32]u8 = [_]u8{0x66} ** 32;
    const cell = makeCellWithOwnerAndPrev(0x77, owner, prev);
    _ = try rawInsertCellBypassingDoPut(&s, &cell);

    const r1 = try s.backfillSecondaryIndices();
    try std.testing.expectEqual(@as(u32, 1), r1.cells_visited);
    try std.testing.expectEqual(@as(u32, 1), r1.owner_index_writes);

    // Second invocation: same visit counts (the migration walks every
    // primary cell every time), but the underlying LMDB puts are
    // no-ops because the key+empty-value entries already exist. The
    // post-state must match the post-state of the first run exactly.
    const r2 = try s.backfillSecondaryIndices();
    try std.testing.expectEqual(@as(u32, 1), r2.cells_visited);
    try std.testing.expectEqual(@as(u32, 1), r2.owner_index_writes);
    try std.testing.expectEqual(@as(u32, 1), r2.prev_state_index_writes);

    // Index views match expectations — no duplicates introduced.
    const owner_view = try s.cellsByOwner(allocator, &owner);
    defer allocator.free(owner_view);
    try std.testing.expectEqual(@as(usize, 1), owner_view.len);

    const prev_view = try s.cellsByPrevState(allocator, &prev);
    defer allocator.free(prev_view);
    try std.testing.expectEqual(@as(usize, 1), prev_view.len);
}

test "D-LC3 follow-up: backfill is operator-scoped" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    const pkh_a: [lmdb_cell_store.OP_PKH_BYTES]u8 = [_]u8{0xAA} ** lmdb_cell_store.OP_PKH_BYTES;
    const pkh_b: [lmdb_cell_store.OP_PKH_BYTES]u8 = [_]u8{0xBB} ** lmdb_cell_store.OP_PKH_BYTES;

    var sa = try lmdb_cell_store.LmdbCellStore.initForOperator(&env, allocator, pkh_a);
    defer sa.deinit();
    var sb = try lmdb_cell_store.LmdbCellStore.initForOperator(&env, allocator, pkh_b);
    defer sb.deinit();

    const owner_shared: [16]u8 = [_]u8{0xCC} ** 16;
    const prev_shared: [32]u8 = [_]u8{0xDD} ** 32;

    // Raw-insert distinct cells under each operator's prefix; neither
    // store's secondary indices are populated yet.
    _ = try rawInsertCellBypassingDoPut(&sa, &makeCellWithOwnerAndPrev(0x01, owner_shared, prev_shared));
    _ = try rawInsertCellBypassingDoPut(&sb, &makeCellWithOwnerAndPrev(0x02, owner_shared, prev_shared));

    // Backfill only operator A. Operator B's indices must remain empty.
    const report_a = try sa.backfillSecondaryIndices();
    try std.testing.expectEqual(@as(u32, 1), report_a.cells_visited);
    try std.testing.expectEqual(@as(u32, 1), report_a.owner_index_writes);

    const a_owner_view = try sa.cellsByOwner(allocator, &owner_shared);
    defer allocator.free(a_owner_view);
    try std.testing.expectEqual(@as(usize, 1), a_owner_view.len);

    const b_owner_view = try sb.cellsByOwner(allocator, &owner_shared);
    defer allocator.free(b_owner_view);
    try std.testing.expectEqual(@as(usize, 0), b_owner_view.len);

    const a_prev_view = try sa.cellsByPrevState(allocator, &prev_shared);
    defer allocator.free(a_prev_view);
    try std.testing.expectEqual(@as(usize, 1), a_prev_view.len);

    const b_prev_view = try sb.cellsByPrevState(allocator, &prev_shared);
    defer allocator.free(b_prev_view);
    try std.testing.expectEqual(@as(usize, 0), b_prev_view.len);
}

test "D-LC3 follow-up: backfill correctly identifies attestation cells" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var s = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer s.deinit();

    const target: [32]u8 = [_]u8{0x42} ** 32;
    const txid: [32]u8 = [_]u8{0x43} ** 32;

    // Raw-insert an anchor-attestation cell (domain_flag = 0x0001FE02
    // at offset 24; targetCellId at 256; txid at 288). Bypassing
    // doPut means the projection AND the reverse index entry are
    // missing — exactly what backfill is supposed to repair.
    const cell = makeAttestationCellWithTxid(target, txid, 0xFE);
    const att_hash = try rawInsertCellBypassingDoPut(&s, &cell);

    // Pre-state: no projection for the target, no reverse-index entry.
    try std.testing.expectEqual(@as(?lmdb_cell_store.AnchorStatus, null), s.getAnchorStatus(&target));
    {
        const pre = try s.cellsByAnchorTxid(allocator, &txid);
        defer allocator.free(pre);
        try std.testing.expectEqual(@as(usize, 0), pre.len);
    }

    const report = try s.backfillSecondaryIndices();
    try std.testing.expectEqual(@as(u32, 1), report.cells_visited);
    try std.testing.expectEqual(@as(u32, 1), report.owner_index_writes);
    try std.testing.expectEqual(@as(u32, 1), report.prev_state_index_writes);
    try std.testing.expectEqual(@as(u32, 1), report.anchor_status_writes);
    try std.testing.expectEqual(@as(u32, 1), report.anchor_txid_index_writes);

    // The attestation cell's existence on disk implies its txid was
    // observed at mint time — backfill writes .confirmed accordingly.
    try std.testing.expectEqual(
        @as(?lmdb_cell_store.AnchorStatus, .confirmed),
        s.getAnchorStatus(&target),
    );
    // Reverse index now resolves txid → target.
    const txid_view = try s.cellsByAnchorTxid(allocator, &txid);
    defer allocator.free(txid_view);
    try std.testing.expectEqual(@as(usize, 1), txid_view.len);
    try std.testing.expect(containsHash(txid_view, target));
    // The attestation cell itself is recorded in cellsByOwner under
    // whatever owner_id its fill byte produced (here 0xFE repeated 16
    // times), confirming the owner-index write counted.
    const att_owner: [16]u8 = [_]u8{0xFE} ** 16;
    const owner_view = try s.cellsByOwner(allocator, &att_owner);
    defer allocator.free(owner_view);
    try std.testing.expect(containsHash(owner_view, att_hash));
}

test "D-LC3 follow-up: non-attestation cells do not get anchor entries" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var s = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer s.deinit();

    // Build a cell whose domain_flag (offset 24) is something OTHER
    // than the canonical anchor-attestation value 0x0001FE02. We
    // pick 0x0001FE01 (COMMERCE_V1 per constants.json) — a real
    // dispatch value but not the attestation one.
    const owner: [16]u8 = [_]u8{0x99} ** 16;
    const prev: [32]u8 = [_]u8{0x88} ** 32;
    var cell = makeCellWithOwnerAndPrev(0x77, owner, prev);
    std.mem.writeInt(u32, cell[OFFSET_DOMAIN_FLAG..][0..4], 0x0001FE01, .little);

    const hash = try rawInsertCellBypassingDoPut(&s, &cell);

    const report = try s.backfillSecondaryIndices();
    try std.testing.expectEqual(@as(u32, 1), report.cells_visited);
    // Owner and prev-state index entries are written for every cell
    // regardless of domain_flag.
    try std.testing.expectEqual(@as(u32, 1), report.owner_index_writes);
    try std.testing.expectEqual(@as(u32, 1), report.prev_state_index_writes);
    // Anchor counters stay zero because the domain_flag isn't the
    // canonical attestation value — the dispatch correctly skipped.
    try std.testing.expectEqual(@as(u32, 0), report.anchor_status_writes);
    try std.testing.expectEqual(@as(u32, 0), report.anchor_txid_index_writes);

    // No projection entry was written, even reading the cell's own
    // hash back returns null status.
    try std.testing.expectEqual(@as(?lmdb_cell_store.AnchorStatus, null), s.getAnchorStatus(&hash));

    // Owner / prev indices are populated as for any other cell.
    const owner_view = try s.cellsByOwner(allocator, &owner);
    defer allocator.free(owner_view);
    try std.testing.expectEqual(@as(usize, 1), owner_view.len);
    const prev_view = try s.cellsByPrevState(allocator, &prev);
    defer allocator.free(prev_view);
    try std.testing.expectEqual(@as(usize, 1), prev_view.len);
}
// ── CellStore vtable promotion round-trips ──────────────────────────
//
// The eight methods below were promoted from `LmdbCellStore` direct
// methods to the `CellStore` vtable. The direct methods remain on the
// impl (back-compat for callers that still hold *LmdbCellStore), but
// the vtable path is the canonical seam for read-path callers
// (reactor.zig, future federated backings). Each test below exercises
// the vtable wrapper path AND asserts it agrees with the direct call,
// so the seam can't silently drift from the impl.

test "vtable: getCell round-trip matches direct getCell" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var s = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer s.deinit();
    const vt = s.store();

    const cell = makeCell(0x4C);
    const hash = try vt.put(&cell);

    const via_vt = try vt.getCell(&hash);
    const via_direct = try s.getCell(&hash);
    try std.testing.expect(via_vt != null);
    try std.testing.expect(via_direct != null);
    try std.testing.expectEqualSlices(u8, &cell, &via_vt.?);
    try std.testing.expectEqualSlices(u8, &via_direct.?, &via_vt.?);

    // Unknown hash: both paths return null.
    var miss = hash;
    miss[0] ^= 0xFF;
    try std.testing.expectEqual(@as(?[cell_store.CELL_BYTES]u8, null), try vt.getCell(&miss));
}

test "vtable: cellsByOwner round-trip matches direct call" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var s = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer s.deinit();
    const vt = s.store();

    const owner: [16]u8 = [_]u8{0x7A} ** 16;
    _ = try vt.put(&makeCellWithOwner(0x01, owner));
    _ = try vt.put(&makeCellWithOwner(0x02, owner));

    const via_vt = try vt.cellsByOwner(allocator, &owner);
    defer allocator.free(via_vt);
    const via_direct = try s.cellsByOwner(allocator, &owner);
    defer allocator.free(via_direct);

    try std.testing.expectEqual(@as(usize, 2), via_vt.len);
    try std.testing.expectEqual(via_direct.len, via_vt.len);
    // Both paths walk the same cursor → same lexicographic order.
    for (via_vt, via_direct) |a, b| try std.testing.expectEqualSlices(u8, &a, &b);
}

test "vtable: cellsByPrevState round-trip matches direct call" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var s = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer s.deinit();
    const vt = s.store();

    const root: [32]u8 = [_]u8{0xC1} ** 32;
    _ = try vt.put(&makeCellWithPrevState(0x11, root));
    _ = try vt.put(&makeCellWithPrevState(0x22, root));

    const via_vt = try vt.cellsByPrevState(allocator, &root);
    defer allocator.free(via_vt);
    const via_direct = try s.cellsByPrevState(allocator, &root);
    defer allocator.free(via_direct);

    try std.testing.expectEqual(@as(usize, 2), via_vt.len);
    try std.testing.expectEqual(via_direct.len, via_vt.len);
    for (via_vt, via_direct) |a, b| try std.testing.expectEqualSlices(u8, &a, &b);
}

test "vtable: cellsByAnchorTxid round-trip matches direct call" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var s = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer s.deinit();
    const vt = s.store();

    const txid: [32]u8 = [_]u8{0xD0} ** 32;
    const target_a: [32]u8 = [_]u8{0x01} ** 32;
    const target_b: [32]u8 = [_]u8{0x02} ** 32;
    _ = try vt.put(&makeAttestationCellWithTxid(target_a, txid, 0x90));
    _ = try vt.put(&makeAttestationCellWithTxid(target_b, txid, 0x91));

    const via_vt = try vt.cellsByAnchorTxid(allocator, &txid);
    defer allocator.free(via_vt);
    const via_direct = try s.cellsByAnchorTxid(allocator, &txid);
    defer allocator.free(via_direct);

    try std.testing.expectEqual(@as(usize, 2), via_vt.len);
    try std.testing.expectEqual(via_direct.len, via_vt.len);
    try std.testing.expect(containsHash(via_vt, target_a));
    try std.testing.expect(containsHash(via_vt, target_b));
}

test "vtable: setAnchorStatus / getAnchorStatus round-trip matches direct call" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var s = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer s.deinit();
    const vt = s.store();

    const hash = try vt.put(&makeCell(0x5E));

    // Default: absent on both paths.
    try std.testing.expectEqual(@as(?cell_store.AnchorStatus, null), vt.getAnchorStatus(&hash));
    try std.testing.expectEqual(@as(?cell_store.AnchorStatus, null), s.getAnchorStatus(&hash));

    // Set via vtable; read via both — must agree.
    try vt.setAnchorStatus(&hash, .pending);
    try std.testing.expectEqual(@as(?cell_store.AnchorStatus, .pending), vt.getAnchorStatus(&hash));
    try std.testing.expectEqual(@as(?cell_store.AnchorStatus, .pending), s.getAnchorStatus(&hash));

    // Set to confirmed via direct; read via vtable — still agrees.
    try s.setAnchorStatus(&hash, .confirmed);
    try std.testing.expectEqual(@as(?cell_store.AnchorStatus, .confirmed), vt.getAnchorStatus(&hash));
}

test "vtable: clearAnchorStatus round-trip matches direct call" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var s = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer s.deinit();
    const vt = s.store();

    const hash = try vt.put(&makeCell(0x6F));
    try vt.setAnchorStatus(&hash, .pending);

    // Clear via vtable; both reads agree.
    try vt.clearAnchorStatus(&hash);
    try std.testing.expectEqual(@as(?cell_store.AnchorStatus, null), vt.getAnchorStatus(&hash));
    try std.testing.expectEqual(@as(?cell_store.AnchorStatus, null), s.getAnchorStatus(&hash));

    // Idempotent: clearing a cell with no entry is a no-op via vtable.
    try vt.clearAnchorStatus(&hash);
    try std.testing.expectEqual(@as(?cell_store.AnchorStatus, null), vt.getAnchorStatus(&hash));
}

test "vtable: sweepPendingAnchors round-trip matches direct call" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var s = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer s.deinit();
    const vt = s.store();

    const txid: [32]u8 = [_]u8{0xE7} ** 32;
    const target_pending: [32]u8 = [_]u8{0x10} ** 32;
    const target_confirmed: [32]u8 = [_]u8{0x20} ** 32;

    _ = try vt.put(&makeAttestationCellWithTxid(target_pending, txid, 0xA0));
    _ = try vt.put(&makeAttestationCellWithTxid(target_confirmed, txid, 0xA1));
    try vt.setAnchorStatus(&target_pending, .pending);
    // target_confirmed keeps the attestation-observer default (.confirmed).

    const via_vt = try vt.sweepPendingAnchors(&txid);
    try std.testing.expectEqual(@as(u32, 1), via_vt.swept);
    try std.testing.expectEqual(@as(u32, 1), via_vt.kept);

    // After the sweep:
    //   pending → cleared (null)
    //   confirmed → preserved
    try std.testing.expectEqual(@as(?cell_store.AnchorStatus, null), vt.getAnchorStatus(&target_pending));
    try std.testing.expectEqual(@as(?cell_store.AnchorStatus, .confirmed), vt.getAnchorStatus(&target_confirmed));

    // Direct call on the now-quiesced state: swept == 0; the reverse-index
    // entries still walk, and both targets now read as either null or
    // .confirmed — both fall into the `kept` branch.
    const via_direct = try s.sweepPendingAnchors(&txid);
    try std.testing.expectEqual(@as(u32, 0), via_direct.swept);
    try std.testing.expectEqual(@as(u32, 2), via_direct.kept);
}

test "vtable: re-exported AnchorStatus type is identical to vtable type" {
    // Compile-time guarantee: the LMDB impl module re-exports the canonical
    // CellStore.AnchorStatus, so old call sites (which write
    // `lmdb_cell_store.AnchorStatus`) and new ones (`cell_store.AnchorStatus`)
    // refer to the exact same type. This protects the back-compat alias from
    // drifting silently if the impl is later refactored.
    try std.testing.expect(lmdb_cell_store.AnchorStatus == cell_store.AnchorStatus);
    try std.testing.expect(lmdb_cell_store.LmdbCellStore.SweepResult == cell_store.SweepResult);
    // Schema-v2 substrate: the impl module re-exports
    // cell_store.AnchorHeightEntry so both call shapes refer to the
    // same nominal type.
    try std.testing.expect(lmdb_cell_store.LmdbCellStore.AnchorHeightEntry == cell_store.AnchorHeightEntry);
}

// ── Anchor-attestation schema v2: height-keyed reorg substrate ──────
//
// Schema v2 retires the v1 `bumpHash` field (BRC-74 BUMP carries
// `blockHeight` natively, not a 24B Merkle-root variant) and promotes
// `anchor_height: u64` to a first-class queryable field at payload
// offset 64 → cell offset 320 (HEADER_SIZE 256 + payload offset 64).
// LMDB key for the new `cells_by_anchor_height` reverse index is
// `op_pkh(8B) ‖ BE(anchor_height)(8B) ‖ target_cell_hash(32B) = 48B`.
// Big-endian encoding of `anchor_height` in the KEY is what makes
// lex-sort match numeric sort, enabling the height-range cursor scan
// behind `cellsByAnchorHeightRange` / `sweepReorgedFromHeight`.

/// Build an anchor-attestation cell (schema v2) with explicit
/// (target_cell_id, txid, anchor_height). `fill` differentiates content
/// hashes across calls when the (target, txid, height) tuple repeats.
fn makeAttestationCellV2(
    target_cell_id: [32]u8,
    txid: [32]u8,
    anchor_height: u64,
    fill: u8,
) [cell_store.CELL_BYTES]u8 {
    var c: [cell_store.CELL_BYTES]u8 = undefined;
    @memset(&c, fill);
    std.mem.writeInt(u32, c[OFFSET_DOMAIN_FLAG..][0..4], ATTESTATION_DOMAIN_FLAG, .little);
    @memcpy(c[OFFSET_PAYLOAD_TARGET_CELL_ID..][0..32], &target_cell_id);
    @memcpy(c[OFFSET_PAYLOAD_TXID..][0..32], &txid);
    // Payload offset 64 → cell offset 320 — anchor_height is u64 LE
    // in the cell payload; the LMDB index key separately re-encodes
    // it as BE.
    std.mem.writeInt(u64, c[320..][0..8], anchor_height, .little);
    return c;
}

/// Linear-search helper for the (height, cell_hash) result set.
fn containsHeightEntry(
    haystack: []const cell_store.AnchorHeightEntry,
    height: u64,
    needle: [32]u8,
) bool {
    for (haystack) |e| {
        if (e.height == height and std.mem.eql(u8, &e.cell_hash, &needle)) return true;
    }
    return false;
}

test "schema v2: cellsByAnchorHeightRange returns attestations in inclusive range, ordered by ascending height" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var s = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer s.deinit();

    // Three attestations spanning heights {100, 200, 250, 400}. The
    // range query [200, 300] should return exactly the middle two,
    // ordered ascending by height.
    const txid: [32]u8 = [_]u8{0xCC} ** 32;
    const t_below: [32]u8 = [_]u8{0x11} ** 32; // height 100, below range
    const t_low: [32]u8 = [_]u8{0x22} ** 32;   // height 200, lower bound
    const t_mid: [32]u8 = [_]u8{0x33} ** 32;   // height 250, in range
    const t_above: [32]u8 = [_]u8{0x44} ** 32; // height 400, above range

    _ = try s.store().put(&makeAttestationCellV2(t_below, txid, 100, 0xA0));
    _ = try s.store().put(&makeAttestationCellV2(t_low, txid, 200, 0xA1));
    _ = try s.store().put(&makeAttestationCellV2(t_mid, txid, 250, 0xA2));
    _ = try s.store().put(&makeAttestationCellV2(t_above, txid, 400, 0xA3));

    const got = try s.cellsByAnchorHeightRange(allocator, 200, 300);
    defer allocator.free(got);

    try std.testing.expectEqual(@as(usize, 2), got.len);
    // BE key encoding gives lex-sort == numeric-sort, so the iteration
    // order is ascending by height: 200 first, then 250.
    try std.testing.expectEqual(@as(u64, 200), got[0].height);
    try std.testing.expectEqualSlices(u8, &t_low, &got[0].cell_hash);
    try std.testing.expectEqual(@as(u64, 250), got[1].height);
    try std.testing.expectEqualSlices(u8, &t_mid, &got[1].cell_hash);

    // An empty range (low > high) returns an empty slice.
    const empty = try s.cellsByAnchorHeightRange(allocator, 500, 400);
    defer allocator.free(empty);
    try std.testing.expectEqual(@as(usize, 0), empty.len);
}

test "schema v2: cellsByAnchorHeightRange is operator-scoped" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    const pkh_a: [8]u8 = [_]u8{ 0xAA, 0, 0, 0, 0, 0, 0, 0 };
    const pkh_b: [8]u8 = [_]u8{ 0xBB, 0, 0, 0, 0, 0, 0, 0 };

    var store_a = try lmdb_cell_store.LmdbCellStore.initForOperator(&env, allocator, pkh_a);
    defer store_a.deinit();
    var store_b = try lmdb_cell_store.LmdbCellStore.initForOperator(&env, allocator, pkh_b);
    defer store_b.deinit();

    const txid: [32]u8 = [_]u8{0xDD} ** 32;
    const target_in_a: [32]u8 = [_]u8{0xA1} ** 32;
    const target_in_b: [32]u8 = [_]u8{0xB1} ** 32;

    // Both operators record an attestation at the same height.
    _ = try store_a.store().put(&makeAttestationCellV2(target_in_a, txid, 1234, 0x55));
    _ = try store_b.store().put(&makeAttestationCellV2(target_in_b, txid, 1234, 0x66));

    const got_a = try store_a.cellsByAnchorHeightRange(allocator, 0, 9999);
    defer allocator.free(got_a);
    try std.testing.expectEqual(@as(usize, 1), got_a.len);
    try std.testing.expect(containsHeightEntry(got_a, 1234, target_in_a));
    // Operator A cannot see operator B's attestation at the same height.
    try std.testing.expect(!containsHeightEntry(got_a, 1234, target_in_b));

    const got_b = try store_b.cellsByAnchorHeightRange(allocator, 0, 9999);
    defer allocator.free(got_b);
    try std.testing.expectEqual(@as(usize, 1), got_b.len);
    try std.testing.expect(containsHeightEntry(got_b, 1234, target_in_b));
    try std.testing.expect(!containsHeightEntry(got_b, 1234, target_in_a));
}

test "schema v2: sweepReorgedFromHeight clears pending at-or-above floor, leaves confirmed, returns counts" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var s = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer s.deinit();

    const txid: [32]u8 = [_]u8{0x77} ** 32;

    // Three attestations at varying heights. Two are .pending at heights
    // 500 and 600; one is .confirmed at height 550. The reorg sweep
    // from height 500 should clear both pending entries (they are
    // at-or-above the floor) and leave the confirmed entry alone.
    const t_pending_low: [32]u8 = [_]u8{0x11} ** 32;   // h=500, pending
    const t_confirmed_mid: [32]u8 = [_]u8{0x22} ** 32; // h=550, confirmed
    const t_pending_high: [32]u8 = [_]u8{0x33} ** 32;  // h=600, pending

    _ = try s.store().put(&makeAttestationCellV2(t_pending_low, txid, 500, 0xB0));
    _ = try s.store().put(&makeAttestationCellV2(t_confirmed_mid, txid, 550, 0xB1));
    _ = try s.store().put(&makeAttestationCellV2(t_pending_high, txid, 600, 0xB2));

    // The attestation observer wrote .confirmed for all three by default;
    // demote the two we want pending.
    try s.setAnchorStatus(&t_pending_low, .pending);
    try s.setAnchorStatus(&t_pending_high, .pending);

    const result = try s.sweepReorgedFromHeight(500);
    try std.testing.expectEqual(@as(u32, 2), result.swept);
    try std.testing.expectEqual(@as(u32, 1), result.kept);

    // Pending entries are now absent.
    try std.testing.expectEqual(
        @as(?lmdb_cell_store.AnchorStatus, null),
        s.getAnchorStatus(&t_pending_low),
    );
    try std.testing.expectEqual(
        @as(?lmdb_cell_store.AnchorStatus, null),
        s.getAnchorStatus(&t_pending_high),
    );
    // Confirmed entry survives.
    try std.testing.expectEqual(
        @as(?lmdb_cell_store.AnchorStatus, .confirmed),
        s.getAnchorStatus(&t_confirmed_mid),
    );
}

test "schema v2: sweepReorgedFromHeight leaves cells below the floor untouched" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var s = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer s.deinit();

    const txid: [32]u8 = [_]u8{0xAB} ** 32;
    const t_old: [32]u8 = [_]u8{0xE1} ** 32; // h=100, below floor — must survive
    const t_new: [32]u8 = [_]u8{0xE2} ** 32; // h=900, above floor — must be swept

    _ = try s.store().put(&makeAttestationCellV2(t_old, txid, 100, 0xC0));
    _ = try s.store().put(&makeAttestationCellV2(t_new, txid, 900, 0xC1));

    try s.setAnchorStatus(&t_old, .pending);
    try s.setAnchorStatus(&t_new, .pending);

    const result = try s.sweepReorgedFromHeight(800);
    try std.testing.expectEqual(@as(u32, 1), result.swept);
    try std.testing.expectEqual(@as(u32, 0), result.kept);

    // Below-floor entry is untouched.
    try std.testing.expectEqual(
        @as(?lmdb_cell_store.AnchorStatus, .pending),
        s.getAnchorStatus(&t_old),
    );
    // At-or-above-floor entry is cleared.
    try std.testing.expectEqual(
        @as(?lmdb_cell_store.AnchorStatus, null),
        s.getAnchorStatus(&t_new),
    );
}

test "schema v2: sweepReorgedFromHeight is idempotent" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var s = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer s.deinit();

    const txid: [32]u8 = [_]u8{0x88} ** 32;
    const target: [32]u8 = [_]u8{0x99} ** 32;

    _ = try s.store().put(&makeAttestationCellV2(target, txid, 700, 0x10));
    try s.setAnchorStatus(&target, .pending);

    const first = try s.sweepReorgedFromHeight(700);
    try std.testing.expectEqual(@as(u32, 1), first.swept);
    try std.testing.expectEqual(@as(u32, 0), first.kept);

    // Second sweep on the same range — the reverse-index entry still
    // resolves the target, but its projection is already null, which
    // falls into the `orelse .confirmed` branch and counts as kept.
    const second = try s.sweepReorgedFromHeight(700);
    try std.testing.expectEqual(@as(u32, 0), second.swept);
    try std.testing.expectEqual(@as(u32, 1), second.kept);
}

test "vtable: cellsByAnchorHeightRange round-trip matches direct call" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var s = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer s.deinit();
    const vt = s.store();

    const txid: [32]u8 = [_]u8{0xD0} ** 32;
    const t_a: [32]u8 = [_]u8{0x01} ** 32;
    const t_b: [32]u8 = [_]u8{0x02} ** 32;
    _ = try vt.put(&makeAttestationCellV2(t_a, txid, 100, 0x90));
    _ = try vt.put(&makeAttestationCellV2(t_b, txid, 200, 0x91));

    const via_vt = try vt.cellsByAnchorHeightRange(allocator, 0, 1_000);
    defer allocator.free(via_vt);
    const via_direct = try s.cellsByAnchorHeightRange(allocator, 0, 1_000);
    defer allocator.free(via_direct);

    try std.testing.expectEqual(@as(usize, 2), via_vt.len);
    try std.testing.expectEqual(via_direct.len, via_vt.len);
    // Both paths walk the same cursor in the same BE-encoded order.
    for (via_vt, via_direct) |a, b| {
        try std.testing.expectEqual(a.height, b.height);
        try std.testing.expectEqualSlices(u8, &a.cell_hash, &b.cell_hash);
    }
}

test "vtable: sweepReorgedFromHeight round-trip matches direct call" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var s = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer s.deinit();
    const vt = s.store();

    const txid: [32]u8 = [_]u8{0xE7} ** 32;
    const t_pending: [32]u8 = [_]u8{0x10} ** 32;
    const t_confirmed: [32]u8 = [_]u8{0x20} ** 32;

    _ = try vt.put(&makeAttestationCellV2(t_pending, txid, 400, 0xA0));
    _ = try vt.put(&makeAttestationCellV2(t_confirmed, txid, 500, 0xA1));
    try vt.setAnchorStatus(&t_pending, .pending);
    // t_confirmed keeps the attestation-observer default (.confirmed).

    const via_vt = try vt.sweepReorgedFromHeight(400);
    try std.testing.expectEqual(@as(u32, 1), via_vt.swept);
    try std.testing.expectEqual(@as(u32, 1), via_vt.kept);

    try std.testing.expectEqual(@as(?cell_store.AnchorStatus, null), vt.getAnchorStatus(&t_pending));
    try std.testing.expectEqual(@as(?cell_store.AnchorStatus, .confirmed), vt.getAnchorStatus(&t_confirmed));

    // A second call (via direct path) on the now-quiesced state walks
    // both reverse-index entries; both fall into the `kept` branch.
    const via_direct = try s.sweepReorgedFromHeight(400);
    try std.testing.expectEqual(@as(u32, 0), via_direct.swept);
    try std.testing.expectEqual(@as(u32, 2), via_direct.kept);
}

```
