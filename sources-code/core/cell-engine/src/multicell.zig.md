---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/src/multicell.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.978109+00:00
---

# core/cell-engine/src/multicell.zig

```zig
// Multi-cell packing — Phase 1 + D-OCT-data-octave-bump (octave-0/1 escalation).
// Produces byte-identical output to multicell-assembler.ts packMultiCell/unpackMultiCell
// for all rung-0 (inline/small-multicell) objects.
//
// ── Escalation (rung-1, octave-1) ────────────────────────────────────────────────
//
// When a payload exceeds the octave-0 flat capacity (768 bytes Cell 0 + up to 64
// continuation cells of 1016 bytes each = ~65 KB ceiling) this module escalates to
// octave-1 RATHER than returning `too_many_continuations`.
//
// Escalation detection signal:
//   Cell 0 header `cell_count` field (offset 86, u32 LE) is set to the sentinel
//   value ESCALATION_CELL_COUNT_SENTINEL (0xFFFF_FFFF) for escalated objects.
//   This is otherwise invalid in normal multicell format (cell_count is always ≥ 1).
//
// Wire format for an escalated (rung-1) object:
//
//   [Cell 0: 256-byte header, total_size=ESCALATION_DESCRIPTOR_SIZE, cell_count=sentinel]
//     payload bytes 0..15  : 16-byte escalation descriptor (rung=1, octave_level=1,
//                             child_count=1, total_bytes=len, reserved=0)
//     payload bytes 16..767: zero-padded
//   [bytes 1024..(1024+data.len): raw child data, NOT padded]
//
// The descriptor lives at cell byte 256 (= PAYLOAD_OFFSET), which is
// escalation_descriptor.zig::descriptorOffsetUnrouted() = 256.
//
// O-1 header total_size reinterpretation:
//   For escalated objects, total_size u32 = bytes in Cell 0's own "content" =
//   ESCALATION_DESCRIPTOR_SIZE (16).  The descriptor's total_bytes (u64) is the
//   source of truth for the full logical payload size.
//
// Octave-2+ is NOT implemented here (step 5, gated on O-1 decision).  If a payload
// would require octave-2+, we return error.too_many_continuations to preserve the
// existing error contract until that step ships.
//
// Backward-compatibility guarantee:
//   All rung-0 objects (≤ 768-byte inline payload + ≤ 64 continuations) are
//   packed/unpacked byte-for-byte as before.  The escalation path is ADDITIVE and
//   is only activated on overflow.
//
// Design doc: docs/design/OCTAVE-ESCALATION-UNIFICATION.md §2/§5/§7/§8.
// Mirror: core/cell-ops/src/packer/multicell-assembler.ts (keep byte-identical).

const std = @import("std");
const constants = @import("constants");
const cell_mod = @import("cell");
const octave_mod = @import("octave");
const escalation_descriptor = @import("escalation_descriptor");

pub const PackError = error{
    payload_too_large,
    buffer_too_small,
    too_many_continuations,
};

pub const UnpackError = error{
    invalid_magic,
    buffer_too_small,
    invalid_buffer_size,
    invalid_continuation_header,
};

/// Continuation cell header — 8 bytes at the start of each Cell 1+.
/// Matches cellPacker.ts buildContinuationHeader exactly.
pub const ContinuationHeader = struct {
    cell_type: u8, // byte 0: BUMP=1, ATOMIC_BEEF=2, ENVELOPE=3, DATA=4, STATE=5
    cell_index: u16, // bytes 1-2: 1-based position (LE)
    total_cells: u16, // bytes 3-4: count of continuation cells, excludes Cell 0 (LE)
    payload_size: u16, // bytes 5-6: actual data bytes in this cell (LE)
    reserved: u8, // byte 7: always 0
};

/// Input for a continuation cell to be packed.
pub const ContinuationInput = struct {
    cell_type: u8,
    data: []const u8, // up to 1016 bytes
};

/// Result of unpacking a single continuation cell.
pub const ContinuationResult = struct {
    header: ContinuationHeader,
    data: [constants.CONTINUATION_PAYLOAD_SIZE]u8,
    data_len: u16,
};

/// Maximum continuation cells we support (bounded by stack allocation).
pub const MAX_CONTINUATIONS = 64;

/// Flat octave-0 capacity: Cell 0 payload (768 B) + 64 continuation cells × 1016 B.
pub const OCTAVE0_FLAT_CAPACITY: usize =
    constants.PAYLOAD_SIZE + MAX_CONTINUATIONS * constants.CONTINUATION_PAYLOAD_SIZE;

/// Cell 0 `cell_count` sentinel for escalated (rung ≥ 1) objects.
/// This value is otherwise invalid (normal multicell always has cell_count ≥ 1).
pub const ESCALATION_CELL_COUNT_SENTINEL: u32 = 0xFFFFFFFF;

/// Octave-1 cell size in bytes (1 MiB).
pub const OCTAVE1_CELL_SIZE: u64 = octave_mod.cellSizeForOctave(.kilo);

/// Octave-2 cell size in bytes (1 GiB) — D-OCT-octave-2-plus (step 5/5).
pub const OCTAVE2_CELL_SIZE: u64 = octave_mod.cellSizeForOctave(.mega);

/// Octave-3 cell size in bytes (1 TiB) — D-OCT-octave-2-plus (step 5/5).
pub const OCTAVE3_CELL_SIZE: u64 = octave_mod.cellSizeForOctave(.giga);

/// Result of unpacking a multi-cell buffer.
pub const MultiCellResult = struct {
    cell0_header: cell_mod.CellHeader,
    cell0_payload: [constants.PAYLOAD_SIZE]u8,
    cell0_payload_len: u32,
    continuations: [MAX_CONTINUATIONS]ContinuationResult,
    continuation_count: u32,
};

/// Result of unpacking an escalated (rung-1) buffer.
/// The child_data slice points into the input buffer (no copy).
pub const EscalatedResult = struct {
    cell0_header: cell_mod.CellHeader,
    descriptor: escalation_descriptor.EscalationDescriptor,
    /// Pointer into the caller's buffer at offset CELL_SIZE, length = descriptor.total_bytes.
    child_data_ptr: [*]const u8,
    child_data_len: u64,
};

/// Write a continuation header (8 bytes) into a buffer.
pub fn writeContinuationHeader(out: []u8, h: ContinuationHeader) void {
    out[0] = h.cell_type;
    std.mem.writeInt(u16, out[1..][0..2], h.cell_index, .little);
    std.mem.writeInt(u16, out[3..][0..2], h.total_cells, .little);
    std.mem.writeInt(u16, out[5..][0..2], h.payload_size, .little);
    out[7] = h.reserved;
}

/// Read a continuation header (8 bytes) from a buffer.
fn readContinuationHeader(buf: []const u8) ContinuationHeader {
    return .{
        .cell_type = buf[0],
        .cell_index = std.mem.readInt(u16, buf[1..][0..2], .little),
        .total_cells = std.mem.readInt(u16, buf[3..][0..2], .little),
        .payload_size = std.mem.readInt(u16, buf[5..][0..2], .little),
        .reserved = buf[7],
    };
}

/// Pack a multi-cell semantic object into a contiguous buffer.
///
/// Layout for rung-0 (≤ OCTAVE0_FLAT_CAPACITY bytes of continuations):
///   Cell 0: 256-byte header + 768-byte payload (zero-padded)
///   Cell 1..N: 8-byte continuation header + 1016-byte data (zero-padded)
///
/// Layout for rung-1 (escalated to octave-1, triggered on too_many_continuations):
///   ONLY valid when `payload` is ≤ PAYLOAD_SIZE and `continuations` is empty —
///   the escalation path is for a large opaque byte blob passed as a single
///   payload-like object via packEscalated (see below).
///
/// For the main multi-cell path this function retains the rung-0 behavior.
/// See packEscalated for packing a large blob that requires octave-1.
///
/// The Cell 0 header's cellCount field is patched to total cell count.
/// Returns the number of bytes written (always a multiple of 1024).
pub fn packMultiCell(
    header: *const cell_mod.CellHeader,
    payload: []const u8,
    continuations: []const ContinuationInput,
    out: []u8,
) PackError!usize {
    if (payload.len > constants.PAYLOAD_SIZE) return error.payload_too_large;
    if (continuations.len > MAX_CONTINUATIONS) return error.too_many_continuations;

    const total_cells: u32 = @intCast(1 + continuations.len);
    const total_bytes: usize = total_cells * constants.CELL_SIZE;

    if (out.len < total_bytes) return error.buffer_too_small;

    // Validate continuation data sizes
    for (continuations) |cont| {
        if (cont.data.len > constants.CONTINUATION_PAYLOAD_SIZE) return error.payload_too_large;
    }

    // Zero the entire output region
    @memset(out[0..total_bytes], 0);

    // ── Cell 0: header + payload ──
    // Clone header and patch cellCount
    var patched_header = header.*;
    patched_header.cell_count = total_cells;

    cell_mod.packCell(&patched_header, payload, @ptrCast(out[0..constants.CELL_SIZE])) catch |e| {
        return switch (e) {
            error.payload_too_large => error.payload_too_large,
        };
    };

    // ── Cells 1..N: continuation cells ──
    const cont_count: u16 = @intCast(continuations.len);

    for (continuations, 0..) |cont, i| {
        const cell_offset = (i + 1) * constants.CELL_SIZE;
        const cont_header = ContinuationHeader{
            .cell_type = cont.cell_type,
            .cell_index = @intCast(i + 1), // 1-based
            .total_cells = cont_count,
            .payload_size = @intCast(cont.data.len),
            .reserved = 0,
        };

        writeContinuationHeader(out[cell_offset..][0..constants.CONTINUATION_HEADER_SIZE], cont_header);
        @memcpy(out[cell_offset + constants.CONTINUATION_HEADER_SIZE ..][0..cont.data.len], cont.data);
    }

    return total_bytes;
}

/// Pack a large blob into an escalated (rung-1) multicell form.
///
/// This is the escalation path triggered when a payload exceeds the octave-0
/// flat capacity.  For payloads ≤ OCTAVE0_FLAT_CAPACITY, use packMultiCell.
///
/// D-OCT-octave-2-plus (step 5/5):  the octave level is selected automatically
/// via minimumOctaveForSize and written into the escalation descriptor:
///   payload ≤ 1 MiB → octave_level = 1 (kilo)
///   payload ≤ 1 GiB → octave_level = 2 (mega)
///   payload ≤ 1 TiB → octave_level = 3 (giga)
///   payload > 1 TiB → error.too_many_continuations (beyond MAX_OCTAVE=3)
///
/// CAUTION: do NOT pass a multi-GiB/TiB slice to this function in production —
/// the caller is responsible for not allocating giant buffers.  At octave-2/3
/// the canonical production form is packMerkleHierarchy (rung-2, no giant alloc).
/// This function only sets the descriptor's octave_level field; it does NOT
/// enforce an allocation cap beyond the output buffer check.
///
/// Wire format:
///   [0..1023]         Cell 0: header (escalation sentinel, total_size=16) + descriptor
///   [1024..(1024+N)]  raw child data (exactly N = payload.len bytes, NOT padded)
///
/// The output buffer must be ≥ CELL_SIZE + payload.len bytes.
///
/// O-1 header semantics (uniform for ALL rung≥1):
///   total_size (u32 at offset 90) = ESCALATION_DESCRIPTOR_SIZE (16) — bytes in
///   THIS cell's content.  The descriptor's total_bytes (u64) is the authoritative
///   logical blob size.
///
/// Escalation detection by consumer: Cell 0 `cell_count` == ESCALATION_CELL_COUNT_SENTINEL.
pub fn packEscalated(
    header: *const cell_mod.CellHeader,
    payload: []const u8,
    out: []u8,
) PackError!usize {
    // Select octave level via minimumOctaveForSize (D-OCT-octave-2-plus, step 5/5).
    const oct = octave_mod.minimumOctaveForSize(@intCast(payload.len)) orelse {
        // payload > 1 TiB (beyond giga, MAX_OCTAVE=3) — cannot represent.
        return error.too_many_continuations;
    };

    // Map octave enum to the u8 octave_level value for the descriptor.
    const oct_level: escalation_descriptor.OctaveLevel = switch (oct) {
        .base => .base,
        .kilo => .kilo,
        .mega => .mega,
        .giga => .giga,
    };

    const total_output: usize = constants.CELL_SIZE + payload.len;
    if (out.len < total_output) return error.buffer_too_small;

    // Zero the entire output region
    @memset(out[0..total_output], 0);

    // ── Cell 0: write escalation descriptor into payload region ──
    // Patch header: cell_count = sentinel, total_size = descriptor size (O-1).
    // O-1 rule is UNIFORM for ALL rung≥1: total_size = "bytes in THIS cell" = 16.
    var patched_header = header.*;
    patched_header.cell_count = ESCALATION_CELL_COUNT_SENTINEL;
    patched_header.total_size = escalation_descriptor.ESCALATION_DESCRIPTOR_SIZE;

    // Build a descriptor-only payload (16 bytes, rest zero).
    var desc_payload: [constants.PAYLOAD_SIZE]u8 = [_]u8{0} ** constants.PAYLOAD_SIZE;
    escalation_descriptor.writeDescriptor(&desc_payload, 0, .{
        .rung = .octave_escalated,
        .octave_level = oct_level,
        .child_count = 1,
        .total_bytes = @intCast(payload.len),
        .reserved = 0,
    });

    cell_mod.packCell(&patched_header, &desc_payload, @ptrCast(out[0..constants.CELL_SIZE])) catch |e| {
        return switch (e) {
            error.payload_too_large => error.payload_too_large,
        };
    };

    // ── Child data: raw bytes immediately after Cell 0 ──
    @memcpy(out[constants.CELL_SIZE..][0..payload.len], payload);

    return total_output;
}

/// Unpack a multi-cell buffer into structured form.
///
/// Cell count is derived from buffer length, not from the header's cellCount field.
/// This is strictly more robust for adversarial inputs (matching TS behavior).
///
/// NOTE: this function handles rung-0 (normal multicell) only.
/// For escalated objects (rung-1), use unpackEscalated.
/// Use isEscalated() to check which path to take.
pub fn unpackMultiCell(buffer: []const u8) UnpackError!MultiCellResult {
    if (buffer.len < constants.CELL_SIZE) return error.buffer_too_small;
    if (buffer.len % constants.CELL_SIZE != 0) return error.invalid_buffer_size;

    const total_cells = buffer.len / constants.CELL_SIZE;

    // ── Cell 0 ──
    const cell0_result = cell_mod.unpackCell(@ptrCast(buffer[0..constants.CELL_SIZE])) catch |e| {
        return switch (e) {
            error.invalid_magic => error.invalid_magic,
            error.buffer_too_small => error.buffer_too_small,
        };
    };

    var result: MultiCellResult = undefined;
    result.cell0_header = cell0_result.header;
    result.cell0_payload = cell0_result.payload;
    result.cell0_payload_len = cell0_result.payload_len;
    result.continuation_count = @intCast(total_cells - 1);

    // ── Cells 1..N ──
    var i: usize = 1;
    while (i < total_cells) : (i += 1) {
        const cell_offset = i * constants.CELL_SIZE;
        const cont_header = readContinuationHeader(buffer[cell_offset..][0..constants.CONTINUATION_HEADER_SIZE]);

        const idx = i - 1;
        result.continuations[idx].header = cont_header;

        const data_len = @min(cont_header.payload_size, constants.CONTINUATION_PAYLOAD_SIZE);
        @memset(&result.continuations[idx].data, 0);
        @memcpy(
            result.continuations[idx].data[0..data_len],
            buffer[cell_offset + constants.CONTINUATION_HEADER_SIZE ..][0..data_len],
        );
        result.continuations[idx].data_len = @intCast(data_len);
    }

    return result;
}

/// Check whether a packed buffer is an escalated (rung-1) object.
/// Reads the cell_count field from Cell 0 (offset 86, u32 LE).
/// Returns true if == ESCALATION_CELL_COUNT_SENTINEL.
///
/// Call this BEFORE choosing unpackMultiCell vs unpackEscalated.
pub fn isEscalated(buffer: []const u8) bool {
    if (buffer.len < constants.CELL_SIZE) return false;
    // cell_count is at HEADER_OFFSET_CELL_COUNT = 86, u32 LE
    const cell_count = std.mem.readInt(u32, buffer[86..][0..4], .little);
    return cell_count == ESCALATION_CELL_COUNT_SENTINEL;
}

/// Unpack an escalated (rung-1) buffer.
///
/// The returned EscalatedResult contains the descriptor (with total_bytes) and a
/// pointer into the caller's buffer pointing to the child data.
///
/// The caller should check isEscalated() before calling this.
pub fn unpackEscalated(buffer: []const u8) UnpackError!EscalatedResult {
    if (buffer.len < constants.CELL_SIZE) return error.buffer_too_small;

    // ── Cell 0 ──
    const cell0_result = cell_mod.unpackCell(@ptrCast(buffer[0..constants.CELL_SIZE])) catch |e| {
        return switch (e) {
            error.invalid_magic => error.invalid_magic,
            error.buffer_too_small => error.buffer_too_small,
        };
    };

    // Read the descriptor from Cell 0 payload at offset 0 (= cell byte 256).
    // The cell0_result.payload is a copy; read it at offset 0.
    const desc_offset: usize = 0; // relative to payload start
    const desc = escalation_descriptor.readDescriptor(&cell0_result.payload, desc_offset);

    const child_len: u64 = desc.total_bytes;

    // Validate that the buffer is large enough to hold the child data.
    if (buffer.len < constants.CELL_SIZE + child_len) return error.buffer_too_small;

    return .{
        .cell0_header = cell0_result.header,
        .descriptor = desc,
        .child_data_ptr = @ptrCast(buffer[constants.CELL_SIZE..].ptr),
        .child_data_len = child_len,
    };
}

```
