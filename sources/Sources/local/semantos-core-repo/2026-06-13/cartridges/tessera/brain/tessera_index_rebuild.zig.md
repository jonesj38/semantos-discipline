---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/tessera/brain/tessera_index_rebuild.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.634963+00:00
---

# cartridges/tessera/brain/tessera_index_rebuild.zig

```zig
// tessera_index_rebuild — replay CellStore into the per-cartridge
// `cell_id_by_domain_id` index at boot.
//
// Why this exists:
//   The P4b index is populated by walker mints (record-as-you-go).
//   At fresh boot, the in-memory store has the FSM but the index is
//   empty until the first mint. The P4c consume helpers depend on the
//   index, so during that window every consume verb would refuse with
//   `unknown_predecessor`. This module closes that window: scan the
//   substrate CellStore for tessera-tagged cells and re-populate the
//   index from the canonical `domainId` field each cell's mint payload
//   carries (P-boot-rebuild — `payloadWithDomainId` in tessera_walkers).
//
// Greenfield: every symbol stays under `cartridges/tessera/brain/`.
// The module imports the generic CellStore vtable and the generic
// substrate_entity helpers — adapter consumption, no `tessera` in
// substrate src/.
//
// Best-effort by design: any per-cell parse/match/insert failure is
// swallowed. A boot that finds a malformed or non-matching cell skips
// it and continues — the binding succeeds, the index just lacks that
// entry until the next walker mint re-records it.

const std = @import("std");
const cell_store_mod = @import("cell_store");
const substrate_entity = @import("substrate_entity");
const tessera_cell_specs = @import("tessera_cell_specs");
const tessera_cells = @import("tessera_cells");
const tessera_store_mod = @import("tessera_store");

const CELL_BYTES: usize = cell_store_mod.CELL_BYTES;

// Cell-format offsets (mirror substrate_entity's private layout — the
// header is publicly documented stable, the offsets are part of the
// substrate contract). Coupling here is deliberate: keeping the parse
// in-cartridge means substrate src/ stays free of `tessera` names.
const OFFSET_TYPE_HASH: usize = 30;
const TYPE_HASH_BYTES: usize = 32;
const OFFSET_PAYLOAD_TOTAL: usize = 90;
const PAYLOAD_START: usize = 256;

/// Compute the 10 type_hashes of tessera's registered SPECs. Stable
/// per build; safe to call at boot. Pure / no allocation.
pub fn tesseraTypeHashes() [tessera_cells.ALL.len][TYPE_HASH_BYTES]u8 {
    var out: [tessera_cells.ALL.len][TYPE_HASH_BYTES]u8 = undefined;
    var i: usize = 0;
    while (i < tessera_cells.ALL.len) : (i += 1) {
        const spec = tessera_cell_specs.specForIndex(i).?;
        out[i] = substrate_entity.computeTypeHash(spec);
    }
    return out;
}

/// Per-cell: if `cell` is a tessera cell (TYPE_HASH matches any entry
/// in `tessera_hashes`) AND its payload carries a `domainId` string,
/// record `(domainId, cell_id)` in `store`. Best-effort: any failure
/// silently skips this cell.
pub fn maybeRecordCell(
    a: std.mem.Allocator,
    store: *tessera_store_mod.Store,
    cell: *const [CELL_BYTES]u8,
    tessera_hashes: []const [TYPE_HASH_BYTES]u8,
) void {
    // 1. Filter by TYPE_HASH.
    const cth: *const [TYPE_HASH_BYTES]u8 = cell[OFFSET_TYPE_HASH..][0..TYPE_HASH_BYTES];
    var matched = false;
    for (tessera_hashes) |th| {
        if (std.mem.eql(u8, cth, &th)) {
            matched = true;
            break;
        }
    }
    if (!matched) return;

    // 2. Bounds-check payload_total.
    const payload_total = std.mem.readInt(u32, cell[OFFSET_PAYLOAD_TOTAL..][0..4], .little);
    if (payload_total == 0 or PAYLOAD_START + payload_total > CELL_BYTES) return;
    const payload = cell[PAYLOAD_START .. PAYLOAD_START + payload_total];

    // 3. Extract `domainId` from JSON payload.
    const did = domainIdFromPayload(a, payload) catch return;
    const did_owned = did orelse return;
    defer a.free(did_owned);

    // 4. cell_id = sha256(cell).
    var cell_id: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(cell, &cell_id, .{});

    // 5. Insert. recordCellId is idempotent for same (id, cell_id) and
    // overwrite-in-place for different cell_id — last write wins for
    // duplicate domain_ids, same shape as the live mint path.
    store.recordCellId(did_owned, cell_id) catch return;
}

/// Scan `cs` end-to-end, calling `maybeRecordCell` for every cell.
/// Idempotent — safe to call once per boot.
pub fn rebuildFromCellStore(
    a: std.mem.Allocator,
    store: *tessera_store_mod.Store,
    cs: *const cell_store_mod.CellStore,
) cell_store_mod.StoreError!void {
    const hashes = tesseraTypeHashes();
    const cur = try cs.cursorOpen();
    defer cs.cursorClose(cur);
    while (try cs.cursorPull(cur)) |cell| {
        maybeRecordCell(a, store, cell, &hashes);
    }
}

fn domainIdFromPayload(a: std.mem.Allocator, payload: []const u8) !?[]u8 {
    var parsed = std.json.parseFromSlice(std.json.Value, a, payload, .{}) catch return null;
    defer parsed.deinit();
    if (parsed.value != .object) return null;
    const v = parsed.value.object.get("domainId") orelse return null;
    if (v != .string) return null;
    return try a.dupe(u8, v.string);
}

// ── Tests ────────────────────────────────────────────────────────────

const testing = std.testing;
const tessera_mint = @import("tessera_mint");

test "tesseraTypeHashes returns 10 distinct hashes (one per SPEC)" {
    const h = tesseraTypeHashes();
    try testing.expectEqual(@as(usize, 10), h.len);
    // Pairwise distinct.
    var i: usize = 0;
    while (i < h.len) : (i += 1) {
        var j: usize = i + 1;
        while (j < h.len) : (j += 1) {
            try testing.expect(!std.mem.eql(u8, &h[i], &h[j]));
        }
    }
}

test "maybeRecordCell records a tessera-tagged cell carrying domainId" {
    var store = tessera_store_mod.Store.init(testing.allocator);
    defer store.deinit();
    const hashes = tesseraTypeHashes();

    // Build a real grape-lot cell via the mint path tessera_walkers uses.
    const owner = [_]u8{0} ** 16;
    const enc = try tessera_mint.encodeCellByName(
        "tessera.grape-lot",
        owner,
        "{\"domainId\":\"L1\",\"grower\":\"alice\"}",
        42,
    );

    maybeRecordCell(testing.allocator, &store, &enc.cell, &hashes);

    const got = store.cellIdByDomainId("L1") orelse return error.TestExpectedNotNull;
    try testing.expectEqualSlices(u8, &enc.cell_id, &got);
}

test "maybeRecordCell skips a non-tessera cell (no TYPE_HASH match)" {
    var store = tessera_store_mod.Store.init(testing.allocator);
    defer store.deinit();
    const hashes = tesseraTypeHashes();

    // Synthetic cell with a TYPE_HASH that doesn't match any tessera.
    var cell: [CELL_BYTES]u8 = [_]u8{0} ** CELL_BYTES;
    var fake_type_hash: [TYPE_HASH_BYTES]u8 = [_]u8{0xFF} ** TYPE_HASH_BYTES;
    @memcpy(cell[OFFSET_TYPE_HASH..][0..TYPE_HASH_BYTES], &fake_type_hash);
    // Valid payload (would be ignored anyway).
    const p = "{\"domainId\":\"X\"}";
    @memcpy(cell[PAYLOAD_START..][0..p.len], p);
    std.mem.writeInt(u32, cell[OFFSET_PAYLOAD_TOTAL..][0..4], @intCast(p.len), .little);

    maybeRecordCell(testing.allocator, &store, &cell, &hashes);
    try testing.expectEqual(@as(usize, 0), store.domainIdIndexCount());
}

test "maybeRecordCell skips a tessera cell whose payload lacks domainId" {
    var store = tessera_store_mod.Store.init(testing.allocator);
    defer store.deinit();
    const hashes = tesseraTypeHashes();

    // Real grape-lot cell with a payload that DOES NOT carry domainId
    // (the shape AFFINE-event mints leave behind today — care/scan/
    // tamper/tasting walkers pass record_domain_id=null and so don't
    // wrap their payload).
    const owner = [_]u8{0} ** 16;
    const enc = try tessera_mint.encodeCellByName(
        "tessera.care-event",
        owner,
        "{\"containerId\":\"C1\"}",
        42,
    );

    maybeRecordCell(testing.allocator, &store, &enc.cell, &hashes);
    try testing.expectEqual(@as(usize, 0), store.domainIdIndexCount());
}

test "maybeRecordCell handles malformed payload gracefully (no crash, no entry)" {
    var store = tessera_store_mod.Store.init(testing.allocator);
    defer store.deinit();
    const hashes = tesseraTypeHashes();

    // Build a real tessera-tagged cell, then clobber its payload with
    // invalid JSON. The function must skip the cell, not crash.
    const owner = [_]u8{0} ** 16;
    var enc = try tessera_mint.encodeCellByName(
        "tessera.barrel",
        owner,
        "{\"domainId\":\"B1\"}",
        42,
    );
    const bad = "not json !!";
    @memcpy(enc.cell[PAYLOAD_START..][0..bad.len], bad);
    std.mem.writeInt(u32, enc.cell[OFFSET_PAYLOAD_TOTAL..][0..4], @intCast(bad.len), .little);

    maybeRecordCell(testing.allocator, &store, &enc.cell, &hashes);
    try testing.expectEqual(@as(usize, 0), store.domainIdIndexCount());
}

test "maybeRecordCell replays multiple cell types into the index" {
    var store = tessera_store_mod.Store.init(testing.allocator);
    defer store.deinit();
    const hashes = tesseraTypeHashes();
    const owner = [_]u8{0} ** 16;

    const cells = [_]struct { name: []const u8, payload: []const u8, expected_id: []const u8 }{
        .{ .name = "tessera.grape-lot", .payload = "{\"domainId\":\"L1\",\"grower\":\"g\"}", .expected_id = "L1" },
        .{ .name = "tessera.barrel", .payload = "{\"domainId\":\"B1\",\"lotId\":\"L1\"}", .expected_id = "B1" },
        .{ .name = "tessera.bottle", .payload = "{\"domainId\":\"x\",\"barrelId\":\"B1\"}", .expected_id = "x" },
        .{ .name = "tessera.case", .payload = "{\"domainId\":\"C1\",\"holder\":\"alice\"}", .expected_id = "C1" },
        .{ .name = "tessera.pallet", .payload = "{\"domainId\":\"P1\",\"kind\":\"pallet\"}", .expected_id = "P1" },
    };

    for (cells) |c| {
        const enc = try tessera_mint.encodeCellByName(c.name, owner, c.payload, 42);
        maybeRecordCell(testing.allocator, &store, &enc.cell, &hashes);
    }

    try testing.expectEqual(@as(usize, cells.len), store.domainIdIndexCount());
    for (cells) |c| {
        try testing.expect(store.cellIdByDomainId(c.expected_id) != null);
    }
}

```
