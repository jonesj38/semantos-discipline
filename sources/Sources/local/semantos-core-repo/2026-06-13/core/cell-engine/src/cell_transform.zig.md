---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/src/cell_transform.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.983220+00:00
---

# core/cell-engine/src/cell_transform.zig

```zig
// cell_transform.zig — transform-on-hop: compute riding the routing.
//
// Spec source: docs/prd/MNCA-LAYER-COLLAPSE-BRIEF.md §13.3 (how a hop
// processes a typed segment) + §13.4 (nodes advertise transform
// capabilities: a registry mapping (input_type → output_type) → handler).
//
// Composes the two on-device halves:
//   routing.zig    — processHop (where does the cell go)
//   mnca_tile.zig  — stepTilePayload (the MNCA compute kernel)
//
// A node holds a TransformRegistry. When a routed cell it must forward
// carries a type the node has a handler for, the node RUNS the transform
// (compute) on the cell payload and rotates the cell's type to the
// handler's output type before forwarding — "the transform is the unit of
// work being paid for" (§13.3). A node with no matching handler just
// forwards (a pure relay).
//
// Key wire-format fact: the cell's typeHash (offset 30) and payload
// (offset 256+) are OUTSIDE the routing checksum coverage window
// (160..216). So transforming the payload + rotating the type does NOT
// invalidate the routing CRC-32 that processHop already sealed — and the
// fresh HMAC is applied by the dispatcher on re-broadcast.

const std = @import("std");
const routing = @import("routing");
const mnca_tile = @import("mnca_tile");

const PAYLOAD_OFFSET = routing.HEADER_SIZE; // 256
const PAYLOAD_LEN = mnca_tile.PAYLOAD_SIZE; // 768
const TYPE_OFF = routing.TYPE_HASH_OFFSET; // 30

/// A transform takes the inbound cell payload (768 bytes) and writes the
/// computed outbound payload. Must not alias in↔out.
pub const TransformFn = *const fn (in_payload: *const [PAYLOAD_LEN]u8, out_payload: *[PAYLOAD_LEN]u8) void;

pub const TransformEntry = struct {
    input_type: [32]u8,
    output_type: [32]u8,
    func: TransformFn,
};

pub const TransformRegistry = struct {
    entries: []const TransformEntry,

    pub fn lookup(self: *const TransformRegistry, input_type: []const u8) ?*const TransformEntry {
        for (self.entries) |*e| {
            if (std.mem.eql(u8, &e.input_type, input_type)) return e;
        }
        return null;
    }
};

/// Empty registry — a pure relay that never transforms.
pub const PURE_RELAY = TransformRegistry{ .entries = &.{} };

pub const HopOutcome = union(enum) {
    not_routed,
    delivered,
    dropped: routing.HopRejectReason,
    /// Forwarded to the next hop; `transformed` true when a handler ran.
    forwarded: struct { transformed: bool },
};

/// processHop + apply a registered transform on forward (compute-on-hop).
///
/// `cell` read-only. On `.forwarded`, `out` (>= CELL_SIZE) holds the cell to
/// re-broadcast: routing region advanced + CRC-sealed by processHop, and —
/// if a handler matched the cell's current type — payload recomputed and
/// type rotated to the handler's output type.
pub fn processHopWithTransform(
    cell: []const u8,
    own_bca: *const [16]u8,
    out: []u8,
    registry: *const TransformRegistry,
) HopOutcome {
    if (cell.len < routing.CELL_SIZE or !routing.isRouted(cell)) return .not_routed;

    // validate_type=false: types are validated by the registry match here,
    // not by processHop's per-segment check (which assumes types are
    // pre-set; transforms set them as we go).
    switch (routing.processHop(cell, own_bca, out, false)) {
        .final_destination => return .delivered,
        .reject => |r| return .{ .dropped = r },
        .forward => {
            const cur_type = cell[TYPE_OFF..][0..32];
            if (registry.lookup(cur_type)) |entry| {
                // Compute: transform the payload (cell.payload → out.payload),
                // then rotate the type. cell and out are distinct buffers, so
                // the transform's in/out don't alias.
                entry.func(cell[PAYLOAD_OFFSET..][0..PAYLOAD_LEN], out[PAYLOAD_OFFSET..][0..PAYLOAD_LEN]);
                @memcpy(out[TYPE_OFF..][0..32], &entry.output_type);
                return .{ .forwarded = .{ .transformed = true } };
            }
            return .{ .forwarded = .{ .transformed = false } };
        },
    }
}

/// The MNCA tile-advance transform: advance the tile one generation via the
/// reference rule. Registered for (mnca.tile.tick → mnca.snapshot).
pub fn tileAdvanceTransform(in_payload: *const [PAYLOAD_LEN]u8, out_payload: *[PAYLOAD_LEN]u8) void {
    mnca_tile.stepTilePayload(in_payload, out_payload, mnca_tile.DEFAULT_MNCA_RULE);
}

/// 32-byte MNCA type-hash = SHA-256(dotted name). Matches the TS registry
/// (protocol-types/mnca/cell-types.ts computeMncaTypeHash).
pub fn mncaTypeHash(name: []const u8) [32]u8 {
    var out: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(name, &out, .{});
    return out;
}

/// Build the default MNCA transform registry: tile.tick → snapshot via
/// tileAdvanceTransform. Returns the single entry; caller wraps it in a
/// TransformRegistry. (Type-hashes computed at call time — call once.)
pub fn tileAdvanceEntry() TransformEntry {
    return .{
        .input_type = mncaTypeHash("mnca.tile.tick"),
        .output_type = mncaTypeHash("mnca.snapshot"),
        .func = tileAdvanceTransform,
    };
}

// ════════════════════════════════════════════════════════════════════════════
// Tests — exercised via the build (imports routing + mnca_tile modules).
// ════════════════════════════════════════════════════════════════════════════
const testing = std.testing;

fn writeU32le(buf: []u8, off: usize, v: u32) void {
    std.mem.writeInt(u32, buf[off..][0..4], v, .little);
}

/// Build a single-relay tile cell: type=tile.tick, NEXT_HOP=relay,
/// FINAL_DEST=dest, SEGMENTS_LEFT=1, with a tile in the payload.
fn buildTileCell(relay_bca: [16]u8, dest_bca: [16]u8) [routing.CELL_SIZE]u8 {
    var cell = [_]u8{0} ** routing.CELL_SIZE;
    @memcpy(cell[TYPE_OFF..][0..32], &mncaTypeHash("mnca.tile.tick"));
    cell[routing.OFF_ROUTING_MODE] = @intFromEnum(routing.RoutingMode.source_routed);
    writeU32le(&cell, routing.OFF_ROUTING_VERSION, routing.ROUTING_VERSION_V1);
    writeU32le(&cell, routing.OFF_SEGMENTS_LEFT, 1);
    writeU32le(&cell, routing.OFF_HOP_COUNT_BUDGET, 4);
    @memcpy(cell[routing.OFF_NEXT_HOP_BCA..][0..16], &relay_bca);
    @memcpy(cell[routing.OFF_FINAL_DEST_BCA..][0..16], &dest_bca);
    // A 7x7 tile in the payload (offset 256). Header at payload[0..16].
    mnca_tile.writeHeader(cell[PAYLOAD_OFFSET..][0..PAYLOAD_LEN], 1, 2, 100, 7, 7, 1, 0);
    // Three alive Moore-neighbours of (3,3) → (3,3) should be born next tick.
    const state = PAYLOAD_OFFSET + mnca_tile.OFF_STATE;
    cell[state + 2 * 7 + 2] = 200; // (2,2)
    cell[state + 3 * 7 + 2] = 200; // (2,3)
    cell[state + 4 * 7 + 2] = 200; // (2,4)
    _ = routing.setRoutingChecksum(&cell);
    return cell;
}

test "transform-on-hop: relay computes tile + rotates type on forward" {
    const relay: [16]u8 = .{0xB1} ** 16;
    const dest: [16]u8 = .{0xD1} ** 16;
    var cell = buildTileCell(relay, dest);

    const reg = TransformRegistry{ .entries = &.{tileAdvanceEntry()} };
    var out: [routing.CELL_SIZE]u8 = undefined;

    const outcome = processHopWithTransform(&cell, &relay, &out, &reg);
    try testing.expect(outcome == .forwarded);
    try testing.expect(outcome.forwarded.transformed);

    // Type rotated tile.tick → snapshot.
    try testing.expect(std.mem.eql(u8, out[TYPE_OFF..][0..32], &mncaTypeHash("mnca.snapshot")));
    // Tile advanced: tick 100 → 101, and (3,3) born (was 0, now grow_step=64).
    const op = out[PAYLOAD_OFFSET..][0..PAYLOAD_LEN];
    try testing.expectEqual(@as(u64, 101), mnca_tile.tick(op));
    try testing.expectEqual(@as(u8, 64), op[mnca_tile.OFF_STATE + 3 * 7 + 3]);
    // Routing advanced + checksum still valid (type/payload outside CRC window).
    try testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, out[routing.OFF_SEGMENTS_LEFT..][0..4], .little));
    try testing.expect(std.mem.eql(u8, out[routing.OFF_NEXT_HOP_BCA..][0..16], &dest));
    try testing.expect(routing.verifyRoutingChecksum(&out));
}

test "transform-on-hop: pure relay (no handler) forwards without transforming" {
    const relay: [16]u8 = .{0xB1} ** 16;
    const dest: [16]u8 = .{0xD1} ** 16;
    var cell = buildTileCell(relay, dest);
    var out: [routing.CELL_SIZE]u8 = undefined;

    const outcome = processHopWithTransform(&cell, &relay, &out, &PURE_RELAY);
    try testing.expect(outcome == .forwarded);
    try testing.expect(!outcome.forwarded.transformed);
    // Type unchanged; payload unchanged (still tile.tick @ tick 100).
    try testing.expect(std.mem.eql(u8, out[TYPE_OFF..][0..32], &mncaTypeHash("mnca.tile.tick")));
    try testing.expectEqual(@as(u64, 100), mnca_tile.tick(out[PAYLOAD_OFFSET..][0..PAYLOAD_LEN]));
}

test "transform-on-hop: delivered / dropped / not_routed pass through" {
    const own: [16]u8 = .{0xAB} ** 16;
    var out: [routing.CELL_SIZE]u8 = undefined;

    // not_routed.
    const short = [_]u8{0} ** 10;
    try testing.expect(processHopWithTransform(&short, &own, &out, &PURE_RELAY) == .not_routed);

    // delivered.
    var cell = [_]u8{0} ** routing.CELL_SIZE;
    cell[routing.OFF_ROUTING_MODE] = @intFromEnum(routing.RoutingMode.source_routed);
    @memcpy(cell[routing.OFF_NEXT_HOP_BCA..][0..16], &own);
    writeU32le(&cell, routing.OFF_SEGMENTS_LEFT, 0);
    _ = routing.setRoutingChecksum(&cell);
    try testing.expect(processHopWithTransform(&cell, &own, &out, &PURE_RELAY) == .delivered);

    // dropped (not_my_hop).
    var cell2 = [_]u8{0} ** routing.CELL_SIZE;
    cell2[routing.OFF_ROUTING_MODE] = @intFromEnum(routing.RoutingMode.source_routed);
    const other: [16]u8 = .{0x11} ** 16;
    @memcpy(cell2[routing.OFF_NEXT_HOP_BCA..][0..16], &other);
    writeU32le(&cell2, routing.OFF_SEGMENTS_LEFT, 1);
    _ = routing.setRoutingChecksum(&cell2);
    const d = processHopWithTransform(&cell2, &own, &out, &PURE_RELAY);
    try testing.expect(d == .dropped and d.dropped == .not_my_hop);
}

```
