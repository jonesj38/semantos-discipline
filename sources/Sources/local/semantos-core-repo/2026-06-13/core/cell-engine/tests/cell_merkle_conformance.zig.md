---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests/cell_merkle_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.964569+00:00
---

# core/cell-engine/tests/cell_merkle_conformance.zig

```zig
// D-OCT-merkle-hierarchy: cell merkle conformance tests.
//
// Test plan:
//   (a) Existing rung-0/1 vectors STILL byte-identical (regression guard).
//   (b) A large blob commits a correct domainPayloadRoot over child-cell leaves (rung-2 descriptor).
//   (c) Inclusion-proof verify succeeds for a valid leaf+path.
//   (d) Inclusion-proof verify FAILS for a tampered leaf/path.
//   (e) Round-trip: packMerkleHierarchy → unpackMerkleHierarchy recovers all fields.
//   (f) Canonical byte-vector: oracle↔Zig mirror agreement on root + proof.
//
// Run: zig build test-cell-merkle -j1 --summary all

const std = @import("std");
const constants = @import("constants");
const cell_mod = @import("cell");
const multicell = @import("multicell");
const cell_merkle = @import("cell_merkle");

// ── Helpers ────────────────────────────────────────────────────────────────────

fn makeChildCell(alloc: std.mem.Allocator, pattern: u8) ![]u8 {
    const buf = try alloc.alloc(u8, constants.CELL_SIZE);
    @memset(buf, pattern);
    return buf;
}

fn makeHeader() [256]u8 {
    return [_]u8{0} ** 256;
}

// ── (a) Regression guard: rung-0/1 bytes are unaffected ───────────────────────

test "(a) rung-0: packMultiCell output NOT detected as merkle hierarchy" {
    var header = cell_mod.defaultHeader();
    header.total_size = 10;
    var payload: [10]u8 = [_]u8{0xAB} ** 10;

    var out: [constants.CELL_SIZE]u8 = undefined;
    _ = try multicell.packMultiCell(&header, &payload, &.{}, &out);

    try std.testing.expect(!cell_merkle.isMerkleHierarchy(&out));
    // Also must not have sentinel
    const cc = std.mem.readInt(u32, out[86..][0..4], .little);
    try std.testing.expect(cc != cell_merkle.ESCALATION_CELL_COUNT_SENTINEL);
}

test "(a) rung-0: multi-cell with 4 continuations NOT merkle hierarchy" {
    var header = cell_mod.defaultHeader();
    header.total_size = 64;
    var payload: [64]u8 = [_]u8{0xCC} ** 64;

    var d1: [100]u8 = [_]u8{0x11} ** 100;
    var d2: [200]u8 = [_]u8{0x22} ** 200;
    const conts = [_]multicell.ContinuationInput{
        .{ .cell_type = constants.CELL_TYPE_DATA, .data = &d1 },
        .{ .cell_type = constants.CELL_TYPE_DATA, .data = &d2 },
    };
    var out: [3 * constants.CELL_SIZE]u8 = undefined;
    _ = try multicell.packMultiCell(&header, &payload, &conts, &out);
    try std.testing.expect(!cell_merkle.isMerkleHierarchy(out[0..constants.CELL_SIZE]));
    try std.testing.expect(!multicell.isEscalated(out[0..constants.CELL_SIZE]));
}

test "(a) rung-1: packEscalated output is escalated but NOT merkle hierarchy" {
    const alloc = std.testing.allocator;
    const payload_len: usize = 5000;
    const data = try alloc.alloc(u8, payload_len);
    defer alloc.free(data);
    @memset(data, 0x55);

    var header = cell_mod.defaultHeader();
    const out_buf = try alloc.alloc(u8, constants.CELL_SIZE + payload_len);
    defer alloc.free(out_buf);

    _ = try multicell.packEscalated(&header, data, out_buf);

    // rung-1: isEscalated returns true
    try std.testing.expect(multicell.isEscalated(out_buf[0..constants.CELL_SIZE]));
    // But it is NOT rung-2
    try std.testing.expect(!cell_merkle.isMerkleHierarchy(out_buf[0..constants.CELL_SIZE]));
    // Byte 256 should be rung=1
    try std.testing.expectEqual(@as(u8, 1), out_buf[256]);
}

// ── (b) Rung-2 anchor cell has correct domainPayloadRoot ──────────────────────

test "(b) packMerkleHierarchy: correct root committed into domainPayloadRoot" {
    const alloc = std.testing.allocator;

    const cell_a = try makeChildCell(alloc, 0x11);
    defer alloc.free(cell_a);
    const cell_b = try makeChildCell(alloc, 0x22);
    defer alloc.free(cell_b);
    const cell_c = try makeChildCell(alloc, 0x33);
    defer alloc.free(cell_c);

    const cells: []const []const u8 = &.{ cell_a, cell_b, cell_c };
    const expected_root = try cell_merkle.computeCellMerkleRoot(alloc, cells);

    var header = makeHeader();
    var anchor: [constants.CELL_SIZE]u8 = undefined;
    try cell_merkle.packMerkleHierarchy(alloc, &header, cells, @as(u64, 3 * constants.CELL_SIZE), cell_merkle.OCTAVE_LEVEL_BASE, &anchor);

    // domainPayloadRoot at offset 224-255
    try std.testing.expectEqualSlices(u8, &expected_root, anchor[224..256]);
}

test "(b) descriptor: rung=2, octave_level=0, child_count=N, total_bytes" {
    const alloc = std.testing.allocator;

    const N: usize = 5;
    var cells_arr: [N][]u8 = undefined;
    for (&cells_arr, 0..) |*ptr, i| {
        ptr.* = try makeChildCell(alloc, @intCast(i + 1));
    }
    defer for (&cells_arr) |ptr| alloc.free(ptr);

    const cells: []const []const u8 = @ptrCast(&cells_arr);
    const total_b: u64 = N * constants.CELL_SIZE;

    var header = makeHeader();
    var anchor: [constants.CELL_SIZE]u8 = undefined;
    try cell_merkle.packMerkleHierarchy(alloc, &header, cells, total_b, cell_merkle.OCTAVE_LEVEL_BASE, &anchor);

    // rung = 2 at cell byte 256
    try std.testing.expectEqual(@as(u8, 2), anchor[256]);
    // octave_level = 0 at cell byte 257
    try std.testing.expectEqual(@as(u8, 0), anchor[257]);
    // child_count = N at bytes 258-259 (u16 LE)
    const cc = std.mem.readInt(u16, anchor[258..][0..2], .little);
    try std.testing.expectEqual(@as(u16, N), cc);
    // total_bytes at bytes 260-267 (u64 LE)
    const tb = std.mem.readInt(u64, anchor[260..][0..8], .little);
    try std.testing.expectEqual(total_b, tb);
    // reserved = 0 at bytes 268-271
    const res = std.mem.readInt(u32, anchor[268..][0..4], .little);
    try std.testing.expectEqual(@as(u32, 0), res);
}

test "(b) sentinel and total_size bytes are correct" {
    const alloc = std.testing.allocator;
    const cell_a = try makeChildCell(alloc, 0xaa);
    defer alloc.free(cell_a);

    const cells: []const []const u8 = &.{cell_a};
    var header = makeHeader();
    var anchor: [constants.CELL_SIZE]u8 = undefined;
    try cell_merkle.packMerkleHierarchy(alloc, &header, cells, 1024, cell_merkle.OCTAVE_LEVEL_BASE, &anchor);

    // sentinel at offset 86
    const sentinel = std.mem.readInt(u32, anchor[86..][0..4], .little);
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), sentinel);
    // total_size = 16 at offset 90
    const ts = std.mem.readInt(u32, anchor[90..][0..4], .little);
    try std.testing.expectEqual(@as(u32, 16), ts);
}

// ── (c) Inclusion proof: valid ────────────────────────────────────────────────

test "(c) proof verifies for leaf 0 of a 2-cell set" {
    const alloc = std.testing.allocator;
    const cell_a = try makeChildCell(alloc, 0xaa);
    defer alloc.free(cell_a);
    const cell_b = try makeChildCell(alloc, 0xbb);
    defer alloc.free(cell_b);

    const cells: []const []const u8 = &.{ cell_a, cell_b };
    const root = try cell_merkle.computeCellMerkleRoot(alloc, cells);

    const proof = try cell_merkle.generateCellInclusionProof(alloc, cells, 0);
    try std.testing.expect(cell_merkle.verifyCellInclusion(cell_a, &proof, &root));
}

test "(c) proof verifies for leaf 1 of a 2-cell set" {
    const alloc = std.testing.allocator;
    const cell_a = try makeChildCell(alloc, 0xaa);
    defer alloc.free(cell_a);
    const cell_b = try makeChildCell(alloc, 0xbb);
    defer alloc.free(cell_b);

    const cells: []const []const u8 = &.{ cell_a, cell_b };
    const root = try cell_merkle.computeCellMerkleRoot(alloc, cells);

    const proof = try cell_merkle.generateCellInclusionProof(alloc, cells, 1);
    try std.testing.expect(cell_merkle.verifyCellInclusion(cell_b, &proof, &root));
}

test "(c) all leaves verify in a 5-cell set (odd count)" {
    const alloc = std.testing.allocator;
    var cells_arr: [5][]u8 = undefined;
    for (&cells_arr, 0..) |*ptr, i| {
        ptr.* = try makeChildCell(alloc, @intCast(i + 1));
    }
    defer for (&cells_arr) |ptr| alloc.free(ptr);

    const cells: []const []const u8 = @ptrCast(&cells_arr);
    const root = try cell_merkle.computeCellMerkleRoot(alloc, cells);

    for (0..5) |i| {
        const proof = try cell_merkle.generateCellInclusionProof(alloc, cells, i);
        try std.testing.expect(cell_merkle.verifyCellInclusion(cells[i], &proof, &root));
    }
}

test "(c) single-cell: root equals leaf hash, proof verifies" {
    const alloc = std.testing.allocator;
    const cell_x = try makeChildCell(alloc, 0x42);
    defer alloc.free(cell_x);

    const cells: []const []const u8 = &.{cell_x};
    const root = try cell_merkle.computeCellMerkleRoot(alloc, cells);

    var expected: [32]u8 = undefined;
    cell_merkle.sha256(cell_x, &expected);
    try std.testing.expectEqualSlices(u8, &expected, &root);

    const proof = try cell_merkle.generateCellInclusionProof(alloc, cells, 0);
    try std.testing.expect(cell_merkle.verifyCellInclusion(cell_x, &proof, &root));
}

// ── (d) Inclusion proof: tampered ────────────────────────────────────────────

test "(d) tampered cell bytes: verification fails" {
    const alloc = std.testing.allocator;
    var cell_a = try makeChildCell(alloc, 0x01);
    defer alloc.free(cell_a);
    const cell_b = try makeChildCell(alloc, 0x02);
    defer alloc.free(cell_b);

    const cells: []const []const u8 = &.{ cell_a, cell_b };
    const root = try cell_merkle.computeCellMerkleRoot(alloc, cells);
    const proof = try cell_merkle.generateCellInclusionProof(alloc, cells, 0);

    // Tamper one byte in cell_a
    cell_a[100] ^= 0xFF;
    try std.testing.expect(!cell_merkle.verifyCellInclusion(cell_a, &proof, &root));
}

test "(d) tampered sibling hash: verification fails" {
    const alloc = std.testing.allocator;
    const cell_a = try makeChildCell(alloc, 0x10);
    defer alloc.free(cell_a);
    const cell_b = try makeChildCell(alloc, 0x20);
    defer alloc.free(cell_b);

    const cells: []const []const u8 = &.{ cell_a, cell_b };
    const root = try cell_merkle.computeCellMerkleRoot(alloc, cells);
    var proof = try cell_merkle.generateCellInclusionProof(alloc, cells, 0);

    // Tamper a sibling hash byte
    proof.siblings[0].hash[5] ^= 0xFF;
    try std.testing.expect(!cell_merkle.verifyCellInclusion(cell_a, &proof, &root));
}

test "(d) wrong root: verification fails" {
    const alloc = std.testing.allocator;
    const cell_a = try makeChildCell(alloc, 0xaa);
    defer alloc.free(cell_a);
    const cell_b = try makeChildCell(alloc, 0xbb);
    defer alloc.free(cell_b);

    const cells: []const []const u8 = &.{ cell_a, cell_b };
    const root = try cell_merkle.computeCellMerkleRoot(alloc, cells);
    const proof = try cell_merkle.generateCellInclusionProof(alloc, cells, 0);

    var wrong_root = root;
    wrong_root[0] ^= 0xFF;
    try std.testing.expect(!cell_merkle.verifyCellInclusion(cell_a, &proof, &wrong_root));
}

test "(d) proof for leaf 0 does NOT verify leaf 1" {
    const alloc = std.testing.allocator;
    const cell_a = try makeChildCell(alloc, 0x11);
    defer alloc.free(cell_a);
    const cell_b = try makeChildCell(alloc, 0x22);
    defer alloc.free(cell_b);

    const cells: []const []const u8 = &.{ cell_a, cell_b };
    const root = try cell_merkle.computeCellMerkleRoot(alloc, cells);
    const proof = try cell_merkle.generateCellInclusionProof(alloc, cells, 0);

    // Use cell_b with leaf-0's proof
    try std.testing.expect(!cell_merkle.verifyCellInclusion(cell_b, &proof, &root));
}

// ── (e) Round-trip ────────────────────────────────────────────────────────────

test "(e) packMerkleHierarchy / unpackMerkleHierarchy round-trip" {
    const alloc = std.testing.allocator;

    const N = 7;
    var cells_arr: [N][]u8 = undefined;
    for (&cells_arr, 0..) |*ptr, i| {
        ptr.* = try makeChildCell(alloc, @intCast(i + 1));
    }
    defer for (&cells_arr) |ptr| alloc.free(ptr);

    const cells: []const []const u8 = @ptrCast(&cells_arr);
    const total_b: u64 = N * constants.CELL_SIZE;

    var header = makeHeader();
    var anchor: [constants.CELL_SIZE]u8 = undefined;
    try cell_merkle.packMerkleHierarchy(alloc, &header, cells, total_b, cell_merkle.OCTAVE_LEVEL_BASE, &anchor);

    try std.testing.expect(cell_merkle.isMerkleHierarchy(&anchor));

    const desc = try cell_merkle.unpackMerkleHierarchy(&anchor);
    try std.testing.expectEqual(@as(u16, N), desc.child_count);
    try std.testing.expectEqual(total_b, desc.total_bytes);
    try std.testing.expectEqual(cell_merkle.OCTAVE_LEVEL_BASE, desc.octave_level);

    // Root matches computeCellMerkleRoot
    const expected = try cell_merkle.computeCellMerkleRoot(alloc, cells);
    try std.testing.expectEqualSlices(u8, &expected, &desc.merkle_root);
}

// ── (f) Canonical byte-vector: oracle↔Zig mirror agreement ───────────────────
//
// Canonical vector:
//   cells = [all 0x41 (1024B), all 0x42, all 0x43]
//   CANONICAL_ROOT (from cell_merkle.zig) must equal:
//   c72747c0b84da25338a1b50152a7c664c38c287359437c67f590d66faef5cba4
//   (confirmed by TS oracle test "canonical root hex value is stable")

test "(f) canonical 3-cell root matches TS oracle" {
    const alloc = std.testing.allocator;

    const cell_a = try makeChildCell(alloc, 0x41);
    defer alloc.free(cell_a);
    const cell_b = try makeChildCell(alloc, 0x42);
    defer alloc.free(cell_b);
    const cell_c = try makeChildCell(alloc, 0x43);
    defer alloc.free(cell_c);

    const cells: []const []const u8 = &.{ cell_a, cell_b, cell_c };
    const root = try cell_merkle.computeCellMerkleRoot(alloc, cells);

    try std.testing.expectEqualSlices(u8, &cell_merkle.CANONICAL_ROOT, &root);
}

test "(f) canonical anchor cell wire bytes (oracle agreement)" {
    const alloc = std.testing.allocator;

    const cell_a = try makeChildCell(alloc, 0x41);
    defer alloc.free(cell_a);
    const cell_b = try makeChildCell(alloc, 0x42);
    defer alloc.free(cell_b);
    const cell_c = try makeChildCell(alloc, 0x43);
    defer alloc.free(cell_c);

    const cells: []const []const u8 = &.{ cell_a, cell_b, cell_c };
    const total_b: u64 = 3 * constants.CELL_SIZE;

    var header = makeHeader();
    var anchor: [constants.CELL_SIZE]u8 = undefined;
    try cell_merkle.packMerkleHierarchy(alloc, &header, cells, total_b, cell_merkle.OCTAVE_LEVEL_BASE, &anchor);

    // sentinel at offset 86
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), std.mem.readInt(u32, anchor[86..][0..4], .little));
    // total_size = 16 at offset 90
    try std.testing.expectEqual(@as(u32, 16), std.mem.readInt(u32, anchor[90..][0..4], .little));
    // rung = 2 at cell byte 256
    try std.testing.expectEqual(@as(u8, 2), anchor[256]);
    // octave_level = 0 at cell byte 257
    try std.testing.expectEqual(@as(u8, 0), anchor[257]);
    // child_count = 3 at bytes 258-259 (u16 LE)
    try std.testing.expectEqual(@as(u16, 3), std.mem.readInt(u16, anchor[258..][0..2], .little));
    // total_bytes = 3072 at bytes 260-267 (u64 LE)
    try std.testing.expectEqual(total_b, std.mem.readInt(u64, anchor[260..][0..8], .little));
    // reserved = 0 at bytes 268-271
    try std.testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, anchor[268..][0..4], .little));
    // domainPayloadRoot at 224-255 = CANONICAL_ROOT
    try std.testing.expectEqualSlices(u8, &cell_merkle.CANONICAL_ROOT, anchor[224..256]);
    // payload bytes 272..1023 are zero
    for (anchor[272..1024]) |b| {
        try std.testing.expectEqual(@as(u8, 0), b);
    }
}

test "(f) canonical inclusion proof for leaf 1 (cell B) verifies" {
    const alloc = std.testing.allocator;

    const cell_a = try makeChildCell(alloc, 0x41);
    defer alloc.free(cell_a);
    const cell_b = try makeChildCell(alloc, 0x42);
    defer alloc.free(cell_b);
    const cell_c = try makeChildCell(alloc, 0x43);
    defer alloc.free(cell_c);

    const cells: []const []const u8 = &.{ cell_a, cell_b, cell_c };
    const root = try cell_merkle.computeCellMerkleRoot(alloc, cells);

    // Confirm root matches canonical
    try std.testing.expectEqualSlices(u8, &cell_merkle.CANONICAL_ROOT, &root);

    const proof = try cell_merkle.generateCellInclusionProof(alloc, cells, 1);
    try std.testing.expect(cell_merkle.verifyCellInclusion(cell_b, &proof, &root));
}

test "(f) canonical inclusion proof for leaf 0 (cell A) verifies" {
    const alloc = std.testing.allocator;

    const cell_a = try makeChildCell(alloc, 0x41);
    defer alloc.free(cell_a);
    const cell_b = try makeChildCell(alloc, 0x42);
    defer alloc.free(cell_b);
    const cell_c = try makeChildCell(alloc, 0x43);
    defer alloc.free(cell_c);

    const cells: []const []const u8 = &.{ cell_a, cell_b, cell_c };
    const root = try cell_merkle.computeCellMerkleRoot(alloc, cells);
    const proof = try cell_merkle.generateCellInclusionProof(alloc, cells, 0);
    try std.testing.expect(cell_merkle.verifyCellInclusion(cell_a, &proof, &root));
}

test "(f) canonical inclusion proof for leaf 2 (cell C) verifies" {
    const alloc = std.testing.allocator;

    const cell_a = try makeChildCell(alloc, 0x41);
    defer alloc.free(cell_a);
    const cell_b = try makeChildCell(alloc, 0x42);
    defer alloc.free(cell_b);
    const cell_c = try makeChildCell(alloc, 0x43);
    defer alloc.free(cell_c);

    const cells: []const []const u8 = &.{ cell_a, cell_b, cell_c };
    const root = try cell_merkle.computeCellMerkleRoot(alloc, cells);
    const proof = try cell_merkle.generateCellInclusionProof(alloc, cells, 2);
    try std.testing.expect(cell_merkle.verifyCellInclusion(cell_c, &proof, &root));
}

// ── Additional: isMerkleHierarchy ─────────────────────────────────────────────

test "isMerkleHierarchy: returns false for tiny buffer" {
    var tiny: [100]u8 = [_]u8{0} ** 100;
    try std.testing.expect(!cell_merkle.isMerkleHierarchy(&tiny));
}

test "isMerkleHierarchy: returns false if rung byte is not 2" {
    var buf: [constants.CELL_SIZE]u8 = [_]u8{0} ** constants.CELL_SIZE;
    std.mem.writeInt(u32, buf[86..][0..4], 0xFFFFFFFF, .little);
    buf[256] = 1; // rung = 1
    try std.testing.expect(!cell_merkle.isMerkleHierarchy(&buf));
}

// ── D-OCT-octave-2-plus: octave-2/3 conformance tests ────────────────────────
//
// These tests use SYNTHETIC total_bytes values. No multi-GiB allocations.
// The anchor cell is always 1024 bytes; octave_level is metadata in the descriptor.

test "(oct2+) octave-2 (mega) anchor cell round-trips correctly" {
    const alloc = std.testing.allocator;

    const cell_a = try makeChildCell(alloc, 0xA1);
    defer alloc.free(cell_a);
    const cell_b = try makeChildCell(alloc, 0xA2);
    defer alloc.free(cell_b);
    const cells: []const []const u8 = &.{ cell_a, cell_b };

    // Synthetic 2 GiB total — no allocation
    const two_gib: u64 = 2 * 1024 * 1024 * 1024;

    var header = makeHeader();
    var anchor: [constants.CELL_SIZE]u8 = undefined;
    try cell_merkle.packMerkleHierarchy(alloc, &header, cells, two_gib, cell_merkle.OCTAVE_LEVEL_MEGA, &anchor);

    try std.testing.expect(cell_merkle.isMerkleHierarchy(&anchor));
    const desc = try cell_merkle.unpackMerkleHierarchy(&anchor);
    try std.testing.expectEqual(@as(u8, 2), desc.octave_level);
    try std.testing.expectEqual(two_gib, desc.total_bytes);
    try std.testing.expectEqual(@as(u16, 2), desc.child_count);
}

test "(oct2+) octave-3 (giga) anchor cell round-trips correctly" {
    const alloc = std.testing.allocator;

    const cell_a = try makeChildCell(alloc, 0xB1);
    defer alloc.free(cell_a);
    const cells: []const []const u8 = &.{cell_a};

    // Synthetic 1 TiB total — no allocation
    const one_tib: u64 = 1024 * 1024 * 1024 * 1024;

    var header = makeHeader();
    var anchor: [constants.CELL_SIZE]u8 = undefined;
    try cell_merkle.packMerkleHierarchy(alloc, &header, cells, one_tib, cell_merkle.OCTAVE_LEVEL_GIGA, &anchor);

    try std.testing.expect(cell_merkle.isMerkleHierarchy(&anchor));
    const desc = try cell_merkle.unpackMerkleHierarchy(&anchor);
    try std.testing.expectEqual(@as(u8, 3), desc.octave_level);
    try std.testing.expectEqual(one_tib, desc.total_bytes);
    try std.testing.expectEqual(@as(u16, 1), desc.child_count);
}

test "(oct2+) O-1: total_size=16 in anchor cell header for octave-2" {
    const alloc = std.testing.allocator;
    const cell_a = try makeChildCell(alloc, 0xC1);
    defer alloc.free(cell_a);
    const cells: []const []const u8 = &.{cell_a};

    var header = makeHeader();
    // Pre-fill total_size with garbage to prove it gets overwritten.
    std.mem.writeInt(u32, header[90..][0..4], 0xDEADBEEF, .little);

    const two_gib: u64 = 2 * 1024 * 1024 * 1024;
    var anchor: [constants.CELL_SIZE]u8 = undefined;
    try cell_merkle.packMerkleHierarchy(alloc, &header, cells, two_gib, cell_merkle.OCTAVE_LEVEL_MEGA, &anchor);

    // O-1 rule: total_size at offset 90 = ESCALATION_DESCRIPTOR_SIZE (16) for ALL rung≥1.
    const ts = std.mem.readInt(u32, anchor[90..][0..4], .little);
    try std.testing.expectEqual(@as(u32, 16), ts);
    // The descriptor's total_bytes u64 is the authoritative logical size.
    const desc = try cell_merkle.unpackMerkleHierarchy(&anchor);
    try std.testing.expectEqual(two_gib, desc.total_bytes);
}

test "(oct2+) O-1: total_size=16 in anchor cell header for octave-3" {
    const alloc = std.testing.allocator;
    const cell_a = try makeChildCell(alloc, 0xD1);
    defer alloc.free(cell_a);
    const cells: []const []const u8 = &.{cell_a};

    var header = makeHeader();
    std.mem.writeInt(u32, header[90..][0..4], 0xDEADBEEF, .little);

    const one_tib: u64 = 1024 * 1024 * 1024 * 1024;
    var anchor: [constants.CELL_SIZE]u8 = undefined;
    try cell_merkle.packMerkleHierarchy(alloc, &header, cells, one_tib, cell_merkle.OCTAVE_LEVEL_GIGA, &anchor);

    const ts = std.mem.readInt(u32, anchor[90..][0..4], .little);
    try std.testing.expectEqual(@as(u32, 16), ts);
    const desc = try cell_merkle.unpackMerkleHierarchy(&anchor);
    try std.testing.expectEqual(one_tib, desc.total_bytes);
}

test "(oct2+) octave_level constants: KILO=1, MEGA=2, GIGA=3, MAX=3" {
    try std.testing.expectEqual(@as(u8, 0), cell_merkle.OCTAVE_LEVEL_BASE);
    try std.testing.expectEqual(@as(u8, 1), cell_merkle.OCTAVE_LEVEL_KILO);
    try std.testing.expectEqual(@as(u8, 2), cell_merkle.OCTAVE_LEVEL_MEGA);
    try std.testing.expectEqual(@as(u8, 3), cell_merkle.OCTAVE_LEVEL_GIGA);
    try std.testing.expectEqual(@as(u8, 3), cell_merkle.MAX_OCTAVE_LEVEL);
}

test "(oct2+) invalid octave_level > 3 returns OctaveLevelTooHigh" {
    const alloc = std.testing.allocator;
    const cell_a = try makeChildCell(alloc, 0xE1);
    defer alloc.free(cell_a);
    const cells: []const []const u8 = &.{cell_a};
    var header = makeHeader();
    var anchor: [constants.CELL_SIZE]u8 = undefined;
    const result = cell_merkle.packMerkleHierarchy(alloc, &header, cells, 100, 4, &anchor);
    try std.testing.expectError(error.OctaveLevelTooHigh, result);
}

test "(oct2+) backward-compat: octave-0 base (OCTAVE_LEVEL_BASE=0) still works" {
    const alloc = std.testing.allocator;
    const cell_a = try makeChildCell(alloc, 0xF1);
    defer alloc.free(cell_a);
    const cells: []const []const u8 = &.{cell_a};
    var header = makeHeader();
    var anchor: [constants.CELL_SIZE]u8 = undefined;
    try cell_merkle.packMerkleHierarchy(alloc, &header, cells, 1024, cell_merkle.OCTAVE_LEVEL_BASE, &anchor);
    const desc = try cell_merkle.unpackMerkleHierarchy(&anchor);
    try std.testing.expectEqual(@as(u8, 0), desc.octave_level);
    try std.testing.expectEqual(@as(u64, 1024), desc.total_bytes);
}

```
