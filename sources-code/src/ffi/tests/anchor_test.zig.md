---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/src/ffi/tests/anchor_test.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.404726+00:00
---

# src/ffi/tests/anchor_test.zig

```zig
// Phase 30D Gate Tests — Anchor FFI Tests
//
// 8 TDD gate tests for anchor batch submission and offline SPV verification.
// Mock anchor callback simulates host-side BSV anchoring; kernel validates
// proof structure, callback invocation, serialisation round-trip, and tamper
// detection.

const std = @import("std");
const exports = @import("exports");
const callbacks = @import("callbacks");

// Re-export C functions
const semantos_init = exports.semantos_init;
const semantos_shutdown = exports.semantos_shutdown;
const semantos_anchor_batch = exports.semantos_anchor_batch;
const semantos_anchor_verify = exports.semantos_anchor_verify;
const semantos_register_callbacks = callbacks.semantos_register_callbacks;

// Error codes
const SEMANTOS_OK: i32 = 0;
const SEMANTOS_ERR_INVALID_PROOF: i32 = -7;
const SEMANTOS_ERR_CALLBACK_NOT_REGISTERED: i32 = -10;

// ── Test AnchorProof fixture ──

/// Build a valid AnchorProof JSON for a given state hash hex string.
/// The proof contains a valid BUMP structure and a blockHash with valid POW.
fn buildValidProofJson(state_hash_hex: []const u8, buf: []u8) []const u8 {
    // Build a minimal valid BUMP proof:
    // [4 bytes block height=800000 LE] [1 byte tree_height=1]
    // Level 0: [varint count=1] [varint offset=0] [flag=1 (txid)]
    // This is the simplest valid BUMP: single tx in block.
    //
    // Block height 800000 = 0x000C3500 → LE: 00 35 0C 00
    // tree_height = 1
    // level 0: count=1, offset=0, flag=1
    const bump_hex = "00350c00" ++ "01" ++ "01" ++ "00" ++ "01";

    // blockHash: valid POW with trailing zero bytes (LE representation).
    // Last 2 bytes must be 0x00 for POW check.
    const block_hash_hex = "0000000000000000025cb04abc4f5c9e4a1b0c3d2e4f56789abcdef012340000";

    // txid: 64-char hex
    const txid_hex = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2";

    const json_template = "{\"stateHash\":\"" ++ "{s}" ++ "\",\"txid\":\"" ++ txid_hex ++ "\",\"blockHeight\":800000,\"blockHash\":\"" ++ block_hash_hex ++ "\",\"merkleProof\":\"" ++ bump_hex ++ "\",\"timestamp\":1700000000000,\"interval\":60000}";
    _ = json_template;

    // Build manually since we need runtime state_hash_hex
    var offset: usize = 0;

    const prefix = "{\"stateHash\":\"";
    @memcpy(buf[offset .. offset + prefix.len], prefix);
    offset += prefix.len;

    @memcpy(buf[offset .. offset + state_hash_hex.len], state_hash_hex);
    offset += state_hash_hex.len;

    const mid1 = "\",\"txid\":\"" ++ txid_hex ++ "\",\"blockHeight\":800000,\"blockHash\":\"" ++ block_hash_hex ++ "\",\"merkleProof\":\"" ++ bump_hex ++ "\",\"timestamp\":1700000000000,\"interval\":60000}";
    @memcpy(buf[offset .. offset + mid1.len], mid1);
    offset += mid1.len;

    return buf[0..offset];
}

// ── Mock anchor callback state ──

var mock_anchor_call_count: usize = 0;
var mock_anchor_last_hash: [256]u8 = undefined;
var mock_anchor_last_hash_len: usize = 0;

fn resetMockAnchorState() void {
    mock_anchor_call_count = 0;
    mock_anchor_last_hash_len = 0;
}

// ── Mock anchor submit callback ──
// Returns a valid AnchorProof JSON for the submitted state hash.

fn mock_anchor_submit(
    state_hash: [*]const u8,
    hash_len: usize,
    _: [*]const u8, // metadata_json
    _: usize, // meta_len
    out_proof: [*]u8,
    inout_len: *usize,
) callconv(.c) i32 {
    mock_anchor_call_count += 1;

    // Record the submitted hash
    if (hash_len <= mock_anchor_last_hash.len) {
        @memcpy(mock_anchor_last_hash[0..hash_len], state_hash[0..hash_len]);
        mock_anchor_last_hash_len = hash_len;
    }

    // Build a valid proof JSON for this state hash
    var proof_buf: [2048]u8 = undefined;
    const proof_json = buildValidProofJson(state_hash[0..hash_len], &proof_buf);

    if (inout_len.* < proof_json.len) {
        inout_len.* = proof_json.len;
        return -6; // BUFFER_TOO_SMALL
    }

    @memcpy(out_proof[0..proof_json.len], proof_json);
    inout_len.* = proof_json.len;

    return SEMANTOS_OK;
}

// ── Stub callbacks for non-anchor adapters ──

fn stub_storage_read(_: [*]const u8, _: usize, _: [*]u8, _: *usize) callconv(.c) i32 {
    return -1;
}
fn stub_storage_write(_: [*]const u8, _: usize, _: [*]const u8, _: usize) callconv(.c) i32 {
    return 0;
}

// ── Helpers ──

fn initKernel() void {
    const config = "{\"version\":\"0.30.0\"}";
    _ = semantos_init(config.ptr, config.len);
}

fn registerWithAnchorCallback() void {
    _ = semantos_register_callbacks(
        @ptrCast(&stub_storage_read),
        @ptrCast(&stub_storage_write),
        null,
        null,
        @ptrCast(&mock_anchor_submit),
        null,
        null,
    );
}

// ── T1: anchor_batch with valid state hashes returns serialised proof array ──

test "30D T1: anchor_batch with valid state hashes returns serialised proof array" {
    resetMockAnchorState();
    initKernel();
    registerWithAnchorCallback();

    const json = "[\"a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2\",\"b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3\"]";

    var out_proofs: [*]u8 = undefined;
    var out_len: usize = 0;
    const rc = semantos_anchor_batch(json.ptr, json.len, &out_proofs, &out_len);

    try std.testing.expectEqual(SEMANTOS_OK, rc);
    try std.testing.expect(out_len > 4); // Must have count + at least one proof

    // Verify count = 2 in wire format
    const count = std.mem.readInt(u32, out_proofs[0..4], .little);
    try std.testing.expectEqual(@as(u32, 2), count);

    // Clean up
    exports.semantos_free(out_proofs, out_len);
    _ = semantos_shutdown();
}

// ── T2: anchor_batch calls host_anchor_submit with correct state hash ──

test "30D T2: anchor_batch calls host_anchor_submit callback with correct state hash" {
    resetMockAnchorState();
    initKernel();
    registerWithAnchorCallback();

    const hash = "abc123def456abc123def456abc123def456abc123def456abc123def456abc1";
    const json = "[\"" ++ hash ++ "\"]";

    var out_proofs: [*]u8 = undefined;
    var out_len: usize = 0;
    const rc = semantos_anchor_batch(json.ptr, json.len, &out_proofs, &out_len);

    try std.testing.expectEqual(SEMANTOS_OK, rc);
    try std.testing.expectEqual(@as(usize, 1), mock_anchor_call_count);
    try std.testing.expectEqualSlices(u8, hash, mock_anchor_last_hash[0..mock_anchor_last_hash_len]);

    exports.semantos_free(out_proofs, out_len);
    _ = semantos_shutdown();
}

// ── T3: anchor_verify with valid proof returns 0 ──

test "30D T3: anchor_verify with valid proof returns 0" {
    const state_hash = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2";
    var proof_buf: [2048]u8 = undefined;
    const proof_json = buildValidProofJson(state_hash, &proof_buf);

    const rc = semantos_anchor_verify(proof_json.ptr, proof_json.len);
    try std.testing.expectEqual(SEMANTOS_OK, rc);
}

// ── T4: anchor_verify with tampered proof returns SEMANTOS_ERR_INVALID_PROOF ──

test "30D T4: anchor_verify with tampered proof returns SEMANTOS_ERR_INVALID_PROOF" {
    const state_hash = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2";
    var proof_buf: [2048]u8 = undefined;
    const proof_json = buildValidProofJson(state_hash, &proof_buf);

    // Tamper: corrupt the blockHash by changing a character
    // Find "blockHash" in the JSON and flip a digit
    var tampered: [2048]u8 = undefined;
    @memcpy(tampered[0..proof_json.len], proof_json);

    // Find blockHash value and tamper with the POW bytes (last chars before closing quote)
    // The blockHash ends with "...0000" — change the trailing zeros to break POW
    var i: usize = 0;
    while (i + 11 < proof_json.len) : (i += 1) {
        if (std.mem.eql(u8, tampered[i .. i + 11], "\"blockHash\"")) {
            // Skip to the value string, find the end, and tamper last bytes
            var j = i + 11;
            while (j < proof_json.len and tampered[j] != '"') : (j += 1) {}
            j += 1; // skip opening quote
            // Find end of hash string
            var k = j;
            while (k < proof_json.len and tampered[k] != '"') : (k += 1) {}
            // Tamper: change last 4 chars (00 00 → ff ff) to break POW
            if (k >= 4) {
                tampered[k - 1] = 'f';
                tampered[k - 2] = 'f';
                tampered[k - 3] = 'f';
                tampered[k - 4] = 'f';
            }
            break;
        }
    }

    const rc = semantos_anchor_verify(tampered[0..proof_json.len].ptr, proof_json.len);
    try std.testing.expectEqual(SEMANTOS_ERR_INVALID_PROOF, rc);
}

// ── T5: Batch of N hashes produces N individual proofs in output ──

test "30D T5: batch of N hashes produces N individual proofs in output" {
    resetMockAnchorState();
    initKernel();
    registerWithAnchorCallback();

    const json =
        "[\"a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1\"," ++
        "\"b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2\"," ++
        "\"c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3\"," ++
        "\"d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4\"," ++
        "\"e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5\"]";

    var out_proofs: [*]u8 = undefined;
    var out_len: usize = 0;
    const rc = semantos_anchor_batch(json.ptr, json.len, &out_proofs, &out_len);

    try std.testing.expectEqual(SEMANTOS_OK, rc);
    try std.testing.expectEqual(@as(usize, 5), mock_anchor_call_count);

    // Deserialise and verify count
    const count = std.mem.readInt(u32, out_proofs[0..4], .little);
    try std.testing.expectEqual(@as(u32, 5), count);

    // Walk the wire format and count individual proofs
    var offset: usize = 4;
    var proof_count: u32 = 0;
    while (proof_count < count) : (proof_count += 1) {
        const proof_len = std.mem.readInt(u32, out_proofs[offset..][0..4], .little);
        offset += 4 + proof_len;
    }
    try std.testing.expectEqual(@as(u32, 5), proof_count);
    try std.testing.expectEqual(out_len, offset); // consumed all bytes

    exports.semantos_free(out_proofs, out_len);
    _ = semantos_shutdown();
}

// ── T6: Empty batch returns success with empty proof array ──

test "30D T6: empty batch returns success with empty proof array" {
    resetMockAnchorState();
    initKernel();
    registerWithAnchorCallback();

    const json = "[]";

    var out_proofs: [*]u8 = undefined;
    var out_len: usize = 0;
    const rc = semantos_anchor_batch(json.ptr, json.len, &out_proofs, &out_len);

    try std.testing.expectEqual(SEMANTOS_OK, rc);
    // Output should be 4 bytes: count = 0
    try std.testing.expectEqual(@as(usize, 4), out_len);
    const count = std.mem.readInt(u32, out_proofs[0..4], .little);
    try std.testing.expectEqual(@as(u32, 0), count);
    try std.testing.expectEqual(@as(usize, 0), mock_anchor_call_count);

    exports.semantos_free(out_proofs, out_len);
    _ = semantos_shutdown();
}

// ── T7: anchor_batch with null callback returns error code ──

test "30D T7: anchor_batch with null callback registered returns error code" {
    resetMockAnchorState();
    initKernel();

    // Register callbacks but with null anchor_submit
    _ = semantos_register_callbacks(
        @ptrCast(&stub_storage_read),
        @ptrCast(&stub_storage_write),
        null,
        null,
        null, // anchor_submit is null
        null,
        null,
    );

    const json = "[\"a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2\"]";

    var out_proofs: [*]u8 = undefined;
    var out_len: usize = 0;
    const rc = semantos_anchor_batch(json.ptr, json.len, &out_proofs, &out_len);

    try std.testing.expectEqual(SEMANTOS_ERR_CALLBACK_NOT_REGISTERED, rc);
    try std.testing.expectEqual(@as(usize, 0), out_len);

    _ = semantos_shutdown();
}

// ── T8: Proof serialisation round-trip ──

test "30D T8: proof serialisation is deserializable (round-trip)" {
    const allocator = std.testing.allocator;

    // Build two valid proof JSONs
    const hash1 = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2";
    const hash2 = "b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3";
    var buf1: [2048]u8 = undefined;
    var buf2: [2048]u8 = undefined;
    const proof1 = buildValidProofJson(hash1, &buf1);
    const proof2 = buildValidProofJson(hash2, &buf2);

    const proofs = [_][]const u8{ proof1, proof2 };

    // Serialize
    const serialized = try exports.serializeProofs(allocator, &proofs);
    defer allocator.free(serialized);

    // Deserialize
    const deserialized = try exports.deserializeProofs(allocator, serialized);
    defer allocator.free(deserialized);

    try std.testing.expectEqual(@as(usize, 2), deserialized.len);
    try std.testing.expectEqualSlices(u8, proof1, deserialized[0]);
    try std.testing.expectEqualSlices(u8, proof2, deserialized[1]);

    // Re-serialize and compare byte-for-byte
    const reserialized = try exports.serializeProofs(allocator, deserialized);
    defer allocator.free(reserialized);

    try std.testing.expectEqualSlices(u8, serialized, reserialized);
}

```
