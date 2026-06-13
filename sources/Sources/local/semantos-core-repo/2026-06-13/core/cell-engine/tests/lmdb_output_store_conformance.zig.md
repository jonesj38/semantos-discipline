---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests/lmdb_output_store_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.962597+00:00
---

# core/cell-engine/tests/lmdb_output_store_conformance.zig

```zig
// M1.3 — LmdbOutputStore conformance tests.
//
// TDD red phase: written before the implementation.
// Mirrors the inline tests in output_store.zig but wires to LmdbOutputStore.
//
// Test IDs: M1.3-T-add-get, M1.3-T-duplicate, M1.3-T-mark-spent-atomic,
//           M1.3-T-list-filter, M1.3-T-prune, M1.3-T-snapshot-replay.
//
// Run: zig build test-lmdb-output-store

const std = @import("std");
const lmdb = @import("lmdb");
const output_store = @import("output_store");
const lmdb_output_store = @import("lmdb_output_store");

const Outpoint = output_store.Outpoint;
const OutputRecord = output_store.OutputRecord;

fn tmpDir(alloc: std.mem.Allocator) ![]u8 {
    var buf: [64]u8 = undefined;
    const name = try std.fmt.bufPrint(
        &buf,
        "/tmp/lmdb-out-test-{d}",
        .{std.time.nanoTimestamp()},
    );
    try std.fs.cwd().makePath(name);
    return alloc.dupe(u8, name);
}

fn makeRecord(outpoint: Outpoint, satoshis: u64, basket: []const u8) OutputRecord {
    return .{
        .outpoint = outpoint,
        .satoshis = satoshis,
        .locking_script = &[_]u8{ 0x76, 0xa9, 0x14 },
        .derived_key_hash = [_]u8{2} ** 32,
        .derivation_protocol_hash = [_]u8{3} ** 16,
        .derivation_counterparty = [_]u8{4} ** 33,
        .derivation_index = 0,
        .beef = &[_]u8{ 0xef, 0xbe, 0x00, 0x01 },
        .basket = basket,
        .tags = &[_]u8{},
        .custom_instructions = &[_]u8{},
        .confirmations = 0,
        .status = .unspent,
        .spending_txid = [_]u8{0} ** 32,
    };
}

// ── M1.3-T-add-get ───────────────────────────────────────────────────

test "M1.3: add → get round-trip" {
    const allocator = std.testing.allocator;

    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var store_impl = try lmdb_output_store.LmdbOutputStore.init(&env, allocator);
    defer store_impl.deinit();
    const store = store_impl.store();

    const op1 = Outpoint{ .txid = [_]u8{1} ** 32, .vout = 0 };
    const rec1 = makeRecord(op1, 50_000, "default");
    try store.addOutput(rec1);

    const got = store.getOutput(op1);
    try std.testing.expect(got != null);
    try std.testing.expectEqual(@as(u64, 50_000), got.?.satoshis);
}

// ── M1.3-T-duplicate ─────────────────────────────────────────────────

test "M1.3: duplicate outpoint is rejected" {
    const allocator = std.testing.allocator;

    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var store_impl = try lmdb_output_store.LmdbOutputStore.init(&env, allocator);
    defer store_impl.deinit();
    const store = store_impl.store();

    const op1 = Outpoint{ .txid = [_]u8{1} ** 32, .vout = 0 };
    const rec1 = makeRecord(op1, 1000, "default");
    try store.addOutput(rec1);
    try std.testing.expectError(error.duplicate_outpoint, store.addOutput(rec1));
}

// ── M1.3-T-mark-spent-atomic ─────────────────────────────────────────
// Atomicity: if mark_spent would fail (unknown outpoint), the UTXO stays
// unspent. Verified by attempting to spend an unknown outpoint and then
// confirming the real one is still unspent.

test "M1.3: mark_spent is atomic — unknown outpoint leaves real one unspent" {
    const allocator = std.testing.allocator;

    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var store_impl = try lmdb_output_store.LmdbOutputStore.init(&env, allocator);
    defer store_impl.deinit();
    const store = store_impl.store();

    const op_real = Outpoint{ .txid = [_]u8{1} ** 32, .vout = 0 };
    const op_unknown = Outpoint{ .txid = [_]u8{9} ** 32, .vout = 0 };

    try store.addOutput(makeRecord(op_real, 1000, "default"));

    // Spending an unknown outpoint must fail.
    try std.testing.expectError(
        error.unknown_outpoint,
        store.markSpent(op_unknown, [_]u8{0xaa} ** 32),
    );

    // The real UTXO must still be unspent.
    const after = store.getOutput(op_real) orelse return error.TestFailed;
    try std.testing.expectEqual(output_store.OutputStatus.unspent, after.status);
}

// ── M1.3-T-list-filter ───────────────────────────────────────────────

test "M1.3: list_outputs filters by basket and excludes spent" {
    const allocator = std.testing.allocator;

    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var store_impl = try lmdb_output_store.LmdbOutputStore.init(&env, allocator);
    defer store_impl.deinit();
    const store = store_impl.store();

    const op1 = Outpoint{ .txid = [_]u8{1} ** 32, .vout = 0 };
    const op2 = Outpoint{ .txid = [_]u8{2} ** 32, .vout = 0 };
    const op3 = Outpoint{ .txid = [_]u8{3} ** 32, .vout = 0 };

    try store.addOutput(makeRecord(op1, 1000, "default"));
    try store.addOutput(makeRecord(op2, 2000, "incoming"));
    try store.addOutput(makeRecord(op3, 3000, "default"));

    // All unspent in "default": op1, op3.
    const list1 = try store.listOutputs("default", null, allocator);
    defer allocator.free(list1);
    try std.testing.expectEqual(@as(usize, 2), list1.len);

    // "incoming": only op2.
    const list2 = try store.listOutputs("incoming", null, allocator);
    defer allocator.free(list2);
    try std.testing.expectEqual(@as(usize, 1), list2.len);

    // Mark op1 spent.
    try store.markSpent(op1, [_]u8{0xaa} ** 32);

    // "default" now has only op3.
    const list3 = try store.listOutputs("default", null, allocator);
    defer allocator.free(list3);
    try std.testing.expectEqual(@as(usize, 1), list3.len);
}

// ── M1.3-T-prune ─────────────────────────────────────────────────────

test "M1.3: prune_confirmed drops BEEF over threshold" {
    const allocator = std.testing.allocator;

    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var store_impl = try lmdb_output_store.LmdbOutputStore.init(&env, allocator);
    defer store_impl.deinit();
    const store = store_impl.store();

    const op_low = Outpoint{ .txid = [_]u8{1} ** 32, .vout = 0 };
    const op_high = Outpoint{ .txid = [_]u8{2} ** 32, .vout = 0 };

    var rec_low = makeRecord(op_low, 1000, "default");
    rec_low.confirmations = 50;
    var rec_high = makeRecord(op_high, 2000, "default");
    rec_high.confirmations = 100;

    try store.addOutput(rec_low);
    try store.addOutput(rec_high);

    const pruned = try store.pruneConfirmed(100);
    try std.testing.expectEqual(@as(u64, 1), pruned);

    // High-confirmation record now has empty BEEF.
    const high_after = store.getOutput(op_high) orelse return error.TestFailed;
    try std.testing.expectEqual(@as(usize, 0), high_after.beef.len);

    // Low-confirmation record still has BEEF.
    const low_after = store.getOutput(op_low) orelse return error.TestFailed;
    try std.testing.expect(low_after.beef.len > 0);
}

// ── M1.3-T-snapshot-replay ───────────────────────────────────────────

test "M1.3: snapshot → replay round-trip" {
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

    var src_impl = try lmdb_output_store.LmdbOutputStore.init(&env_src, allocator);
    defer src_impl.deinit();
    const src = src_impl.store();

    var i: u8 = 0;
    while (i < 3) : (i += 1) {
        const op = Outpoint{ .txid = [_]u8{i} ** 32, .vout = i };
        try src.addOutput(makeRecord(op, @as(u64, i) * 1000, "default"));
    }

    const snap = try src.snapshot(allocator);
    defer allocator.free(snap);
    try std.testing.expectEqual(@as(usize, 3), snap.len);

    var dst_impl = try lmdb_output_store.LmdbOutputStore.init(&env_dst, allocator);
    defer dst_impl.deinit();
    const dst = dst_impl.store();
    try dst.replay(snap);

    const dst_snap = try dst.snapshot(allocator);
    defer allocator.free(dst_snap);
    try std.testing.expectEqual(@as(usize, 3), dst_snap.len);
}

```
