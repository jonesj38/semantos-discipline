---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests/cell_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.970071+00:00
---

# core/cell-engine/tests/cell_conformance.zig

```zig
// Phase 1: Cell packing conformance tests
// (RM-032b stripped the Commerce extension; RM-042 stripped
// OnChainBinding. The corresponding round-trip + cross-lang vector
// tests in this file were removed because the underlying TS packer
// no longer writes those bytes. The cross-lang vectors under
// tests/vectors/single_cell_*.bin need regenerating against the new
// TS packer before the cross-lang test block can be restored.)
const std = @import("std");
const constants = @import("constants");
const cell = @import("cell");

// Type hash for "services.trades.carpentry:hire:inst.contract.service-agreement"
const TEST_TYPE_HASH = [32]u8{
    0x2b, 0x8a, 0x61, 0x18, 0x83, 0x11, 0xfa, 0x55,
    0x73, 0x46, 0xb4, 0x3e, 0xaa, 0xea, 0x8f, 0xbe,
    0x4b, 0x0f, 0x79, 0x40, 0x4e, 0x8e, 0xa6, 0xf1,
    0x2a, 0x2a, 0xc0, 0x08, 0xa4, 0x44, 0x47, 0x61,
};

const TEST_OWNER_ID = [16]u8{
    0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
};

const TEST_TIMESTAMP: u64 = 1700000000000;

test "pack/unpack round-trip preserves all header fields" {
    var header = cell.defaultHeader();
    header.linearity = constants.LINEARITY_LINEAR;
    header.flags = 0x12345678;
    header.ref_count = 42;
    header.timestamp = 1700000000000;
    header.cell_count = 1;
    header.total_size = 32;

    // Set a known type hash
    for (&header.type_hash, 0..) |*b, i| b.* = @intCast(i);
    // Set a known owner id
    for (&header.owner_id, 0..) |*b, i| b.* = @intCast(i + 0x10);

    // Payload: 32 bytes of sequential data
    var payload: [32]u8 = undefined;
    for (&payload, 0..) |*b, i| b.* = @intCast(i);

    var out: [constants.CELL_SIZE]u8 = undefined;
    try cell.packCell(&header, &payload, &out);

    const result = try cell.unpackCell(&out);

    try std.testing.expectEqualSlices(u8, &cell.MAGIC_BYTES, &result.header.magic);
    try std.testing.expectEqual(@as(u32, constants.LINEARITY_LINEAR), result.header.linearity);
    try std.testing.expectEqual(@as(u32, constants.VERSION), result.header.version);
    try std.testing.expectEqual(@as(u32, 0x12345678), result.header.flags);
    try std.testing.expectEqual(@as(u16, 42), result.header.ref_count);
    try std.testing.expectEqualSlices(u8, &header.type_hash, &result.header.type_hash);
    try std.testing.expectEqualSlices(u8, &header.owner_id, &result.header.owner_id);
    try std.testing.expectEqual(@as(u64, 1700000000000), result.header.timestamp);
    try std.testing.expectEqual(@as(u32, 1), result.header.cell_count);
    try std.testing.expectEqual(@as(u32, 32), result.header.total_size);
    try std.testing.expectEqual(@as(u32, 32), result.payload_len);
    try std.testing.expectEqualSlices(u8, &payload, result.payload[0..32]);
}

test "packed cell is exactly 1024 bytes" {
    var header = cell.defaultHeader();
    header.linearity = constants.LINEARITY_AFFINE;
    header.cell_count = 1;
    header.total_size = 0;

    var out: [constants.CELL_SIZE]u8 = undefined;
    try cell.packCell(&header, &.{}, &out);

    try std.testing.expectEqual(@as(usize, 1024), out.len);
}

test "header is exactly 256 bytes at offset 0" {
    var header = cell.defaultHeader();
    header.linearity = constants.LINEARITY_LINEAR;
    header.cell_count = 1;
    header.total_size = 0;

    var out: [constants.CELL_SIZE]u8 = undefined;
    try cell.packCell(&header, &.{}, &out);

    // Magic at offset 0
    try std.testing.expectEqualSlices(u8, &cell.MAGIC_BYTES, out[0..16]);

    // Linearity at offset 16
    const lin = std.mem.readInt(u32, out[16..20], .little);
    try std.testing.expectEqual(@as(u32, constants.LINEARITY_LINEAR), lin);

    // Version at offset 20
    const ver = std.mem.readInt(u32, out[20..24], .little);
    try std.testing.expectEqual(@as(u32, constants.VERSION), ver);
}

test "payload is exactly 768 bytes at offset 256" {
    var header = cell.defaultHeader();
    header.linearity = constants.LINEARITY_LINEAR;
    header.cell_count = 1;
    header.total_size = 10;

    var payload = [_]u8{ 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x11, 0x22, 0x33, 0x44 };
    var out: [constants.CELL_SIZE]u8 = undefined;
    try cell.packCell(&header, &payload, &out);

    // First 10 bytes of payload area should match
    try std.testing.expectEqualSlices(u8, &payload, out[256..266]);
    // Remaining should be zero
    for (out[266..1024]) |b| {
        try std.testing.expectEqual(@as(u8, 0), b);
    }
}

test "magic validation rejects wrong magic" {
    var out: [constants.CELL_SIZE]u8 = undefined;
    @memset(&out, 0);

    // No magic set → should fail
    try std.testing.expectEqual(false, cell.validateMagic(&out));

    // Set magic then corrupt one byte
    @memcpy(out[0..16], &cell.MAGIC_BYTES);
    try std.testing.expectEqual(true, cell.validateMagic(&out));

    out[0] = 0xFF; // Corrupt first byte
    try std.testing.expectEqual(false, cell.validateMagic(&out));
}

test "unpack rejects invalid magic" {
    var out: [constants.CELL_SIZE]u8 = undefined;
    @memset(&out, 0);

    const result = cell.unpackCell(&out);
    try std.testing.expectError(error.invalid_magic, result);
}

test "zero-padding fills unused payload bytes" {
    var header = cell.defaultHeader();
    header.linearity = constants.LINEARITY_LINEAR;
    header.cell_count = 1;
    header.total_size = 4;

    var payload = [_]u8{ 0x01, 0x02, 0x03, 0x04 };
    var out: [constants.CELL_SIZE]u8 = undefined;

    // Fill output with 0xFF to ensure zero-padding works
    @memset(&out, 0xFF);
    try cell.packCell(&header, &payload, &out);

    // Payload bytes present
    try std.testing.expectEqualSlices(u8, &payload, out[256..260]);
    // Rest is zero-padded
    for (out[260..1024]) |b| {
        try std.testing.expectEqual(@as(u8, 0), b);
    }
    // Header area beyond used fields is also zero
    // (reserved area offset 94-255 should be zeroed since header.reserved is zeroed)
    for (out[160..256]) |b| {
        try std.testing.expectEqual(@as(u8, 0), b);
    }
}

test "packCell rejects payload larger than 768 bytes" {
    var header = cell.defaultHeader();
    header.linearity = constants.LINEARITY_LINEAR;
    header.cell_count = 1;
    header.total_size = 769;

    var payload: [769]u8 = undefined;
    @memset(&payload, 0);

    var out: [constants.CELL_SIZE]u8 = undefined;
    const result = cell.packCell(&header, &payload, &out);
    try std.testing.expectError(error.payload_too_large, result);
}

test "full payload (768 bytes) round-trips correctly" {
    var header = cell.defaultHeader();
    header.linearity = constants.LINEARITY_AFFINE;
    header.cell_count = 1;
    header.total_size = constants.PAYLOAD_SIZE;

    var payload: [constants.PAYLOAD_SIZE]u8 = undefined;
    for (&payload, 0..) |*b, i| b.* = @intCast(i & 0xFF);

    var out: [constants.CELL_SIZE]u8 = undefined;
    try cell.packCell(&header, &payload, &out);

    const result = try cell.unpackCell(&out);
    try std.testing.expectEqual(constants.PAYLOAD_SIZE, result.payload_len);
    try std.testing.expectEqualSlices(u8, &payload, &result.payload);
}

// "commerce extension round-trip via cell header" — REMOVED (RM-032b).
// "on-chain binding round-trip via cell header" — REMOVED (RM-042).
// Both tested header surfaces that no longer exist on cell.zig.
//
// Cross-language byte-identity tests vs tests/vectors/single_cell_*.bin
// — REMOVED. The vectors were generated by a TS packer that wrote
// commerce phase/dimension bytes at offsets 94-95; RM-032b removed
// those writes, so the existing vectors no longer match. The block
// is restorable once new vectors are regenerated against the
// post-RM-032b TS packer (likely as part of RM-050's kernel-rebuild
// + ABI bump work).

```
