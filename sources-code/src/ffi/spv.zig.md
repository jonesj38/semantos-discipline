---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/src/ffi/spv.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.400874+00:00
---

# src/ffi/spv.zig

```zig
// Semantos FFI — SPV Verification (D30A.6)
// Native BUMP merkle proof verification using SHA-256 double-hash.
// Verifies that a transaction's txid is included in a block via merkle path.
//
// BUMP format (Binary Unified Merkle Path):
//   - 4 bytes: block height (LE)
//   - 1 byte: tree height
//   - For each level (0..tree_height):
//     - varint: number of nodes at this level
//     - For each node:
//       - varint: offset
//       - 1 byte: flags (0=hash provided, 1=txid, 2=duplicate)
//       - if flags==0: 32 bytes hash
//
// Verification: starting from the txid at level 0, combine with sibling
// hashes up the tree to compute the merkle root.

const std = @import("std");
const Sha256 = std.crypto.hash.sha2.Sha256;

pub const SpvError = error{
    invalid_proof,
    txid_not_found,
    proof_too_short,
    invalid_bump_format,
};

/// Double-SHA256
fn hash256(data: []const u8, out: *[32]u8) void {
    var first: [32]u8 = undefined;
    Sha256.hash(data, &first, .{});
    Sha256.hash(&first, out, .{});
}

/// Read a varint from BUMP data. Returns value and bytes consumed.
fn readVarInt(data: []const u8) struct { value: u64, bytes: usize } {
    if (data.len == 0) return .{ .value = 0, .bytes = 0 };
    const first = data[0];
    if (first < 0xfd) {
        return .{ .value = first, .bytes = 1 };
    } else if (first == 0xfd) {
        if (data.len < 3) return .{ .value = 0, .bytes = 0 };
        return .{ .value = std.mem.readInt(u16, data[1..][0..2], .little), .bytes = 3 };
    } else if (first == 0xfe) {
        if (data.len < 5) return .{ .value = 0, .bytes = 0 };
        return .{ .value = std.mem.readInt(u32, data[1..][0..4], .little), .bytes = 5 };
    } else {
        if (data.len < 9) return .{ .value = 0, .bytes = 0 };
        return .{ .value = std.mem.readInt(u64, data[1..][0..8], .little), .bytes = 9 };
    }
}

/// Verify a BUMP merkle proof for a given txid.
/// Returns the computed merkle root on success.
pub fn verifyBump(txid: [32]u8, bump_data: []const u8) SpvError![32]u8 {
    if (bump_data.len < 6) return error.proof_too_short;

    var pos: usize = 0;

    // Block height (4 bytes LE) — informational, not used in verification
    if (pos + 4 > bump_data.len) return error.invalid_bump_format;
    pos += 4;

    // Tree height (1 byte)
    if (pos >= bump_data.len) return error.invalid_bump_format;
    const tree_height = bump_data[pos];
    pos += 1;

    if (tree_height == 0 or tree_height > 64) return error.invalid_bump_format;

    // We need to work up the tree from the txid.
    // At each level, we find our node and its sibling, combine them.
    var current_hash = txid;
    var current_offset: u64 = 0;
    var found_txid = false;

    // Parse level 0 to find the txid's offset
    var level: u8 = 0;
    const saved_pos = pos;

    // First pass on level 0: find the txid
    if (pos >= bump_data.len) return error.invalid_bump_format;
    const node_count_result = readVarInt(bump_data[pos..]);
    if (node_count_result.bytes == 0) return error.invalid_bump_format;
    pos += node_count_result.bytes;

    var ni: u64 = 0;
    while (ni < node_count_result.value) : (ni += 1) {
        const offset_result = readVarInt(bump_data[pos..]);
        if (offset_result.bytes == 0) return error.invalid_bump_format;
        pos += offset_result.bytes;

        if (pos >= bump_data.len) return error.invalid_bump_format;
        const flags = bump_data[pos];
        pos += 1;

        if (flags == 1) {
            // This is the txid position
            if (!found_txid) {
                current_offset = offset_result.value;
                found_txid = true;
            }
        } else if (flags == 0) {
            // Hash provided
            if (pos + 32 > bump_data.len) return error.invalid_bump_format;
            pos += 32;
        }
        // flags == 2: duplicate, no data
    }

    if (!found_txid) return error.txid_not_found;

    // Now re-parse from level 0 and work up
    pos = saved_pos;
    level = 0;

    while (level < tree_height) : (level += 1) {
        const nc_result = readVarInt(bump_data[pos..]);
        if (nc_result.bytes == 0) return error.invalid_bump_format;
        pos += nc_result.bytes;

        // Find our sibling at this level
        const sibling_offset = if (current_offset % 2 == 0) current_offset + 1 else current_offset - 1;
        var sibling_hash: [32]u8 = undefined;
        var found_sibling = false;
        var is_duplicate = false;

        var ni2: u64 = 0;
        while (ni2 < nc_result.value) : (ni2 += 1) {
            const off_result = readVarInt(bump_data[pos..]);
            if (off_result.bytes == 0) return error.invalid_bump_format;
            pos += off_result.bytes;

            if (pos >= bump_data.len) return error.invalid_bump_format;
            const flags = bump_data[pos];
            pos += 1;

            if (flags == 0) {
                if (pos + 32 > bump_data.len) return error.invalid_bump_format;
                if (off_result.value == sibling_offset) {
                    @memcpy(&sibling_hash, bump_data[pos..][0..32]);
                    found_sibling = true;
                }
                pos += 32;
            } else if (flags == 1) {
                // txid position — we already have it
                if (off_result.value == sibling_offset) {
                    sibling_hash = txid;
                    found_sibling = true;
                }
            } else if (flags == 2) {
                // Duplicate — sibling is same as current
                if (off_result.value == sibling_offset or off_result.value == current_offset) {
                    sibling_hash = current_hash;
                    found_sibling = true;
                    is_duplicate = true;
                }
            }
        }

        if (!found_sibling) {
            // If tree has odd number of nodes, duplicate the last
            if (current_offset % 2 == 0 and !is_duplicate) {
                sibling_hash = current_hash;
            } else {
                return error.invalid_bump_format;
            }
        }

        // Combine: if current_offset is even, current is left; else right
        var combined: [64]u8 = undefined;
        if (current_offset % 2 == 0) {
            @memcpy(combined[0..32], &current_hash);
            @memcpy(combined[32..64], &sibling_hash);
        } else {
            @memcpy(combined[0..32], &sibling_hash);
            @memcpy(combined[32..64], &current_hash);
        }
        hash256(&combined, &current_hash);

        // Move up: offset halves
        current_offset = current_offset / 2;
    }

    return current_hash;
}

// ── Tests ──

test "BUMP verify with single txid" {
    // Construct a minimal BUMP: 1 tx at offset 0, sibling at offset 1, tree height 1
    var bump: [128]u8 = undefined;
    var pos: usize = 0;

    // Block height = 100
    std.mem.writeInt(u32, bump[pos..][0..4], 100, .little);
    pos += 4;

    // Tree height = 1
    bump[pos] = 1;
    pos += 1;

    // Level 0: 2 nodes
    bump[pos] = 2; // varint count
    pos += 1;

    // Node 0: offset=0, flags=1 (txid)
    bump[pos] = 0; // offset
    pos += 1;
    bump[pos] = 1; // flags=txid
    pos += 1;

    // Node 1: offset=1, flags=0 (hash provided)
    bump[pos] = 1; // offset
    pos += 1;
    bump[pos] = 0; // flags=hash
    pos += 1;
    const sibling: [32]u8 = .{0xBB} ** 32;
    @memcpy(bump[pos..][0..32], &sibling);
    pos += 32;

    const txid: [32]u8 = .{0xAA} ** 32;
    const root = try verifyBump(txid, bump[0..pos]);

    // Manually compute expected: hash256(txid ++ sibling)
    var expected_combined: [64]u8 = undefined;
    @memcpy(expected_combined[0..32], &txid);
    @memcpy(expected_combined[32..64], &sibling);
    var expected_root: [32]u8 = undefined;
    hash256(&expected_combined, &expected_root);

    try std.testing.expectEqualSlices(u8, &expected_root, &root);
}

test "BUMP verify rejects too-short data" {
    const txid: [32]u8 = .{0xAA} ** 32;
    const result = verifyBump(txid, &[_]u8{ 0, 0, 0 });
    try std.testing.expectError(error.proof_too_short, result);
}

```
