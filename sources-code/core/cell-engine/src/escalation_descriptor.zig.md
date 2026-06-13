---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/src/escalation_descriptor.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.976086+00:00
---

# core/cell-engine/src/escalation_descriptor.zig

```zig
// escalation_descriptor.zig — unified 16-byte payload-side escalation descriptor.
//
// Faithful mirror of the TypeScript reference oracle:
//   core/protocol-types/src/escalation-descriptor.ts  (offsets, accessors, tests)
//
// Same pattern as routing.zig ↔ its TS mirror: the TS implementation is the
// source of truth for the wire layout + semantics; this is the on-device
// implementation. Deliberately self-contained (std only, defines its own
// offsets like routing.zig does) so `zig test src/escalation_descriptor.zig`
// runs standalone.
//
// Design doc: docs/design/OCTAVE-ESCALATION-UNIFICATION.md §5, §7.
// This is Step 1 (D-OCT-escalation-descriptor) of a 5-step decomposition.
// NO behaviour change — wire shape, accessors, and tests only.
//
// ---
//
// Wire layout (little-endian, 16 bytes):
//
//   off  size  field          meaning
//    0   1     rung           u8:  0=inline, 1=octave-escalated, 2=merkle-rooted-hierarchy
//    1   1     octave_level   u8:  0..3 (base 1KiB / kilo 1MiB / mega 1GiB / giga 1TiB); 0 when rung=0
//    2   2     child_count    u16 LE: number of child cells (meaningful when rung >= 1)
//    4   8     total_bytes    u64 LE: logical blob size — THE payload-side source of truth
//   12   4     reserved       u32 LE: 0 — alignment + future flags
//
// Total = 16 bytes.
//
// ---
//
// Resolved design decisions (O-1 .. O-4 from the design doc)
//
// O-1 (total_bytes / header total_size): total_bytes (u64) in this descriptor
// is the source of truth for the whole escalated object's logical size.
// The header's total_size (u32, offset 90) is reinterpreted as "bytes in THIS
// cell" for escalated objects. THIS FILE does NOT change header semantics —
// that is D-OCT-data-octave-bump (step 2). For octave-0/1 blobs (<= 1 GiB)
// the u32 header field is sufficient; the u64 matters for octave 2+.
//
// O-2 (descriptor offset): For an unrouted data cell the descriptor sits at
// payload offset 0 (absolute cell offset 256). For a routed cell it sits
// immediately AFTER the typed-segments [u16 N || u16 payloadStartsAt] header
// (absolute cell offset 256 + 4 = 260). Use the helpers
// descriptorOffsetUnrouted() and descriptorOffsetRouted().
//
// O-3 (merkle leaf size): A merkle LEAF is a full 1024-byte child cell (not
// the 768 payload bytes). Documented here for the future D-OCT-merkle-hierarchy
// step — no merkle code in this file.
//
// O-4 (fragment-correlation key): The routing header's flow_label (offset 176,
// u64 LE) is the fragment-correlation key for reassembly — even when
// routing_mode == unrouted (it is zero by default in that case and the producer
// sets it when emitting an escalated blob). There is NO duplicate 8-byte key
// field inside this descriptor; flow_label at offset 176 is the single
// canonical key.
//
// ---
//
// Octave sizes (×1024 binary — NOT ×1000):
// The ×1000 factor in octave.zig::costSatsPerCell is a pricing knob and is
// independent of byte math. Cell sizes are strict binary shifts:
//   octave 0 = 1024 B   (base)
//   octave 1 = 1 MiB    (kilo)
//   octave 2 = 1 GiB    (mega)
//   octave 3 = 1 TiB    (giga)
// These match octave.zig::cellSizeForOctave / minimumOctaveForSize.
//
// ---
//
// Oracle <-> mirror contract:
// The TypeScript oracle is at core/protocol-types/src/escalation-descriptor.ts.
// Both sides MUST agree on the CANONICAL_VECTOR defined below.

const std = @import("std");

// ── Descriptor size ────────────────────────────────────────────────────────────
pub const ESCALATION_DESCRIPTOR_SIZE: usize = 16;

// ── Field offsets within the 16-byte descriptor ────────────────────────────────
// Offsets are relative to the START of the descriptor, not the start of the cell.
pub const OFF_RUNG: usize = 0; // u8
pub const OFF_OCTAVE_LEVEL: usize = 1; // u8
pub const OFF_CHILD_COUNT: usize = 2; // u16 LE
pub const OFF_TOTAL_BYTES: usize = 4; // u64 LE
pub const OFF_RESERVED: usize = 12; // u32 LE (must be zero)

// ── Cell layout constants (mirrors core/protocol-types/src/constants.ts) ────────
/// Byte offset at which the payload region begins within a 1024-byte cell.
pub const PAYLOAD_OFFSET: usize = 256;

/// Size of the typed-segments header [u16 N || u16 payloadStartsAt] (§13.2).
pub const TYPED_SEGMENTS_HEADER_SIZE: usize = 4;

// ── Rung enum ─────────────────────────────────────────────────────────────────
pub const Rung = enum(u8) {
    /// Blob fits entirely in the cell's own inline payload region.
    inline_data = 0,
    /// Blob overflows inline but fits in a single larger-octave child cell.
    octave_escalated = 1,
    /// Blob spans multiple cells; a merkle root is committed in the canonical slot.
    merkle_rooted_hierarchy = 2,
    /// Catch-all for unknown future rungs — do not write.
    _,
};

// ── Octave level enum ─────────────────────────────────────────────────────────
pub const OctaveLevel = enum(u8) {
    /// 1024 B cells (octave 0, base).
    base = 0,
    /// 1,048,576 B cells (octave 1, kilo).
    kilo = 1,
    /// 1,073,741,824 B cells (octave 2, mega).
    mega = 2,
    /// 1,099,511,627,776 B cells (octave 3, giga).
    giga = 3,
    /// Catch-all for unknown future octave levels.
    _,
};

// ── Descriptor struct ─────────────────────────────────────────────────────────
pub const EscalationDescriptor = struct {
    rung: Rung,
    octave_level: OctaveLevel,
    child_count: u16,
    total_bytes: u64,
    reserved: u32, // must be 0 on the wire
};

// ── Offset helpers ────────────────────────────────────────────────────────────

/// Absolute byte offset of the descriptor within a cell for an unrouted data
/// cell (O-2, option A). The descriptor occupies bytes [256, 272) of the cell.
pub inline fn descriptorOffsetUnrouted() usize {
    return PAYLOAD_OFFSET; // 256
}

/// Absolute byte offset of the descriptor within a cell for a routed cell
/// (O-2, option B). The descriptor sits immediately AFTER the typed-segments
/// [u16 N || u16 payloadStartsAt] header, so its absolute offset is
/// PAYLOAD_OFFSET + TYPED_SEGMENTS_HEADER_SIZE = 260.
///
/// Note: payloadStartsAt from the typed-segments header tells the consumer
/// where application payload begins — the descriptor occupies the 16 bytes
/// immediately after the 4-byte typed-segments header. The descriptor ends at
/// PAYLOAD_OFFSET + 4 + ESCALATION_DESCRIPTOR_SIZE = 276.
pub inline fn descriptorOffsetRouted() usize {
    return PAYLOAD_OFFSET + TYPED_SEGMENTS_HEADER_SIZE; // 260
}

// ── Little-endian helpers ─────────────────────────────────────────────────────
inline fn readU16(buf: []const u8, off: usize) u16 {
    return std.mem.readInt(u16, buf[off..][0..2], .little);
}
inline fn writeU16(buf: []u8, off: usize, v: u16) void {
    std.mem.writeInt(u16, buf[off..][0..2], v, .little);
}
inline fn readU32(buf: []const u8, off: usize) u32 {
    return std.mem.readInt(u32, buf[off..][0..4], .little);
}
inline fn writeU32(buf: []u8, off: usize, v: u32) void {
    std.mem.writeInt(u32, buf[off..][0..4], v, .little);
}
inline fn readU64(buf: []const u8, off: usize) u64 {
    return std.mem.readInt(u64, buf[off..][0..8], .little);
}
inline fn writeU64(buf: []u8, off: usize, v: u64) void {
    std.mem.writeInt(u64, buf[off..][0..8], v, .little);
}

// ── Individual field accessors ─────────────────────────────────────────────────
// `desc_start` is the absolute byte offset of the descriptor within `buf`
// (either descriptorOffsetUnrouted() or descriptorOffsetRouted()).

pub fn readRung(buf: []const u8, desc_start: usize) Rung {
    return @enumFromInt(buf[desc_start + OFF_RUNG]);
}
pub fn writeRung(buf: []u8, desc_start: usize, rung: Rung) void {
    buf[desc_start + OFF_RUNG] = @intFromEnum(rung);
}

pub fn readOctaveLevel(buf: []const u8, desc_start: usize) OctaveLevel {
    return @enumFromInt(buf[desc_start + OFF_OCTAVE_LEVEL]);
}
pub fn writeOctaveLevel(buf: []u8, desc_start: usize, level: OctaveLevel) void {
    buf[desc_start + OFF_OCTAVE_LEVEL] = @intFromEnum(level);
}

pub fn readChildCount(buf: []const u8, desc_start: usize) u16 {
    return readU16(buf, desc_start + OFF_CHILD_COUNT);
}
pub fn writeChildCount(buf: []u8, desc_start: usize, count: u16) void {
    writeU16(buf, desc_start + OFF_CHILD_COUNT, count);
}

pub fn readTotalBytes(buf: []const u8, desc_start: usize) u64 {
    return readU64(buf, desc_start + OFF_TOTAL_BYTES);
}
pub fn writeTotalBytes(buf: []u8, desc_start: usize, bytes: u64) void {
    writeU64(buf, desc_start + OFF_TOTAL_BYTES, bytes);
}

// ── Composite read/write ───────────────────────────────────────────────────────

/// Read the full escalation descriptor from `buf` starting at `desc_start`.
/// `buf` must have at least `desc_start + ESCALATION_DESCRIPTOR_SIZE` bytes.
pub fn readDescriptor(buf: []const u8, desc_start: usize) EscalationDescriptor {
    std.debug.assert(buf.len >= desc_start + ESCALATION_DESCRIPTOR_SIZE);
    return .{
        .rung = readRung(buf, desc_start),
        .octave_level = readOctaveLevel(buf, desc_start),
        .child_count = readChildCount(buf, desc_start),
        .total_bytes = readTotalBytes(buf, desc_start),
        .reserved = readU32(buf, desc_start + OFF_RESERVED),
    };
}

/// Write the full escalation descriptor into `buf` starting at `desc_start`.
/// `buf` must have at least `desc_start + ESCALATION_DESCRIPTOR_SIZE` bytes.
/// `reserved` is always written as 0.
pub fn writeDescriptor(buf: []u8, desc_start: usize, desc: EscalationDescriptor) void {
    std.debug.assert(buf.len >= desc_start + ESCALATION_DESCRIPTOR_SIZE);
    writeRung(buf, desc_start, desc.rung);
    writeOctaveLevel(buf, desc_start, desc.octave_level);
    writeChildCount(buf, desc_start, desc.child_count);
    writeTotalBytes(buf, desc_start, desc.total_bytes);
    writeU32(buf, desc_start + OFF_RESERVED, 0); // always zero
}

// ── Canonical byte vector (oracle <-> mirror contract) ─────────────────────────
//
// Hand-encoded canonical byte vector for cross-language conformance testing.
//
// Encodes the descriptor:
//   rung          = 1     (octave_escalated)
//   octave_level  = 2     (mega = 1 GiB cells)
//   child_count   = 7     (u16 LE -> 0x07 0x00)
//   total_bytes   = 0x0000_0ABC_DEF0_1234  (u64 LE)
//                 = decimal 46,614,352,962,612 bytes (~42 TiB, tests u64 range)
//   reserved      = 0     (u32 LE -> 0x00 0x00 0x00 0x00)
//
// Little-endian layout, 16 bytes:
//   off  byte   field
//    0   0x01   rung = 1
//    1   0x02   octave_level = 2
//    2   0x07   child_count low byte
//    3   0x00   child_count high byte
//    4   0x34   total_bytes byte 0  (LSB)
//    5   0x12   total_bytes byte 1
//    6   0xF0   total_bytes byte 2
//    7   0xDE   total_bytes byte 3
//    8   0xBC   total_bytes byte 4
//    9   0x0A   total_bytes byte 5
//   10   0x00   total_bytes byte 6
//   11   0x00   total_bytes byte 7  (MSB)
//   12   0x00   reserved byte 0
//   13   0x00   reserved byte 1
//   14   0x00   reserved byte 2
//   15   0x00   reserved byte 3
//
// The TypeScript oracle in escalation-descriptor.ts asserts the same vector
// byte-for-byte in its CANONICAL_DESCRIPTOR_BYTES constant.

pub const CANONICAL_VECTOR = [ESCALATION_DESCRIPTOR_SIZE]u8{
    0x01, // rung = 1 (octave_escalated)
    0x02, // octave_level = 2 (mega)
    0x07, 0x00, // child_count = 7 (u16 LE)
    0x34, 0x12, 0xF0, 0xDE, 0xBC, 0x0A, 0x00, 0x00, // total_bytes = 0x0000_0ABC_DEF0_1234 (u64 LE)
    0x00, 0x00, 0x00, 0x00, // reserved = 0
};

pub const CANONICAL_TOTAL_BYTES: u64 = 0x00000ABCDEF01234;

// ════════════════════════════════════════════════════════════════════════════
// Tests — vectors mirror the TS oracle (escalation-descriptor.test.ts).
// Run: zig test core/cell-engine/src/escalation_descriptor.zig
// ════════════════════════════════════════════════════════════════════════════
const testing = std.testing;

test "layout: ESCALATION_DESCRIPTOR_SIZE is 16" {
    try testing.expectEqual(@as(usize, 16), ESCALATION_DESCRIPTOR_SIZE);
}

test "layout: field offsets are correct" {
    try testing.expectEqual(@as(usize, 0), OFF_RUNG);
    try testing.expectEqual(@as(usize, 1), OFF_OCTAVE_LEVEL);
    try testing.expectEqual(@as(usize, 2), OFF_CHILD_COUNT);
    try testing.expectEqual(@as(usize, 4), OFF_TOTAL_BYTES);
    try testing.expectEqual(@as(usize, 12), OFF_RESERVED);
}

test "layout: field offsets sum to 16 bytes total" {
    const total = 1 + 1 + 2 + 8 + 4; // rung + octave_level + child_count + total_bytes + reserved
    try testing.expectEqual(@as(usize, ESCALATION_DESCRIPTOR_SIZE), total);
}

test "layout: PAYLOAD_OFFSET is 256" {
    try testing.expectEqual(@as(usize, 256), PAYLOAD_OFFSET);
}

test "layout: TYPED_SEGMENTS_HEADER_SIZE is 4" {
    try testing.expectEqual(@as(usize, 4), TYPED_SEGMENTS_HEADER_SIZE);
}

test "Rung enum values" {
    try testing.expectEqual(@as(u8, 0), @intFromEnum(Rung.inline_data));
    try testing.expectEqual(@as(u8, 1), @intFromEnum(Rung.octave_escalated));
    try testing.expectEqual(@as(u8, 2), @intFromEnum(Rung.merkle_rooted_hierarchy));
}

test "OctaveLevel enum values" {
    try testing.expectEqual(@as(u8, 0), @intFromEnum(OctaveLevel.base));
    try testing.expectEqual(@as(u8, 1), @intFromEnum(OctaveLevel.kilo));
    try testing.expectEqual(@as(u8, 2), @intFromEnum(OctaveLevel.mega));
    try testing.expectEqual(@as(u8, 3), @intFromEnum(OctaveLevel.giga));
}

test "offset helpers: unrouted = 256, routed = 260" {
    try testing.expectEqual(@as(usize, 256), descriptorOffsetUnrouted());
    try testing.expectEqual(@as(usize, 260), descriptorOffsetRouted());
}

test "offset helpers: routed descriptor ends at 276" {
    try testing.expectEqual(@as(usize, 276), descriptorOffsetRouted() + ESCALATION_DESCRIPTOR_SIZE);
}

test "readRung / writeRung round-trips" {
    var buf = [_]u8{0} ** ESCALATION_DESCRIPTOR_SIZE;
    // inline_data
    writeRung(&buf, 0, .inline_data);
    try testing.expectEqual(Rung.inline_data, readRung(&buf, 0));
    // octave_escalated
    writeRung(&buf, 0, .octave_escalated);
    try testing.expectEqual(Rung.octave_escalated, readRung(&buf, 0));
    // merkle_rooted_hierarchy
    writeRung(&buf, 0, .merkle_rooted_hierarchy);
    try testing.expectEqual(Rung.merkle_rooted_hierarchy, readRung(&buf, 0));
}

test "writeRung lands at byte offset 0 within the descriptor" {
    var buf = [_]u8{0xff} ** 64;
    const base: usize = 16;
    writeRung(&buf, base, .octave_escalated);
    try testing.expectEqual(@as(u8, 1), buf[base + OFF_RUNG]);
}

test "readOctaveLevel / writeOctaveLevel round-trips" {
    var buf = [_]u8{0} ** ESCALATION_DESCRIPTOR_SIZE;
    inline for (.{ OctaveLevel.base, OctaveLevel.kilo, OctaveLevel.mega, OctaveLevel.giga }) |level| {
        writeOctaveLevel(&buf, 0, level);
        try testing.expectEqual(level, readOctaveLevel(&buf, 0));
    }
}

test "readChildCount / writeChildCount round-trips" {
    var buf = [_]u8{0} ** ESCALATION_DESCRIPTOR_SIZE;
    // 0
    writeChildCount(&buf, 0, 0);
    try testing.expectEqual(@as(u16, 0), readChildCount(&buf, 0));
    // 1
    writeChildCount(&buf, 0, 1);
    try testing.expectEqual(@as(u16, 1), readChildCount(&buf, 0));
    // 1024
    writeChildCount(&buf, 0, 1024);
    try testing.expectEqual(@as(u16, 1024), readChildCount(&buf, 0));
    // u16 max
    writeChildCount(&buf, 0, 0xFFFF);
    try testing.expectEqual(@as(u16, 0xFFFF), readChildCount(&buf, 0));
}

test "readChildCount: little-endian — low byte first" {
    var buf = [_]u8{0} ** ESCALATION_DESCRIPTOR_SIZE;
    writeChildCount(&buf, 0, 0x0307); // low=0x07, high=0x03
    try testing.expectEqual(@as(u8, 0x07), buf[OFF_CHILD_COUNT]); // low byte
    try testing.expectEqual(@as(u8, 0x03), buf[OFF_CHILD_COUNT + 1]); // high byte
}

test "readTotalBytes / writeTotalBytes round-trips" {
    var buf = [_]u8{0} ** ESCALATION_DESCRIPTOR_SIZE;
    // 0
    writeTotalBytes(&buf, 0, 0);
    try testing.expectEqual(@as(u64, 0), readTotalBytes(&buf, 0));
    // 1
    writeTotalBytes(&buf, 0, 1);
    try testing.expectEqual(@as(u64, 1), readTotalBytes(&buf, 0));
    // 1 KiB (octave-0 cell size)
    writeTotalBytes(&buf, 0, 1024);
    try testing.expectEqual(@as(u64, 1024), readTotalBytes(&buf, 0));
    // 1 MiB (octave-1 cell size)
    writeTotalBytes(&buf, 0, 1024 * 1024);
    try testing.expectEqual(@as(u64, 1024 * 1024), readTotalBytes(&buf, 0));
    // 1 GiB (octave-2 cell size)
    writeTotalBytes(&buf, 0, 1024 * 1024 * 1024);
    try testing.expectEqual(@as(u64, 1024 * 1024 * 1024), readTotalBytes(&buf, 0));
    // 1 TiB (octave-3 cell size): 1024^4
    const tib: u64 = 1024 * 1024 * 1024 * 1024;
    writeTotalBytes(&buf, 0, tib);
    try testing.expectEqual(tib, readTotalBytes(&buf, 0));
    // u64 max
    writeTotalBytes(&buf, 0, std.math.maxInt(u64));
    try testing.expectEqual(std.math.maxInt(u64), readTotalBytes(&buf, 0));
}

test "readTotalBytes: little-endian encoding — LSB first" {
    // 0x0102_0304_0506_0708 -> bytes [0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01]
    var buf = [_]u8{0} ** ESCALATION_DESCRIPTOR_SIZE;
    writeTotalBytes(&buf, 0, 0x0102_0304_0506_0708);
    try testing.expectEqual(@as(u8, 0x08), buf[OFF_TOTAL_BYTES + 0]); // LSB
    try testing.expectEqual(@as(u8, 0x07), buf[OFF_TOTAL_BYTES + 1]);
    try testing.expectEqual(@as(u8, 0x06), buf[OFF_TOTAL_BYTES + 2]);
    try testing.expectEqual(@as(u8, 0x05), buf[OFF_TOTAL_BYTES + 3]);
    try testing.expectEqual(@as(u8, 0x04), buf[OFF_TOTAL_BYTES + 4]);
    try testing.expectEqual(@as(u8, 0x03), buf[OFF_TOTAL_BYTES + 5]);
    try testing.expectEqual(@as(u8, 0x02), buf[OFF_TOTAL_BYTES + 6]);
    try testing.expectEqual(@as(u8, 0x01), buf[OFF_TOTAL_BYTES + 7]); // MSB
}

test "writeDescriptor / readDescriptor: inline rung round-trip" {
    var buf = [_]u8{0} ** ESCALATION_DESCRIPTOR_SIZE;
    writeDescriptor(&buf, 0, .{
        .rung = .inline_data,
        .octave_level = .base,
        .child_count = 0,
        .total_bytes = 512,
        .reserved = 0,
    });
    const d = readDescriptor(&buf, 0);
    try testing.expectEqual(Rung.inline_data, d.rung);
    try testing.expectEqual(OctaveLevel.base, d.octave_level);
    try testing.expectEqual(@as(u16, 0), d.child_count);
    try testing.expectEqual(@as(u64, 512), d.total_bytes);
    try testing.expectEqual(@as(u32, 0), d.reserved);
}

test "writeDescriptor / readDescriptor: octave-escalated rung round-trip" {
    var buf = [_]u8{0} ** ESCALATION_DESCRIPTOR_SIZE;
    writeDescriptor(&buf, 0, .{
        .rung = .octave_escalated,
        .octave_level = .kilo,
        .child_count = 1,
        .total_bytes = 1024 * 1024,
        .reserved = 0,
    });
    const d = readDescriptor(&buf, 0);
    try testing.expectEqual(Rung.octave_escalated, d.rung);
    try testing.expectEqual(OctaveLevel.kilo, d.octave_level);
    try testing.expectEqual(@as(u16, 1), d.child_count);
    try testing.expectEqual(@as(u64, 1024 * 1024), d.total_bytes);
    try testing.expectEqual(@as(u32, 0), d.reserved);
}

test "writeDescriptor / readDescriptor: merkle-rooted-hierarchy round-trip" {
    var buf = [_]u8{0} ** ESCALATION_DESCRIPTOR_SIZE;
    writeDescriptor(&buf, 0, .{
        .rung = .merkle_rooted_hierarchy,
        .octave_level = .mega,
        .child_count = 1024,
        .total_bytes = 1024 * 1024 * 1024 * 1024, // 1 TiB
        .reserved = 0,
    });
    const d = readDescriptor(&buf, 0);
    try testing.expectEqual(Rung.merkle_rooted_hierarchy, d.rung);
    try testing.expectEqual(OctaveLevel.mega, d.octave_level);
    try testing.expectEqual(@as(u16, 1024), d.child_count);
    try testing.expectEqual(@as(u64, 1024 * 1024 * 1024 * 1024), d.total_bytes);
    try testing.expectEqual(@as(u32, 0), d.reserved);
}

test "writeDescriptor: reserved is always written as 0" {
    // Pre-fill buffer with 0xff.
    var buf = [_]u8{0xff} ** ESCALATION_DESCRIPTOR_SIZE;
    writeDescriptor(&buf, 0, .{
        .rung = .inline_data,
        .octave_level = .base,
        .child_count = 0,
        .total_bytes = 0,
        .reserved = 0xDEADBEEF, // should be overridden to 0
    });
    const d = readDescriptor(&buf, 0);
    try testing.expectEqual(@as(u32, 0), d.reserved);
    // Check the raw bytes.
    try testing.expectEqual(@as(u8, 0x00), buf[OFF_RESERVED]);
    try testing.expectEqual(@as(u8, 0x00), buf[OFF_RESERVED + 1]);
    try testing.expectEqual(@as(u8, 0x00), buf[OFF_RESERVED + 2]);
    try testing.expectEqual(@as(u8, 0x00), buf[OFF_RESERVED + 3]);
}

test "writeDescriptor / readDescriptor: non-zero offset in a larger buffer" {
    var cell = [_]u8{0} ** 1024;
    const off = descriptorOffsetUnrouted(); // 256
    writeDescriptor(&cell, off, .{
        .rung = .octave_escalated,
        .octave_level = .giga,
        .child_count = 7,
        .total_bytes = CANONICAL_TOTAL_BYTES,
        .reserved = 0,
    });
    // Header region must be untouched.
    try testing.expectEqual(@as(u8, 0), cell[0]);
    try testing.expectEqual(@as(u8, 0), cell[255]);
    const d = readDescriptor(&cell, off);
    try testing.expectEqual(Rung.octave_escalated, d.rung);
    try testing.expectEqual(OctaveLevel.giga, d.octave_level);
    try testing.expectEqual(@as(u16, 7), d.child_count);
    try testing.expectEqual(CANONICAL_TOTAL_BYTES, d.total_bytes);
    try testing.expectEqual(@as(u32, 0), d.reserved);
}

test "writeDescriptor / readDescriptor: routed offset (260) does not clobber typed-segments header" {
    var cell = [_]u8{0} ** 1024;
    // Write typed-segments header sentinel values at 256-259.
    cell[256] = 0x03; // segment count = 3 (low byte)
    cell[257] = 0x00; // segment count (high byte)
    cell[258] = 0x10; // payloadStartsAt low byte
    cell[259] = 0x00; // payloadStartsAt high byte

    const off = descriptorOffsetRouted(); // 260
    writeDescriptor(&cell, off, .{
        .rung = .merkle_rooted_hierarchy,
        .octave_level = .mega,
        .child_count = 1024,
        .total_bytes = 1024 * 1024 * 1024,
        .reserved = 0,
    });
    // Typed-segments header must be untouched.
    try testing.expectEqual(@as(u8, 0x03), cell[256]);
    try testing.expectEqual(@as(u8, 0x00), cell[257]);
    try testing.expectEqual(@as(u8, 0x10), cell[258]);
    try testing.expectEqual(@as(u8, 0x00), cell[259]);
    // Descriptor round-trips correctly.
    const d = readDescriptor(&cell, off);
    try testing.expectEqual(Rung.merkle_rooted_hierarchy, d.rung);
    try testing.expectEqual(OctaveLevel.mega, d.octave_level);
    try testing.expectEqual(@as(u16, 1024), d.child_count);
    try testing.expectEqual(@as(u64, 1024 * 1024 * 1024), d.total_bytes);
}

test "canonical byte vector: CANONICAL_VECTOR matches expected hand-encoded bytes" {
    // rung = 0x01 (octave_escalated)
    try testing.expectEqual(@as(u8, 0x01), CANONICAL_VECTOR[0]);
    // octave_level = 0x02 (mega)
    try testing.expectEqual(@as(u8, 0x02), CANONICAL_VECTOR[1]);
    // child_count = 7 (u16 LE: 0x07 0x00)
    try testing.expectEqual(@as(u8, 0x07), CANONICAL_VECTOR[2]);
    try testing.expectEqual(@as(u8, 0x00), CANONICAL_VECTOR[3]);
    // total_bytes = 0x0000_0ABC_DEF0_1234 (u64 LE)
    try testing.expectEqual(@as(u8, 0x34), CANONICAL_VECTOR[4]);
    try testing.expectEqual(@as(u8, 0x12), CANONICAL_VECTOR[5]);
    try testing.expectEqual(@as(u8, 0xF0), CANONICAL_VECTOR[6]);
    try testing.expectEqual(@as(u8, 0xDE), CANONICAL_VECTOR[7]);
    try testing.expectEqual(@as(u8, 0xBC), CANONICAL_VECTOR[8]);
    try testing.expectEqual(@as(u8, 0x0A), CANONICAL_VECTOR[9]);
    try testing.expectEqual(@as(u8, 0x00), CANONICAL_VECTOR[10]);
    try testing.expectEqual(@as(u8, 0x00), CANONICAL_VECTOR[11]);
    // reserved = 0x00 x 4
    try testing.expectEqual(@as(u8, 0x00), CANONICAL_VECTOR[12]);
    try testing.expectEqual(@as(u8, 0x00), CANONICAL_VECTOR[13]);
    try testing.expectEqual(@as(u8, 0x00), CANONICAL_VECTOR[14]);
    try testing.expectEqual(@as(u8, 0x00), CANONICAL_VECTOR[15]);
}

test "canonical byte vector: CANONICAL_TOTAL_BYTES matches encoded value" {
    try testing.expectEqual(@as(u64, 0x00000ABCDEF01234), CANONICAL_TOTAL_BYTES);
    // Also verify reading it back from the canonical vector.
    try testing.expectEqual(CANONICAL_TOTAL_BYTES, readTotalBytes(&CANONICAL_VECTOR, 0));
}

test "canonical byte vector: decodes correctly via readDescriptor" {
    var buf: [ESCALATION_DESCRIPTOR_SIZE]u8 = undefined;
    @memcpy(&buf, &CANONICAL_VECTOR);
    const d = readDescriptor(&buf, 0);
    try testing.expectEqual(Rung.octave_escalated, d.rung);
    try testing.expectEqual(OctaveLevel.mega, d.octave_level);
    try testing.expectEqual(@as(u16, 7), d.child_count);
    try testing.expectEqual(CANONICAL_TOTAL_BYTES, d.total_bytes);
    try testing.expectEqual(@as(u32, 0), d.reserved);
}

test "canonical byte vector: writeDescriptor produces identical bytes" {
    var buf = [_]u8{0} ** ESCALATION_DESCRIPTOR_SIZE;
    writeDescriptor(&buf, 0, .{
        .rung = .octave_escalated,
        .octave_level = .mega,
        .child_count = 7,
        .total_bytes = CANONICAL_TOTAL_BYTES,
        .reserved = 0,
    });
    try testing.expectEqualSlices(u8, &CANONICAL_VECTOR, &buf);
}

```
