---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/src/pointer.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.978396+00:00
---

# core/cell-engine/src/pointer.zig

```zig
// Pointer cell packing — Phase 6
// A pointer cell is a 1024-byte continuation cell (type 0x06) whose payload
// contains an address in a higher octave. The 2-PDA dereferences it via
// OP_DEREF_POINTER (0xC8) which calls host_fetch_cell.
//
// Wire format (1024 bytes total):
//   [0..7]    8-byte continuation header (cellType=0x06)
//   [8..97]   90-byte PointerPayload
//   [98..1023] 926 zero bytes (padding)
//
// Pointer cells are always RELEVANT linearity — they can be copied and dropped
// freely. The referenced content keeps its own linearity from its header.
//
// Reference: PHASE-6-OCTAVE-MEMORY.md D6.1, D6.3

const std = @import("std");
const constants = @import("constants");
const multicell = @import("multicell");
const octave_mod = @import("octave");

/// Continuation type value for pointer cells.
pub const POINTER_CELL_TYPE: u8 = 0x06;

/// Size of the pointer payload in bytes.
pub const POINTER_PAYLOAD_SIZE: u16 = 90;

/// Pointer payload flags (bit field).
pub const PointerFlags = struct {
    pub const IMMUTABLE: u8 = 0x01; // bit 0
    pub const ENCRYPTED: u8 = 0x02; // bit 1
    pub const COMPRESSED: u8 = 0x04; // bit 2
};

/// Payload of a pointer cell — 90 bytes total.
///
/// Maps to the Forth COORD-STORE-2 pattern: two values (address + metadata)
/// stored in an object's data area.
///
/// Wire layout (90 bytes):
///   [0]      octave         u8     target octave level
///   [1..2]   slot           u16 LE slot within that octave (0-1023)
///   [3..6]   offset         u32 LE byte offset within the cell
///   [7]      _slot_pad      u8     padding to maintain 90-byte total
///   [8..39]  content_hash   [32]u8 SHA256 of referenced content
///   [40..71] type_hash      [32]u8 type hash for CAS lookup
///   [72..79] total_size     u64 LE actual byte size of referenced object
///   [80]     flags          u8     IMMUTABLE|ENCRYPTED|COMPRESSED
///   [81..82] fragment_count u16 LE sub-cells at target octave (0 = single)
///   [83..89] reserved       [7]u8  future use
pub const PointerPayload = struct {
    octave: u8, // target octave level (0-3) — 1 byte
    slot: u16, // slot within that octave (0-1023) — 2 bytes
    offset: u32, // byte offset within the cell — 4 bytes
    content_hash: [32]u8, // SHA256 hash of referenced content — 32 bytes
    type_hash: [32]u8, // type hash of referenced object (for CAS) — 32 bytes
    total_size: u64, // actual byte size of referenced object — 8 bytes
    flags: u8, // IMMUTABLE|ENCRYPTED|COMPRESSED — 1 byte
    fragment_count: u16, // sub-cells at target octave (0 = single) — 2 bytes
    reserved: [7]u8, // future use — 7 bytes
    // Total: 1 + 2 + 4 + 1(pad) + 32 + 32 + 8 + 1 + 2 + 7 = 90 bytes
};

pub const UnpackError = error{
    not_a_pointer_cell,
    buffer_too_small,
};

/// Pack a PointerPayload into a 1024-byte cell buffer.
///
/// Layout: 8-byte continuation header + 90-byte payload + 926 zero bytes.
pub fn packPointerCell(
    payload: *const PointerPayload,
    cell_index: u16,
    total_cells: u16,
    out: *[constants.CELL_SIZE]u8,
) void {
    // Zero the entire cell
    @memset(out, 0);

    // Write 8-byte continuation header (use multicell's pub fn)
    const header = multicell.ContinuationHeader{
        .cell_type = POINTER_CELL_TYPE,
        .cell_index = cell_index,
        .total_cells = total_cells,
        .payload_size = POINTER_PAYLOAD_SIZE,
        .reserved = 0,
    };
    multicell.writeContinuationHeader(out[0..constants.CONTINUATION_HEADER_SIZE], header);

    // Write 90-byte pointer payload starting at offset 8
    const p = constants.CONTINUATION_HEADER_SIZE;
    out[p] = payload.octave;
    std.mem.writeInt(u16, out[p + 1 ..][0..2], payload.slot, .little);
    std.mem.writeInt(u32, out[p + 3 ..][0..4], payload.offset, .little);
    out[p + 7] = 0; // slot_pad
    @memcpy(out[p + 8 ..][0..32], &payload.content_hash);
    @memcpy(out[p + 40 ..][0..32], &payload.type_hash);
    std.mem.writeInt(u64, out[p + 72 ..][0..8], payload.total_size, .little);
    out[p + 80] = payload.flags;
    std.mem.writeInt(u16, out[p + 81 ..][0..2], payload.fragment_count, .little);
    @memcpy(out[p + 83 ..][0..7], &payload.reserved);
    // Remaining bytes (offset 98..1023) are already zero
}

/// Unpack a PointerPayload from a 1024-byte cell buffer.
/// Returns error if the cell is not a pointer cell (type != 0x06).
pub fn unpackPointerCell(cell: *const [constants.CELL_SIZE]u8) UnpackError!PointerPayload {
    // Verify continuation type
    if (cell[0] != POINTER_CELL_TYPE) return error.not_a_pointer_cell;

    const p = constants.CONTINUATION_HEADER_SIZE;
    var payload: PointerPayload = undefined;
    payload.octave = cell[p];
    payload.slot = std.mem.readInt(u16, cell[p + 1 ..][0..2], .little);
    payload.offset = std.mem.readInt(u32, cell[p + 3 ..][0..4], .little);
    // skip pad byte at p+7
    @memcpy(&payload.content_hash, cell[p + 8 ..][0..32]);
    @memcpy(&payload.type_hash, cell[p + 40 ..][0..32]);
    payload.total_size = std.mem.readInt(u64, cell[p + 72 ..][0..8], .little);
    payload.flags = cell[p + 80];
    payload.fragment_count = std.mem.readInt(u16, cell[p + 81 ..][0..2], .little);
    @memcpy(&payload.reserved, cell[p + 83 ..][0..7]);

    return payload;
}

/// Check if a 1024-byte cell is a pointer cell (continuation type 0x06).
pub fn isPointerCell(cell: *const [constants.CELL_SIZE]u8) bool {
    return cell[0] == POINTER_CELL_TYPE;
}

/// Extract the OctaveAddress from a pointer cell's payload.
/// Convenience wrapper for OP_DEREF_POINTER.
pub fn getOctaveAddress(cell: *const [constants.CELL_SIZE]u8) UnpackError!octave_mod.OctaveAddress {
    const payload = try unpackPointerCell(cell);
    return .{
        .octave = @enumFromInt(payload.octave),
        .slot = payload.slot,
        .offset = payload.offset,
    };
}

// ── Tests ──

test "T6.07 Pointer cell pack → unpack round-trip (bit-identical)" {
    var content_hash: [32]u8 = undefined;
    @memset(&content_hash, 0xAA);
    var type_hash: [32]u8 = undefined;
    @memset(&type_hash, 0xBB);

    const payload = PointerPayload{
        .octave = 1,
        .slot = 42,
        .offset = 1024,
        .content_hash = content_hash,
        .type_hash = type_hash,
        .total_size = 2_000_000,
        .flags = PointerFlags.IMMUTABLE,
        .fragment_count = 2,
        .reserved = [_]u8{0} ** 7,
    };

    var cell: [constants.CELL_SIZE]u8 = undefined;
    packPointerCell(&payload, 1, 1, &cell);

    const unpacked = try unpackPointerCell(&cell);
    try std.testing.expectEqual(@as(u8, 1), unpacked.octave);
    try std.testing.expectEqual(@as(u16, 42), unpacked.slot);
    try std.testing.expectEqual(@as(u32, 1024), unpacked.offset);
    try std.testing.expect(std.mem.eql(u8, &content_hash, &unpacked.content_hash));
    try std.testing.expect(std.mem.eql(u8, &type_hash, &unpacked.type_hash));
    try std.testing.expectEqual(@as(u64, 2_000_000), unpacked.total_size);
    try std.testing.expectEqual(PointerFlags.IMMUTABLE, unpacked.flags);
    try std.testing.expectEqual(@as(u16, 2), unpacked.fragment_count);
}

test "T6.08 isPointerCell correctly identifies CONTINUATION_TYPE 0x06" {
    // Build a pointer cell
    var cell: [constants.CELL_SIZE]u8 = [_]u8{0} ** constants.CELL_SIZE;
    cell[0] = POINTER_CELL_TYPE;
    try std.testing.expect(isPointerCell(&cell));

    // A non-pointer cell (DATA = 0x04)
    var data_cell: [constants.CELL_SIZE]u8 = [_]u8{0} ** constants.CELL_SIZE;
    data_cell[0] = 0x04;
    try std.testing.expect(!isPointerCell(&data_cell));

    // A zero cell
    var zero_cell: [constants.CELL_SIZE]u8 = [_]u8{0} ** constants.CELL_SIZE;
    try std.testing.expect(!isPointerCell(&zero_cell));
}

test "Pointer cell is exactly 1024 bytes with correct padding" {
    const payload = PointerPayload{
        .octave = 2,
        .slot = 999,
        .offset = 0,
        .content_hash = [_]u8{0xFF} ** 32,
        .type_hash = [_]u8{0xEE} ** 32,
        .total_size = 1_073_741_824,
        .flags = PointerFlags.ENCRYPTED | PointerFlags.COMPRESSED,
        .fragment_count = 0,
        .reserved = [_]u8{0} ** 7,
    };

    var cell: [constants.CELL_SIZE]u8 = undefined;
    packPointerCell(&payload, 1, 1, &cell);

    // Verify total size
    try std.testing.expectEqual(@as(usize, 1024), cell.len);

    // Verify continuation header type
    try std.testing.expectEqual(POINTER_CELL_TYPE, cell[0]);

    // Verify payload_size in continuation header (bytes 5-6 LE)
    const payload_size = std.mem.readInt(u16, cell[5..7], .little);
    try std.testing.expectEqual(POINTER_PAYLOAD_SIZE, payload_size);

    // Verify padding is zero (bytes 98..1023)
    for (cell[98..]) |byte| {
        try std.testing.expectEqual(@as(u8, 0), byte);
    }
}

test "getOctaveAddress extracts slot and offset correctly" {
    const payload = PointerPayload{
        .octave = 1,
        .slot = 512,
        .offset = 2048,
        .content_hash = [_]u8{0} ** 32,
        .type_hash = [_]u8{0} ** 32,
        .total_size = 0,
        .flags = 0,
        .fragment_count = 0,
        .reserved = [_]u8{0} ** 7,
    };

    var cell: [constants.CELL_SIZE]u8 = undefined;
    packPointerCell(&payload, 1, 1, &cell);

    const addr = try getOctaveAddress(&cell);
    try std.testing.expectEqual(octave_mod.Octave.kilo, addr.octave);
    try std.testing.expectEqual(@as(u16, 512), addr.slot);
    try std.testing.expectEqual(@as(u32, 2048), addr.offset);
}

```
