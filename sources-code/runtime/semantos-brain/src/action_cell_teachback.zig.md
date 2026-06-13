---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/action_cell_teachback.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.228552+00:00
---

# runtime/semantos-brain/src/action_cell_teachback.zig

```zig
// M5.14 — Action-cell teachback: sir_program_hash in phase-0x06 payload.
//
// The first 32 bytes of an action-phase (0x06) cell's 768-byte payload
// are reserved for the SIR program hash that produced the action.
// This creates a verifiable teachback chain: action cell → sir_program row.

const std = @import("std");

pub const PHASE_ACTION: u8 = 0x06;
pub const SIR_HASH_OFFSET: usize = 0; // First 32 bytes of payload
pub const SIR_HASH_LEN: usize = 32;

/// Returns the sir_program_hash from an action-phase cell's payload bytes.
/// payload must be at least 32 bytes.
/// Returns error.NotActionPhase if phase != 0x06.
/// Returns error.PayloadTooShort if payload.len < 32.
pub fn extractSirHash(phase: u8, payload: []const u8) ![SIR_HASH_LEN]u8 {
    if (phase != PHASE_ACTION) return error.NotActionPhase;
    if (payload.len < SIR_HASH_LEN) return error.PayloadTooShort;
    var result: [SIR_HASH_LEN]u8 = undefined;
    @memcpy(&result, payload[SIR_HASH_OFFSET .. SIR_HASH_OFFSET + SIR_HASH_LEN]);
    return result;
}

/// Writes sir_program_hash into the first 32 bytes of an action-phase cell payload.
/// payload must be at least 32 bytes.
/// Returns error.NotActionPhase if phase != 0x06.
pub fn embedSirHash(phase: u8, payload: []u8, sir_hash: *const [SIR_HASH_LEN]u8) !void {
    if (phase != PHASE_ACTION) return error.NotActionPhase;
    if (payload.len < SIR_HASH_LEN) return error.PayloadTooShort;
    @memcpy(payload[SIR_HASH_OFFSET .. SIR_HASH_OFFSET + SIR_HASH_LEN], sir_hash);
}

/// Checks whether the sir_program_hash in the cell payload is zeroed.
/// A zeroed hash means the teachback backref is missing (policy violation).
pub fn hasSirHash(phase: u8, payload: []const u8) bool {
    if (phase != PHASE_ACTION) return false;
    if (payload.len < SIR_HASH_LEN) return false;
    const hash_slice = payload[SIR_HASH_OFFSET .. SIR_HASH_OFFSET + SIR_HASH_LEN];
    for (hash_slice) |byte| {
        if (byte != 0x00) return true;
    }
    return false;
}

```
