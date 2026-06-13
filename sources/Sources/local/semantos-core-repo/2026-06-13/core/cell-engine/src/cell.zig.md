---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/src/cell.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.975799+00:00
---

# core/cell-engine/src/cell.zig

```zig
// Cell packing — Phase 1 implementation
// Produces byte-identical output to typeHashRegistry.ts packCell/unpackCell.

const std = @import("std");
const constants = @import("constants");
const errors = @import("errors");
// RM-042: `commerce` module no longer imported here — its Commerce*
// surface (stripped in RM-032b) and OnChainBinding surface (stripped
// here) were the only callers from this file.

/// Magic bytes — raw byte sequence matching TypeScript Buffer.from([0xde, 0xad, ...]).
/// NOT written as little-endian u32 values (that would reverse each group of 4 bytes).
pub const MAGIC_BYTES = [16]u8{
    0xDE, 0xAD, 0xBE, 0xEF,
    0xCA, 0xFE, 0xBA, 0xBE,
    0x13, 0x37, 0x13, 0x37,
    0x42, 0x42, 0x42, 0x42,
};

/// Semantic cell header — 256 bytes when packed.
pub const CellHeader = struct {
    magic: [16]u8,
    linearity: u32,
    version: u32,
    flags: u32,
    ref_count: u16,
    type_hash: [32]u8,
    owner_id: [16]u8,
    timestamp: u64,
    cell_count: u32,
    total_size: u32,
    /// Reserved block — 162 bytes at header offsets 94..255.
    ///   - Bytes 94-95 (2): unnamed reserved (former
    ///     commerce phase / dimension — stripped in RM-032b)
    ///   - Bytes 96-127 (32): parentHash
    ///   - Bytes 128-159 (32): prevStateHash
    ///   - Bytes 160-223 (64): unnamed reserved (former OnChainBinding
    ///     region — stripped in RM-042; anchoring is now a separate
    ///     AnchorAttestation cell, see @semantos/anchor-attestation)
    ///   - Bytes 224-255 (32): domainPayloadRoot (RM-023)
    reserved: [162]u8,
};

pub const UnpackResult = struct {
    header: CellHeader,
    payload: [constants.PAYLOAD_SIZE]u8,
    payload_len: u32,
};

pub const PackError = error{
    payload_too_large,
};

pub const UnpackError = error{
    invalid_magic,
    buffer_too_small,
};

/// Pack a CellHeader + payload into exactly 1024 bytes.
/// Payload is zero-padded to 768 bytes. Header fields are written at
/// absolute byte offsets from constants.zig, little-endian for integers.
pub fn packCell(header: *const CellHeader, payload: []const u8, out: *[constants.CELL_SIZE]u8) PackError!void {
    if (payload.len > constants.PAYLOAD_SIZE) return error.payload_too_large;

    // Zero the entire output
    @memset(out, 0);

    // Magic (offset 0, 16 bytes) — raw bytes, NOT endian-converted
    const magic_off: usize = constants.HEADER_OFFSET_MAGIC;
    @memcpy(out[magic_off..][0..16], &header.magic);

    // Linearity (offset 16, 4 bytes LE)
    const lin_off: usize = constants.HEADER_OFFSET_LINEARITY;
    std.mem.writeInt(u32, out[lin_off..][0..4], header.linearity, .little);

    // Version (offset 20, 4 bytes LE)
    const ver_off: usize = constants.HEADER_OFFSET_VERSION;
    std.mem.writeInt(u32, out[ver_off..][0..4], header.version, .little);

    // Flags (offset 24, 4 bytes LE)
    const flags_off: usize = constants.HEADER_OFFSET_FLAGS;
    std.mem.writeInt(u32, out[flags_off..][0..4], header.flags, .little);

    // RefCount (offset 28, 2 bytes LE)
    const ref_off: usize = constants.HEADER_OFFSET_REF_COUNT;
    std.mem.writeInt(u16, out[ref_off..][0..2], header.ref_count, .little);

    // TypeHash (offset 30, 32 bytes)
    const th_off: usize = constants.HEADER_OFFSET_TYPE_HASH;
    @memcpy(out[th_off..][0..32], &header.type_hash);

    // OwnerID (offset 62, 16 bytes)
    const oid_off: usize = constants.HEADER_OFFSET_OWNER_ID;
    @memcpy(out[oid_off..][0..16], &header.owner_id);

    // Timestamp (offset 78, 8 bytes LE)
    const ts_off: usize = constants.HEADER_OFFSET_TIMESTAMP;
    std.mem.writeInt(u64, out[ts_off..][0..8], header.timestamp, .little);

    // CellCount (offset 86, 4 bytes LE)
    const cc_off: usize = constants.HEADER_OFFSET_CELL_COUNT;
    std.mem.writeInt(u32, out[cc_off..][0..4], header.cell_count, .little);

    // TotalSize / PayloadTotal (offset 90, 4 bytes LE)
    const ts_size_off: usize = constants.HEADER_OFFSET_PAYLOAD_TOTAL;
    std.mem.writeInt(u32, out[ts_size_off..][0..4], header.total_size, .little);

    // Reserved block (offset 94, 162 bytes)
    const reserved_off: usize = 94; // RM-032b: HEADER_OFFSET_COMMERCE_PHASE was stripped; the reserved block still starts at byte 94 per CellHeader struct
    @memcpy(out[reserved_off..][0..162], &header.reserved);

    // Payload (offset 256, up to 768 bytes — remainder stays zero)
    const payload_off: usize = constants.HEADER_SIZE;
    @memcpy(out[payload_off..][0..payload.len], payload);
}

/// Unpack a 1024-byte cell into header fields + payload.
/// Returns error.invalid_magic if magic bytes don't match.
pub fn unpackCell(cell_buf: *const [constants.CELL_SIZE]u8) UnpackError!UnpackResult {
    // Validate magic
    if (!validateMagic(cell_buf)) return error.invalid_magic;

    var result: UnpackResult = undefined;

    // Magic
    @memcpy(&result.header.magic, cell_buf[0..16]);

    // Linearity
    const lin_off: usize = constants.HEADER_OFFSET_LINEARITY;
    result.header.linearity = std.mem.readInt(u32, cell_buf[lin_off..][0..4], .little);

    // Version
    const ver_off: usize = constants.HEADER_OFFSET_VERSION;
    result.header.version = std.mem.readInt(u32, cell_buf[ver_off..][0..4], .little);

    // Flags
    const flags_off: usize = constants.HEADER_OFFSET_FLAGS;
    result.header.flags = std.mem.readInt(u32, cell_buf[flags_off..][0..4], .little);

    // RefCount
    const ref_off: usize = constants.HEADER_OFFSET_REF_COUNT;
    result.header.ref_count = std.mem.readInt(u16, cell_buf[ref_off..][0..2], .little);

    // TypeHash
    const th_off: usize = constants.HEADER_OFFSET_TYPE_HASH;
    @memcpy(&result.header.type_hash, cell_buf[th_off..][0..32]);

    // OwnerID
    const oid_off: usize = constants.HEADER_OFFSET_OWNER_ID;
    @memcpy(&result.header.owner_id, cell_buf[oid_off..][0..16]);

    // Timestamp
    const ts_off: usize = constants.HEADER_OFFSET_TIMESTAMP;
    result.header.timestamp = std.mem.readInt(u64, cell_buf[ts_off..][0..8], .little);

    // CellCount
    const cc_off: usize = constants.HEADER_OFFSET_CELL_COUNT;
    result.header.cell_count = std.mem.readInt(u32, cell_buf[cc_off..][0..4], .little);

    // TotalSize
    const ts_size_off: usize = constants.HEADER_OFFSET_PAYLOAD_TOTAL;
    result.header.total_size = std.mem.readInt(u32, cell_buf[ts_size_off..][0..4], .little);

    // Reserved block
    const reserved_off: usize = 94; // RM-032b: HEADER_OFFSET_COMMERCE_PHASE was stripped; the reserved block still starts at byte 94 per CellHeader struct
    @memcpy(&result.header.reserved, cell_buf[reserved_off..][0..162]);

    // Payload — extract up to total_size bytes, clamped to PAYLOAD_SIZE
    const payload_off: usize = constants.HEADER_SIZE;
    const payload_len = @min(result.header.total_size, constants.PAYLOAD_SIZE);
    @memset(&result.payload, 0);
    @memcpy(result.payload[0..payload_len], cell_buf[payload_off..][0..payload_len]);
    result.payload_len = payload_len;

    return result;
}

/// Validate magic bytes at offset 0-15.
pub fn validateMagic(cell_buf: *const [constants.CELL_SIZE]u8) bool {
    return std.mem.eql(u8, cell_buf[0..16], &MAGIC_BYTES);
}

/// Create a default CellHeader with magic bytes set and all else zeroed.
pub fn defaultHeader() CellHeader {
    var h: CellHeader = std.mem.zeroes(CellHeader);
    h.magic = MAGIC_BYTES;
    h.version = constants.VERSION;
    h.ref_count = 1;
    return h;
}

/// Reserved-block start = byte 94 of the 256-byte header (matches the
/// `reserved: [162]u8` field). RM-032b stripped the commerce-shaped
/// HEADER_OFFSET_COMMERCE_* constants that used to anchor this; the
/// byte position is unchanged.
const RESERVED_BLOCK_START: usize = 94;

// `getOnChainBinding` / `setOnChainBinding` removed in RM-042.
// Anchoring a cell now creates a separate AnchorAttestation cell
// (@semantos/anchor-attestation) instead of mutating the target
// cell's header. Header bytes 160-223 are unnamed reserved space.

/// Get the domainPayloadRoot (Phase H §3.3 / RM-023) — 32B SHA-256
/// binding the payload bytes to the header. Reads from the reserved
/// block at offset 130 (absolute offset 224 in the 256-byte header).
pub fn getDomainPayloadRoot(header: *const CellHeader) [32]u8 {
    const reserved_offset: usize = constants.HEADER_OFFSET_DOMAIN_PAYLOAD_ROOT - RESERVED_BLOCK_START;
    var out: [32]u8 = undefined;
    @memcpy(&out, header.reserved[reserved_offset..][0..32]);
    return out;
}

/// Set the domainPayloadRoot in the header. Writes 32 bytes at the
/// fixed offset within the reserved block.
pub fn setDomainPayloadRoot(header: *CellHeader, root: [32]u8) void {
    const reserved_offset: usize = constants.HEADER_OFFSET_DOMAIN_PAYLOAD_ROOT - RESERVED_BLOCK_START;
    @memcpy(header.reserved[reserved_offset..][0..32], &root);
}


```
