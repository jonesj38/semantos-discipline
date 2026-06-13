---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/src/path_merkle.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.977530+00:00
---

# core/cell-engine/src/path_merkle.zig

```zig
// path_merkle.zig — routing path-merkle overload (D-OCT-path-merkle-unify, step 4 of 5).
//
// Design doc: docs/design/OCTAVE-ESCALATION-UNIFICATION.md §5 / §7 step 4.
// TS oracle: core/protocol-types/src/mnca/path-merkle.ts
//
// When FLAG_PATH_MERKLE_OVERLOAD (bit 4 of ROUTING_FLAGS) is set, the inline
// typed-segments array is replaced by a 32-byte PATH-MERKLE ROOT at the start
// of the payload region (cell offset 256), plus a per-hop proof for the CURRENT
// hop's 48-byte segment tuple.
//
// ## Leaf definition (routing vs data — the unification)
//
// The data side (D-OCT-merkle-hierarchy, step 3) uses sha256(full 1024-byte
// child cell) as the leaf.  The routing side uses sha256(48-byte segment
// tuple) as the leaf.  The hash math is IDENTICAL — only the leaf size differs.
// Both share cell_merkle.verifyInclusion(leaf_bytes, proof, root).
//
// ## Wire layout (at payload offset 0 within the 768-byte payload region, i.e. cell offset 256)
//
//   off  size  field
//    0   32    path_merkle_root   — 32-byte root over all N 48-byte segment tuples
//   32    4    total_hops         — u32 LE: total number of segments N
//   36    4    leaf_index         — u32 LE: index of the CURRENT hop's tuple (0-based)
//   40    1    sibling_count      — u8: number of sibling proof steps
//   41    sibling_count×33       — proof siblings:
//                                    32 bytes: sibling hash
//                                     1 byte:  position (0x00 = left, 0x01 = right)
//
// Total minimum: 41 bytes (zero siblings for single-hop route).
// Maximum: 41 + 16×33 = 569 bytes (16 sibling levels for ≤ 65536 hops).
//
// ## CRC relationship
//
// The routing CRC covers bytes 160..216 ONLY.
// FLAG_PATH_MERKLE_OVERLOAD at offset 164 IS in the CRC window (protected).
// The path-merkle root + proof at offset 256+ are OUTSIDE the CRC window
// (not protected by the routing CRC, same as inline tuples are not).
//
// ## flow_label as fragment-correlation key
//
// flow_label (routing header offset 176, u64) ties fragments of a deep route
// together. Relays/reassemblers use it to gather fragments without a central index.
//
// ## Oracle <-> Zig mirror contract
//
// TS oracle: core/protocol-types/src/mnca/path-merkle.ts
// Both sides MUST agree on CANONICAL_PATH_MERKLE_ROOT and the hop0 proof bytes
// computed from mkBca/mkTypeHash seed conventions.

const std = @import("std");
const cell_merkle = @import("cell_merkle");

// Re-export the shared primitive for routing use.
pub const verifyInclusion = cell_merkle.verifyInclusion;
pub const CellMerkleProof = cell_merkle.CellMerkleProof;
pub const MerkleSibling = cell_merkle.MerkleSibling;
pub const SiblingPosition = cell_merkle.SiblingPosition;

// ── Segment tuple constants ────────────────────────────────────────────────────

pub const SEGMENT_BCA_SIZE: usize = 16;
pub const SEGMENT_TYPE_HASH_SIZE: usize = 32;
/// Size of a single segment tuple: 16B BCA + 32B type-hash.
pub const SEGMENT_TUPLE_SIZE: usize = SEGMENT_BCA_SIZE + SEGMENT_TYPE_HASH_SIZE; // 48

// ── Path-merkle payload layout constants ──────────────────────────────────────

/// Offset (within the PAYLOAD region) of the 32-byte path-merkle root.
pub const PATH_MERKLE_ROOT_OFFSET: usize = 0;
pub const PATH_MERKLE_ROOT_SIZE: usize = 32;

/// Offset (within payload) of the u32 LE total_hops field.
pub const PATH_MERKLE_TOTAL_HOPS_OFFSET: usize = 32;

/// Offset (within payload) of the u32 LE leaf_index field.
pub const PATH_MERKLE_LEAF_INDEX_OFFSET: usize = 36;

/// Offset (within payload) of the u8 sibling_count field.
pub const PATH_MERKLE_SIBLING_COUNT_OFFSET: usize = 40;

/// Offset (within payload) of the first sibling entry.
pub const PATH_MERKLE_SIBLINGS_OFFSET: usize = 41;

/// Size of one sibling entry: 32-byte hash + 1-byte position.
pub const PATH_MERKLE_SIBLING_ENTRY_SIZE: usize = 33;

/// Maximum proof siblings (ceil(log2(65536)) = 16 levels).
pub const PATH_MERKLE_MAX_SIBLINGS: usize = 16;

/// Minimum payload bytes for a path-merkle overload (zero siblings).
pub const PATH_MERKLE_PAYLOAD_MIN_SIZE: usize = PATH_MERKLE_SIBLINGS_OFFSET; // 41

// ── Segment tuple ─────────────────────────────────────────────────────────────

/// A 48-byte segment tuple: [16B BCA ‖ 32B type-hash].
pub const SegmentTuple = struct {
    bca: [SEGMENT_BCA_SIZE]u8,
    type_hash: [SEGMENT_TYPE_HASH_SIZE]u8,
};

/// Encode a SegmentTuple into a 48-byte array.
pub fn encodeSegmentTuple(seg: *const SegmentTuple, out: *[SEGMENT_TUPLE_SIZE]u8) void {
    @memcpy(out[0..SEGMENT_BCA_SIZE], &seg.bca);
    @memcpy(out[SEGMENT_BCA_SIZE..SEGMENT_TUPLE_SIZE], &seg.type_hash);
}

/// Decode a 48-byte array into a SegmentTuple.
pub fn decodeSegmentTuple(bytes: *const [SEGMENT_TUPLE_SIZE]u8, out: *SegmentTuple) void {
    @memcpy(&out.bca, bytes[0..SEGMENT_BCA_SIZE]);
    @memcpy(&out.type_hash, bytes[SEGMENT_BCA_SIZE..SEGMENT_TUPLE_SIZE]);
}

// ── Decoded path-merkle payload ───────────────────────────────────────────────

/// The decoded path-merkle overload payload.
pub const PathMerklePayload = struct {
    path_merkle_root: [PATH_MERKLE_ROOT_SIZE]u8,
    total_hops: u32,
    leaf_index: u32,
    sibling_count: u8,
    siblings: [PATH_MERKLE_MAX_SIBLINGS]MerkleSibling,
};

// ── Payload decode ────────────────────────────────────────────────────────────

/// Decode a path-merkle overload payload from the beginning of the payload region
/// (cell offset 256, i.e. payload[0..]).
///
/// `payload_buf` must be at least `41 + sibling_count * 33` bytes long.
pub fn decodePathMerklePayload(payload_buf: []const u8, out: *PathMerklePayload) !void {
    if (payload_buf.len < PATH_MERKLE_PAYLOAD_MIN_SIZE) return error.PayloadTooSmall;

    @memcpy(&out.path_merkle_root, payload_buf[PATH_MERKLE_ROOT_OFFSET..][0..PATH_MERKLE_ROOT_SIZE]);
    out.total_hops = std.mem.readInt(u32, payload_buf[PATH_MERKLE_TOTAL_HOPS_OFFSET..][0..4], .little);
    out.leaf_index = std.mem.readInt(u32, payload_buf[PATH_MERKLE_LEAF_INDEX_OFFSET..][0..4], .little);
    out.sibling_count = payload_buf[PATH_MERKLE_SIBLING_COUNT_OFFSET];

    if (out.sibling_count > PATH_MERKLE_MAX_SIBLINGS) return error.TooManySiblings;

    const required = PATH_MERKLE_SIBLINGS_OFFSET + @as(usize, out.sibling_count) * PATH_MERKLE_SIBLING_ENTRY_SIZE;
    if (payload_buf.len < required) return error.PayloadTooSmall;

    var i: usize = 0;
    var off: usize = PATH_MERKLE_SIBLINGS_OFFSET;
    while (i < out.sibling_count) : (i += 1) {
        @memcpy(&out.siblings[i].hash, payload_buf[off..][0..32]);
        const pos_byte = payload_buf[off + 32];
        out.siblings[i].position = if (pos_byte == 0x00) .left else .right;
        off += PATH_MERKLE_SIBLING_ENTRY_SIZE;
    }
}

// ── Payload encode ────────────────────────────────────────────────────────────

/// Encode a PathMerklePayload into `out_buf`.
/// `out_buf` must be at least `41 + payload.sibling_count * 33` bytes.
pub fn encodePathMerklePayload(payload: *const PathMerklePayload, out_buf: []u8) !void {
    const size = PATH_MERKLE_SIBLINGS_OFFSET + @as(usize, payload.sibling_count) * PATH_MERKLE_SIBLING_ENTRY_SIZE;
    if (out_buf.len < size) return error.BufferTooSmall;
    if (payload.sibling_count > PATH_MERKLE_MAX_SIBLINGS) return error.TooManySiblings;

    @memcpy(out_buf[PATH_MERKLE_ROOT_OFFSET..][0..PATH_MERKLE_ROOT_SIZE], &payload.path_merkle_root);
    std.mem.writeInt(u32, out_buf[PATH_MERKLE_TOTAL_HOPS_OFFSET..][0..4], payload.total_hops, .little);
    std.mem.writeInt(u32, out_buf[PATH_MERKLE_LEAF_INDEX_OFFSET..][0..4], payload.leaf_index, .little);
    out_buf[PATH_MERKLE_SIBLING_COUNT_OFFSET] = payload.sibling_count;

    var i: usize = 0;
    var off: usize = PATH_MERKLE_SIBLINGS_OFFSET;
    while (i < payload.sibling_count) : (i += 1) {
        @memcpy(out_buf[off..][0..32], &payload.siblings[i].hash);
        out_buf[off + 32] = if (payload.siblings[i].position == .left) 0x00 else 0x01;
        off += PATH_MERKLE_SIBLING_ENTRY_SIZE;
    }
}

// ── Merkle tree over segment tuples ───────────────────────────────────────────

/// Compute the merkle root over segment tuples using heap allocation.
/// The leaf hash for each segment tuple is sha256(48-byte tuple).
pub fn computePathMerkleRoot(
    alloc: std.mem.Allocator,
    segments: []const SegmentTuple,
) !([32]u8) {
    if (segments.len == 0) return error.EmptySegmentSet;

    const hashes = try alloc.alloc([32]u8, segments.len);
    defer alloc.free(hashes);

    // Compute leaf hashes: sha256(48-byte tuple) for each segment.
    for (segments, 0..) |*seg, i| {
        var tuple: [SEGMENT_TUPLE_SIZE]u8 = undefined;
        encodeSegmentTuple(seg, &tuple);
        cell_merkle.sha256(&tuple, &hashes[i]);
    }

    return cell_merkle.computeMerkleRoot(alloc, hashes);
}

/// Generate an inclusion proof for segment at `hop_index`.
pub fn generateSegmentInclusionProof(
    alloc: std.mem.Allocator,
    segments: []const SegmentTuple,
    hop_index: usize,
) !CellMerkleProof {
    if (segments.len == 0) return error.EmptySegmentSet;
    if (hop_index >= segments.len) return error.HopIndexOutOfRange;

    const hashes = try alloc.alloc([32]u8, segments.len);
    defer alloc.free(hashes);

    for (segments, 0..) |*seg, i| {
        var tuple: [SEGMENT_TUPLE_SIZE]u8 = undefined;
        encodeSegmentTuple(seg, &tuple);
        cell_merkle.sha256(&tuple, &hashes[i]);
    }

    // Use the cell_merkle proof generator (it works on pre-computed hashes).
    return generateProofFromHashes(alloc, hashes, hop_index);
}

/// Generate an inclusion proof from pre-computed leaf hashes.
fn generateProofFromHashes(
    alloc: std.mem.Allocator,
    leaf_hashes: []const [32]u8,
    leaf_index: usize,
) !CellMerkleProof {
    var proof: CellMerkleProof = undefined;
    proof.leaf_index = @intCast(leaf_index);
    proof.sibling_count = 0;
    @memset(std.mem.asBytes(&proof.siblings), 0);

    var current_index = leaf_index;
    var level = try alloc.dupe([32]u8, leaf_hashes);
    defer alloc.free(level);

    while (level.len > 1) {
        if (level.len % 2 != 0) {
            level = try alloc.realloc(level, level.len + 1);
            level[level.len - 1] = level[level.len - 2];
        }

        const padded_len = level.len;
        const next_len = padded_len / 2;
        const next = try alloc.alloc([32]u8, next_len);

        var i: usize = 0;
        while (i < padded_len) : (i += 2) {
            if (i == current_index or i + 1 == current_index) {
                const sibling_idx = proof.sibling_count;
                if (sibling_idx >= cell_merkle.MAX_PROOF_SIBLINGS) return error.TooManyProofLevels;

                if (current_index % 2 == 0) {
                    proof.siblings[sibling_idx] = .{
                        .hash = level[i + 1],
                        .position = .right,
                    };
                } else {
                    proof.siblings[sibling_idx] = .{
                        .hash = level[i],
                        .position = .left,
                    };
                }
                proof.sibling_count += 1;
            }

            var combined: [64]u8 = undefined;
            @memcpy(combined[0..32], &level[i]);
            @memcpy(combined[32..64], &level[i + 1]);
            cell_merkle.sha256(&combined, &next[i / 2]);
        }

        current_index /= 2;
        alloc.free(level);
        level = next;
    }

    return proof;
}

/// Verify that a segment tuple is included under the path-merkle root.
///
/// This is the ROUTING half of the unified inclusion-proof verifier.
/// Calls verifyInclusion(48B tuple bytes, proof, root) from cell_merkle.
///
/// Leaf size note:
///   Data side:    leaf = 1024-byte child cell → sha256(1024B)
///   Routing side: leaf = 48-byte segment tuple → sha256(48B)
///   The sha256 + sibling-walk is identical. Only the leaf differs.
pub fn verifySegmentInclusion(
    seg: *const SegmentTuple,
    proof: *const CellMerkleProof,
    root: *const [32]u8,
) bool {
    var tuple: [SEGMENT_TUPLE_SIZE]u8 = undefined;
    encodeSegmentTuple(seg, &tuple);
    // The SHARED verifier from cell_merkle — identical math as data side.
    return verifyInclusion(&tuple, proof, root);
}

// ════════════════════════════════════════════════════════════════════════════
// Tests
// Run: zig test src/path_merkle.zig (with @import("cell_merkle") resolved by build)
// ════════════════════════════════════════════════════════════════════════════
const testing = std.testing;

// ── Canonical vector (oracle↔Zig agreement) ────────────────────────────────────
//
// Segments (using mkBca/mkTypeHash conventions from TS tests):
//   seg0: bca = mkBca(1), type_hash = mkTypeHash(10)
//   seg1: bca = mkBca(2), type_hash = mkTypeHash(20)
//   seg2: bca = mkBca(3), type_hash = mkTypeHash(30)
//
//   mkBca(seed):    b[i] = (i + seed * 31) & 0xFF   → 16 bytes
//   mkTypeHash(s):  h[i] = (i * 5 + s) & 0xFF       → 32 bytes
//
// TS oracle canonical values (logged by path-merkle.test.ts):
//   CANONICAL_PATH_MERKLE_ROOT_HEX:
//     a3f0c5b3c8eee4209b5870b16efb7ac2619ee29f949fd56b62664711642abb44
//
//   CANONICAL_SEG0_TUPLE_HEX:
//     1f202122232425262728292a2b2c2d2e0a0f14191e23282d32373c41464b50555a5f64696e73787d82878c91969ba0a5

fn mkBca(seed: u8) [16]u8 {
    var b: [16]u8 = undefined;
    for (0..16) |i| b[i] = @intCast((i + @as(usize, seed) * 31) & 0xFF);
    return b;
}

fn mkTypeHash(seed: u8) [32]u8 {
    var h: [32]u8 = undefined;
    for (0..32) |i| h[i] = @intCast((i * 5 + @as(usize, seed)) & 0xFF);
    return h;
}

fn mkSegment(bca_seed: u8, type_seed: u8) SegmentTuple {
    return .{
        .bca = mkBca(bca_seed),
        .type_hash = mkTypeHash(type_seed),
    };
}

/// Canonical path-merkle root over 3 segments (seg0/seg1/seg2 as defined above).
/// Must match TS oracle CANONICAL_PATH_MERKLE_ROOT_HEX.
pub const CANONICAL_PATH_MERKLE_ROOT: [32]u8 = [_]u8{
    0xa3, 0xf0, 0xc5, 0xb3, 0xc8, 0xee, 0xe4, 0x20,
    0x9b, 0x58, 0x70, 0xb1, 0x6e, 0xfb, 0x7a, 0xc2,
    0x61, 0x9e, 0xe2, 0x9f, 0x94, 0x9f, 0xd5, 0x6b,
    0x62, 0x66, 0x47, 0x11, 0x64, 0x2a, 0xbb, 0x44,
};

test "canonical segment tuple encoding matches TS oracle" {
    const seg0 = mkSegment(1, 10);
    var tuple: [SEGMENT_TUPLE_SIZE]u8 = undefined;
    encodeSegmentTuple(&seg0, &tuple);

    // CANONICAL_SEG0_TUPLE_HEX from TS oracle:
    //   BCA: 1f202122232425262728292a2b2c2d2e
    //   type_hash: 0a0f14191e23282d32373c41464b50555a5f64696e73787d82878c91969ba0a5
    const expected = [_]u8{
        // BCA (mkBca(1): b[i] = (i + 31) & 0xFF)
        0x1f, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26,
        0x27, 0x28, 0x29, 0x2a, 0x2b, 0x2c, 0x2d, 0x2e,
        // type_hash (mkTypeHash(10): h[i] = (i*5 + 10) & 0xFF)
        0x0a, 0x0f, 0x14, 0x19, 0x1e, 0x23, 0x28, 0x2d,
        0x32, 0x37, 0x3c, 0x41, 0x46, 0x4b, 0x50, 0x55,
        0x5a, 0x5f, 0x64, 0x69, 0x6e, 0x73, 0x78, 0x7d,
        0x82, 0x87, 0x8c, 0x91, 0x96, 0x9b, 0xa0, 0xa5,
    };
    try testing.expectEqualSlices(u8, &expected, &tuple);
}

test "canonical path-merkle root matches TS oracle" {
    const alloc = testing.allocator;
    const segments = [_]SegmentTuple{
        mkSegment(1, 10),
        mkSegment(2, 20),
        mkSegment(3, 30),
    };
    const root = try computePathMerkleRoot(alloc, &segments);
    try testing.expectEqualSlices(u8, &CANONICAL_PATH_MERKLE_ROOT, &root);
}

test "canonical path-merkle root matches hand-computed value" {
    // Compute step by step to verify the math.
    const seg0 = mkSegment(1, 10);
    const seg1 = mkSegment(2, 20);
    const seg2 = mkSegment(3, 30);

    var t0: [SEGMENT_TUPLE_SIZE]u8 = undefined;
    var t1: [SEGMENT_TUPLE_SIZE]u8 = undefined;
    var t2: [SEGMENT_TUPLE_SIZE]u8 = undefined;
    encodeSegmentTuple(&seg0, &t0);
    encodeSegmentTuple(&seg1, &t1);
    encodeSegmentTuple(&seg2, &t2);

    var leaf0: [32]u8 = undefined;
    var leaf1: [32]u8 = undefined;
    var leaf2: [32]u8 = undefined;
    cell_merkle.sha256(&t0, &leaf0);
    cell_merkle.sha256(&t1, &leaf1);
    cell_merkle.sha256(&t2, &leaf2);

    // branch01 = sha256(leaf0 || leaf1)
    var combined_01: [64]u8 = undefined;
    @memcpy(combined_01[0..32], &leaf0);
    @memcpy(combined_01[32..64], &leaf1);
    var branch01: [32]u8 = undefined;
    cell_merkle.sha256(&combined_01, &branch01);

    // branch22 = sha256(leaf2 || leaf2) — duplicate last (3 leaves, odd)
    var combined_22: [64]u8 = undefined;
    @memcpy(combined_22[0..32], &leaf2);
    @memcpy(combined_22[32..64], &leaf2);
    var branch22: [32]u8 = undefined;
    cell_merkle.sha256(&combined_22, &branch22);

    // root = sha256(branch01 || branch22)
    var combined_root: [64]u8 = undefined;
    @memcpy(combined_root[0..32], &branch01);
    @memcpy(combined_root[32..64], &branch22);
    var root: [32]u8 = undefined;
    cell_merkle.sha256(&combined_root, &root);

    try testing.expectEqualSlices(u8, &CANONICAL_PATH_MERKLE_ROOT, &root);
}

test "canonical hop0 proof verifies against canonical root" {
    const alloc = testing.allocator;
    const segments = [_]SegmentTuple{
        mkSegment(1, 10),
        mkSegment(2, 20),
        mkSegment(3, 30),
    };
    const root = try computePathMerkleRoot(alloc, &segments);
    try testing.expectEqualSlices(u8, &CANONICAL_PATH_MERKLE_ROOT, &root);

    const proof = try generateSegmentInclusionProof(alloc, &segments, 0);
    try testing.expect(verifySegmentInclusion(&segments[0], &proof, &CANONICAL_PATH_MERKLE_ROOT));
    // 3-leaf tree: 2 sibling levels
    try testing.expectEqual(@as(u8, 2), proof.sibling_count);
    // First sibling is right (leaf1 is right of leaf0)
    try testing.expect(proof.siblings[0].position == .right);
    // Second sibling is right (branch22 is right of branch01)
    try testing.expect(proof.siblings[1].position == .right);
}

test "all 3 hops verify in canonical vector" {
    const alloc = testing.allocator;
    const segments = [_]SegmentTuple{
        mkSegment(1, 10),
        mkSegment(2, 20),
        mkSegment(3, 30),
    };
    const root = try computePathMerkleRoot(alloc, &segments);
    for (0..3) |i| {
        const proof = try generateSegmentInclusionProof(alloc, &segments, i);
        try testing.expect(verifySegmentInclusion(&segments[i], &proof, &root));
    }
}

test "canonical hop0 payload encode matches TS oracle bytes" {
    const alloc = testing.allocator;
    const segments = [_]SegmentTuple{
        mkSegment(1, 10),
        mkSegment(2, 20),
        mkSegment(3, 30),
    };
    const root = try computePathMerkleRoot(alloc, &segments);
    const proof = try generateSegmentInclusionProof(alloc, &segments, 0);

    // Build the PathMerklePayload for hop0.
    var pm: PathMerklePayload = undefined;
    pm.path_merkle_root = root;
    pm.total_hops = 3;
    pm.leaf_index = 0;
    pm.sibling_count = proof.sibling_count;
    @memcpy(pm.siblings[0..proof.sibling_count], proof.siblings[0..proof.sibling_count]);

    // Encode.
    var buf: [PATH_MERKLE_PAYLOAD_MIN_SIZE + 2 * PATH_MERKLE_SIBLING_ENTRY_SIZE]u8 = undefined;
    try encodePathMerklePayload(&pm, &buf);

    // TS oracle CANONICAL_HOP0_PAYLOAD_HEX:
    // a3f0c5b3c8eee4209b5870b16efb7ac2619ee29f949fd56b62664711642abb44  (root, 32B)
    // 03000000  (total_hops = 3, u32 LE)
    // 00000000  (leaf_index = 0, u32 LE)
    // 02        (sibling_count = 2)
    // 8286475b8807fdc949a35892c0ac59ef44977a3fa8903fd3cd7cc3360239c68d  (sibling0 hash)
    // 01        (right)
    // 4d7b5bc1dd552d94f9031d3abb3d33c407695b4e7cc73601300dbc602121daf6  (sibling1 hash)
    // 01        (right)

    // Verify root bytes.
    try testing.expectEqualSlices(u8, &CANONICAL_PATH_MERKLE_ROOT, buf[0..32]);
    // total_hops = 3
    try testing.expectEqual(@as(u8, 3), buf[32]);
    try testing.expectEqual(@as(u8, 0), buf[33]);
    try testing.expectEqual(@as(u8, 0), buf[34]);
    try testing.expectEqual(@as(u8, 0), buf[35]);
    // leaf_index = 0
    try testing.expectEqual(@as(u8, 0), buf[36]);
    try testing.expectEqual(@as(u8, 0), buf[37]);
    try testing.expectEqual(@as(u8, 0), buf[38]);
    try testing.expectEqual(@as(u8, 0), buf[39]);
    // sibling_count = 2
    try testing.expectEqual(@as(u8, 2), buf[40]);
    // sibling0 position = right (0x01)
    try testing.expectEqual(@as(u8, 0x01), buf[41 + 32]);
    // sibling1 position = right (0x01)
    try testing.expectEqual(@as(u8, 0x01), buf[41 + 33 + 32]);

    // Full byte comparison with TS oracle.
    const expected_hex = "a3f0c5b3c8eee4209b5870b16efb7ac2619ee29f949fd56b62664711642abb440300000000000000028286475b8807fdc949a35892c0ac59ef44977a3fa8903fd3cd7cc3360239c68d014d7b5bc1dd552d94f9031d3abb3d33c407695b4e7cc73601300dbc602121daf601";
    var expected: [107]u8 = undefined;
    _ = try std.fmt.hexToBytes(&expected, expected_hex);
    try testing.expectEqualSlices(u8, &expected, buf[0..107]);
}

test "payload encode/decode round-trip" {
    const alloc = testing.allocator;
    const segments = [_]SegmentTuple{
        mkSegment(1, 10),
        mkSegment(2, 20),
        mkSegment(3, 30),
    };
    const root = try computePathMerkleRoot(alloc, &segments);
    const proof = try generateSegmentInclusionProof(alloc, &segments, 1);

    var original: PathMerklePayload = undefined;
    original.path_merkle_root = root;
    original.total_hops = 3;
    original.leaf_index = 1;
    original.sibling_count = proof.sibling_count;
    @memcpy(original.siblings[0..proof.sibling_count], proof.siblings[0..proof.sibling_count]);

    var buf: [PATH_MERKLE_PAYLOAD_MIN_SIZE + PATH_MERKLE_MAX_SIBLINGS * PATH_MERKLE_SIBLING_ENTRY_SIZE]u8 = undefined;
    try encodePathMerklePayload(&original, &buf);

    var decoded: PathMerklePayload = undefined;
    try decodePathMerklePayload(&buf, &decoded);

    try testing.expectEqualSlices(u8, &original.path_merkle_root, &decoded.path_merkle_root);
    try testing.expectEqual(original.total_hops, decoded.total_hops);
    try testing.expectEqual(original.leaf_index, decoded.leaf_index);
    try testing.expectEqual(original.sibling_count, decoded.sibling_count);

    var i: usize = 0;
    while (i < original.sibling_count) : (i += 1) {
        try testing.expectEqualSlices(u8, &original.siblings[i].hash, &decoded.siblings[i].hash);
        try testing.expect(original.siblings[i].position == decoded.siblings[i].position);
    }
}

test "verifySegmentInclusion: correct segment verifies" {
    const alloc = testing.allocator;
    const segments = [_]SegmentTuple{
        mkSegment(1, 10),
        mkSegment(2, 20),
        mkSegment(3, 30),
    };
    const root = try computePathMerkleRoot(alloc, &segments);
    const proof = try generateSegmentInclusionProof(alloc, &segments, 0);
    try testing.expect(verifySegmentInclusion(&segments[0], &proof, &root));
}

test "verifySegmentInclusion: tampered BCA fails" {
    const alloc = testing.allocator;
    const segments = [_]SegmentTuple{
        mkSegment(1, 10),
        mkSegment(2, 20),
    };
    const root = try computePathMerkleRoot(alloc, &segments);
    const proof = try generateSegmentInclusionProof(alloc, &segments, 0);

    var tampered = segments[0];
    tampered.bca[3] ^= 0xff;
    try testing.expect(!verifySegmentInclusion(&tampered, &proof, &root));
}

test "verifySegmentInclusion: tampered type_hash fails" {
    const alloc = testing.allocator;
    const segments = [_]SegmentTuple{
        mkSegment(1, 10),
        mkSegment(2, 20),
    };
    const root = try computePathMerkleRoot(alloc, &segments);
    const proof = try generateSegmentInclusionProof(alloc, &segments, 0);

    var tampered = segments[0];
    tampered.type_hash[5] ^= 0xff;
    try testing.expect(!verifySegmentInclusion(&tampered, &proof, &root));
}

test "verifySegmentInclusion: tampered sibling hash fails" {
    const alloc = testing.allocator;
    const segments = [_]SegmentTuple{
        mkSegment(1, 10),
        mkSegment(2, 20),
    };
    const root = try computePathMerkleRoot(alloc, &segments);
    var proof = try generateSegmentInclusionProof(alloc, &segments, 0);

    proof.siblings[0].hash[0] ^= 0xff;
    try testing.expect(!verifySegmentInclusion(&segments[0], &proof, &root));
}

test "verifySegmentInclusion: proof for hop 0 does not verify hop 1" {
    const alloc = testing.allocator;
    const segments = [_]SegmentTuple{
        mkSegment(1, 10),
        mkSegment(2, 20),
    };
    const root = try computePathMerkleRoot(alloc, &segments);
    const proof = try generateSegmentInclusionProof(alloc, &segments, 0);
    try testing.expect(!verifySegmentInclusion(&segments[1], &proof, &root));
}

test "5-hop route (odd count): all hops verify" {
    const alloc = testing.allocator;
    const segments = [_]SegmentTuple{
        mkSegment(1, 10),
        mkSegment(2, 20),
        mkSegment(3, 30),
        mkSegment(4, 40),
        mkSegment(5, 50),
    };
    const root = try computePathMerkleRoot(alloc, &segments);
    for (0..5) |i| {
        const proof = try generateSegmentInclusionProof(alloc, &segments, i);
        try testing.expect(verifySegmentInclusion(&segments[i], &proof, &root));
    }
}

```
