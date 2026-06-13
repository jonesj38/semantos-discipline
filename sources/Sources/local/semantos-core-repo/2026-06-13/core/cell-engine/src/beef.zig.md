---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/src/beef.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.975250+00:00
---

# core/cell-engine/src/beef.zig

```zig
// Phase 5: BEEF/BUMP parsing and SPV verification via BSVZ
// Full profile only — not compiled in embedded builds.

const std = @import("std");
const bsvz = @import("bsvz");
const errors = @import("errors");

// ── BEEF version magic constants ──

pub const BEEF_V1_MAGIC: u32 = 0x0100BEEF;
pub const BEEF_V2_MAGIC: u32 = 0x0200BEEF;
pub const ATOMIC_BEEF_MAGIC: u32 = 0x01010101;

pub const BeefVersion = enum(i32) {
    v1 = 1, // BRC-62
    v2 = 2, // BRC-96
    atomic = 3, // BRC-95
    invalid = -1,
};

pub const BeefError = error{
    beef_parse_error,
    beef_invalid_proof,
    beef_txid_not_found,
    bump_invalid_proof,
    bump_parse_error,
};

/// Detect BEEF version from the first 4 bytes (little-endian).
/// Validates minimum structure: magic + at least 1 byte of payload (nBUMPs count or version).
/// Returns .invalid for magic-only data that lacks any structure.
pub fn detectVersion(data: []const u8) BeefVersion {
    if (data.len < 4) return .invalid;
    const magic = std.mem.readInt(u32, data[0..4], .little);
    return switch (magic) {
        // Require at least 1 byte after magic for minimum structure
        BEEF_V1_MAGIC => if (data.len >= 5) .v1 else .invalid,
        BEEF_V2_MAGIC => if (data.len >= 5) .v2 else .invalid,
        ATOMIC_BEEF_MAGIC => if (data.len >= 5) .atomic else .invalid,
        else => .invalid,
    };
}

/// Parse and verify BEEF structure using BSVZ.
///
/// WARNING: Uses GullibleChainTracker — validates BEEF structure and merkle path
/// computation, but does NOT verify merkle roots against real block headers.
/// Any well-formed BEEF with valid internal merkle paths will pass.
///
/// For true SPV verification, use `verifyBeefSpv()` which requires caller-supplied
/// trusted merkle roots, or independently verify the merkle roots returned by
/// BSVZ's BEEF parser against a block header chain.
///
/// Returns true if the BEEF is structurally valid and the subject txid is found.
pub fn verifyBeef(allocator: std.mem.Allocator, beef_bytes: []const u8, txid: [32]u8) BeefError!bool {
    // BSVZ's newBeefFromBytes handles V1, V2, and Atomic BEEF transparently
    var beef = bsvz.transaction.beef.newBeefFromBytes(allocator, beef_bytes) catch {
        return error.beef_parse_error;
    };
    defer beef.deinit();

    // Check that the subject txid exists
    const chain_hash = bsvz.primitives.chainhash.Hash{ .bytes = txid };
    if (beef.findTransaction(chain_hash) == null) {
        return error.beef_txid_not_found;
    }

    // Structure-only verification (GullibleChainTracker accepts any merkle root)
    const tracker = bsvz.spv.GullibleChainTracker{};
    const valid = bsvz.spv.verifyBeef(allocator, &beef, chain_hash, tracker, null) catch {
        return error.beef_invalid_proof;
    };

    return valid;
}

/// Parse and verify BEEF with real SPV: caller supplies trusted merkle roots.
///
/// The caller provides an array of trusted merkle roots (32 bytes each) from
/// a block header chain. The BEEF's computed merkle roots must match at least
/// one trusted root for each BUMP in the envelope.
///
/// This is the real SPV path — use when you have access to block headers
/// (e.g., via WhatsOnChain, a local header chain, or an SPV wallet).
///
/// Returns true if the BEEF is valid AND all merkle roots match trusted roots.
pub fn verifyBeefSpv(
    allocator: std.mem.Allocator,
    beef_bytes: []const u8,
    txid: [32]u8,
    trusted_roots: []const [32]u8,
) BeefError!bool {
    var beef = bsvz.transaction.beef.newBeefFromBytes(allocator, beef_bytes) catch {
        return error.beef_parse_error;
    };
    defer beef.deinit();

    const chain_hash = bsvz.primitives.chainhash.Hash{ .bytes = txid };
    if (beef.findTransaction(chain_hash) == null) {
        return error.beef_txid_not_found;
    }

    // First pass: structure validation with gullible tracker
    const tracker = bsvz.spv.GullibleChainTracker{};
    const structurally_valid = bsvz.spv.verifyBeef(allocator, &beef, chain_hash, tracker, null) catch {
        return error.beef_invalid_proof;
    };
    if (!structurally_valid) return false;

    // Second pass: verify that BUMP merkle roots match trusted roots.
    // Extract BUMPs from the BEEF and compute their roots.
    const txid_hash256 = bsvz.crypto.Hash256{ .bytes = txid };
    for (beef.bumps) |*bump| {
        const computed_root = bump.computeRoot(allocator, txid_hash256) catch {
            return error.beef_invalid_proof;
        };

        var root_found = false;
        for (trusted_roots) |trusted| {
            if (std.mem.eql(u8, &computed_root.bytes, &trusted)) {
                root_found = true;
                break;
            }
        }
        if (!root_found) return false;
    }

    return true;
}

/// Parse and verify a standalone BUMP merkle proof.
/// Computes the merkle root from the BUMP data and txid, then compares
/// against the expected root.
pub fn verifyBump(allocator: std.mem.Allocator, bump_bytes: []const u8, txid: [32]u8, expected_root: [32]u8) BeefError!bool {
    // Parse the BUMP using BSVZ MerklePath
    var path = bsvz.spv.MerklePath.parse(allocator, bump_bytes) catch {
        return error.bump_parse_error;
    };
    defer path.deinit(allocator);

    // Compute the merkle root from the proof and txid
    const txid_hash = bsvz.crypto.Hash256{ .bytes = txid };
    const computed_root = path.computeRoot(allocator, txid_hash) catch {
        return error.bump_invalid_proof;
    };

    return std.mem.eql(u8, &computed_root.bytes, &expected_root);
}

// ── Tests ──

test "detectVersion: BEEF V1 with structure" {
    const data = [_]u8{ 0xEF, 0xBE, 0x00, 0x01, 0x00 }; // magic + nBUMPs byte
    try std.testing.expectEqual(BeefVersion.v1, detectVersion(&data));
}

test "detectVersion: BEEF V2 with structure" {
    const data = [_]u8{ 0xEF, 0xBE, 0x00, 0x02, 0x00 }; // magic + nBUMPs byte
    try std.testing.expectEqual(BeefVersion.v2, detectVersion(&data));
}

test "detectVersion: Atomic BEEF with structure" {
    const data = [_]u8{ 0x01, 0x01, 0x01, 0x01, 0x00 }; // magic + version byte
    try std.testing.expectEqual(BeefVersion.atomic, detectVersion(&data));
}

test "detectVersion: magic-only (no structure) is invalid" {
    const data = [_]u8{ 0xEF, 0xBE, 0x00, 0x01 }; // only 4 bytes
    try std.testing.expectEqual(BeefVersion.invalid, detectVersion(&data));
}

test "detectVersion: invalid" {
    const data = [_]u8{ 0x00, 0x00, 0x00, 0x00 };
    try std.testing.expectEqual(BeefVersion.invalid, detectVersion(&data));
}

test "detectVersion: too short" {
    const data = [_]u8{ 0xEF, 0xBE };
    try std.testing.expectEqual(BeefVersion.invalid, detectVersion(&data));
}

```
