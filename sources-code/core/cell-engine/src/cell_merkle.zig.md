---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/src/cell_merkle.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.981244+00:00
---

# core/cell-engine/src/cell_merkle.zig

```zig
// cell_merkle.zig — binary merkle tree over 1024-byte child cells (rung-2 hierarchy).
//
// Design doc: docs/design/OCTAVE-ESCALATION-UNIFICATION.md §3/§7 step 3.
// This is D-OCT-merkle-hierarchy (step 3 of 5).
//
// ## Hash scheme
//
// Cells are content-addressed with single SHA-256 (std.crypto.hash.sha2.Sha256).
// NOT double-SHA-256 (headers.zig sha256d is for BSV tx-merkle, a distinct primitive).
//
//   leaf hash   = SHA-256(full 1024-byte child cell)
//   branch hash = SHA-256(left_hash_32B ++ right_hash_32B)
//
// Odd number of nodes at a level: duplicate the last node (same convention as
// Bitcoin tx-merkle, but single-SHA-256).
//
// The root is the canonical `domainPayloadRoot` committed into the header at
// byte offset 224 (HEADER_OFFSET_DOMAIN_PAYLOAD_ROOT = 224).
//
// ## Verifier reuse
//
// `verifyCellInclusion` is the shared inclusion-proof verifier that step 4
// (D-OCT-path-merkle-unify) will ALSO use for routing-path merkle proofs.
// Keep the function signature stable.
//
// ## Oracle ↔ mirror contract
//
// The TypeScript oracle is at core/cell-ops/src/packer/cell-merkle.ts.
// Both sides MUST agree on the canonical 3-cell vector:
//   cells = [cell_A (all 0x41), cell_B (all 0x42), cell_C (all 0x43)]
//   CANONICAL_ROOT_HEX = c72747c0b84da25338a1b50152a7c664c38c287359437c67f590d66faef5cba4
//
// ## Backward-compat
//
// This module is ADDITIVE. It does not modify packMultiCell (rung-0) or
// packEscalated (rung-1). Rung-2 detection uses the descriptor rung field (= 2)
// AND the ESCALATION_CELL_COUNT_SENTINEL in the cell_count field.

const std = @import("std");
const Sha256 = std.crypto.hash.sha2.Sha256;
const constants = @import("constants");
const escalation_descriptor = @import("escalation_descriptor");

// ── Header offset ──────────────────────────────────────────────────────────────

/// Byte offset of the 32-byte domainPayloadRoot within the 1024-byte cell header.
/// Matches constants.zig HEADER_OFFSET_DOMAIN_PAYLOAD_ROOT = 224.
pub const DOMAIN_PAYLOAD_ROOT_OFFSET: usize = 224;
pub const DOMAIN_PAYLOAD_ROOT_SIZE: usize = 32;

// ── Sentinel (mirrors multicell.zig) ──────────────────────────────────────────

/// Cell 0 `cell_count` sentinel for escalated (rung ≥ 1) objects.
pub const ESCALATION_CELL_COUNT_SENTINEL: u32 = 0xFFFFFFFF;

// ── Rung-2 descriptor values ───────────────────────────────────────────────────

/// Descriptor rung value for merkle-rooted hierarchy.
pub const RUNG_MERKLE_ROOTED: u8 = 2;

/// Octave level constants — mirrors octave.zig::Octave and escalation_descriptor.zig::OctaveLevel.
/// Used to stamp the octave_level field in the rung-2 descriptor.
pub const OCTAVE_LEVEL_BASE: u8 = 0; // 1 KiB cells
pub const OCTAVE_LEVEL_KILO: u8 = 1; // 1 MiB cells
pub const OCTAVE_LEVEL_MEGA: u8 = 2; // 1 GiB cells — D-OCT-octave-2-plus (step 5/5)
pub const OCTAVE_LEVEL_GIGA: u8 = 3; // 1 TiB cells — D-OCT-octave-2-plus (step 5/5)

/// Maximum octave level: giga (3). Beyond this is an error.
pub const MAX_OCTAVE_LEVEL: u8 = 3;

// ── Merkle proof types ─────────────────────────────────────────────────────────

/// Position of a sibling node in the merkle path.
pub const SiblingPosition = enum(u8) {
    left = 0,
    right = 1,
};

/// One sibling node in a merkle inclusion proof.
pub const MerkleSibling = struct {
    hash: [32]u8,
    position: SiblingPosition,
};

/// Maximum siblings in a proof path.
/// ceil(log2(65536)) = 16 levels is enough for u16 max child count (65535 leaves).
pub const MAX_PROOF_SIBLINGS: usize = 16;

/// Inclusion proof for one leaf (child cell).
pub const CellMerkleProof = struct {
    leaf_index: u32,
    sibling_count: u8,
    siblings: [MAX_PROOF_SIBLINGS]MerkleSibling,
};

// ── Descriptor for an unpacked rung-2 anchor cell ─────────────────────────────

pub const MerkleHierarchyDescriptor = struct {
    merkle_root: [32]u8,
    child_count: u16,
    total_bytes: u64,
    octave_level: u8,
};

// ── Hash helpers ───────────────────────────────────────────────────────────────

/// Single SHA-256 of `data` into `out[0..32]`.
pub fn sha256(data: []const u8, out: *[32]u8) void {
    Sha256.hash(data, out, .{});
}

/// Compute a branch hash = SHA-256(left || right).
fn branchHash(left: *const [32]u8, right: *const [32]u8, out: *[32]u8) void {
    var combined: [64]u8 = undefined;
    @memcpy(combined[0..32], left);
    @memcpy(combined[32..64], right);
    sha256(&combined, out);
}

// ── Core merkle operations ─────────────────────────────────────────────────────

/// Compute the merkle root over an array of 32-byte leaf hashes.
/// Uses heap allocation via `alloc` for intermediate buffers.
pub fn computeMerkleRoot(
    alloc: std.mem.Allocator,
    leaf_hashes: []const [32]u8,
) !([32]u8) {
    if (leaf_hashes.len == 0) return error.EmptyLeafSet;
    if (leaf_hashes.len == 1) return leaf_hashes[0];

    // Copy leaves into a mutable current-level buffer.
    var current = try alloc.dupe([32]u8, leaf_hashes);
    defer alloc.free(current);

    while (current.len > 1) {
        // Compute length of next level (round up to even for duplication).
        const padded_len = current.len + (current.len & 1);
        const next_len = padded_len / 2;
        const next = try alloc.alloc([32]u8, next_len);

        var i: usize = 0;
        while (i < padded_len) : (i += 2) {
            const left = &current[i];
            const right = if (i + 1 < current.len) &current[i + 1] else &current[i];
            branchHash(left, right, &next[i / 2]);
        }

        alloc.free(current);
        current = next;
    }

    return current[0];
}

/// Compute leaf hashes for a set of full 1024-byte child cells.
/// leaf hash = SHA-256(full 1024-byte child cell)
pub fn computeLeafHashes(
    alloc: std.mem.Allocator,
    child_cells: []const []const u8,
) ![]([32]u8) {
    const hashes = try alloc.alloc([32]u8, child_cells.len);
    for (child_cells, 0..) |cell, i| {
        sha256(cell, &hashes[i]);
    }
    return hashes;
}

/// Compute the merkle root over an array of child cells (each CELL_SIZE bytes).
pub fn computeCellMerkleRoot(
    alloc: std.mem.Allocator,
    child_cells: []const []const u8,
) !([32]u8) {
    if (child_cells.len == 0) return error.EmptyLeafSet;
    const hashes = try computeLeafHashes(alloc, child_cells);
    defer alloc.free(hashes);
    return computeMerkleRoot(alloc, hashes);
}

/// Generate an inclusion proof for the leaf at `leaf_index` within the child cells.
pub fn generateCellInclusionProof(
    alloc: std.mem.Allocator,
    child_cells: []const []const u8,
    leaf_index: usize,
) !CellMerkleProof {
    if (child_cells.len == 0) return error.EmptyLeafSet;
    if (leaf_index >= child_cells.len) return error.LeafIndexOutOfRange;

    const leaf_hashes = try computeLeafHashes(alloc, child_cells);
    defer alloc.free(leaf_hashes);

    return generateProofFromHashes(alloc, leaf_hashes, leaf_index);
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

    // Copy into a mutable buffer.
    var level = try alloc.dupe([32]u8, leaf_hashes);
    defer alloc.free(level);

    while (level.len > 1) {
        const padded_len = level.len + (level.len & 1);

        // If odd, append a duplicate of the last element (don't modify original).
        if (level.len % 2 != 0) {
            level = try alloc.realloc(level, level.len + 1);
            level[level.len - 1] = level[level.len - 2];
        }

        const next_len = padded_len / 2;
        const next = try alloc.alloc([32]u8, next_len);

        var i: usize = 0;
        while (i < padded_len) : (i += 2) {
            // If current_index is in this pair, record the sibling.
            if (i == current_index or i + 1 == current_index) {
                const sibling_idx = proof.sibling_count;
                if (sibling_idx >= MAX_PROOF_SIBLINGS) return error.TooManyProofLevels;

                if (current_index % 2 == 0) {
                    // current is left, sibling is right
                    proof.siblings[sibling_idx] = .{
                        .hash = level[i + 1],
                        .position = .right,
                    };
                } else {
                    // current is right, sibling is left
                    proof.siblings[sibling_idx] = .{
                        .hash = level[i],
                        .position = .left,
                    };
                }
                proof.sibling_count += 1;
            }

            branchHash(&level[i], &level[i + 1], &next[i / 2]);
        }

        current_index /= 2;
        alloc.free(level);
        level = next;
    }

    return proof;
}

// ── Inclusion proof verifier ───────────────────────────────────────────────────

/// Generic leaf-bytes-agnostic inclusion-proof verifier.
///
/// This is the UNIFIED PRIMITIVE shared by:
///   - Data side (D-OCT-merkle-hierarchy): leaf_bytes = full 1024-byte child cell.
///   - Routing side (D-OCT-path-merkle-unify): leaf_bytes = 48-byte segment tuple
///     [16B BCA ++ 32B type-hash].
///
/// The hash math is identical regardless of leaf size:
///   leaf_hash = sha256(leaf_bytes)   // arbitrary length
///   branch    = sha256(left32 ++ right32)
///
/// leaf_bytes: arbitrary bytes — 1024B for data cells, 48B for routing segments.
/// proof:      inclusion proof (leaf_index + siblings)
/// root:       the committed 32-byte merkle root
///
/// Returns true iff the leaf is provably included under `root`.
pub fn verifyInclusion(
    leaf_bytes: []const u8,
    proof: *const CellMerkleProof,
    root: *const [32]u8,
) bool {
    var current: [32]u8 = undefined;
    sha256(leaf_bytes, &current);

    var i: usize = 0;
    while (i < proof.sibling_count) : (i += 1) {
        const sib = &proof.siblings[i];
        var combined: [64]u8 = undefined;
        switch (sib.position) {
            .right => {
                @memcpy(combined[0..32], &current);
                @memcpy(combined[32..64], &sib.hash);
            },
            .left => {
                @memcpy(combined[0..32], &sib.hash);
                @memcpy(combined[32..64], &current);
            },
        }
        sha256(&combined, &current);
    }

    return std.mem.eql(u8, &current, root);
}

/// Verify that a child cell is included under a committed merkle root.
///
/// Delegates to `verifyInclusion` with the full cell bytes as the leaf.
/// For routing-path proofs (48-byte segment tuples), call `verifyInclusion`
/// directly instead of this wrapper.
///
/// Parameters:
///   cell_bytes - full 1024-byte child cell bytes
///   proof      - inclusion proof (leaf_index + siblings)
///   root       - the committed 32-byte merkle root
///
/// Returns true iff the cell is provably included under `root`.
pub fn verifyCellInclusion(
    cell_bytes: []const u8,
    proof: *const CellMerkleProof,
    root: *const [32]u8,
) bool {
    // Delegates to the leaf-size-agnostic verifier. 1024-byte leaf is conventional
    // for data cells; routing passes 48-byte segment tuples via verifyInclusion directly.
    return verifyInclusion(cell_bytes, proof, root);
}

// ── domainPayloadRoot read/write ───────────────────────────────────────────────

/// Write a 32-byte merkle root into the domainPayloadRoot slot of a cell.
/// `cell_buf` must be at least `DOMAIN_PAYLOAD_ROOT_OFFSET + DOMAIN_PAYLOAD_ROOT_SIZE` bytes.
pub fn writeDomainPayloadRoot(cell_buf: []u8, root: *const [32]u8) void {
    std.debug.assert(cell_buf.len >= DOMAIN_PAYLOAD_ROOT_OFFSET + DOMAIN_PAYLOAD_ROOT_SIZE);
    @memcpy(cell_buf[DOMAIN_PAYLOAD_ROOT_OFFSET..][0..32], root);
}

/// Read the 32-byte domainPayloadRoot from a cell buffer into `out`.
pub fn readDomainPayloadRoot(cell_buf: []const u8, out: *[32]u8) void {
    std.debug.assert(cell_buf.len >= DOMAIN_PAYLOAD_ROOT_OFFSET + DOMAIN_PAYLOAD_ROOT_SIZE);
    @memcpy(out, cell_buf[DOMAIN_PAYLOAD_ROOT_OFFSET..][0..32]);
}

// ── Rung-2 pack/unpack ─────────────────────────────────────────────────────────

/// Pack a rung-2 (merkle-rooted hierarchy) anchor cell.
///
/// Given:
///   - header: 256-byte cell header (copied and patched; original not mutated)
///   - child_cells: array of child cells (each exactly CELL_SIZE bytes)
///   - total_bytes: logical blob size written into escalation descriptor (u64 — the
///     source of truth for the full logical payload size, resolving O-1)
///   - octave_level: the octave class of child cells (0=base, 1=kilo, 2=mega, 3=giga).
///     Use OCTAVE_LEVEL_BASE for ordinary 1 KiB child cells.  Use OCTAVE_LEVEL_MEGA /
///     OCTAVE_LEVEL_GIGA when the hierarchy's child cells are themselves 1 GiB / 1 TiB
///     cells (D-OCT-octave-2-plus, step 5/5).
///
/// Builds the binary merkle tree over the child cells, commits the root into
/// domainPayloadRoot (offset 224), writes the escalation descriptor (rung=2)
/// at payload offset 0, and patches cell_count + total_size in the header.
///
/// O-1 header semantics (uniform for ALL rung≥1):
///   total_size (u32 at offset 90) = bytes in THIS anchor cell's own "content"
///   = ESCALATION_DESCRIPTOR_SIZE (16).  The descriptor's total_bytes (u64) is
///   the authoritative logical blob size and CAN exceed u32 for octave-2/3 objects.
///
/// The child cells are NOT concatenated — the caller stores/transmits them
/// separately. Only the 1024-byte anchor Cell 0 is written into `out`.
///
/// `out` must be at least CELL_SIZE (1024) bytes.
pub fn packMerkleHierarchy(
    alloc: std.mem.Allocator,
    header: *const [256]u8,
    child_cells: []const []const u8,
    total_bytes: u64,
    octave_level: u8,
    out: []u8,
) !void {
    if (child_cells.len == 0) return error.EmptyLeafSet;
    if (child_cells.len > 0xFFFF) return error.TooManyChildCells;
    if (out.len < constants.CELL_SIZE) return error.BufferTooSmall;
    if (octave_level > MAX_OCTAVE_LEVEL) return error.OctaveLevelTooHigh;

    // Compute merkle root.
    const merkle_root = try computeCellMerkleRoot(alloc, child_cells);

    // Zero the anchor cell output region.
    @memset(out[0..constants.CELL_SIZE], 0);

    // Copy header bytes (first 256 bytes).
    @memcpy(out[0..256], header);

    // Patch cell_count (offset 86, u32 LE) = sentinel.
    std.mem.writeInt(u32, out[86..][0..4], ESCALATION_CELL_COUNT_SENTINEL, .little);

    // Patch total_size (offset 90, u32 LE) = descriptor size (O-1).
    // For ALL rung≥1, total_size = "bytes in THIS cell's content" = ESCALATION_DESCRIPTOR_SIZE (16).
    // The descriptor's total_bytes u64 is the authoritative logical blob size (resolves O-1).
    std.mem.writeInt(u32, out[90..][0..4], escalation_descriptor.ESCALATION_DESCRIPTOR_SIZE, .little);

    // Write domainPayloadRoot at offset 224.
    writeDomainPayloadRoot(out, &merkle_root);

    // Write escalation descriptor at payload offset 0 (cell byte 256).
    const desc_off = constants.HEADER_SIZE; // 256
    out[desc_off + 0] = RUNG_MERKLE_ROOTED; // rung = 2
    out[desc_off + 1] = octave_level;        // octave_level (0=base, 1=kilo, 2=mega, 3=giga)
    std.mem.writeInt(u16, out[desc_off + 2 ..][0..2], @intCast(child_cells.len), .little); // child_count
    std.mem.writeInt(u64, out[desc_off + 4 ..][0..8], total_bytes, .little);               // total_bytes
    std.mem.writeInt(u32, out[desc_off + 12..][0..4], 0, .little);                         // reserved = 0
}

/// Unpack (read) the rung-2 hierarchy descriptor from an anchor Cell 0.
pub fn unpackMerkleHierarchy(cell_buf: []const u8) !MerkleHierarchyDescriptor {
    if (cell_buf.len < constants.CELL_SIZE) return error.BufferTooSmall;

    const desc_off = constants.HEADER_SIZE; // 256
    const rung = cell_buf[desc_off + 0];
    if (rung != RUNG_MERKLE_ROOTED) return error.NotMerkleHierarchy;

    var desc = MerkleHierarchyDescriptor{
        .merkle_root = undefined,
        .child_count = std.mem.readInt(u16, cell_buf[desc_off + 2 ..][0..2], .little),
        .total_bytes = std.mem.readInt(u64, cell_buf[desc_off + 4 ..][0..8], .little),
        .octave_level = cell_buf[desc_off + 1],
    };
    readDomainPayloadRoot(cell_buf, &desc.merkle_root);

    return desc;
}

/// Check whether a cell buffer is a rung-2 (merkle-rooted hierarchy) object.
///
/// Checks that:
///   1. cell_count (offset 86, u32 LE) == ESCALATION_CELL_COUNT_SENTINEL
///   2. descriptor rung (cell byte 256) == RUNG_MERKLE_ROOTED (2)
pub fn isMerkleHierarchy(buf: []const u8) bool {
    if (buf.len < constants.CELL_SIZE) return false;
    const sentinel = std.mem.readInt(u32, buf[86..][0..4], .little);
    if (sentinel != ESCALATION_CELL_COUNT_SENTINEL) return false;
    return buf[constants.HEADER_SIZE] == RUNG_MERKLE_ROOTED;
}

// ════════════════════════════════════════════════════════════════════════════
// Tests
// ════════════════════════════════════════════════════════════════════════════
const testing = std.testing;

// ── Helper: fill a CELL_SIZE buffer with a pattern ────────────────────────────

fn makeChildCell(alloc: std.mem.Allocator, pattern: u8) ![]u8 {
    const cell = try alloc.alloc(u8, constants.CELL_SIZE);
    @memset(cell, pattern);
    return cell;
}

// ── Canonical vector ───────────────────────────────────────────────────────────
//
// Cells: A = all 0x41 (1024B), B = all 0x42, C = all 0x43
// root  = SHA256( SHA256(SHA256(A) || SHA256(B)) || SHA256(SHA256(C) || SHA256(C)) )
// (odd count 3 → duplicate C at level 1)
//
// TS oracle confirms:
//   CANONICAL_ROOT_HEX = c72747c0b84da25338a1b50152a7c664c38c287359437c67f590d66faef5cba4

pub const CANONICAL_ROOT: [32]u8 = [_]u8{
    0xc7, 0x27, 0x47, 0xc0, 0xb8, 0x4d, 0xa2, 0x53,
    0x38, 0xa1, 0xb5, 0x01, 0x52, 0xa7, 0xc6, 0x64,
    0xc3, 0x8c, 0x28, 0x73, 0x59, 0x43, 0x7c, 0x67,
    0xf5, 0x90, 0xd6, 0x6f, 0xae, 0xf5, 0xcb, 0xa4,
};

test "canonical 3-cell merkle root matches TS oracle" {
    const alloc = testing.allocator;

    const cell_a = try makeChildCell(alloc, 0x41);
    defer alloc.free(cell_a);
    const cell_b = try makeChildCell(alloc, 0x42);
    defer alloc.free(cell_b);
    const cell_c = try makeChildCell(alloc, 0x43);
    defer alloc.free(cell_c);

    const cells: []const []const u8 = &.{ cell_a, cell_b, cell_c };
    const root = try computeCellMerkleRoot(alloc, cells);

    try testing.expectEqualSlices(u8, &CANONICAL_ROOT, &root);
}

test "canonical root matches hand-computed value" {
    const alloc = testing.allocator;

    // Step-by-step hand computation (mirrors TS test "canonical root matches hand-computed value").
    const cell_a = try makeChildCell(alloc, 0x41);
    defer alloc.free(cell_a);
    const cell_b = try makeChildCell(alloc, 0x42);
    defer alloc.free(cell_b);
    const cell_c = try makeChildCell(alloc, 0x43);
    defer alloc.free(cell_c);

    var leaf_a: [32]u8 = undefined;
    var leaf_b: [32]u8 = undefined;
    var leaf_c: [32]u8 = undefined;
    sha256(cell_a, &leaf_a);
    sha256(cell_b, &leaf_b);
    sha256(cell_c, &leaf_c);

    var branch_ab: [32]u8 = undefined;
    branchHash(&leaf_a, &leaf_b, &branch_ab);

    var branch_cc: [32]u8 = undefined;
    branchHash(&leaf_c, &leaf_c, &branch_cc); // duplicate last

    var expected_root: [32]u8 = undefined;
    branchHash(&branch_ab, &branch_cc, &expected_root);

    try testing.expectEqualSlices(u8, &expected_root, &CANONICAL_ROOT);
}

// ── Inclusion proof — valid ────────────────────────────────────────────────────

test "inclusion proof: 2-cell set, both leaves verify" {
    const alloc = testing.allocator;
    const cell_a = try makeChildCell(alloc, 0xaa);
    defer alloc.free(cell_a);
    const cell_b = try makeChildCell(alloc, 0xbb);
    defer alloc.free(cell_b);

    const cells: []const []const u8 = &.{ cell_a, cell_b };
    const root = try computeCellMerkleRoot(alloc, cells);

    const proof_a = try generateCellInclusionProof(alloc, cells, 0);
    try testing.expect(verifyCellInclusion(cell_a, &proof_a, &root));

    const proof_b = try generateCellInclusionProof(alloc, cells, 1);
    try testing.expect(verifyCellInclusion(cell_b, &proof_b, &root));
}

test "inclusion proof: 5-cell set (odd), all leaves verify" {
    const alloc = testing.allocator;
    var cells_arr: [5][]u8 = undefined;
    for (&cells_arr, 0..) |*ptr, i| {
        ptr.* = try makeChildCell(alloc, @intCast(i + 1));
    }
    defer for (&cells_arr) |ptr| alloc.free(ptr);

    const cells: []const []const u8 = @ptrCast(&cells_arr);
    const root = try computeCellMerkleRoot(alloc, cells);

    for (0..5) |i| {
        const proof = try generateCellInclusionProof(alloc, cells, i);
        try testing.expect(verifyCellInclusion(cells[i], &proof, &root));
    }
}

test "inclusion proof: single-cell — root equals leaf hash" {
    const alloc = testing.allocator;
    const cell = try makeChildCell(alloc, 0x42);
    defer alloc.free(cell);

    const cells: []const []const u8 = &.{cell};
    const root = try computeCellMerkleRoot(alloc, cells);

    var expected: [32]u8 = undefined;
    sha256(cell, &expected);
    try testing.expectEqualSlices(u8, &expected, &root);

    const proof = try generateCellInclusionProof(alloc, cells, 0);
    try testing.expect(verifyCellInclusion(cell, &proof, &root));
}

test "canonical inclusion proof: leaf 1 (cell B) verifies" {
    const alloc = testing.allocator;
    const cell_a = try makeChildCell(alloc, 0x41);
    defer alloc.free(cell_a);
    const cell_b = try makeChildCell(alloc, 0x42);
    defer alloc.free(cell_b);
    const cell_c = try makeChildCell(alloc, 0x43);
    defer alloc.free(cell_c);

    const cells: []const []const u8 = &.{ cell_a, cell_b, cell_c };
    const root = try computeCellMerkleRoot(alloc, cells);

    try testing.expectEqualSlices(u8, &CANONICAL_ROOT, &root);

    const proof = try generateCellInclusionProof(alloc, cells, 1);
    try testing.expect(verifyCellInclusion(cell_b, &proof, &root));
}

// ── Inclusion proof — tampered ────────────────────────────────────────────────

test "tampered cell bytes: verification fails" {
    const alloc = testing.allocator;
    var cell_a = try makeChildCell(alloc, 0x01);
    defer alloc.free(cell_a);
    const cell_b = try makeChildCell(alloc, 0x02);
    defer alloc.free(cell_b);

    const cells: []const []const u8 = &.{ cell_a, cell_b };
    const root = try computeCellMerkleRoot(alloc, cells);
    const proof = try generateCellInclusionProof(alloc, cells, 0);

    // Tamper one byte
    cell_a[100] ^= 0xff;
    try testing.expect(!verifyCellInclusion(cell_a, &proof, &root));
}

test "tampered sibling hash: verification fails" {
    const alloc = testing.allocator;
    const cell_a = try makeChildCell(alloc, 0x10);
    defer alloc.free(cell_a);
    const cell_b = try makeChildCell(alloc, 0x20);
    defer alloc.free(cell_b);

    const cells: []const []const u8 = &.{ cell_a, cell_b };
    const root = try computeCellMerkleRoot(alloc, cells);
    var proof = try generateCellInclusionProof(alloc, cells, 0);

    // Tamper sibling hash
    proof.siblings[0].hash[5] ^= 0xff;
    try testing.expect(!verifyCellInclusion(cell_a, &proof, &root));
}

test "wrong root: verification fails" {
    const alloc = testing.allocator;
    const cell_a = try makeChildCell(alloc, 0xaa);
    defer alloc.free(cell_a);
    const cell_b = try makeChildCell(alloc, 0xbb);
    defer alloc.free(cell_b);

    const cells: []const []const u8 = &.{ cell_a, cell_b };
    const root = try computeCellMerkleRoot(alloc, cells);
    const proof = try generateCellInclusionProof(alloc, cells, 0);

    var wrong_root = root;
    wrong_root[0] ^= 0xff;
    try testing.expect(!verifyCellInclusion(cell_a, &proof, &wrong_root));
}

test "proof for leaf 0 does NOT verify for leaf 1" {
    const alloc = testing.allocator;
    const cell_a = try makeChildCell(alloc, 0x11);
    defer alloc.free(cell_a);
    const cell_b = try makeChildCell(alloc, 0x22);
    defer alloc.free(cell_b);

    const cells: []const []const u8 = &.{ cell_a, cell_b };
    const root = try computeCellMerkleRoot(alloc, cells);
    const proof = try generateCellInclusionProof(alloc, cells, 0);

    try testing.expect(!verifyCellInclusion(cell_b, &proof, &root));
}

// ── Pack/unpack round-trip ─────────────────────────────────────────────────────

test "packMerkleHierarchy / unpackMerkleHierarchy round-trip" {
    const alloc = testing.allocator;

    var header: [256]u8 = [_]u8{0} ** 256;
    const N = 4;
    var cells_arr: [N][]u8 = undefined;
    for (&cells_arr, 0..) |*ptr, i| {
        ptr.* = try makeChildCell(alloc, @intCast(i + 1));
    }
    defer for (&cells_arr) |ptr| alloc.free(ptr);

    const cells: []const []const u8 = @ptrCast(&cells_arr);
    const total_b: u64 = N * constants.CELL_SIZE;

    var anchor: [constants.CELL_SIZE]u8 = undefined;
    try packMerkleHierarchy(alloc, &header, cells, total_b, OCTAVE_LEVEL_BASE, &anchor);

    try testing.expect(isMerkleHierarchy(&anchor));

    const desc = try unpackMerkleHierarchy(&anchor);
    try testing.expectEqual(@as(u16, N), desc.child_count);
    try testing.expectEqual(total_b, desc.total_bytes);
    try testing.expectEqual(@as(u8, OCTAVE_LEVEL_BASE), desc.octave_level);

    // Root should match computeCellMerkleRoot
    const expected_root = try computeCellMerkleRoot(alloc, cells);
    try testing.expectEqualSlices(u8, &expected_root, &desc.merkle_root);
}

test "anchor cell sentinel and descriptor bytes are correct" {
    const alloc = testing.allocator;

    var header: [256]u8 = [_]u8{0} ** 256;
    const cell_a = try makeChildCell(alloc, 0x41);
    defer alloc.free(cell_a);
    const cell_b = try makeChildCell(alloc, 0x42);
    defer alloc.free(cell_b);
    const cell_c = try makeChildCell(alloc, 0x43);
    defer alloc.free(cell_c);

    const cells: []const []const u8 = &.{ cell_a, cell_b, cell_c };
    const total_b: u64 = 3 * constants.CELL_SIZE;

    var anchor: [constants.CELL_SIZE]u8 = undefined;
    try packMerkleHierarchy(alloc, &header, cells, total_b, OCTAVE_LEVEL_BASE, &anchor);

    // sentinel at offset 86
    try testing.expectEqual(@as(u32, 0xFFFFFFFF), std.mem.readInt(u32, anchor[86..][0..4], .little));
    // total_size = 16 at offset 90
    try testing.expectEqual(@as(u32, 16), std.mem.readInt(u32, anchor[90..][0..4], .little));
    // rung = 2 at payload offset 0 (cell byte 256)
    try testing.expectEqual(@as(u8, 2), anchor[256]);
    // octave_level = 0 at cell byte 257
    try testing.expectEqual(@as(u8, 0), anchor[257]);
    // child_count = 3 at bytes 258-259 (u16 LE)
    try testing.expectEqual(@as(u16, 3), std.mem.readInt(u16, anchor[258..][0..2], .little));
    // total_bytes = 3072 at bytes 260-267 (u64 LE)
    try testing.expectEqual(total_b, std.mem.readInt(u64, anchor[260..][0..8], .little));
    // reserved = 0 at bytes 268-271
    try testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, anchor[268..][0..4], .little));
    // domainPayloadRoot at 224-255 = CANONICAL_ROOT
    try testing.expectEqualSlices(u8, &CANONICAL_ROOT, anchor[224..256]);
    // payload bytes 272..1023 are zero
    for (anchor[272..1024]) |b| {
        try testing.expectEqual(@as(u8, 0), b);
    }
}

// ── isMerkleHierarchy ──────────────────────────────────────────────────────────

test "isMerkleHierarchy: rung-0 cell returns false" {
    // A normal rung-0 cell has cell_count != sentinel.
    var buf: [constants.CELL_SIZE]u8 = [_]u8{0} ** constants.CELL_SIZE;
    // Write a plausible cell_count (e.g. 1) at offset 86
    std.mem.writeInt(u32, buf[86..][0..4], 1, .little);
    try testing.expect(!isMerkleHierarchy(&buf));
}

test "isMerkleHierarchy: rung-1 cell returns false (rung=1, not 2)" {
    var buf: [constants.CELL_SIZE]u8 = [_]u8{0} ** constants.CELL_SIZE;
    std.mem.writeInt(u32, buf[86..][0..4], ESCALATION_CELL_COUNT_SENTINEL, .little);
    buf[256] = 1; // rung = 1 (octave_escalated)
    try testing.expect(!isMerkleHierarchy(&buf));
}

test "isMerkleHierarchy: rung-2 cell returns true" {
    var buf: [constants.CELL_SIZE]u8 = [_]u8{0} ** constants.CELL_SIZE;
    std.mem.writeInt(u32, buf[86..][0..4], ESCALATION_CELL_COUNT_SENTINEL, .little);
    buf[256] = 2; // rung = 2
    try testing.expect(isMerkleHierarchy(&buf));
}

test "isMerkleHierarchy: buffer smaller than CELL_SIZE returns false" {
    var tiny: [100]u8 = [_]u8{0} ** 100;
    try testing.expect(!isMerkleHierarchy(&tiny));
}

// ── Backward-compat: rung-0/1 multi-cell operations are unaffected ─────────────

// ── D-OCT-octave-2-plus: octave-2/3 hierarchy tests ──────────────────────────
//
// These tests use SYNTHETIC total_bytes values (constants, NOT giant allocations).
// The merkle hierarchy anchor cell is 1024 bytes regardless of octave_level;
// octave_level is metadata recorded in the descriptor so consumers know what
// kind of child cells the tree contains.  No multi-GiB buffers are allocated.

test "octave-2-plus: packMerkleHierarchy records octave_level=2 (mega) correctly" {
    const alloc = testing.allocator;

    var header: [256]u8 = [_]u8{0} ** 256;
    const cell_a = try makeChildCell(alloc, 0xAA);
    defer alloc.free(cell_a);
    const cells: []const []const u8 = &.{cell_a};

    // Synthetic total_bytes = 2 GiB (octave-2 territory) — NO allocation.
    const two_gib: u64 = 2 * 1024 * 1024 * 1024;

    var anchor: [constants.CELL_SIZE]u8 = undefined;
    try packMerkleHierarchy(alloc, &header, cells, two_gib, OCTAVE_LEVEL_MEGA, &anchor);

    try testing.expect(isMerkleHierarchy(&anchor));

    const desc = try unpackMerkleHierarchy(&anchor);
    try testing.expectEqual(@as(u8, OCTAVE_LEVEL_MEGA), desc.octave_level);
    try testing.expectEqual(two_gib, desc.total_bytes);
    try testing.expectEqual(@as(u16, 1), desc.child_count);
}

test "octave-2-plus: packMerkleHierarchy records octave_level=3 (giga) correctly" {
    const alloc = testing.allocator;

    var header: [256]u8 = [_]u8{0} ** 256;
    const cell_a = try makeChildCell(alloc, 0xBB);
    defer alloc.free(cell_a);
    const cell_b = try makeChildCell(alloc, 0xCC);
    defer alloc.free(cell_b);
    const cells: []const []const u8 = &.{ cell_a, cell_b };

    // Synthetic total_bytes = 1 TiB (octave-3 territory) — NO allocation.
    const one_tib: u64 = 1024 * 1024 * 1024 * 1024;

    var anchor: [constants.CELL_SIZE]u8 = undefined;
    try packMerkleHierarchy(alloc, &header, cells, one_tib, OCTAVE_LEVEL_GIGA, &anchor);

    try testing.expect(isMerkleHierarchy(&anchor));

    const desc = try unpackMerkleHierarchy(&anchor);
    try testing.expectEqual(@as(u8, OCTAVE_LEVEL_GIGA), desc.octave_level);
    try testing.expectEqual(one_tib, desc.total_bytes);
    try testing.expectEqual(@as(u16, 2), desc.child_count);
}

test "octave-2-plus: O-1 header total_size = ESCALATION_DESCRIPTOR_SIZE for octave-2" {
    const alloc = testing.allocator;

    var header: [256]u8 = [_]u8{0} ** 256;
    // Pre-fill header offset 90 (total_size) with a non-zero value.
    std.mem.writeInt(u32, header[90..][0..4], 0xDEADBEEF, .little);

    const cell_a = try makeChildCell(alloc, 0x55);
    defer alloc.free(cell_a);
    const cells: []const []const u8 = &.{cell_a};

    const two_gib: u64 = 2 * 1024 * 1024 * 1024;
    var anchor: [constants.CELL_SIZE]u8 = undefined;
    try packMerkleHierarchy(alloc, &header, cells, two_gib, OCTAVE_LEVEL_MEGA, &anchor);

    // O-1: total_size at offset 90 MUST be ESCALATION_DESCRIPTOR_SIZE (16),
    // NOT the large logical total_bytes value.
    const total_size = std.mem.readInt(u32, anchor[90..][0..4], .little);
    try testing.expectEqual(@as(u32, escalation_descriptor.ESCALATION_DESCRIPTOR_SIZE), total_size);

    // The descriptor's total_bytes (u64) is the authoritative logical size.
    const desc = try unpackMerkleHierarchy(&anchor);
    try testing.expectEqual(two_gib, desc.total_bytes);
}

test "octave-2-plus: O-1 header total_size = ESCALATION_DESCRIPTOR_SIZE for octave-3" {
    const alloc = testing.allocator;

    var header: [256]u8 = [_]u8{0} ** 256;
    std.mem.writeInt(u32, header[90..][0..4], 0xDEADBEEF, .little);

    const cell_a = try makeChildCell(alloc, 0x66);
    defer alloc.free(cell_a);
    const cells: []const []const u8 = &.{cell_a};

    const one_tib: u64 = 1024 * 1024 * 1024 * 1024;
    var anchor: [constants.CELL_SIZE]u8 = undefined;
    try packMerkleHierarchy(alloc, &header, cells, one_tib, OCTAVE_LEVEL_GIGA, &anchor);

    // O-1 uniform for ALL rung≥1: total_size = 16 (descriptor size only).
    const total_size = std.mem.readInt(u32, anchor[90..][0..4], .little);
    try testing.expectEqual(@as(u32, escalation_descriptor.ESCALATION_DESCRIPTOR_SIZE), total_size);

    const desc = try unpackMerkleHierarchy(&anchor);
    try testing.expectEqual(one_tib, desc.total_bytes);
}

test "octave-2-plus: octave_level byte at cell[257] matches expected" {
    const alloc = testing.allocator;

    var header: [256]u8 = [_]u8{0} ** 256;
    const cell_a = try makeChildCell(alloc, 0x77);
    defer alloc.free(cell_a);
    const cells: []const []const u8 = &.{cell_a};

    // 2 GiB synthetic total
    const two_gib: u64 = 2 * 1024 * 1024 * 1024;

    // Test mega (octave-2)
    var anchor_mega: [constants.CELL_SIZE]u8 = undefined;
    try packMerkleHierarchy(alloc, &header, cells, two_gib, OCTAVE_LEVEL_MEGA, &anchor_mega);
    try testing.expectEqual(@as(u8, 2), anchor_mega[257]); // octave_level at descriptor offset 1

    // Test giga (octave-3)
    var anchor_giga: [constants.CELL_SIZE]u8 = undefined;
    try packMerkleHierarchy(alloc, &header, cells, two_gib, OCTAVE_LEVEL_GIGA, &anchor_giga);
    try testing.expectEqual(@as(u8, 3), anchor_giga[257]); // octave_level at descriptor offset 1
}

test "octave-2-plus: invalid octave_level > MAX_OCTAVE_LEVEL returns error" {
    const alloc = testing.allocator;

    var header: [256]u8 = [_]u8{0} ** 256;
    const cell_a = try makeChildCell(alloc, 0x88);
    defer alloc.free(cell_a);
    const cells: []const []const u8 = &.{cell_a};

    var anchor: [constants.CELL_SIZE]u8 = undefined;
    const result = packMerkleHierarchy(alloc, &header, cells, 100, 4, &anchor); // 4 > MAX_OCTAVE_LEVEL=3
    try testing.expectError(error.OctaveLevelTooHigh, result);
}

test "octave-2-plus: descriptor round-trip at octave-2 with synthetic 2 GiB total_bytes" {
    const alloc = testing.allocator;

    var header: [256]u8 = [_]u8{0} ** 256;
    var cells_arr: [3][]u8 = undefined;
    for (&cells_arr, 0..) |*ptr, i| {
        ptr.* = try makeChildCell(alloc, @intCast(i + 0x20));
    }
    defer for (&cells_arr) |ptr| alloc.free(ptr);
    const cells: []const []const u8 = @ptrCast(&cells_arr);

    // Synthetic: 2 GiB — octave-2 territory, no allocation
    const two_gib: u64 = 2 * 1024 * 1024 * 1024;
    var anchor: [constants.CELL_SIZE]u8 = undefined;
    try packMerkleHierarchy(alloc, &header, cells, two_gib, OCTAVE_LEVEL_MEGA, &anchor);

    const desc = try unpackMerkleHierarchy(&anchor);
    try testing.expectEqual(Rung2Desc{ .octave_level = 2, .child_count = 3, .total_bytes = two_gib }, desc_to_check(desc));
}

test "octave-2-plus: descriptor round-trip at octave-3 with synthetic 1 TiB total_bytes" {
    const alloc = testing.allocator;

    var header: [256]u8 = [_]u8{0} ** 256;
    const cell_a = try makeChildCell(alloc, 0xAB);
    defer alloc.free(cell_a);
    const cells: []const []const u8 = &.{cell_a};

    // Synthetic: 1 TiB = 1024^4 bytes — octave-3 territory, no allocation
    const one_tib: u64 = 1024 * 1024 * 1024 * 1024;
    var anchor: [constants.CELL_SIZE]u8 = undefined;
    try packMerkleHierarchy(alloc, &header, cells, one_tib, OCTAVE_LEVEL_GIGA, &anchor);

    const desc = try unpackMerkleHierarchy(&anchor);
    try testing.expectEqual(@as(u8, OCTAVE_LEVEL_GIGA), desc.octave_level);
    try testing.expectEqual(one_tib, desc.total_bytes);
    try testing.expectEqual(@as(u16, 1), desc.child_count);
    // Rung byte at cell[256] = 2 (RUNG_MERKLE_ROOTED)
    try testing.expectEqual(@as(u8, RUNG_MERKLE_ROOTED), anchor[256]);
}

// Helper struct for comparing descriptor fields in round-trip tests.
const Rung2Desc = struct { octave_level: u8, child_count: u16, total_bytes: u64 };
fn desc_to_check(d: MerkleHierarchyDescriptor) Rung2Desc {
    return .{ .octave_level = d.octave_level, .child_count = d.child_count, .total_bytes = d.total_bytes };
}

test "backward-compat: isMerkleHierarchy never triggers on packMultiCell output" {
    const multicell = @import("multicell");
    const cell_mod = @import("cell");

    var header = cell_mod.defaultHeader();
    header.total_size = 10;
    var payload: [10]u8 = [_]u8{0xAB} ** 10;

    var out: [constants.CELL_SIZE]u8 = undefined;
    _ = try multicell.packMultiCell(&header, &payload, &.{}, &out);
    try testing.expect(!isMerkleHierarchy(&out));
}

test "backward-compat: packMerkleHierarchy does not affect rung-1 isEscalated" {
    // packMerkleHierarchy produces a buffer with sentinel + rung=2.
    // Rung-1 (isEscalated) checks sentinel only — so it would return true.
    // This is expected: the sentinel is necessary for both rung-1 and rung-2.
    // The key guarantee is that isMerkleHierarchy(rung-1 buf) == false.
    const multicell = @import("multicell");

    var header: [256]u8 = [_]u8{0} ** 256;
    // Pack a rung-2 anchor.
    const alloc = testing.allocator;
    const cell_a = try makeChildCell(alloc, 0x11);
    defer alloc.free(cell_a);
    const cells: []const []const u8 = &.{cell_a};

    var anchor: [constants.CELL_SIZE]u8 = undefined;
    try packMerkleHierarchy(alloc, &header, cells, @as(u64, constants.CELL_SIZE), OCTAVE_LEVEL_BASE, &anchor);

    // rung-1 isEscalated sees the sentinel → returns true (expected, it's escalated)
    try testing.expect(multicell.isEscalated(&anchor));
    // rung-2 isMerkleHierarchy sees sentinel + rung=2 → returns true
    try testing.expect(isMerkleHierarchy(&anchor));
    // A rung-1 buffer would have rung=1 at byte 256, so isMerkleHierarchy returns false
    // (tested in "isMerkleHierarchy: rung-1 cell returns false" above).
}

```
