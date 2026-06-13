---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/escalation.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.217920+00:00
---

# runtime/semantos-brain/src/escalation.zig

```zig
// M4.5 — storeWithEscalation: octave routing based on payload size.
//
// Routes raw bytes to the correct octave tier:
//   ≤ OCTAVE0_MAX (768):    octave 0 — pack inline into a 1024-byte cell
//   ≤ OCTAVE1_MAX (2 MB):   octave 1 — writeSlot + return pointer cell
//   > OCTAVE1_MAX:          error.Octave2NotImplemented (stub for M4.2)
//
// No heap allocation in the fast path. SHA-256 via std.crypto.hash.sha2.Sha256.

const std = @import("std");
const content_store = @import("content_store_local_fs");

pub const OCTAVE0_MAX: usize = 768; // fits in cell payload
pub const OCTAVE1_MAX: usize = 2 * 1024 * 1024; // 2 MB

pub const EscalationResult = union(enum) {
    /// Octave 0: the full 1024-byte cell bytes (data packed inline).
    cell: [1024]u8,
    /// Octave 1+: pointer cell bytes + where the content was stored.
    pointer_cell: struct {
        cell_bytes: [1024]u8,
        octave: u8,
        slot: u32,
    },
};

/// Pack `data` into the payload area of a 1024-byte cell (octave 0).
/// Bytes [0..7]: zeroed (no continuation header for octave-0 inline cells).
/// Bytes [8..(8+data.len)]: data verbatim.
/// Remaining bytes: zeroed.
fn packInlineCell(data: []const u8) [1024]u8 {
    var cell: [1024]u8 = [_]u8{0} ** 1024;
    @memcpy(cell[8 .. 8 + data.len], data);
    return cell;
}

/// Pack a pointer cell for octave 1.
///
/// Wire layout (1024 bytes):
///   [0..7]   8-byte continuation header:
///              byte 0: cell_type = 0x06
///              bytes 1..2: cell_index = 0 (u16 LE)
///              bytes 3..4: total_cells = 1 (u16 LE)
///              bytes 5..6: payload_size = 90 (u16 LE)
///              byte 7: reserved = 0
///   [8]      octave (u8)
///   [9..10]  slot (u16 LE)
///   [11..14] offset (u32 LE, always 0 for full-slot pointer)
///   [15]     slot_pad (0x00)
///   [16..47] content_hash (SHA-256 of data, [32]u8)
///   [48..79] type_hash ([32]u8)
///   [80..87] total_size (u64 LE)
///   [88]     flags (u8)
///   [89..90] fragment_count (u16 LE, 1 for single-slot)
///   [91..97] reserved ([7]u8, zero)
///   [98..1023] padding (zero)
fn packPointerCell1(
    slot: u32,
    content_hash: *const [32]u8,
    type_hash: *const [32]u8,
    total_size: u64,
) [1024]u8 {
    var cell: [1024]u8 = [_]u8{0} ** 1024;

    // 8-byte continuation header
    cell[0] = 0x06; // POINTER_CELL_TYPE
    std.mem.writeInt(u16, cell[1..3], 0, .little); // cell_index = 0
    std.mem.writeInt(u16, cell[3..5], 1, .little); // total_cells = 1
    std.mem.writeInt(u16, cell[5..7], 90, .little); // payload_size = 90
    cell[7] = 0; // reserved

    // Payload at offset 8
    cell[8] = 1; // octave = 1
    std.mem.writeInt(u16, cell[9..11], @truncate(slot), .little); // slot
    std.mem.writeInt(u32, cell[11..15], 0, .little); // offset = 0
    cell[15] = 0; // slot_pad
    @memcpy(cell[16..48], content_hash); // content_hash
    @memcpy(cell[48..80], type_hash); // type_hash
    std.mem.writeInt(u64, cell[80..88], total_size, .little); // total_size
    cell[88] = 0; // flags
    std.mem.writeInt(u16, cell[89..91], 1, .little); // fragment_count = 1
    // cell[91..97] reserved — already zero
    // cell[98..1023] padding — already zero

    return cell;
}

pub fn storeWithEscalation(
    store: *content_store.ContentStoreLocalFs,
    slot: u32,
    data: []const u8,
    type_hash: *const [32]u8,
) !EscalationResult {
    if (data.len <= OCTAVE0_MAX) {
        // Octave 0: pack data inline into a 1024-byte cell.
        return .{ .cell = packInlineCell(data) };
    }

    if (data.len <= OCTAVE1_MAX) {
        // Octave 1: write to ContentStoreLocalFs, return pointer cell.
        try store.writeSlot(slot, data);

        // Compute SHA-256 of the full payload.
        var content_hash: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(data, &content_hash, .{});

        const cell_bytes = packPointerCell1(slot, &content_hash, type_hash, data.len);

        return .{ .pointer_cell = .{
            .cell_bytes = cell_bytes,
            .octave = 1,
            .slot = slot,
        } };
    }

    // Octave 2+: not implemented in M4.5.
    return error.Octave2NotImplemented;
}

```
