---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/swarm/brain/swarm_index_rebuild.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.679209+00:00
---

# cartridges/swarm/brain/swarm_index_rebuild.zig

```zig
// swarm_index_rebuild — replay the CellStore into the in-memory tracker at boot.
//
// The tracker (swarm_tracker) is ephemeral; manifests persist as swarm.manifest
// cells in the CellStore. At bind time the brain scans cells_by_type(manifest)
// and re-publishes each into the tracker so a restarted node answers
// swarm.locate without re-downloading. Mirrors tessera_index_rebuild.

const std = @import("std");
const cell_store = @import("cell_store");
const swarm_tracker = @import("swarm_tracker");
const swarm_manifest = @import("swarm_manifest");
const swarm_walkers = @import("swarm_walkers"); // M7 integration test only

/// Re-populate `tracker` from every swarm.manifest cell in `cs`. Best-effort:
/// a read error on one cell skips it; the rest still load.
pub fn rebuildTrackerFromCellStore(
    allocator: std.mem.Allocator,
    tracker: *swarm_tracker.Tracker,
    cs: *const cell_store.CellStore,
) !void {
    const hashes = cs.cellsByType(allocator, &swarm_manifest.MANIFEST_TYPE_HASH) catch return;
    defer allocator.free(hashes);
    for (hashes) |h| {
        const maybe = cs.getCell(&h) catch continue;
        const cell = maybe orelse continue;
        const infohash = swarm_manifest.infohashFromManifestCell(&cell);
        const infohash_hex = std.fmt.bytesToHex(infohash, .lower);
        const cell_hex = std.fmt.bytesToHex(cell, .lower);
        // semanticPath is recoverable from the payload JSON; M6 leaves it empty
        // on rebuild (locate still returns the manifest cell + seeders).
        tracker.publish(&infohash_hex, &cell_hex, "") catch return error.out_of_memory;
    }
}

// ─── In-memory CellStore fake + tests ──────────────────────────────────────────

const testing = std.testing;

/// Minimal in-memory CellStore for tests: real put / get_cell / cells_by_type
/// (keyed by sha256 of the cell), every other vtable method stubbed inert.
const FakeStore = struct {
    allocator: std.mem.Allocator,
    cells: std.AutoHashMapUnmanaged([32]u8, [1024]u8) = .{},
    anchors: std.AutoHashMapUnmanaged([32]u8, cell_store.AnchorStatus) = .{},

    fn init(allocator: std.mem.Allocator) FakeStore {
        return .{ .allocator = allocator };
    }
    fn deinit(self: *FakeStore) void {
        self.cells.deinit(self.allocator);
        self.anchors.deinit(self.allocator);
    }
    fn store(self: *FakeStore) cell_store.CellStore {
        return .{ .ctx = @ptrCast(self), .vtable = &vtable };
    }

    const vtable = cell_store.CellStore.VTable{
        .put = put,
        .exists = exists,
        .cursor_open = cursorOpen,
        .cursor_pull = cursorPull,
        .cursor_close = cursorClose,
        .count = count,
        .spend = spend,
        .is_spent = isSpent,
        .get_cell = getCell,
        .cells_by_owner = emptyHashes,
        .cells_by_type = cellsByType,
        .cells_by_type_prefix = emptyHashesPrefix,
        .cells_by_prev_state = emptyHashesHash,
        .cells_by_anchor_txid = emptyHashesHash,
        .set_anchor_status = setAnchorStatus,
        .get_anchor_status = getAnchorStatus,
        .clear_anchor_status = clearAnchorStatus,
        .sweep_pending_anchors = sweepPending,
        .cells_by_anchor_height_range = emptyHeights,
        .sweep_reorged_from_height = sweepHeight,
        .cells_by_prev_state_range = prevStateRange,
    };

    fn fromCtx(ctx: *anyopaque) *FakeStore {
        return @ptrCast(@alignCast(ctx));
    }

    fn put(ctx: *anyopaque, cell: *const [1024]u8) cell_store.StoreError![32]u8 {
        const s = fromCtx(ctx);
        var hash: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(cell, &hash, .{});
        s.cells.put(s.allocator, hash, cell.*) catch return error.out_of_memory;
        return hash;
    }
    fn exists(ctx: *anyopaque, hash: *const [32]u8) bool {
        return fromCtx(ctx).cells.contains(hash.*);
    }
    fn getCell(ctx: *anyopaque, hash: *const [32]u8) cell_store.StoreError!?[1024]u8 {
        return fromCtx(ctx).cells.get(hash.*);
    }
    fn cellsByType(ctx: *anyopaque, allocator: std.mem.Allocator, type_hash: *const [32]u8) cell_store.StoreError![][32]u8 {
        const s = fromCtx(ctx);
        var list: std.ArrayListUnmanaged([32]u8) = .{};
        errdefer list.deinit(allocator);
        var it = s.cells.iterator();
        while (it.next()) |kv| {
            if (std.mem.eql(u8, kv.value_ptr[30..62], type_hash)) {
                list.append(allocator, kv.key_ptr.*) catch return error.out_of_memory;
            }
        }
        return list.toOwnedSlice(allocator) catch error.out_of_memory;
    }
    fn count(ctx: *anyopaque) cell_store.StoreError!u64 {
        return fromCtx(ctx).cells.count();
    }

    // ── inert stubs ──
    fn cursorOpen(_: *anyopaque) cell_store.StoreError!cell_store.CellCursorHandle {
        return error.persistence_failed;
    }
    fn cursorPull(_: *anyopaque, _: cell_store.CellCursorHandle) cell_store.StoreError!?*const [1024]u8 {
        return null;
    }
    fn cursorClose(_: *anyopaque, _: cell_store.CellCursorHandle) void {}
    fn spend(_: *anyopaque, _: *const [32]u8) cell_store.StoreError!bool {
        return false;
    }
    fn isSpent(_: *anyopaque, _: *const [32]u8) bool {
        return false;
    }
    fn emptyHashes(_: *anyopaque, allocator: std.mem.Allocator, _: *const [16]u8) cell_store.StoreError![][32]u8 {
        return allocator.alloc([32]u8, 0) catch unreachable;
    }
    fn emptyHashesHash(_: *anyopaque, allocator: std.mem.Allocator, _: *const [32]u8) cell_store.StoreError![][32]u8 {
        return allocator.alloc([32]u8, 0) catch unreachable;
    }
    fn emptyHashesPrefix(_: *anyopaque, allocator: std.mem.Allocator, _: []const u8) cell_store.StoreError![][32]u8 {
        return allocator.alloc([32]u8, 0) catch unreachable;
    }
    fn setAnchorStatus(ctx: *anyopaque, hash: *const [32]u8, status: cell_store.AnchorStatus) cell_store.StoreError!void {
        const s = fromCtx(ctx);
        s.anchors.put(s.allocator, hash.*, status) catch return error.out_of_memory;
    }
    fn getAnchorStatus(ctx: *anyopaque, hash: *const [32]u8) ?cell_store.AnchorStatus {
        return fromCtx(ctx).anchors.get(hash.*);
    }
    fn clearAnchorStatus(ctx: *anyopaque, hash: *const [32]u8) cell_store.StoreError!void {
        _ = fromCtx(ctx).anchors.remove(hash.*);
    }
    fn sweepPending(_: *anyopaque, _: *const [32]u8) cell_store.StoreError!cell_store.SweepResult {
        return .{ .swept = 0, .kept = 0 };
    }
    fn emptyHeights(_: *anyopaque, allocator: std.mem.Allocator, _: u64, _: u64) cell_store.StoreError![]cell_store.AnchorHeightEntry {
        return allocator.alloc(cell_store.AnchorHeightEntry, 0) catch unreachable;
    }
    fn sweepHeight(_: *anyopaque, _: u64) cell_store.StoreError!cell_store.SweepResult {
        return .{ .swept = 0, .kept = 0 };
    }
    fn prevStateRange(_: *anyopaque, allocator: std.mem.Allocator, _: *const [32]u8, _: ?*const [32]u8, _: usize) cell_store.StoreError!cell_store.PrevStateRangeResult {
        return .{ .hashes = allocator.alloc([32]u8, 0) catch unreachable, .has_more = false };
    }
};

test "rebuild repopulates the tracker from persisted manifest cells" {
    var fake = FakeStore.init(testing.allocator);
    defer fake.deinit();
    const cs = fake.store();

    // Persist two manifest cells with distinct payloads → distinct infohashes.
    var infohashes: [2][64]u8 = undefined;
    inline for (.{ "{\"v\":1,\"p\":\"a\"}", "{\"v\":1,\"p\":\"bb\"}" }, 0..) |payload, i| {
        var cell: [1024]u8 = undefined;
        @memset(&cell, 0);
        @memcpy(cell[30..62], &swarm_manifest.MANIFEST_TYPE_HASH);
        std.mem.writeInt(u32, cell[90..94], @intCast(payload.len), .little);
        @memcpy(cell[256 .. 256 + payload.len], payload);
        _ = try cs.put(&cell);
        infohashes[i] = std.fmt.bytesToHex(swarm_manifest.infohashFromManifestCell(&cell), .lower);
    }

    var tracker = swarm_tracker.Tracker.init(testing.allocator);
    defer tracker.deinit();
    try rebuildTrackerFromCellStore(testing.allocator, &tracker, &cs);

    try testing.expectEqual(@as(u32, 2), tracker.by_infohash.count());
    try testing.expect(tracker.locate(&infohashes[0]) != null);
    try testing.expect(tracker.locate(&infohashes[1]) != null);
}

test "rebuild ignores non-manifest cells" {
    var fake = FakeStore.init(testing.allocator);
    defer fake.deinit();
    const cs = fake.store();
    var cell: [1024]u8 = undefined;
    @memset(&cell, 0);
    @memcpy(cell[30..62], &swarm_manifest.RECEIPT_TYPE_HASH); // a receipt, not a manifest
    _ = try cs.put(&cell);

    var tracker = swarm_tracker.Tracker.init(testing.allocator);
    defer tracker.deinit();
    try rebuildTrackerFromCellStore(testing.allocator, &tracker, &cs);
    try testing.expectEqual(@as(u32, 0), tracker.by_infohash.count());
}

fn zeroClock() i64 {
    return 0;
}

test "M7: publish marks anchor pending, locate reports it, confirm flips it" {
    var fake = FakeStore.init(testing.allocator);
    defer fake.deinit();
    const cs = fake.store();
    var tracker = swarm_tracker.Tracker.init(testing.allocator);
    defer tracker.deinit();
    var st = swarm_walkers.State{ .tracker = &tracker, .clock_fn = zeroClock, .cell_store = &cs };

    // A manifest cell + its hex + infohash.
    var cell: [1024]u8 = undefined;
    @memset(&cell, 0);
    @memcpy(cell[30..62], &swarm_manifest.MANIFEST_TYPE_HASH);
    const payload = "{\"v\":1,\"p\":\"x\"}";
    std.mem.writeInt(u32, cell[90..94], @intCast(payload.len), .little);
    @memcpy(cell[256 .. 256 + payload.len], payload);
    const cell_hex = std.fmt.bytesToHex(cell, .lower);
    const infohash_hex = std.fmt.bytesToHex(swarm_manifest.infohashFromManifestCell(&cell), .lower);

    const params = try std.fmt.allocPrint(testing.allocator, "{{\"infohash\":\"{s}\",\"manifestCellHex\":\"{s}\",\"semanticPath\":\"x\"}}", .{ infohash_hex, cell_hex });
    defer testing.allocator.free(params);
    testing.allocator.free(try swarm_walkers.publishWalker(testing.allocator, &st, params));

    const loc_params = try std.fmt.allocPrint(testing.allocator, "{{\"infohash\":\"{s}\"}}", .{infohash_hex});
    defer testing.allocator.free(loc_params);

    const loc1 = try swarm_walkers.locateWalker(testing.allocator, &st, loc_params);
    defer testing.allocator.free(loc1);
    try testing.expect(std.mem.indexOf(u8, loc1, "\"anchorStatus\":\"pending\"") != null);

    // Simulate the anchor runner confirming the manifest on-chain.
    const h = tracker.locate(&infohash_hex).?.manifest_cell_hash.?;
    try cs.setAnchorStatus(&h, .confirmed);
    const loc2 = try swarm_walkers.locateWalker(testing.allocator, &st, loc_params);
    defer testing.allocator.free(loc2);
    try testing.expect(std.mem.indexOf(u8, loc2, "\"anchorStatus\":\"confirmed\"") != null);
}

```
