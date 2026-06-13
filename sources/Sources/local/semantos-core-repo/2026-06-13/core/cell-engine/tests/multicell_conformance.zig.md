---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests/multicell_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.960604+00:00
---

# core/cell-engine/tests/multicell_conformance.zig

```zig
// Phase 1: Multi-cell packing conformance tests
const std = @import("std");
const constants = @import("constants");
const cell = @import("cell");
const multicell = @import("multicell");

test "continuation header is exactly 8 bytes" {
    try std.testing.expectEqual(@as(u32, 8), constants.CONTINUATION_HEADER_SIZE);
}

test "continuation payload is exactly 1016 bytes" {
    try std.testing.expectEqual(@as(u32, 1016), constants.CONTINUATION_PAYLOAD_SIZE);
}

test "single cell object (no continuations) round-trips" {
    var header = cell.defaultHeader();
    header.linearity = constants.LINEARITY_LINEAR;
    header.total_size = 32;

    var payload: [32]u8 = undefined;
    for (&payload, 0..) |*b, i| b.* = @intCast(i);

    var out: [constants.CELL_SIZE]u8 = undefined;
    const written = try multicell.packMultiCell(&header, &payload, &.{}, &out);

    try std.testing.expectEqual(@as(usize, 1024), written);

    const result = try multicell.unpackMultiCell(out[0..written]);
    try std.testing.expectEqual(@as(u32, 0), result.continuation_count);
    try std.testing.expectEqual(@as(u32, 32), result.cell0_payload_len);
    try std.testing.expectEqualSlices(u8, &payload, result.cell0_payload[0..32]);
    // cellCount should be patched to 1
    try std.testing.expectEqual(@as(u32, 1), result.cell0_header.cell_count);
}

test "cell ordering: Cell 0 is header, Cell 1 is BUMP, Cell 2 is DATA" {
    var header = cell.defaultHeader();
    header.linearity = constants.LINEARITY_LINEAR;
    header.total_size = 64;

    var payload: [64]u8 = undefined;
    @memset(&payload, 0xAA);

    var bump_data: [330]u8 = undefined;
    @memset(&bump_data, 0x42);

    var data_payload: [200]u8 = undefined;
    @memset(&data_payload, 0xDD);

    const continuations = [_]multicell.ContinuationInput{
        .{ .cell_type = constants.CELL_TYPE_BUMP, .data = &bump_data },
        .{ .cell_type = constants.CELL_TYPE_DATA, .data = &data_payload },
    };

    var out: [3 * constants.CELL_SIZE]u8 = undefined;
    const written = try multicell.packMultiCell(&header, &payload, &continuations, &out);

    try std.testing.expectEqual(@as(usize, 3 * 1024), written);

    // Cell 0: magic at offset 0
    try std.testing.expectEqualSlices(u8, &cell.MAGIC_BYTES, out[0..16]);

    // Cell 1: BUMP type at offset 1024
    try std.testing.expectEqual(constants.CELL_TYPE_BUMP, out[1024]);

    // Cell 2: DATA type at offset 2048
    try std.testing.expectEqual(constants.CELL_TYPE_DATA, out[2048]);
}

test "cellIndex increments sequentially (1-based)" {
    var header = cell.defaultHeader();
    header.linearity = constants.LINEARITY_LINEAR;
    header.total_size = 0;

    var d1: [100]u8 = undefined;
    @memset(&d1, 0x11);
    var d2: [200]u8 = undefined;
    @memset(&d2, 0x22);
    var d3: [300]u8 = undefined;
    @memset(&d3, 0x33);

    const continuations = [_]multicell.ContinuationInput{
        .{ .cell_type = constants.CELL_TYPE_BUMP, .data = &d1 },
        .{ .cell_type = constants.CELL_TYPE_ATOMIC_BEEF, .data = &d2 },
        .{ .cell_type = constants.CELL_TYPE_DATA, .data = &d3 },
    };

    var out: [4 * constants.CELL_SIZE]u8 = undefined;
    const written = try multicell.packMultiCell(&header, &.{}, &continuations, &out);
    try std.testing.expectEqual(@as(usize, 4 * 1024), written);

    const result = try multicell.unpackMultiCell(out[0..written]);
    try std.testing.expectEqual(@as(u32, 3), result.continuation_count);

    // Check cell indices are 1, 2, 3
    try std.testing.expectEqual(@as(u16, 1), result.continuations[0].header.cell_index);
    try std.testing.expectEqual(@as(u16, 2), result.continuations[1].header.cell_index);
    try std.testing.expectEqual(@as(u16, 3), result.continuations[2].header.cell_index);

    // Check total_cells is 3 for all
    try std.testing.expectEqual(@as(u16, 3), result.continuations[0].header.total_cells);
    try std.testing.expectEqual(@as(u16, 3), result.continuations[1].header.total_cells);
    try std.testing.expectEqual(@as(u16, 3), result.continuations[2].header.total_cells);
}

test "total_cells field matches actual continuation count" {
    var header = cell.defaultHeader();
    header.linearity = constants.LINEARITY_LINEAR;
    header.total_size = 0;

    var d1: [50]u8 = undefined;
    @memset(&d1, 0x11);
    var d2: [50]u8 = undefined;
    @memset(&d2, 0x22);

    const continuations = [_]multicell.ContinuationInput{
        .{ .cell_type = constants.CELL_TYPE_BUMP, .data = &d1 },
        .{ .cell_type = constants.CELL_TYPE_DATA, .data = &d2 },
    };

    var out: [3 * constants.CELL_SIZE]u8 = undefined;
    const written = try multicell.packMultiCell(&header, &.{}, &continuations, &out);
    const result = try multicell.unpackMultiCell(out[0..written]);

    // Cell 0 header.cell_count should be 3 (1 header + 2 continuations)
    try std.testing.expectEqual(@as(u32, 3), result.cell0_header.cell_count);

    // Each continuation's total_cells should be 2
    try std.testing.expectEqual(@as(u16, 2), result.continuations[0].header.total_cells);
    try std.testing.expectEqual(@as(u16, 2), result.continuations[1].header.total_cells);
}

test "unpack(pack(input)) == input for multi-cell objects" {
    var header = cell.defaultHeader();
    header.linearity = constants.LINEARITY_AFFINE;
    header.total_size = 128;

    var payload: [128]u8 = undefined;
    for (&payload, 0..) |*b, i| b.* = @intCast(i & 0xFF);

    var bump_data: [500]u8 = undefined;
    for (&bump_data, 0..) |*b, i| b.* = @intCast((i + 0x42) & 0xFF);

    var data_payload: [800]u8 = undefined;
    for (&data_payload, 0..) |*b, i| b.* = @intCast((i + 0xAA) & 0xFF);

    const continuations = [_]multicell.ContinuationInput{
        .{ .cell_type = constants.CELL_TYPE_BUMP, .data = &bump_data },
        .{ .cell_type = constants.CELL_TYPE_DATA, .data = &data_payload },
    };

    var out: [3 * constants.CELL_SIZE]u8 = undefined;
    const written = try multicell.packMultiCell(&header, &payload, &continuations, &out);

    const result = try multicell.unpackMultiCell(out[0..written]);

    // Verify Cell 0
    try std.testing.expectEqual(@as(u32, 128), result.cell0_payload_len);
    try std.testing.expectEqualSlices(u8, &payload, result.cell0_payload[0..128]);

    // Verify continuations
    try std.testing.expectEqual(@as(u32, 2), result.continuation_count);

    try std.testing.expectEqual(constants.CELL_TYPE_BUMP, result.continuations[0].header.cell_type);
    try std.testing.expectEqual(@as(u16, 500), result.continuations[0].data_len);
    try std.testing.expectEqualSlices(u8, &bump_data, result.continuations[0].data[0..500]);

    try std.testing.expectEqual(constants.CELL_TYPE_DATA, result.continuations[1].header.cell_type);
    try std.testing.expectEqual(@as(u16, 800), result.continuations[1].data_len);
    try std.testing.expectEqualSlices(u8, &data_payload, result.continuations[1].data[0..800]);
}

test "unpack rejects buffer that is not a multiple of 1024" {
    var buf: [1025]u8 = undefined;
    @memset(&buf, 0);
    @memcpy(buf[0..16], &cell.MAGIC_BYTES);

    const result = multicell.unpackMultiCell(&buf);
    try std.testing.expectError(error.invalid_buffer_size, result);
}

test "unpack rejects buffer smaller than 1024" {
    var buf: [512]u8 = undefined;
    @memset(&buf, 0);

    const result = multicell.unpackMultiCell(&buf);
    try std.testing.expectError(error.buffer_too_small, result);
}

test "continuation header byte layout matches cellPacker.ts" {
    // Verify the exact byte positions of continuation header fields
    var header = cell.defaultHeader();
    header.linearity = constants.LINEARITY_LINEAR;
    header.total_size = 0;

    var data: [100]u8 = undefined;
    @memset(&data, 0x42);

    const continuations = [_]multicell.ContinuationInput{
        .{ .cell_type = constants.CELL_TYPE_ENVELOPE, .data = &data },
    };

    var out: [2 * constants.CELL_SIZE]u8 = undefined;
    _ = try multicell.packMultiCell(&header, &.{}, &continuations, &out);

    // Cell 1 starts at offset 1024
    const c1 = out[1024..];

    // Byte 0: cellType
    try std.testing.expectEqual(constants.CELL_TYPE_ENVELOPE, c1[0]);

    // Bytes 1-2: cellIndex (u16 LE) = 1
    try std.testing.expectEqual(@as(u16, 1), std.mem.readInt(u16, c1[1..3], .little));

    // Bytes 3-4: totalCells (u16 LE) = 1
    try std.testing.expectEqual(@as(u16, 1), std.mem.readInt(u16, c1[3..5], .little));

    // Bytes 5-6: payloadSize (u16 LE) = 100
    try std.testing.expectEqual(@as(u16, 100), std.mem.readInt(u16, c1[5..7], .little));

    // Byte 7: reserved = 0
    try std.testing.expectEqual(@as(u8, 0), c1[7]);
}

```
