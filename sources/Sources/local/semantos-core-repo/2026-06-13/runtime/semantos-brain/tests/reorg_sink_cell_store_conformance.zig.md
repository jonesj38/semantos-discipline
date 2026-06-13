---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/reorg_sink_cell_store_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.211775+00:00
---

# runtime/semantos-brain/tests/reorg_sink_cell_store_conformance.zig

```zig
// D-LC5 — conformance for `ReorgSinkCellStore`, the brain-side
// concrete `ReorgSink` impl. End-to-end coverage of the
// (cartridge-facing sink → LmdbCellStore.sweepReorgedFromHeight) path.
//
// Pairs with cartridge-side tests in
// `cartridges/bsv-anchor-bundle/brain/zig/src/reorg_sink.zig` (inline
// `StubReorgSink` tests cover the cartridge-side surface in isolation;
// the cartridge has no LMDB dependency).

const std = @import("std");
const lmdb = @import("lmdb");
const cell_store = @import("cell_store");
const lmdb_cell_store = @import("lmdb_cell_store");
const reorg_sink_cell_store = @import("reorg_sink_cell_store");

fn tmpDir(alloc: std.mem.Allocator) ![]u8 {
    var buf: [80]u8 = undefined;
    const name = try std.fmt.bufPrint(
        &buf,
        "/tmp/reorg-sink-test-{d}",
        .{std.time.nanoTimestamp()},
    );
    try std.fs.cwd().makePath(name);
    return alloc.dupe(u8, name);
}

/// Build an attestation cell with a specific anchor_height. Mirrors
/// the schema-v2 wire shape so the doPut observer in LmdbCellStore
/// triggers the height-projection index update. Layout:
///   domain_flag       u32  @ 24  = 0x0001FE02 (canonical anchor-
///                                 attestation wire value)
///   payload @ 256:
///     targetCellId    u256 @ 256
///     txid            u256 @ 288
///     anchor_height   u64  @ 320   (LE in payload bytes)
///     vout            u32  @ 328
///     derivationIndex u32  @ 332
fn makeAttestationCell(
    target_id: [32]u8,
    txid: [32]u8,
    anchor_height: u64,
) [cell_store.CELL_BYTES]u8 {
    var c: [cell_store.CELL_BYTES]u8 = undefined;
    @memset(&c, 0);
    std.mem.writeInt(u32, c[24..28], 0x0001FE02, .little);
    @memcpy(c[256..288], &target_id);
    @memcpy(c[288..320], &txid);
    std.mem.writeInt(u64, c[320..328], anchor_height, .little);
    return c;
}

test "D-LC5 sink: sweeps pending entries at-and-above floor; preserves below floor and confirmed" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var store_impl = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer store_impl.deinit();
    const store = store_impl.store();

    // Three attestation cells at distinct heights, distinct targets.
    // doPut populates the height projection and flips each target's
    // anchor status to .confirmed. We manually downgrade A and B to
    // .pending so the sweep has something to clear; C stays .confirmed
    // to exercise the preservation rule.
    var target_a: [32]u8 = undefined;
    @memset(&target_a, 0xAA);
    var target_b: [32]u8 = undefined;
    @memset(&target_b, 0xBB);
    var target_c: [32]u8 = undefined;
    @memset(&target_c, 0xCC);

    var txid_a: [32]u8 = undefined;
    @memset(&txid_a, 0x01);
    var txid_b: [32]u8 = undefined;
    @memset(&txid_b, 0x02);
    var txid_c: [32]u8 = undefined;
    @memset(&txid_c, 0x03);

    const cell_a = makeAttestationCell(target_a, txid_a, 100);
    const cell_b = makeAttestationCell(target_b, txid_b, 200);
    const cell_c = makeAttestationCell(target_c, txid_c, 300);

    _ = try store.put(&cell_a);
    _ = try store.put(&cell_b);
    _ = try store.put(&cell_c);

    try store_impl.setAnchorStatus(&target_a, .pending);
    try store_impl.setAnchorStatus(&target_b, .pending);

    var wrapper = reorg_sink_cell_store.ReorgSinkCellStore.init(&store_impl);
    const s = wrapper.sink();

    // Floor=200 — should sweep target_b (.pending @ 200) but leave
    // target_a (.pending @ 100, below floor) and target_c (.confirmed
    // @ 300, above floor but confirmed survives reorg).
    const report = try s.sweepReorgedFromHeight(200);
    try std.testing.expectEqual(@as(u32, 1), report.swept);
    try std.testing.expectEqual(@as(u32, 1), report.kept); // target_c

    // Verify projection state matches expectation.
    try std.testing.expectEqual(
        @as(?lmdb_cell_store.AnchorStatus, .pending),
        store_impl.getAnchorStatus(&target_a),
    );
    try std.testing.expectEqual(
        @as(?lmdb_cell_store.AnchorStatus, null),
        store_impl.getAnchorStatus(&target_b),
    );
    try std.testing.expectEqual(
        @as(?lmdb_cell_store.AnchorStatus, .confirmed),
        store_impl.getAnchorStatus(&target_c),
    );
}

test "D-LC5 sink: floor=0 sweeps every pending entry" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var store_impl = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer store_impl.deinit();
    const store = store_impl.store();

    var target_a: [32]u8 = undefined;
    @memset(&target_a, 0xDD);
    var txid_a: [32]u8 = undefined;
    @memset(&txid_a, 0x10);
    const cell_a = makeAttestationCell(target_a, txid_a, 1_000_000);
    _ = try store.put(&cell_a);
    try store_impl.setAnchorStatus(&target_a, .pending);

    var wrapper = reorg_sink_cell_store.ReorgSinkCellStore.init(&store_impl);
    const s = wrapper.sink();
    const report = try s.sweepReorgedFromHeight(0);
    try std.testing.expectEqual(@as(u32, 1), report.swept);
    try std.testing.expectEqual(
        @as(?lmdb_cell_store.AnchorStatus, null),
        store_impl.getAnchorStatus(&target_a),
    );
}

test "D-LC5 sink: floor above all heights is a no-op (pending entries preserved)" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var store_impl = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer store_impl.deinit();
    const store = store_impl.store();

    var target_a: [32]u8 = undefined;
    @memset(&target_a, 0xEE);
    var txid_a: [32]u8 = undefined;
    @memset(&txid_a, 0x20);
    const cell_a = makeAttestationCell(target_a, txid_a, 500);
    _ = try store.put(&cell_a);
    try store_impl.setAnchorStatus(&target_a, .pending);

    var wrapper = reorg_sink_cell_store.ReorgSinkCellStore.init(&store_impl);
    const s = wrapper.sink();
    const report = try s.sweepReorgedFromHeight(1_000_000);
    try std.testing.expectEqual(@as(u32, 0), report.swept);
    try std.testing.expectEqual(@as(u32, 0), report.kept);
    try std.testing.expectEqual(
        @as(?lmdb_cell_store.AnchorStatus, .pending),
        store_impl.getAnchorStatus(&target_a),
    );
}

test "D-LC5 sink: empty store sweep is a clean no-op" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var store_impl = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer store_impl.deinit();

    var wrapper = reorg_sink_cell_store.ReorgSinkCellStore.init(&store_impl);
    const s = wrapper.sink();
    const report = try s.sweepReorgedFromHeight(0);
    try std.testing.expectEqual(@as(u32, 0), report.swept);
    try std.testing.expectEqual(@as(u32, 0), report.kept);
}

test "D-LC5 sink: idempotent — second call after first sweep returns (0, 0)" {
    const allocator = std.testing.allocator;
    const path = try tmpDir(allocator);
    defer allocator.free(path);
    defer std.fs.cwd().deleteTree(path) catch {};

    var env = try lmdb.Env.open(path, .{});
    defer env.close();

    var store_impl = try lmdb_cell_store.LmdbCellStore.init(&env, allocator);
    defer store_impl.deinit();
    const store = store_impl.store();

    var target_a: [32]u8 = undefined;
    @memset(&target_a, 0xFE);
    var txid_a: [32]u8 = undefined;
    @memset(&txid_a, 0x30);
    const cell_a = makeAttestationCell(target_a, txid_a, 50);
    _ = try store.put(&cell_a);
    try store_impl.setAnchorStatus(&target_a, .pending);

    var wrapper = reorg_sink_cell_store.ReorgSinkCellStore.init(&store_impl);
    const s = wrapper.sink();

    const first = try s.sweepReorgedFromHeight(0);
    try std.testing.expectEqual(@as(u32, 1), first.swept);

    const second = try s.sweepReorgedFromHeight(0);
    // The reverse index still has the entry, but the projection is
    // already null → counted as `kept` (orelse .confirmed branch in
    // sweepReorgedFromHeight).
    try std.testing.expectEqual(@as(u32, 0), second.swept);
    try std.testing.expectEqual(@as(u32, 1), second.kept);
}

```
