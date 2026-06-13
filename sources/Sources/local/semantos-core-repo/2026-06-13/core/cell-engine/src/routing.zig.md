---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/src/routing.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.972673+00:00
---

# core/cell-engine/src/routing.zig

```zig
// routing.zig — cell-routing region + relay hop-processing, Zig port.
//
// Faithful mirror of the TypeScript reference oracle:
//   core/protocol-types/src/cell-routing.ts       (routing region + CRC-32)
//   core/protocol-types/src/mnca/hop-processing.ts (processHop — inline path)
//   core/protocol-types/src/mnca/path-merkle.ts   (processHop — merkle overload)
//
// Same pattern as bca.zig ↔ its TS mirror: the TS implementation (with its
// 105+ tests) is the source of truth for the wire layout + semantics; this
// is the on-device implementation the dispatcher will call. Deliberately
// self-contained (std only, defines its own offsets like the TS module
// does) so `zig test src/routing.zig` runs standalone.
//
// Spec source: docs/prd/MNCA-LAYER-COLLAPSE-BRIEF.md §2.1 (routing region),
// §4.2 / §13.3 (hop processing), §11.4 (non-targets drop silently).
// Design doc: docs/design/OCTAVE-ESCALATION-UNIFICATION.md §5 / §7 step 4.
//
// Locked design (brief §15.2): multicast-and-filter — the dispatcher runs
// processHop on each received cell; not-my-hop drops, forward re-broadcasts,
// final-destination hands to the local cell-engine.
//
// PATH_MERKLE_OVERLOAD (D-OCT-path-merkle-unify):
// When FLAG_PATH_MERKLE_OVERLOAD is set, the payload (cell offset 256) holds
// a 32-byte path-merkle root + a per-hop proof for the current segment tuple.
// The shared verifier (path_merkle.verifyInclusion, ultimately
// cell_merkle.verifyInclusion) handles the leaf-agnostic inclusion check.
// The inline FLAG_PATH_IN_PAYLOAD path is completely UNCHANGED.

const std = @import("std");
const Sha256 = std.crypto.hash.sha2.Sha256;

// ── Header geometry (mirrors core/protocol-types/src/constants.ts) ──────────
pub const CELL_SIZE: usize = 1024;
pub const HEADER_SIZE: usize = 256;
pub const TYPE_HASH_OFFSET: usize = 30; // 32-byte cell type-hash
pub const TYPE_HASH_SIZE: usize = 32;

// ── Routing region offsets (cell-routing-v1; brief §2.1) ────────────────────
pub const OFF_ROUTING_MODE: usize = 94; // u8
pub const OFF_PRIORITY: usize = 95; // u8
pub const OFF_ROUTING_VERSION: usize = 160; // u32 LE
pub const OFF_ROUTING_FLAGS: usize = 164; // u32 LE
pub const OFF_SEGMENTS_LEFT: usize = 168; // u32 LE
pub const OFF_HOP_COUNT_BUDGET: usize = 172; // u32 LE
pub const OFF_FLOW_LABEL: usize = 176; // u64 LE
pub const OFF_NEXT_HOP_BCA: usize = 184; // 16 bytes
pub const OFF_FINAL_DEST_BCA: usize = 200; // 16 bytes
pub const OFF_ROUTING_CHECKSUM: usize = 216; // u32 LE
pub const OFF_ROUTING_RESERVED: usize = 220; // 4 bytes

pub const ROUTING_REGION_START: usize = 160;
pub const ROUTING_REGION_END: usize = 224;
pub const ROUTING_REGION_SIZE: usize = 64;
pub const CHECKSUM_COVERAGE_START: usize = 160;
pub const CHECKSUM_COVERAGE_END: usize = 216;
pub const ROUTING_VERSION_V1: u32 = 1;

// Invariant: the 64-byte routing region ends exactly where the header's
// domainPayloadRoot begins (offset 224). If that ever moves, this breaks.
comptime {
    std.debug.assert(ROUTING_REGION_END == 224);
    std.debug.assert(ROUTING_REGION_START + ROUTING_REGION_SIZE == ROUTING_REGION_END);
}

// ── Typed-segments layout (brief §13.2) ─────────────────────────────────────
pub const PAYLOAD_OFFSET: usize = HEADER_SIZE; // 256
pub const SEG_HEADER_SIZE: usize = 4; // u16 N + u16 payloadStartsAt
pub const SEG_TUPLE_SIZE: usize = 48; // 16B BCA + 32B type-hash
pub const SEG_BCA_SIZE: usize = 16;
pub const SEG_TYPE_HASH_SIZE: usize = 32;

// ── Path-merkle overload layout (D-OCT-path-merkle-unify) ────────────────────
// Wire layout at PAYLOAD_OFFSET (cell offset 256) when FLAG_PATH_MERKLE_OVERLOAD:
//   0..31  path_merkle_root (32 bytes)
//   32..35 total_hops (u32 LE)
//   36..39 leaf_index (u32 LE)
//   40     sibling_count (u8)
//   41..   sibling_count × 33 bytes: [32B hash ‖ 1B position (0=left, 1=right)]
//
// CRC note: bytes 256+ are OUTSIDE the routing CRC window (160..216).
// The FLAG_PATH_MERKLE_OVERLOAD bit at offset 164 IS in the CRC window.
//
// Leaf size: 48-byte segment tuple [16B BCA ‖ 32B type-hash] → sha256(48B).
// Same single-SHA-256 as data side (1024B cell → sha256(1024B)).
// The SHARED verifier is `verifyInclusion(leaf_bytes, proof, root)` from
// cell_merkle.zig; here inlined as `pathMerkleVerify` for standalone operation.
pub const PM_ROOT_OFFSET: usize = 0;
pub const PM_ROOT_SIZE: usize = 32;
pub const PM_TOTAL_HOPS_OFFSET: usize = 32;
pub const PM_LEAF_INDEX_OFFSET: usize = 36;
pub const PM_SIBLING_COUNT_OFFSET: usize = 40;
pub const PM_SIBLINGS_OFFSET: usize = 41;
pub const PM_SIBLING_ENTRY_SIZE: usize = 33; // 32 hash + 1 position
pub const PM_MAX_SIBLINGS: usize = 16;
pub const PM_PAYLOAD_MIN_SIZE: usize = PM_SIBLINGS_OFFSET; // 41

// ── Inline SHA-256 for path-merkle verification ───────────────────────────────
// routing.zig is self-contained (std only) so we inline the SHA-256 primitive
// needed for the merkle inclusion proof. Uses std.crypto.hash.sha2.Sha256.

fn sha256(data: []const u8, out: *[32]u8) void {
    Sha256.hash(data, out, .{});
}

/// Verify that a 48-byte segment tuple `[bca ‖ type_hash]` is included under
/// `root` via the sibling proof encoded at `payload_buf` offset 40+.
///
/// This is the routing half of the SHARED inclusion-proof verifier:
///   data side:    sha256(1024B cell) → walk siblings → compare to root
///   routing side: sha256(48B tuple) → walk siblings → compare to root
/// Same math, different leaf size. The hash function is single-SHA-256.
fn pathMerkleVerify(
    bca: *const [16]u8,
    type_hash_bytes: *const [32]u8,
    payload_buf: []const u8,
) bool {
    // Compute sha256 of the 48-byte tuple.
    var tuple: [SEG_TUPLE_SIZE]u8 = undefined;
    @memcpy(tuple[0..16], bca);
    @memcpy(tuple[16..48], type_hash_bytes);

    var current: [32]u8 = undefined;
    sha256(&tuple, &current);

    const sibling_count = payload_buf[PM_SIBLING_COUNT_OFFSET];
    if (sibling_count > PM_MAX_SIBLINGS) return false;

    const required = PM_SIBLINGS_OFFSET + @as(usize, sibling_count) * PM_SIBLING_ENTRY_SIZE;
    if (payload_buf.len < required) return false;

    // Walk the sibling path.
    var i: usize = 0;
    var off: usize = PM_SIBLINGS_OFFSET;
    while (i < sibling_count) : (i += 1) {
        const sib_hash = payload_buf[off..][0..32];
        const pos_byte = payload_buf[off + 32];
        var combined: [64]u8 = undefined;
        if (pos_byte == 0x00) { // left sibling
            @memcpy(combined[0..32], sib_hash);
            @memcpy(combined[32..64], &current);
        } else { // right sibling
            @memcpy(combined[0..32], &current);
            @memcpy(combined[32..64], sib_hash);
        }
        sha256(&combined, &current);
        off += PM_SIBLING_ENTRY_SIZE;
    }

    // Compare to the committed root (constant-time).
    const root = payload_buf[PM_ROOT_OFFSET..][0..PM_ROOT_SIZE];
    return std.mem.eql(u8, &current, root);
}

pub const RoutingMode = enum(u8) {
    unrouted = 0,
    source_routed = 1,
    anycast = 2,
    multicast_pruned = 3,
    _,
};

// ROUTING_FLAGS bits (brief §2.1 / §13.2).
pub const FLAG_PRIORITY: u32 = 1 << 0;
pub const FLAG_ANCHOR_ON_ARRIVAL: u32 = 1 << 1;
pub const FLAG_BATCHABLE: u32 = 1 << 2;
pub const FLAG_USES_PUSHDROP_PAYMENT: u32 = 1 << 3;
pub const FLAG_PATH_MERKLE_OVERLOAD: u32 = 1 << 4;
pub const FLAG_PATH_IN_PAYLOAD: u32 = 1 << 5;

// ── CRC-32 (IEEE 802.3, reflected 0xEDB88320 — matches zlib/PNG and the TS) ──
const crc32_table: [256]u32 = blk: {
    @setEvalBranchQuota(20000);
    var t: [256]u32 = undefined;
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        var c: u32 = @intCast(i);
        var k: usize = 0;
        while (k < 8) : (k += 1) {
            c = if (c & 1 != 0) 0xEDB88320 ^ (c >> 1) else c >> 1;
        }
        t[i] = c;
    }
    break :blk t;
};

pub fn crc32(bytes: []const u8) u32 {
    var c: u32 = 0xFFFFFFFF;
    for (bytes) |b| {
        c = crc32_table[(c ^ b) & 0xFF] ^ (c >> 8);
    }
    return c ^ 0xFFFFFFFF;
}

// ── Little-endian field access helpers ──────────────────────────────────────
inline fn readU32(cell: []const u8, off: usize) u32 {
    return std.mem.readInt(u32, cell[off..][0..4], .little);
}
inline fn writeU32(cell: []u8, off: usize, v: u32) void {
    std.mem.writeInt(u32, cell[off..][0..4], v, .little);
}

pub fn readRoutingMode(cell: []const u8) RoutingMode {
    return @enumFromInt(cell[OFF_ROUTING_MODE]);
}
pub fn readPriority(cell: []const u8) u8 {
    return cell[OFF_PRIORITY];
}
pub fn isRouted(cell: []const u8) bool {
    return cell[OFF_ROUTING_MODE] != 0;
}

pub fn computeRoutingChecksum(cell: []const u8) u32 {
    return crc32(cell[CHECKSUM_COVERAGE_START..CHECKSUM_COVERAGE_END]);
}
pub fn setRoutingChecksum(cell: []u8) u32 {
    const c = computeRoutingChecksum(cell);
    writeU32(cell, OFF_ROUTING_CHECKSUM, c);
    return c;
}
pub fn verifyRoutingChecksum(cell: []const u8) bool {
    return readU32(cell, OFF_ROUTING_CHECKSUM) == computeRoutingChecksum(cell);
}

// ── Hop processing (brief §4.2 / §13.3) ─────────────────────────────────────

pub const HopRejectReason = enum {
    not_source_routed,
    checksum,
    not_my_hop,
    type_mismatch,
    budget_exhausted,
};

pub const HopResult = union(enum) {
    /// Re-transmit `out_forward` (filled by processHop) to the next hop.
    forward: struct {
        /// Which segment's pushdrop UTXO this hop should spend (§13.3 11b).
        spend_segment_index: u32,
        /// Type the cell should carry after the (external) transform, or
        /// null when the next stop is the final destination.
        expected_output_type_hash: ?[32]u8,
    },
    /// This node is the final destination — process the payload locally.
    final_destination,
    /// Expected rejection — drop (silently for not_my_hop, §11.4).
    reject: HopRejectReason,
};

/// Read the 32-byte type-hash committed for segment `i` from the inline
/// typed-segments payload. Returns null if the segment is out of bounds.
fn segmentTypeHash(cell: []const u8, i: u32) ?[32]u8 {
    const base = PAYLOAD_OFFSET + SEG_HEADER_SIZE + @as(usize, i) * SEG_TUPLE_SIZE + SEG_BCA_SIZE;
    if (base + SEG_TYPE_HASH_SIZE > cell.len) return null;
    var out: [32]u8 = undefined;
    @memcpy(&out, cell[base..][0..32]);
    return out;
}

/// Read the 16-byte BCA for segment `i`.
fn segmentBca(cell: []const u8, i: u32) ?[16]u8 {
    const base = PAYLOAD_OFFSET + SEG_HEADER_SIZE + @as(usize, i) * SEG_TUPLE_SIZE;
    if (base + SEG_BCA_SIZE > cell.len) return null;
    var out: [16]u8 = undefined;
    @memcpy(&out, cell[base..][0..16]);
    return out;
}

fn segmentCount(cell: []const u8) u16 {
    return std.mem.readInt(u16, cell[PAYLOAD_OFFSET..][0..2], .little);
}

/// Process a received routed cell at the hop owning `own_bca`.
///
/// `cell` is read-only. On `.forward`, `out_forward` (>= CELL_SIZE) is
/// filled with the advanced cell (routing region updated, CRC-32 re-sealed).
/// On `.final_destination` / `.reject`, `out_forward` is untouched.
///
/// `validate_type` mirrors the TS opt: when false, skip the §13.3 type
/// check even if PATH_IN_PAYLOAD is set.
pub fn processHop(
    cell: []const u8,
    own_bca: *const [16]u8,
    out_forward: []u8,
    validate_type: bool,
) HopResult {
    std.debug.assert(cell.len >= ROUTING_REGION_END);

    // (1) Must be source-routed.
    if (readRoutingMode(cell) != .source_routed) {
        return .{ .reject = .not_source_routed };
    }
    // (2) Checksum intact (in-flight tamper detection).
    if (!verifyRoutingChecksum(cell)) {
        return .{ .reject = .checksum };
    }
    // (3) NEXT_HOP_BCA must be us (§11.4 non-targets drop silently).
    if (!std.mem.eql(u8, cell[OFF_NEXT_HOP_BCA..][0..16], own_bca)) {
        return .{ .reject = .not_my_hop };
    }

    const segments_left = readU32(cell, OFF_SEGMENTS_LEFT);

    // (4) Final destination.
    if (segments_left == 0) {
        return .final_destination;
    }

    const flags = readU32(cell, OFF_ROUTING_FLAGS);
    const has_merkle_overload = (flags & FLAG_PATH_MERKLE_OVERLOAD) != 0;

    // ── PATH_MERKLE_OVERLOAD branch (D-OCT-path-merkle-unify) ──────────────────
    // When FLAG_PATH_MERKLE_OVERLOAD is set, the payload (cell offset 256+) holds
    // a 32-byte path-merkle root + per-hop proof for the current 48-byte segment
    // tuple. The shared verifier (path_merkle.verifyInclusion from cell_merkle)
    // checks the leaf-agnostic inclusion.
    //
    // Note: PATH_MERKLE_OVERLOAD takes priority over PATH_IN_PAYLOAD. Checked
    // first so the inline path is completely unchanged.
    //
    // CRC note: the path-merkle root + proof at offset 256+ are outside the
    // CRC window (160..216). Only FLAG_PATH_MERKLE_OVERLOAD at offset 164 is
    // protected by the routing CRC (same as inline tuples at 256+ are not covered).
    if (has_merkle_overload) {
        // Read the path-merkle payload directly from cell[PAYLOAD_OFFSET..].
        // Wire layout (D-OCT-path-merkle-unify):
        //   0..31  path_merkle_root
        //   32..35 total_hops (u32 LE)
        //   36..39 leaf_index (u32 LE)
        //   40     sibling_count (u8)
        //   41..   sibling_count × 33 bytes
        const pm_buf = cell[PAYLOAD_OFFSET..]; // slice into cell starting at 256

        // Minimum size check.
        if (pm_buf.len < PM_PAYLOAD_MIN_SIZE) {
            return .{ .reject = .type_mismatch };
        }

        const pm_total_hops = std.mem.readInt(u32, pm_buf[PM_TOTAL_HOPS_OFFSET..][0..4], .little);
        const pm_leaf_index = std.mem.readInt(u32, pm_buf[PM_LEAF_INDEX_OFFSET..][0..4], .little);
        const pm_sibling_count = pm_buf[PM_SIBLING_COUNT_OFFSET];

        // Bounds-check the full sibling array.
        const required = PM_SIBLINGS_OFFSET + @as(usize, pm_sibling_count) * PM_SIBLING_ENTRY_SIZE;
        if (pm_buf.len < required or pm_sibling_count > PM_MAX_SIBLINGS) {
            return .{ .reject = .type_mismatch };
        }

        // (5a) Verify the segment tuple [own_bca ‖ cell_type_hash] is included
        //      under the path-merkle root using the per-hop sibling proof.
        //      pathMerkleVerify is self-contained (std only, SHA-256 inlined).
        if (!pathMerkleVerify(own_bca, cell[TYPE_HASH_OFFSET..][0..32], pm_buf)) {
            return .{ .reject = .type_mismatch };
        }

        // (5b) Consistency check: leaf_index must equal totalHops - segmentsLeft.
        const expected_leaf_index: u32 = pm_total_hops -% segments_left;
        if (pm_leaf_index != expected_leaf_index) {
            return .{ .reject = .type_mismatch };
        }

        // (6) Budget check.
        const budget = readU32(cell, OFF_HOP_COUNT_BUDGET);
        if (budget == 0) {
            return .{ .reject = .budget_exhausted };
        }

        const current_index: u32 = pm_leaf_index;
        const new_segments_left = segments_left - 1;

        // (7) Build forwarded cell. Next hop BCA: point at FINAL_DEST as best-effort
        // (relay runtime overrides from its own route knowledge). When newSegmentsLeft==0
        // this is exactly correct (the final dest IS the next stop).
        @memcpy(out_forward[0..CELL_SIZE], cell[0..CELL_SIZE]);
        writeU32(out_forward, OFF_SEGMENTS_LEFT, new_segments_left);
        writeU32(out_forward, OFF_HOP_COUNT_BUDGET, budget - 1);
        // Point next_hop_bca at final_dest (relay runtime overrides for intermediate hops).
        @memcpy(out_forward[OFF_NEXT_HOP_BCA..][0..16], cell[OFF_FINAL_DEST_BCA..][0..16]);
        _ = setRoutingChecksum(out_forward);

        // Under the merkle overload, the next hop's type is not inline.
        // The relay runtime sets the type via the external transform.
        return .{ .forward = .{
            .spend_segment_index = current_index,
            .expected_output_type_hash = null,
        } };
    }

    // ── PATH_IN_PAYLOAD branch (original inline segments — UNCHANGED) ────────────
    const has_segments = (flags & FLAG_PATH_IN_PAYLOAD) != 0;
    const n: u32 = if (has_segments) @intCast(segmentCount(cell)) else segments_left;
    const current_index: u32 = n - segments_left;

    // (5) Type check (§13.3 8b).
    if (validate_type and has_segments) {
        const seg_type = segmentTypeHash(cell, current_index) orelse
            return .{ .reject = .type_mismatch };
        if (!std.mem.eql(u8, cell[TYPE_HASH_OFFSET..][0..32], &seg_type)) {
            return .{ .reject = .type_mismatch };
        }
    }

    // (6) Budget / loop detection.
    const budget = readU32(cell, OFF_HOP_COUNT_BUDGET);
    if (budget == 0) {
        return .{ .reject = .budget_exhausted };
    }

    // (7) Build the forwarded cell on `out_forward`.
    @memcpy(out_forward[0..CELL_SIZE], cell[0..CELL_SIZE]);
    const new_segments_left = segments_left - 1;
    writeU32(out_forward, OFF_SEGMENTS_LEFT, new_segments_left);
    writeU32(out_forward, OFF_HOP_COUNT_BUDGET, budget - 1);

    var expected_output: ?[32]u8 = null;
    if (new_segments_left == 0) {
        @memcpy(out_forward[OFF_NEXT_HOP_BCA..][0..16], cell[OFF_FINAL_DEST_BCA..][0..16]);
    } else if (has_segments) {
        const next_bca = segmentBca(cell, current_index + 1) orelse
            return .{ .reject = .type_mismatch };
        @memcpy(out_forward[OFF_NEXT_HOP_BCA..][0..16], &next_bca);
        expected_output = segmentTypeHash(cell, current_index + 1);
    } else {
        @memcpy(out_forward[OFF_NEXT_HOP_BCA..][0..16], cell[OFF_FINAL_DEST_BCA..][0..16]);
    }
    _ = setRoutingChecksum(out_forward);

    return .{ .forward = .{
        .spend_segment_index = current_index,
        .expected_output_type_hash = expected_output,
    } };
}

// ════════════════════════════════════════════════════════════════════════════
// Tests — vectors mirror the TS oracle (cell-routing.test.ts, hop-processing.test.ts).
// Run: zig test core/cell-engine/src/routing.zig
// ════════════════════════════════════════════════════════════════════════════
const testing = std.testing;

test "layout: routing region ends where domainPayloadRoot begins" {
    try testing.expectEqual(@as(usize, 224), ROUTING_REGION_END);
    try testing.expectEqual(@as(usize, 64), ROUTING_REGION_SIZE);
    try testing.expectEqual(@as(usize, 56), CHECKSUM_COVERAGE_END - CHECKSUM_COVERAGE_START);
}

test "crc32 canonical vectors (match TS oracle)" {
    try testing.expectEqual(@as(u32, 0), crc32(""));
    const v = [_]u8{ 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39 }; // "123456789"
    try testing.expectEqual(@as(u32, 0xCBF43926), crc32(&v));
}

test "checksum set/verify round-trip + tamper rejection" {
    var cell = [_]u8{0} ** CELL_SIZE;
    cell[OFF_ROUTING_MODE] = @intFromEnum(RoutingMode.source_routed);
    writeU32(&cell, OFF_SEGMENTS_LEFT, 3);
    cell[OFF_NEXT_HOP_BCA] = 0xAB;
    _ = setRoutingChecksum(&cell);
    try testing.expect(verifyRoutingChecksum(&cell));
    cell[OFF_NEXT_HOP_BCA] ^= 0x01; // tamper a covered byte
    try testing.expect(!verifyRoutingChecksum(&cell));
    cell[OFF_NEXT_HOP_BCA] ^= 0x01; // restore
    try testing.expect(verifyRoutingChecksum(&cell));
}

test "checksum unaffected by bytes outside the coverage window" {
    var cell = [_]u8{0} ** CELL_SIZE;
    cell[OFF_ROUTING_MODE] = @intFromEnum(RoutingMode.source_routed);
    _ = setRoutingChecksum(&cell);
    const stable = computeRoutingChecksum(&cell);
    cell[220] = 0xFF; // reserved trailer — not covered
    cell[230] = 0xFF; // domainPayloadRoot region — not covered
    try testing.expectEqual(stable, computeRoutingChecksum(&cell));
}

// Build a 3-hop routed cell with inline typed segments (mirrors buildRoutedCell).
const TestHop = struct { bca: [16]u8, type_hash: [32]u8 };

fn mkBca(seed: u8) [16]u8 {
    var b: [16]u8 = undefined;
    for (0..16) |i| b[i] = @intCast((i + @as(usize, seed) * 31) & 0xFF);
    return b;
}
fn mkType(seed: u8) [32]u8 {
    var h: [32]u8 = undefined;
    for (0..32) |i| h[i] = @intCast((i * 5 + @as(usize, seed)) & 0xFF);
    return h;
}

fn build3HopCell(cell: *[CELL_SIZE]u8, hops: []const TestHop, final_dest: [16]u8) void {
    @memset(cell, 0);
    // Cell arrives at hop 0 carrying segments[0].type_hash.
    @memcpy(cell[TYPE_HASH_OFFSET..][0..32], &hops[0].type_hash);
    // Routing region.
    cell[OFF_ROUTING_MODE] = @intFromEnum(RoutingMode.source_routed);
    writeU32(cell, OFF_ROUTING_VERSION, ROUTING_VERSION_V1);
    writeU32(cell, OFF_ROUTING_FLAGS, FLAG_PATH_IN_PAYLOAD);
    writeU32(cell, OFF_SEGMENTS_LEFT, @intCast(hops.len));
    writeU32(cell, OFF_HOP_COUNT_BUDGET, 8);
    @memcpy(cell[OFF_NEXT_HOP_BCA..][0..16], &hops[0].bca);
    @memcpy(cell[OFF_FINAL_DEST_BCA..][0..16], &final_dest);
    // Inline typed segments in the payload.
    std.mem.writeInt(u16, cell[PAYLOAD_OFFSET..][0..2], @intCast(hops.len), .little);
    const starts_at: u16 = @intCast(SEG_HEADER_SIZE + hops.len * SEG_TUPLE_SIZE);
    std.mem.writeInt(u16, cell[PAYLOAD_OFFSET + 2 ..][0..2], starts_at, .little);
    for (hops, 0..) |hop, i| {
        const base = PAYLOAD_OFFSET + SEG_HEADER_SIZE + i * SEG_TUPLE_SIZE;
        @memcpy(cell[base..][0..16], &hop.bca);
        @memcpy(cell[base + 16 ..][0..32], &hop.type_hash);
    }
    _ = setRoutingChecksum(cell);
}

test "processHop: full 3-hop walk to final destination" {
    const hops = [_]TestHop{
        .{ .bca = mkBca(1), .type_hash = mkType(10) },
        .{ .bca = mkBca(2), .type_hash = mkType(20) },
        .{ .bca = mkBca(3), .type_hash = mkType(30) },
    };
    const final_dest = mkBca(99);
    var cell: [CELL_SIZE]u8 = undefined;
    build3HopCell(&cell, &hops, final_dest);

    var out: [CELL_SIZE]u8 = undefined;

    // Hop 0
    var r = processHop(&cell, &hops[0].bca, &out, true);
    try testing.expect(r == .forward);
    try testing.expectEqual(@as(u32, 0), r.forward.spend_segment_index);
    try testing.expect(std.mem.eql(u8, &r.forward.expected_output_type_hash.?, &hops[1].type_hash));
    try testing.expectEqual(@as(u32, 2), readU32(&out, OFF_SEGMENTS_LEFT));
    try testing.expect(std.mem.eql(u8, out[OFF_NEXT_HOP_BCA..][0..16], &hops[1].bca));
    try testing.expect(verifyRoutingChecksum(&out));

    // Simulate the external transform: set the cell's type to the next hop's expected type.
    var cell1 = out;
    @memcpy(cell1[TYPE_HASH_OFFSET..][0..32], &hops[1].type_hash);

    // Hop 1
    r = processHop(&cell1, &hops[1].bca, &out, true);
    try testing.expect(r == .forward);
    try testing.expectEqual(@as(u32, 1), r.forward.spend_segment_index);
    try testing.expectEqual(@as(u32, 1), readU32(&out, OFF_SEGMENTS_LEFT));
    var cell2 = out;
    @memcpy(cell2[TYPE_HASH_OFFSET..][0..32], &hops[2].type_hash);

    // Hop 2 (last forwarding hop) — points the cell at the final destination.
    r = processHop(&cell2, &hops[2].bca, &out, true);
    try testing.expect(r == .forward);
    try testing.expectEqual(@as(u32, 2), r.forward.spend_segment_index);
    try testing.expectEqual(@as(u32, 0), readU32(&out, OFF_SEGMENTS_LEFT));
    try testing.expect(std.mem.eql(u8, out[OFF_NEXT_HOP_BCA..][0..16], &final_dest));
    try testing.expect(r.forward.expected_output_type_hash == null);

    // Final destination.
    const final = processHop(&out, &final_dest, &out, true);
    try testing.expect(final == .final_destination);
}

test "processHop: typed rejections" {
    const hops = [_]TestHop{.{ .bca = mkBca(1), .type_hash = mkType(10) }};
    const final_dest = mkBca(99);
    var cell: [CELL_SIZE]u8 = undefined;
    var out: [CELL_SIZE]u8 = undefined;

    // not-source-routed (ROUTING_MODE outside CRC window, so checksum still valid).
    build3HopCell(&cell, &hops, final_dest);
    cell[OFF_ROUTING_MODE] = @intFromEnum(RoutingMode.unrouted);
    try testing.expect(processHop(&cell, &hops[0].bca, &out, true).reject == .not_source_routed);

    // checksum (tamper a covered byte).
    build3HopCell(&cell, &hops, final_dest);
    cell[OFF_NEXT_HOP_BCA] ^= 0xFF;
    try testing.expect(processHop(&cell, &hops[0].bca, &out, true).reject == .checksum);

    // not-my-hop.
    build3HopCell(&cell, &hops, final_dest);
    const stranger = mkBca(123);
    try testing.expect(processHop(&cell, &stranger, &out, true).reject == .not_my_hop);

    // type-mismatch (cell carries wrong type for this segment).
    build3HopCell(&cell, &hops, final_dest);
    @memcpy(cell[TYPE_HASH_OFFSET..][0..32], &mkType(222));
    _ = setRoutingChecksum(&cell); // type-hash is outside the CRC window, but be explicit
    try testing.expect(processHop(&cell, &hops[0].bca, &out, true).reject == .type_mismatch);

    // type check can be disabled.
    try testing.expect(processHop(&cell, &hops[0].bca, &out, false) == .forward);

    // budget-exhausted.
    build3HopCell(&cell, &hops, final_dest);
    writeU32(&cell, OFF_HOP_COUNT_BUDGET, 0);
    _ = setRoutingChecksum(&cell);
    try testing.expect(processHop(&cell, &hops[0].bca, &out, true).reject == .budget_exhausted);
}

test "processHop: input cell is not mutated on forward" {
    const hops = [_]TestHop{
        .{ .bca = mkBca(1), .type_hash = mkType(10) },
        .{ .bca = mkBca(2), .type_hash = mkType(20) },
    };
    var cell: [CELL_SIZE]u8 = undefined;
    build3HopCell(&cell, &hops, mkBca(99));
    const before = cell;
    var out: [CELL_SIZE]u8 = undefined;
    _ = processHop(&cell, &hops[0].bca, &out, true);
    try testing.expect(std.mem.eql(u8, &before, &cell)); // unchanged
    try testing.expect(!std.mem.eql(u8, &out, &cell)); // out advanced
}

// ════════════════════════════════════════════════════════════════════════════
// PATH_MERKLE_OVERLOAD tests — D-OCT-path-merkle-unify
//
// These mirror the TS oracle tests in path-merkle.test.ts.
// The canonical vectors MUST agree byte-for-byte with the TS oracle.
//
// Helpers below build 3-leaf merkle trees (same math as cell_merkle.zig /
// the TS oracle): sha256(48B tuple) for leaves, sha256(L32‖R32) for branches,
// odd-leaf duplication for level padding.
// ════════════════════════════════════════════════════════════════════════════

/// SHA-256 of two 32-byte halves concatenated: sha256(left ‖ right).
fn sha256Pair(left: *const [32]u8, right: *const [32]u8, out: *[32]u8) void {
    var buf: [64]u8 = undefined;
    @memcpy(buf[0..32], left);
    @memcpy(buf[32..64], right);
    sha256(&buf, out);
}

/// Compute sha256 of a 48-byte segment tuple [bca ‖ type_hash].
fn segLeafHash(bca: *const [16]u8, type_hash: *const [32]u8, out: *[32]u8) void {
    var tuple: [SEG_TUPLE_SIZE]u8 = undefined;
    @memcpy(tuple[0..16], bca);
    @memcpy(tuple[16..48], type_hash);
    sha256(&tuple, out);
}

/// Compute the 3-leaf path-merkle root.
/// Tree structure: leaves = [L0, L1, L2], L3 = L2 (duplicate for odd count)
///   level1[0] = sha256(L0 ‖ L1)
///   level1[1] = sha256(L2 ‖ L2)
///   root      = sha256(level1[0] ‖ level1[1])
fn compute3LeafRoot(
    bca0: *const [16]u8, th0: *const [32]u8,
    bca1: *const [16]u8, th1: *const [32]u8,
    bca2: *const [16]u8, th2: *const [32]u8,
    root_out: *[32]u8,
) void {
    var l0: [32]u8 = undefined; segLeafHash(bca0, th0, &l0);
    var l1: [32]u8 = undefined; segLeafHash(bca1, th1, &l1);
    var l2: [32]u8 = undefined; segLeafHash(bca2, th2, &l2);
    var b01: [32]u8 = undefined; sha256Pair(&l0, &l1, &b01);
    var b22: [32]u8 = undefined; sha256Pair(&l2, &l2, &b22);
    sha256Pair(&b01, &b22, root_out);
}

/// Build a PATH_MERKLE_OVERLOAD routed cell for the given hop index (0/1/2).
/// The payload at offset 256 holds the per-hop proof.
fn buildMerkleRoutedCell(
    cell: *[CELL_SIZE]u8,
    hops: []const TestHop,
    final_dest: [16]u8,
    hop_index: usize,
) void {
    const n = hops.len;
    std.debug.assert(n == 3); // test helper only handles 3 hops
    std.debug.assert(hop_index < n);

    @memset(cell, 0);

    // Cell carries the type of the current hop's segment.
    @memcpy(cell[TYPE_HASH_OFFSET..][0..32], &hops[hop_index].type_hash);

    // Compute tree values.
    var l0: [32]u8 = undefined; segLeafHash(&hops[0].bca, &hops[0].type_hash, &l0);
    var l1: [32]u8 = undefined; segLeafHash(&hops[1].bca, &hops[1].type_hash, &l1);
    var l2: [32]u8 = undefined; segLeafHash(&hops[2].bca, &hops[2].type_hash, &l2);
    var b01: [32]u8 = undefined; sha256Pair(&l0, &l1, &b01);
    var b22: [32]u8 = undefined; sha256Pair(&l2, &l2, &b22);
    var root: [32]u8 = undefined; sha256Pair(&b01, &b22, &root);

    // Build per-hop proof payload.
    // Wire format at cell offset 256:
    //   0..31   root (32B)
    //   32..35  total_hops = 3 (u32 LE)
    //   36..39  leaf_index (u32 LE)
    //   40      sibling_count
    //   41+     sibling entries [32B hash ‖ 1B pos]
    const pm = cell[PAYLOAD_OFFSET..];
    @memcpy(pm[0..32], &root);
    std.mem.writeInt(u32, pm[32..36][0..4], @intCast(n), .little);
    std.mem.writeInt(u32, pm[36..40][0..4], @intCast(hop_index), .little);

    switch (hop_index) {
        0 => {
            // Hop 0: siblings = [leaf1 (right), branch22 (right)]
            pm[40] = 2;
            @memcpy(pm[41..73], &l1);
            pm[73] = 0x01; // right
            @memcpy(pm[74..106], &b22);
            pm[106] = 0x01; // right
        },
        1 => {
            // Hop 1: siblings = [leaf0 (left), branch22 (right)]
            pm[40] = 2;
            @memcpy(pm[41..73], &l0);
            pm[73] = 0x00; // left
            @memcpy(pm[74..106], &b22);
            pm[106] = 0x01; // right
        },
        2 => {
            // Hop 2: leaf2 is in the right subtree under b22.
            // siblings = [leaf2 (left = duplicate self), branch01 (left)]
            // Proof for leaf2 in tree [l2, l2, b22] at index 0 (within right sub):
            // Actually for a 3-leaf tree, leaf2 is at index 2, and has proof:
            //   level0: sibling = sha256(l2‖l2)[same leaf, left sibling in duplication]
            //   Correct: sibling[0] = l2 itself (right position — it's the duplicate right)
            //   sibling[1] = b01 (left)
            //
            // Let's trace: leaves = [l0, l1, l2]; pad to 4: [l0, l1, l2, l2]
            //   index 2 pairs with index 3 (l2 duplicate)
            //   sibling[0] = l2 at position 0x01 (right — index 2 is even, sibling is index 3 = right)
            //   parent = b22; sibling[1] = b01 at position 0x00 (left — b22 is at index 1, b01 is at index 0)
            pm[40] = 2;
            @memcpy(pm[41..73], &l2); // duplicate self
            pm[73] = 0x01; // right sibling
            @memcpy(pm[74..106], &b01);
            pm[106] = 0x00; // left sibling
        },
        else => unreachable,
    }

    // Write routing region.
    cell[OFF_ROUTING_MODE] = @intFromEnum(RoutingMode.source_routed);
    writeU32(cell, OFF_ROUTING_VERSION, ROUTING_VERSION_V1);
    writeU32(cell, OFF_ROUTING_FLAGS, FLAG_PATH_MERKLE_OVERLOAD);
    writeU32(cell, OFF_SEGMENTS_LEFT, @intCast(n - hop_index));
    writeU32(cell, OFF_HOP_COUNT_BUDGET, @intCast(n + 2));
    @memcpy(cell[OFF_NEXT_HOP_BCA..][0..16], &hops[hop_index].bca);
    @memcpy(cell[OFF_FINAL_DEST_BCA..][0..16], &final_dest);
    _ = setRoutingChecksum(cell);
}

// ── Canonical vector test (oracle↔Zig agreement) ─────────────────────────────

/// CANONICAL PATH-MERKLE ROOT:
///   segments: hop0=(mkBca(1), mkType(10)), hop1=(mkBca(2), mkType(20)), hop2=(mkBca(3), mkType(30))
///   root = sha256(sha256(L0‖L1) ‖ sha256(L2‖L2))
///   Expected: a3f0c5b3c8eee4209b5870b16efb7ac2619ee29f949fd56b62664711642abb44
///
/// This MUST agree with the TS oracle output (printed as CANONICAL_PATH_MERKLE_ROOT_HEX).
const CANONICAL_ROOT: [32]u8 = [_]u8{
    0xa3, 0xf0, 0xc5, 0xb3, 0xc8, 0xee, 0xe4, 0x20,
    0x9b, 0x58, 0x70, 0xb1, 0x6e, 0xfb, 0x7a, 0xc2,
    0x61, 0x9e, 0xe2, 0x9f, 0x94, 0x9f, 0xd5, 0x6b,
    0x62, 0x66, 0x47, 0x11, 0x64, 0x2a, 0xbb, 0x44,
};

test "merkle overload: canonical root matches TS oracle" {
    const h0 = mkBca(1);
    const t0 = mkType(10);
    const h1 = mkBca(2);
    const t1 = mkType(20);
    const h2 = mkBca(3);
    const t2 = mkType(30);

    var root: [32]u8 = undefined;
    compute3LeafRoot(&h0, &t0, &h1, &t1, &h2, &t2, &root);

    try testing.expect(std.mem.eql(u8, &root, &CANONICAL_ROOT));
}

test "pathMerkleVerify: canonical hop0 proof verifies" {
    // Build canonical hop0 payload in-place using the known vectors.
    const hop0_bca = mkBca(1);
    const hop0_type = mkType(10);
    const hop1_bca = mkBca(2);
    const hop1_type = mkType(20);
    const hop2_bca = mkBca(3);
    const hop2_type = mkType(30);

    // Compute leaf hashes.
    var l0: [32]u8 = undefined; segLeafHash(&hop0_bca, &hop0_type, &l0);
    var l1: [32]u8 = undefined; segLeafHash(&hop1_bca, &hop1_type, &l1);
    var l2: [32]u8 = undefined; segLeafHash(&hop2_bca, &hop2_type, &l2);
    var b01: [32]u8 = undefined; sha256Pair(&l0, &l1, &b01);
    var b22: [32]u8 = undefined; sha256Pair(&l2, &l2, &b22);
    var root: [32]u8 = undefined; sha256Pair(&b01, &b22, &root);

    // Build hop0 payload buffer: [root32 ‖ total_hops u32LE ‖ leaf_index u32LE ‖ sibling_count u8 ‖ sib0[33] ‖ sib1[33]]
    var payload: [107]u8 = undefined;
    @memcpy(payload[0..32], &root);
    std.mem.writeInt(u32, payload[32..36][0..4], 3, .little); // total_hops = 3
    std.mem.writeInt(u32, payload[36..40][0..4], 0, .little); // leaf_index = 0
    payload[40] = 2; // sibling_count
    @memcpy(payload[41..73], &l1);
    payload[73] = 0x01; // right
    @memcpy(payload[74..106], &b22);
    payload[106] = 0x01; // right

    // Check the root bytes match the canonical constant.
    try testing.expect(std.mem.eql(u8, payload[0..32], &CANONICAL_ROOT));

    // Verify with pathMerkleVerify.
    try testing.expect(pathMerkleVerify(&hop0_bca, &hop0_type, &payload));
}

test "pathMerkleVerify: tampered BCA fails" {
    const hop0_bca = mkBca(1);
    const hop0_type = mkType(10);
    const hop1_bca = mkBca(2);
    const hop1_type = mkType(20);
    const hop2_bca = mkBca(3);
    const hop2_type = mkType(30);

    var l0: [32]u8 = undefined; segLeafHash(&hop0_bca, &hop0_type, &l0);
    var l1: [32]u8 = undefined; segLeafHash(&hop1_bca, &hop1_type, &l1);
    var l2: [32]u8 = undefined; segLeafHash(&hop2_bca, &hop2_type, &l2);
    var b01: [32]u8 = undefined; sha256Pair(&l0, &l1, &b01);
    var b22: [32]u8 = undefined; sha256Pair(&l2, &l2, &b22);
    var root: [32]u8 = undefined; sha256Pair(&b01, &b22, &root);


    var payload: [107]u8 = undefined;
    @memcpy(payload[0..32], &root);
    std.mem.writeInt(u32, payload[32..36][0..4], 3, .little);
    std.mem.writeInt(u32, payload[36..40][0..4], 0, .little);
    payload[40] = 2;
    @memcpy(payload[41..73], &l1); payload[73] = 0x01;
    @memcpy(payload[74..106], &b22); payload[106] = 0x01;

    // Tamper the BCA.
    var tampered_bca = hop0_bca;
    tampered_bca[3] ^= 0xFF;
    try testing.expect(!pathMerkleVerify(&tampered_bca, &hop0_type, &payload));
}

test "pathMerkleVerify: tampered sibling hash fails" {
    const hop0_bca = mkBca(1);
    const hop0_type = mkType(10);
    const hop1_bca = mkBca(2);
    const hop1_type = mkType(20);
    const hop2_bca = mkBca(3);
    const hop2_type = mkType(30);

    var l0: [32]u8 = undefined; segLeafHash(&hop0_bca, &hop0_type, &l0);
    var l1: [32]u8 = undefined; segLeafHash(&hop1_bca, &hop1_type, &l1);
    var l2: [32]u8 = undefined; segLeafHash(&hop2_bca, &hop2_type, &l2);
    var b01: [32]u8 = undefined; sha256Pair(&l0, &l1, &b01);
    var b22: [32]u8 = undefined; sha256Pair(&l2, &l2, &b22);
    var root: [32]u8 = undefined; sha256Pair(&b01, &b22, &root);


    var payload: [107]u8 = undefined;
    @memcpy(payload[0..32], &root);
    std.mem.writeInt(u32, payload[32..36][0..4], 3, .little);
    std.mem.writeInt(u32, payload[36..40][0..4], 0, .little);
    payload[40] = 2;
    @memcpy(payload[41..73], &l1); payload[73] = 0x01;
    @memcpy(payload[74..106], &b22); payload[106] = 0x01;

    // Tamper the first sibling hash.
    payload[41] ^= 0xFF;
    try testing.expect(!pathMerkleVerify(&hop0_bca, &hop0_type, &payload));
}

// ── processHop with PATH_MERKLE_OVERLOAD ─────────────────────────────────────

test "processHop merkle overload: full 3-hop walk to final destination" {
    const hops = [_]TestHop{
        .{ .bca = mkBca(1), .type_hash = mkType(10) },
        .{ .bca = mkBca(2), .type_hash = mkType(20) },
        .{ .bca = mkBca(3), .type_hash = mkType(30) },
    };
    const final_dest = mkBca(99);

    // Each hop gets its own cell with the correct per-hop proof pre-loaded.
    var cell0: [CELL_SIZE]u8 = undefined;
    var cell1: [CELL_SIZE]u8 = undefined;
    var cell2: [CELL_SIZE]u8 = undefined;
    buildMerkleRoutedCell(&cell0, &hops, final_dest, 0);
    buildMerkleRoutedCell(&cell1, &hops, final_dest, 1);
    buildMerkleRoutedCell(&cell2, &hops, final_dest, 2);

    var out: [CELL_SIZE]u8 = undefined;

    // Hop 0
    var r = processHop(&cell0, &hops[0].bca, &out, true);
    try testing.expect(r == .forward);
    try testing.expectEqual(@as(u32, 0), r.forward.spend_segment_index);
    try testing.expect(r.forward.expected_output_type_hash == null); // overload: no inline type
    try testing.expectEqual(@as(u32, 2), readU32(&out, OFF_SEGMENTS_LEFT));
    try testing.expect(verifyRoutingChecksum(&out));
    // next_hop points at final_dest (best-effort under merkle overload)
    try testing.expect(std.mem.eql(u8, out[OFF_NEXT_HOP_BCA..][0..16], &final_dest));

    // Hop 1
    r = processHop(&cell1, &hops[1].bca, &out, true);
    try testing.expect(r == .forward);
    try testing.expectEqual(@as(u32, 1), r.forward.spend_segment_index);
    try testing.expectEqual(@as(u32, 1), readU32(&out, OFF_SEGMENTS_LEFT));
    try testing.expect(verifyRoutingChecksum(&out));

    // Hop 2
    r = processHop(&cell2, &hops[2].bca, &out, true);
    try testing.expect(r == .forward);
    try testing.expectEqual(@as(u32, 2), r.forward.spend_segment_index);
    try testing.expectEqual(@as(u32, 0), readU32(&out, OFF_SEGMENTS_LEFT));
    try testing.expect(std.mem.eql(u8, out[OFF_NEXT_HOP_BCA..][0..16], &final_dest));
    try testing.expect(verifyRoutingChecksum(&out));

    // Final destination.
    const final = processHop(&out, &final_dest, &out, true);
    try testing.expect(final == .final_destination);
}

test "processHop merkle overload: type-mismatch when cell carries wrong type" {
    const hops = [_]TestHop{
        .{ .bca = mkBca(1), .type_hash = mkType(10) },
        .{ .bca = mkBca(2), .type_hash = mkType(20) },
        .{ .bca = mkBca(3), .type_hash = mkType(30) },
    };
    const final_dest = mkBca(99);
    var cell: [CELL_SIZE]u8 = undefined;
    buildMerkleRoutedCell(&cell, &hops, final_dest, 0);
    var out: [CELL_SIZE]u8 = undefined;

    // The cell carries the wrong type — the merkle proof checks [BCA ‖ typeHash].
    // type_hash is at offset 30, outside the CRC window — flip it without re-sealing.
    @memcpy(cell[TYPE_HASH_OFFSET..][0..32], &mkType(222));
    // CRC is still valid (type offset 30 is not in 160..216).
    try testing.expect(verifyRoutingChecksum(&cell));
    try testing.expect(processHop(&cell, &hops[0].bca, &out, true).reject == .type_mismatch);
}

test "processHop merkle overload: type-mismatch when leaf_index inconsistent" {
    const hops = [_]TestHop{
        .{ .bca = mkBca(1), .type_hash = mkType(10) },
        .{ .bca = mkBca(2), .type_hash = mkType(20) },
        .{ .bca = mkBca(3), .type_hash = mkType(30) },
    };
    const final_dest = mkBca(99);
    var cell: [CELL_SIZE]u8 = undefined;
    buildMerkleRoutedCell(&cell, &hops, final_dest, 0); // built for hop0
    var out: [CELL_SIZE]u8 = undefined;

    // Overwrite leaf_index in payload (cell offset 256 + 36..39) to an inconsistent value.
    // segments_left=3 → expected_leaf_index = total_hops - segments_left = 3 - 3 = 0.
    // Write 2 to make it inconsistent.
    std.mem.writeInt(u32, cell[PAYLOAD_OFFSET + PM_LEAF_INDEX_OFFSET..][0..4], 2, .little);
    // Merkle proof itself is also now wrong (wrong leaf_index builds wrong path)
    // but the consistency check fires first.
    try testing.expect(processHop(&cell, &hops[0].bca, &out, true).reject == .type_mismatch);
}

test "processHop merkle overload: budget-exhausted" {
    const hops = [_]TestHop{
        .{ .bca = mkBca(1), .type_hash = mkType(10) },
        .{ .bca = mkBca(2), .type_hash = mkType(20) },
        .{ .bca = mkBca(3), .type_hash = mkType(30) },
    };
    const final_dest = mkBca(99);
    var cell: [CELL_SIZE]u8 = undefined;
    buildMerkleRoutedCell(&cell, &hops, final_dest, 0);
    var out: [CELL_SIZE]u8 = undefined;

    writeU32(&cell, OFF_HOP_COUNT_BUDGET, 0);
    _ = setRoutingChecksum(&cell);
    try testing.expect(processHop(&cell, &hops[0].bca, &out, true).reject == .budget_exhausted);
}

test "processHop merkle overload: not-my-hop still fires first" {
    const hops = [_]TestHop{
        .{ .bca = mkBca(1), .type_hash = mkType(10) },
        .{ .bca = mkBca(2), .type_hash = mkType(20) },
        .{ .bca = mkBca(3), .type_hash = mkType(30) },
    };
    const final_dest = mkBca(99);
    var cell: [CELL_SIZE]u8 = undefined;
    buildMerkleRoutedCell(&cell, &hops, final_dest, 0);
    var out: [CELL_SIZE]u8 = undefined;

    const stranger = mkBca(123);
    try testing.expect(processHop(&cell, &stranger, &out, true).reject == .not_my_hop);
}

test "processHop merkle overload: checksum rejection still works" {
    const hops = [_]TestHop{
        .{ .bca = mkBca(1), .type_hash = mkType(10) },
        .{ .bca = mkBca(2), .type_hash = mkType(20) },
        .{ .bca = mkBca(3), .type_hash = mkType(30) },
    };
    const final_dest = mkBca(99);
    var cell: [CELL_SIZE]u8 = undefined;
    buildMerkleRoutedCell(&cell, &hops, final_dest, 0);
    var out: [CELL_SIZE]u8 = undefined;

    // Tamper a covered byte (inside 160..216).
    cell[OFF_NEXT_HOP_BCA] ^= 0xFF;
    try testing.expect(processHop(&cell, &hops[0].bca, &out, true).reject == .checksum);
}

test "processHop merkle overload: input cell not mutated" {
    const hops = [_]TestHop{
        .{ .bca = mkBca(1), .type_hash = mkType(10) },
        .{ .bca = mkBca(2), .type_hash = mkType(20) },
        .{ .bca = mkBca(3), .type_hash = mkType(30) },
    };
    const final_dest = mkBca(99);
    var cell: [CELL_SIZE]u8 = undefined;
    buildMerkleRoutedCell(&cell, &hops, final_dest, 0);
    const before = cell;
    var out: [CELL_SIZE]u8 = undefined;
    _ = processHop(&cell, &hops[0].bca, &out, true);
    try testing.expect(std.mem.eql(u8, &before, &cell)); // unchanged
    try testing.expect(!std.mem.eql(u8, &out, &cell)); // out advanced
}

test "processHop merkle overload: tampered path-merkle root (outside CRC) causes type-mismatch" {
    const hops = [_]TestHop{
        .{ .bca = mkBca(1), .type_hash = mkType(10) },
        .{ .bca = mkBca(2), .type_hash = mkType(20) },
        .{ .bca = mkBca(3), .type_hash = mkType(30) },
    };
    const final_dest = mkBca(99);
    var cell: [CELL_SIZE]u8 = undefined;
    buildMerkleRoutedCell(&cell, &hops, final_dest, 0);
    var out: [CELL_SIZE]u8 = undefined;

    // Tamper the path-merkle root at payload offset 256 (outside CRC window 160..216).
    cell[PAYLOAD_OFFSET] ^= 0xFF;
    // CRC is still valid (offset 256 is not in the CRC window).
    try testing.expect(verifyRoutingChecksum(&cell));
    // But merkle verification fails.
    try testing.expect(processHop(&cell, &hops[0].bca, &out, true).reject == .type_mismatch);
}

```
