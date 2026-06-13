---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/src/linearity.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.973265+00:00
---

# core/cell-engine/src/linearity.zig

```zig
// Linearity enforcement — Phase 4
// Implements type-aware resource semantics for semantic objects on the 2-PDA.
// Reference: FORTH:LINEARITY (linearity-enforcement.fs), CORE:SEMOBJ (semantic-objects.ts)

const std = @import("std");
const constants = @import("constants");

/// Linearity classification for semantic objects.
/// Values match constants.zig (LINEARITY_LINEAR=1, etc.)
pub const LinearityType = enum(u32) {
    linear = 1, // Must be consumed exactly once — no DUP, no DROP
    affine = 2, // Can be consumed at most once — no DUP, DROP allowed
    relevant = 3, // Must be consumed at least once — DUP allowed, no DROP
    debug = 4, // Unrestricted — development only
};

/// Categories of stack operations for linearity checking.
pub const LinearityOperation = enum {
    duplicate, // DUP, OVER, PICK, 2DUP, 3DUP
    discard, // DROP, 2DROP, NIP
    consume, // Normal read-and-use (CHECKSIG, etc.)
    swap, // SWAP, ROT (reorder, no copy/destroy)
    inspect, // SPEEK, SIZE, DEPTH (read-only)
};

pub const LinearityError = error{
    cannot_duplicate_linear,
    cannot_discard_linear,
    cannot_duplicate_affine,
    cannot_discard_relevant,
    invalid_linearity_type,
    linearity_check_failed,
    domain_flag_mismatch,
    type_hash_mismatch,
    owner_id_mismatch,
    capability_type_mismatch,
    cell_too_short,
};

/// Check if a linearity type permits a given operation.
/// Returns void on success, error on violation.
pub fn checkLinearity(linearity: LinearityType, operation: LinearityOperation) LinearityError!void {
    switch (linearity) {
        .linear => switch (operation) {
            .duplicate => return error.cannot_duplicate_linear,
            .discard => return error.cannot_discard_linear,
            .consume, .swap, .inspect => {},
        },
        .affine => switch (operation) {
            .duplicate => return error.cannot_duplicate_affine,
            .discard, .consume, .swap, .inspect => {},
        },
        .relevant => switch (operation) {
            .discard => return error.cannot_discard_relevant,
            .duplicate, .consume, .swap, .inspect => {},
        },
        .debug => {}, // All operations allowed
    }
}

/// Extract linearity type from cell data. Reads offset 16, 4 bytes LE.
/// Returns error if cell data is too short or value is invalid.
pub fn getLinearity(cell_data: []const u8) LinearityError!LinearityType {
    const offset: usize = constants.HEADER_OFFSET_LINEARITY;
    const size: usize = constants.HEADER_SIZE_LINEARITY;
    if (cell_data.len < offset + size) return error.cell_too_short;
    const value = std.mem.readInt(u32, cell_data[offset..][0..4], .little);
    return std.meta.intToEnum(LinearityType, value) catch error.invalid_linearity_type;
}

/// Extract domain flag from cell data. Reads offset 24, 4 bytes LE.
pub fn getDomainFlag(cell_data: []const u8) LinearityError!u32 {
    const offset: usize = constants.HEADER_OFFSET_FLAGS;
    const size: usize = constants.HEADER_SIZE_FLAGS;
    if (cell_data.len < offset + size) return error.cell_too_short;
    return std.mem.readInt(u32, cell_data[offset..][0..4], .little);
}

/// Extract type hash from cell data. Reads offset 30, 32 bytes.
pub fn getTypeHash(cell_data: []const u8) LinearityError![32]u8 {
    const offset: usize = constants.HEADER_OFFSET_TYPE_HASH;
    const size: usize = constants.HEADER_SIZE_TYPE_HASH;
    if (cell_data.len < offset + size) return error.cell_too_short;
    return cell_data[offset..][0..32].*;
}

/// Extract owner ID from cell data. Reads offset 62, 16 bytes.
pub fn getOwnerId(cell_data: []const u8) LinearityError![16]u8 {
    const offset: usize = constants.HEADER_OFFSET_OWNER_ID;
    const size: usize = constants.HEADER_SIZE_OWNER_ID;
    if (cell_data.len < offset + size) return error.cell_too_short;
    return cell_data[offset..][0..16].*;
}

/// Extract capability type from cell payload. Reads byte 256 (payload offset 0).
/// Capability types: 0=RECOVERY, 1=PERMISSION, 2=DATA_ACCESS,
/// 3=COMPUTE_DELEGATION, 4=METERED_ACCESS, 5=TRANSFER
pub fn getCapabilityType(cell_data: []const u8) LinearityError!u8 {
    const offset: usize = constants.HEADER_SIZE; // 256 — first byte of payload
    if (cell_data.len < offset + 1) return error.cell_too_short;
    return cell_data[offset];
}

/// Classify a domain flag into its tier.
/// Flag 0 is reserved/unassigned. The 3-tier system starts at 0x01.
pub const FlagTier = enum {
    well_known, // [0x01, 0xFF] — Plexus protocol-level
    extended, // [0x100, 0xFFFF] — Dusk-reserved extensions
    sovereign, // [0x10000, 0xFFFFFFFF] — Client application use
    reserved, // 0 — unassigned
};

pub fn classifyFlag(flag: u32) FlagTier {
    if (flag == 0) return .reserved;
    if (flag >= constants.DOMAIN_FLAG_PLEXUS_RESERVED_MIN and flag <= constants.DOMAIN_FLAG_PLEXUS_RESERVED_MAX) return .well_known;
    if (flag >= constants.DOMAIN_FLAG_EXTENDED_MIN and flag <= constants.DOMAIN_FLAG_EXTENDED_MAX) return .extended;
    return .sovereign;
}

```
