---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/extension_publish_stub.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.236165+00:00
---

# runtime/semantos-brain/src/extension_publish_stub.zig

```zig
// Phase D-W2 Phase 1 — extension_publish stub (built when bsvz is
// unavailable, mirroring refund_tx_stub.zig).
//
// Pure-Zig functions that don't touch bsvz (bundle hash, shard-group
// derivation, payload assembly, sign digest) ARE implemented here so
// the non-bsvz build path can still exercise them.  Tx
// construction + signing + ARC broadcast all return
// `error.bsvz_unavailable`.

const std = @import("std");

pub const PAYLOAD_VERSION_TAG: []const u8 = "extension-publish-v1";
pub const SHARD_GROUP_PREFIX: []const u8 = "extension-publish:";
pub const MAX_NAME_LEN: usize = 64;
pub const MAX_VERSION_LEN: usize = 32;
pub const PUBKEY_LEN: usize = 33;
pub const SIG_LEN: usize = 64;
pub const BUNDLE_HASH_LEN: usize = 32;
pub const SHARD_GROUP_ID_LEN: usize = 32;
pub const DEFAULT_ARC_URL: []const u8 = "https://arc.taal.com/v1/tx";

pub const PublishError = error{
    bsvz_unavailable,
    bad_priv_key,
    bad_pubkey,
    bad_locking_script,
    bad_change_address,
    bundle_open_failed,
    bundle_too_large,
    name_too_long,
    name_empty,
    version_too_long,
    version_empty,
    payload_too_large,
    sign_failed,
    serialize_failed,
    insufficient_funds,
    out_of_memory,
    broadcast_failed,
};

pub const VerifyError = error{ proof_mismatch, bad_signature };

pub const BundleManifest = struct {
    extension_name: []const u8,
    version: []const u8,
    bundle_path: []const u8,
    signer_priv: [32]u8,
};

pub const FundingUtxo = struct {
    txid: [32]u8,
    vout: u32,
    locking_script: []const u8,
    satoshis: u64,
};

pub const BuiltTx = struct {
    tx_bytes: []u8 = &.{},
    txid: [32]u8 = [_]u8{0} ** 32,
    op_return_payload: []u8 = &.{},
    change_satoshis: u64 = 0,
    fee_satoshis: u64 = 0,
};

pub fn freeBuiltTx(allocator: std.mem.Allocator, tx: BuiltTx) void {
    if (tx.tx_bytes.len > 0) allocator.free(tx.tx_bytes);
    if (tx.op_return_payload.len > 0) allocator.free(tx.op_return_payload);
}

pub const BroadcastOutcome = struct {
    ok: bool = false,
    detail: []u8 = &.{},
};

pub fn freeBroadcastOutcome(allocator: std.mem.Allocator, outcome: BroadcastOutcome) void {
    if (outcome.detail.len > 0) allocator.free(outcome.detail);
}

// ── Pure-Zig (no bsvz) primitives — reachable in stub mode too ──

pub fn computeBundleHash(allocator: std.mem.Allocator, bundle_path: []const u8) PublishError![32]u8 {
    _ = allocator;
    const f = std.fs.cwd().openFile(bundle_path, .{}) catch return error.bundle_open_failed;
    defer f.close();
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    var buf: [64 * 1024]u8 = undefined;
    while (true) {
        const n = f.read(&buf) catch return error.bundle_open_failed;
        if (n == 0) break;
        hasher.update(buf[0..n]);
    }
    var out: [32]u8 = undefined;
    hasher.final(&out);
    return out;
}

pub fn deriveShardGroupId(txid: [32]u8) [SHARD_GROUP_ID_LEN]u8 {
    var hex_buf: [64]u8 = undefined;
    const hex_chars = "0123456789abcdef";
    for (txid, 0..) |b, i| {
        hex_buf[i * 2] = hex_chars[(b >> 4) & 0x0f];
        hex_buf[i * 2 + 1] = hex_chars[b & 0x0f];
    }
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(SHARD_GROUP_PREFIX);
    hasher.update(&hex_buf);
    var out: [SHARD_GROUP_ID_LEN]u8 = undefined;
    hasher.final(&out);
    return out;
}

pub fn computeSignDigest(bundle_hash: [BUNDLE_HASH_LEN]u8, version: []const u8) [32]u8 {
    var first: [32]u8 = undefined;
    {
        var h = std.crypto.hash.sha2.Sha256.init(.{});
        h.update(&bundle_hash);
        h.update(version);
        h.final(&first);
    }
    var second: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(&first, &second, .{});
    return second;
}

pub fn assemblePayload(
    allocator: std.mem.Allocator,
    bundle_hash: [BUNDLE_HASH_LEN]u8,
    extension_name: []const u8,
    version: []const u8,
    signer_pubkey: [PUBKEY_LEN]u8,
    signature: [SIG_LEN]u8,
) PublishError![]u8 {
    if (extension_name.len == 0) return error.name_empty;
    if (extension_name.len > MAX_NAME_LEN) return error.name_too_long;
    if (version.len == 0) return error.version_empty;
    if (version.len > MAX_VERSION_LEN) return error.version_too_long;

    const total =
        PAYLOAD_VERSION_TAG.len +
        BUNDLE_HASH_LEN +
        1 + extension_name.len +
        1 + version.len +
        PUBKEY_LEN +
        SIG_LEN;
    if (total > 255) return error.payload_too_large;

    const buf = allocator.alloc(u8, total) catch return error.out_of_memory;
    var i: usize = 0;
    @memcpy(buf[i .. i + PAYLOAD_VERSION_TAG.len], PAYLOAD_VERSION_TAG);
    i += PAYLOAD_VERSION_TAG.len;
    @memcpy(buf[i .. i + BUNDLE_HASH_LEN], &bundle_hash);
    i += BUNDLE_HASH_LEN;
    buf[i] = @intCast(extension_name.len);
    i += 1;
    @memcpy(buf[i .. i + extension_name.len], extension_name);
    i += extension_name.len;
    buf[i] = @intCast(version.len);
    i += 1;
    @memcpy(buf[i .. i + version.len], version);
    i += version.len;
    @memcpy(buf[i .. i + PUBKEY_LEN], &signer_pubkey);
    i += PUBKEY_LEN;
    @memcpy(buf[i .. i + SIG_LEN], &signature);
    i += SIG_LEN;
    std.debug.assert(i == total);
    return buf;
}

pub fn hexEncode(bytes: []const u8, out: []u8) void {
    std.debug.assert(out.len == bytes.len * 2);
    const chars = "0123456789abcdef";
    for (bytes, 0..) |b, i| {
        out[i * 2] = chars[b >> 4];
        out[i * 2 + 1] = chars[b & 0x0f];
    }
}

// ── Stub-only entries (return bsvz_unavailable) ──

pub fn signOverBundle(
    signer_priv: [32]u8,
    bundle_hash: [BUNDLE_HASH_LEN]u8,
    version: []const u8,
) PublishError![SIG_LEN]u8 {
    _ = signer_priv;
    _ = bundle_hash;
    _ = version;
    return error.bsvz_unavailable;
}

pub fn verifySignature(
    signer_pubkey: [PUBKEY_LEN]u8,
    bundle_hash: [BUNDLE_HASH_LEN]u8,
    version: []const u8,
    signature: [SIG_LEN]u8,
) VerifyError!void {
    _ = signer_pubkey;
    _ = bundle_hash;
    _ = version;
    _ = signature;
    return error.bad_signature;
}

pub fn buildPublishTx(
    allocator: std.mem.Allocator,
    manifest: BundleManifest,
    bundle_hash: [BUNDLE_HASH_LEN]u8,
    utxo: FundingUtxo,
    change_address_text: []const u8,
    fee_sats_per_kb_opt: u64,
) PublishError!BuiltTx {
    _ = allocator;
    _ = manifest;
    _ = bundle_hash;
    _ = utxo;
    _ = change_address_text;
    _ = fee_sats_per_kb_opt;
    return error.bsvz_unavailable;
}

pub fn broadcastViaArc(
    allocator: std.mem.Allocator,
    tx_bytes: []const u8,
    arc_url_opt: ?[]const u8,
    api_key: ?[]const u8,
) PublishError!BroadcastOutcome {
    _ = allocator;
    _ = tx_bytes;
    _ = arc_url_opt;
    _ = api_key;
    return error.bsvz_unavailable;
}

```
