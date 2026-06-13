---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/extension_publish.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.222869+00:00
---

# runtime/semantos-brain/src/extension_publish.zig

```zig
// Phase D-W2 Phase 1 — Extension publish: bundle hash, OP_RETURN tx
// construction + signing, ARC broadcast, shard-group derivation.
//
// Reference: docs/design/BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md §5.1
//   (Publishing flow), §3 (shard_group derivation), §6 (frame types),
//   §7 Phase 1 (this deliverable).
//
// Cross-language seam:
//   • Zig (this file): bundle hash + tx construction + signing + ARC.
//   • TS (cartridges/oddjobz/brain/tools/publish-bundle.ts): shard-proxy
//     framing + UDP publish.  Lives in TS because the canonical
//     ShardProxyClient is in TS at core/protocol-types/src/overlay/.
//   `brain extension publish` (cli.zig) is the Zig entry point that
//   drives both halves: it does the chain side itself, then shells
//   out via `bun` to the TS helper for the shard-proxy push.
//
// OP_RETURN payload byte layout — pinned by tests:
//
//   ┌─────────────────────────────────────────────────────────────┐
//   │ extension-publish-v1                          (20 bytes)    │
//   │ bundle_hash                                   (32 bytes)    │
//   │ extension_name_len            u8              (1  byte)     │
//   │ extension_name                                (≤ 64 bytes)  │
//   │ version_len                   u8              (1  byte)     │
//   │ version                                       (≤ 32 bytes)  │
//   │ signer_pubkey                 SEC1 compressed (33 bytes)    │
//   │ signature                     compact r||s    (64 bytes)    │
//   └─────────────────────────────────────────────────────────────┘
//
// Total payload: 20 + 32 + 1 + |name| + 1 + |version| + 33 + 64
//   ≤ 20 + 32 + 1 + 64 + 1 + 32 + 33 + 64 = 247 bytes  (single PUSHDATA1
//   slot, prefix 0x4c + u8 length).
//
// Signature: ECDSA-SHA256 over the BSV-canonical sha256d of
// (bundle_hash || version), signed with the operator's secp256k1
// priv (the same `<data_dir>/operator-root-priv.hex` D-O5p / D-O10
// established).  We emit the 65-byte compact form bsvz produces and
// strip the 1-byte recovery prefix to land on the spec's 64-byte
// compact (r || s).  Verification round-trips by reconstructing all
// four candidate recovery bytes and asking bsvz which one recovers
// to the publisher's pubkey.
//
// shard_group_id derivation: `sha256("extension-publish:" || tx_id_hex)`
// per §3.  `tx_id_hex` is the display-order (block-explorer) hex of the
// publish-tx's txid.  Tests pin the byte derivation.

const std = @import("std");
const bsvz = @import("bsvz");

// ─────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────

pub const PAYLOAD_VERSION_TAG: []const u8 = "extension-publish-v1";
pub const SHARD_GROUP_PREFIX: []const u8 = "extension-publish:";
pub const MAX_NAME_LEN: usize = 64;
pub const MAX_VERSION_LEN: usize = 32;
pub const PUBKEY_LEN: usize = 33;
pub const SIG_LEN: usize = 64;
pub const BUNDLE_HASH_LEN: usize = 32;
pub const SHARD_GROUP_ID_LEN: usize = 32;

/// Default ARC endpoint — Taal's free public endpoint, same as
/// refund_tx.zig's documented default.
pub const DEFAULT_ARC_URL: []const u8 = "https://arc.taal.com/v1/tx";

// ─────────────────────────────────────────────────────────────────────
// Errors
// ─────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────────────

/// Manifest for one publish event.  Borrowed slices — caller owns
/// storage; the function does not retain references past return.
pub const BundleManifest = struct {
    extension_name: []const u8,
    version: []const u8,
    bundle_path: []const u8,
    signer_priv: [32]u8,
};

/// Caller-owned storage describing the funding UTXO — one input.  Kept
/// minimal at v0.1; future PR will add wallet-side selection.
pub const FundingUtxo = struct {
    /// txid in display (big-endian) order — same convention OutputStore
    /// + refund_tx use.
    txid: [32]u8,
    vout: u32,
    /// Raw P2PKH locking script bytes for the UTXO.  bsvz uses this
    /// during sigHash construction.
    locking_script: []const u8,
    satoshis: u64,
};

/// Output of buildPublishTx — caller frees `tx_bytes` and
/// `op_return_payload`.
pub const BuiltTx = struct {
    /// Raw signed transaction bytes (alloc-owned).
    tx_bytes: []u8,
    /// txid in display (big-endian) order — block-explorer convention.
    txid: [32]u8,
    /// The exact OP_RETURN payload (without the OP_RETURN/PUSHDATA
    /// prefix) — useful for tests + for the TS helper to embed in the
    /// extension-bundle frame so subscribers can SPV-cross-reference.
    op_return_payload: []u8,
    /// Net change satoshis paid to the operator's change address.
    change_satoshis: u64,
    /// Computed fee.
    fee_satoshis: u64,
};

pub fn freeBuiltTx(allocator: std.mem.Allocator, tx: BuiltTx) void {
    if (tx.tx_bytes.len > 0) allocator.free(tx.tx_bytes);
    if (tx.op_return_payload.len > 0) allocator.free(tx.op_return_payload);
}

pub const BroadcastOutcome = struct {
    ok: bool = false,
    /// Allocator-owned.  Either the txid hex (success) or the ARC error
    /// code (failure).  Caller frees.
    detail: []u8 = &.{},
};

pub fn freeBroadcastOutcome(allocator: std.mem.Allocator, outcome: BroadcastOutcome) void {
    if (outcome.detail.len > 0) allocator.free(outcome.detail);
}

// ─────────────────────────────────────────────────────────────────────
// Bundle hash
// ─────────────────────────────────────────────────────────────────────

/// SHA-256 of the file at `bundle_path`.  v0.1 treats the bundle as
/// whatever single file the operator points at — `.wasm`, `.tar.gz`,
/// etc.  Hash is over the bytes verbatim.
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

// ─────────────────────────────────────────────────────────────────────
// Shard-group derivation
// ─────────────────────────────────────────────────────────────────────

/// Derive the shard_group_id per §3:
///   shard_group_id = sha256("extension-publish:" || tx_id_hex_display)
///
/// `txid` is in display (big-endian) order.  We hex-encode it (lowercase)
/// and feed the concatenation through SHA-256.  Pure function — tests
/// pin the byte derivation against a fixture.
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

// ─────────────────────────────────────────────────────────────────────
// OP_RETURN payload assembly
// ─────────────────────────────────────────────────────────────────────

/// Compute the sha256d (BSV-canonical) digest the publisher signs.
///
/// digest = sha256(sha256(bundle_hash || version_bytes))
///
/// `version_bytes` is the version string as raw bytes (UTF-8), no
/// length prefix — the prefix exists in the OP_RETURN payload, not in
/// the signed message, since the signed digest is over the *content*
/// being committed (bundle hash + version), not the framing.
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

/// Assemble the OP_RETURN payload (without the OP_RETURN opcode + push
/// prefix — those go on top of this in `wrapPushdata1`).  Returns
/// alloc-owned bytes; caller frees.
///
/// Layout (byte-stable; tests pin):
///
///   PAYLOAD_VERSION_TAG (20)
///   bundle_hash         (32)
///   name_len             (1)
///   name                (n)
///   version_len          (1)
///   version             (v)
///   signer_pubkey       (33)
///   signature           (64)
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

/// Wrap a payload with `OP_RETURN || PUSHDATA1 || u8(len) || payload`.
/// Caller frees.  Used to construct the script body of output 1.
fn wrapPushdata1(allocator: std.mem.Allocator, payload: []const u8) PublishError![]u8 {
    if (payload.len > 255) return error.payload_too_large;
    const out = allocator.alloc(u8, 3 + payload.len) catch return error.out_of_memory;
    out[0] = 0x6a; // OP_RETURN
    out[1] = 0x4c; // OP_PUSHDATA1
    out[2] = @intCast(payload.len);
    @memcpy(out[3..], payload);
    return out;
}

// ─────────────────────────────────────────────────────────────────────
// Signing
// ─────────────────────────────────────────────────────────────────────

/// Sign `(bundle_hash || version)` per the spec.  Returns the 64-byte
/// compact (r || s) form — the bsvz-internal form is 65 bytes (1
/// recovery byte + r + s); we strip the recovery prefix.
///
/// Verification round-trip path is `verifySignature` below.
pub fn signOverBundle(
    signer_priv: [32]u8,
    bundle_hash: [BUNDLE_HASH_LEN]u8,
    version: []const u8,
) PublishError![SIG_LEN]u8 {
    const digest = computeSignDigest(bundle_hash, version);
    const priv = bsvz.primitives.ec.PrivateKey.fromBytes(signer_priv) catch return error.bad_priv_key;
    // is_compressed_key=true matches our 33-byte SEC1 emit path.
    const compact = priv.signCompact(digest, true) catch return error.sign_failed;
    var out: [SIG_LEN]u8 = undefined;
    @memcpy(&out, compact[1..65]);
    return out;
}

/// Verify the 64-byte compact signature against the publisher's pubkey
/// + `(bundle_hash || version)`.  Tries all four recovery bytes; if
/// any reproduces the expected pubkey, the sig is valid.  Returns
/// `error.proof_mismatch` on no match.
pub const VerifyError = error{ proof_mismatch, bad_signature };

pub fn verifySignature(
    signer_pubkey: [PUBKEY_LEN]u8,
    bundle_hash: [BUNDLE_HASH_LEN]u8,
    version: []const u8,
    signature: [SIG_LEN]u8,
) VerifyError!void {
    const digest = computeSignDigest(bundle_hash, version);
    // Reconstruct the 65-byte form by trying recovery bytes
    // 27..30 (uncompressed) and 31..34 (compressed).  bsvz's
    // `recoverCompactDigest256` interprets the prefix per
    // src/crypto/compact.zig; we sign with `is_compressed_key=true`
    // which lands in 31..34.
    var candidate: [65]u8 = undefined;
    @memcpy(candidate[1..65], &signature);
    var rec_byte: u8 = 31;
    while (rec_byte <= 34) : (rec_byte += 1) {
        candidate[0] = rec_byte;
        const recovered = bsvz.crypto.compact.recoverCompactDigest256(candidate, digest) catch continue;
        const recovered_sec1 = recovered.pubkey.toCompressedSec1();
        if (std.crypto.timing_safe.eql([PUBKEY_LEN]u8, recovered_sec1, signer_pubkey)) return;
    }
    // Try the uncompressed range too in case the priv was emitted that way.
    rec_byte = 27;
    while (rec_byte <= 30) : (rec_byte += 1) {
        candidate[0] = rec_byte;
        const recovered = bsvz.crypto.compact.recoverCompactDigest256(candidate, digest) catch continue;
        const recovered_sec1 = recovered.pubkey.toCompressedSec1();
        if (std.crypto.timing_safe.eql([PUBKEY_LEN]u8, recovered_sec1, signer_pubkey)) return;
    }
    return error.proof_mismatch;
}

// ─────────────────────────────────────────────────────────────────────
// Tx construction
// ─────────────────────────────────────────────────────────────────────

/// Construct + sign the publish transaction.
///
/// Output 0 — OP_RETURN payload (as documented above), 0 satoshis.
/// Output 1 — change to the operator's P2PKH address.
///
/// `change_address_text` is a base58check P2PKH address (mainnet).
/// `fee_sats_per_kb` defaults to 50 when 0 is passed.
///
/// Caller frees the returned BuiltTx via `freeBuiltTx`.
pub fn buildPublishTx(
    allocator: std.mem.Allocator,
    manifest: BundleManifest,
    bundle_hash: [BUNDLE_HASH_LEN]u8,
    utxo: FundingUtxo,
    change_address_text: []const u8,
    fee_sats_per_kb_opt: u64,
) PublishError!BuiltTx {
    const fee_sats_per_kb = if (fee_sats_per_kb_opt == 0) @as(u64, 50) else fee_sats_per_kb_opt;

    // 1. Derive signer pubkey from priv.  We use bsvz.crypto.PrivateKey
    // (= secp256k1.PrivateKey) directly here because the tx-builder's
    // signAllP2pkh expects this concrete type, not the primitives.ec
    // wrapper.  signOverBundle and verifySignature use the wrapper for
    // signCompact/recoverCompact convenience — both surfaces operate on
    // the same underlying scalar so the bytes round-trip.
    const priv_inner = bsvz.crypto.PrivateKey.fromBytes(manifest.signer_priv) catch return error.bad_priv_key;
    const pub_key = priv_inner.publicKey() catch return error.bad_priv_key;
    const signer_pubkey = pub_key.bytes;

    // 2. Sign over (bundle_hash || version).
    const signature = try signOverBundle(manifest.signer_priv, bundle_hash, manifest.version);

    // 3. Assemble OP_RETURN payload + script.
    const payload = try assemblePayload(
        allocator,
        bundle_hash,
        manifest.extension_name,
        manifest.version,
        signer_pubkey,
        signature,
    );
    errdefer allocator.free(payload);

    const op_return_script = wrapPushdata1(allocator, payload) catch |e| switch (e) {
        error.out_of_memory => return error.out_of_memory,
        else => return error.serialize_failed,
    };
    defer allocator.free(op_return_script);

    // 4. Build the tx.
    var builder = bsvz.transaction.Builder.init(allocator);
    defer builder.deinit();

    const input_outpoint: bsvz.transaction.OutPoint = .{
        .txid = .{ .bytes = utxo.txid },
        .index = utxo.vout,
    };
    // Pass a Script.init view (no alloc); addInput clones internally.
    const source_output = bsvz.transaction.Output{
        .satoshis = @intCast(utxo.satoshis),
        .locking_script = bsvz.script.Script.init(utxo.locking_script),
    };
    const input = bsvz.transaction.Input{
        .previous_outpoint = input_outpoint,
        .unlocking_script = bsvz.script.Script.empty(),
        .sequence = 0xffff_ffff,
        .source_output = source_output,
        .source_transaction = null,
    };
    builder.addInput(input) catch |err| switch (err) {
        error.OutOfMemory => return error.out_of_memory,
    };

    // Output 0 — OP_RETURN.  Manually construct since bsvz's op_return
    // template caps at 75 bytes (single-byte direct push) and our
    // payload exceeds that.  Pass a Script.init view (no alloc) so the
    // single Output.clone call inside addOutput is the only copy —
    // avoids the double-alloc-leak the manual clone would cause.
    const op_return_output = bsvz.transaction.Output{
        .satoshis = 0,
        .locking_script = bsvz.script.Script.init(op_return_script),
    };
    builder.addOutput(op_return_output) catch |err| switch (err) {
        error.OutOfMemory => return error.out_of_memory,
    };

    // Output 1 — change to the operator's address.
    builder.payToAddress(change_address_text, @intCast(utxo.satoshis)) catch |err| switch (err) {
        error.OutOfMemory => return error.out_of_memory,
        else => return error.bad_change_address,
    };
    // Mark the change output as `change=true` so applyFee deducts the
    // fee from it (Output 0 is a 0-sat OP_RETURN — no change there).
    builder.outputs.items[1].change = true;

    // 5. Apply fee.
    const fee_model = bsvz.transaction.fee_model.SatoshisPerKilobyte{ .satoshis = fee_sats_per_kb };
    builder.applyFee(fee_model, .equal) catch |err| switch (err) {
        error.OutOfMemory => return error.out_of_memory,
        error.Overflow => return error.insufficient_funds,
        else => return error.serialize_failed,
    };

    // 6. Sign all P2PKH inputs.
    const keys = [_]bsvz.crypto.PrivateKey{priv_inner};
    builder.signAllP2pkh(&keys) catch |err| switch (err) {
        error.OutOfMemory => return error.out_of_memory,
        else => return error.sign_failed,
    };

    // 7. Build + serialize.
    var tx = builder.build() catch |err| switch (err) {
        error.OutOfMemory => return error.out_of_memory,
    };
    defer tx.deinit(allocator);

    const raw = tx.serialize(allocator) catch return error.serialize_failed;
    errdefer allocator.free(raw);
    const txid_chain = tx.txid(allocator) catch return error.serialize_failed;
    const fee = bsvz.transaction.fees.getFee(&tx) catch utxo.satoshis;
    const change_sats = utxo.satoshis -| fee;

    return .{
        .tx_bytes = raw,
        .txid = txid_chain.bytes,
        .op_return_payload = payload,
        .change_satoshis = change_sats,
        .fee_satoshis = fee,
    };
}

// ─────────────────────────────────────────────────────────────────────
// ARC broadcast
// ─────────────────────────────────────────────────────────────────────

/// POST raw tx bytes to ARC.  Mirrors `refund_tx.broadcastViaArc`'s
/// shape; callers translate the BroadcastOutcome.detail string.  Pass
/// `null` for `arc_url` to use the default.
pub fn broadcastViaArc(
    allocator: std.mem.Allocator,
    tx_bytes: []const u8,
    arc_url_opt: ?[]const u8,
    api_key: ?[]const u8,
) PublishError!BroadcastOutcome {
    const arc_url = arc_url_opt orelse DEFAULT_ARC_URL;

    var tx = bsvz.transaction.Transaction.parse(allocator, tx_bytes) catch return error.broadcast_failed;
    defer tx.deinit(allocator);

    var arc: bsvz.broadcast.arc.Arc = .{
        .api_url = arc_url,
        .api_key = api_key orelse "",
    };
    var result = arc.broadcast(allocator, &tx) catch return error.broadcast_failed;
    defer result.deinit(allocator);

    return switch (result) {
        .ok => |s| .{
            .ok = true,
            .detail = allocator.dupe(u8, s.txid) catch return error.out_of_memory,
        },
        .err => |e| .{
            .ok = false,
            .detail = allocator.dupe(u8, e.code) catch return error.out_of_memory,
        },
    };
}

// ─────────────────────────────────────────────────────────────────────
// Hex helpers — local copies kept so this module stays self-contained.
// ─────────────────────────────────────────────────────────────────────

pub fn hexEncode(bytes: []const u8, out: []u8) void {
    std.debug.assert(out.len == bytes.len * 2);
    const chars = "0123456789abcdef";
    for (bytes, 0..) |b, i| {
        out[i * 2] = chars[b >> 4];
        out[i * 2 + 1] = chars[b & 0x0f];
    }
}

// ─────────────────────────────────────────────────────────────────────
// Inline tests — pure-logic only (no bsvz tx-builder).  Full tx-build
// + sig round-trip lives in tests/extension_publish_conformance.zig
// (gated on enable_wasmtime so the non-bsvz build path stays clean).
// ─────────────────────────────────────────────────────────────────────

test "deriveShardGroupId is byte-stable for a fixture txid" {
    const txid: [32]u8 = .{
        0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88,
        0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff, 0x00,
        0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
        0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10,
    };
    const id = deriveShardGroupId(txid);
    // Pinned digest: sha256("extension-publish:" ||
    //  "1122334455667788" ||
    //  "99aabbccddeeff00" ||
    //  "0102030405060708" ||
    //  "090a0b0c0d0e0f10")
    // Recomputed once + locked here for byte-stability.
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(SHARD_GROUP_PREFIX);
    var hex_buf: [64]u8 = undefined;
    hexEncode(&txid, &hex_buf);
    hasher.update(&hex_buf);
    var expected: [32]u8 = undefined;
    hasher.final(&expected);
    try std.testing.expectEqualSlices(u8, &expected, &id);
}

test "computeSignDigest is sha256d(bundle_hash || version)" {
    const bundle_hash: [BUNDLE_HASH_LEN]u8 = .{0xab} ** 32;
    const version = "0.1.0";
    const got = computeSignDigest(bundle_hash, version);

    var first: [32]u8 = undefined;
    {
        var h = std.crypto.hash.sha2.Sha256.init(.{});
        h.update(&bundle_hash);
        h.update(version);
        h.final(&first);
    }
    var expected: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(&first, &expected, .{});
    try std.testing.expectEqualSlices(u8, &expected, &got);
}

test "assemblePayload byte layout — pin against canonical fixture" {
    const allocator = std.testing.allocator;
    const bundle_hash: [BUNDLE_HASH_LEN]u8 = .{0x11} ** 32;
    const name = "oddjobz.invoicer";
    const version = "0.1.0";
    const signer_pubkey: [PUBKEY_LEN]u8 = .{0x02} ++ [_]u8{0xaa} ** 32;
    const signature: [SIG_LEN]u8 = .{0xcc} ** 64;

    const payload = try assemblePayload(allocator, bundle_hash, name, version, signer_pubkey, signature);
    defer allocator.free(payload);

    // Layout invariants:
    try std.testing.expectEqualSlices(u8, PAYLOAD_VERSION_TAG, payload[0..PAYLOAD_VERSION_TAG.len]);
    var off: usize = PAYLOAD_VERSION_TAG.len;
    try std.testing.expectEqualSlices(u8, &bundle_hash, payload[off .. off + BUNDLE_HASH_LEN]);
    off += BUNDLE_HASH_LEN;
    try std.testing.expectEqual(@as(u8, name.len), payload[off]);
    off += 1;
    try std.testing.expectEqualSlices(u8, name, payload[off .. off + name.len]);
    off += name.len;
    try std.testing.expectEqual(@as(u8, version.len), payload[off]);
    off += 1;
    try std.testing.expectEqualSlices(u8, version, payload[off .. off + version.len]);
    off += version.len;
    try std.testing.expectEqualSlices(u8, &signer_pubkey, payload[off .. off + PUBKEY_LEN]);
    off += PUBKEY_LEN;
    try std.testing.expectEqualSlices(u8, &signature, payload[off .. off + SIG_LEN]);
    off += SIG_LEN;
    try std.testing.expectEqual(payload.len, off);
}

test "assemblePayload rejects bad lengths" {
    const allocator = std.testing.allocator;
    const bh: [BUNDLE_HASH_LEN]u8 = .{0} ** 32;
    const sp: [PUBKEY_LEN]u8 = .{0} ** 33;
    const sg: [SIG_LEN]u8 = .{0} ** 64;

    // empty name
    try std.testing.expectError(
        error.name_empty,
        assemblePayload(allocator, bh, "", "0.1.0", sp, sg),
    );
    // empty version
    try std.testing.expectError(
        error.version_empty,
        assemblePayload(allocator, bh, "n", "", sp, sg),
    );
    // name too long
    const long_name = [_]u8{'x'} ** (MAX_NAME_LEN + 1);
    try std.testing.expectError(
        error.name_too_long,
        assemblePayload(allocator, bh, &long_name, "0.1.0", sp, sg),
    );
    // version too long
    const long_ver = [_]u8{'1'} ** (MAX_VERSION_LEN + 1);
    try std.testing.expectError(
        error.version_too_long,
        assemblePayload(allocator, bh, "n", &long_ver, sp, sg),
    );
}

test "computeBundleHash matches std.crypto for a temp file" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const f = try tmp.dir.createFile("bundle.bin", .{});
    const data = "the-bundle-bytes-v0.1";
    try f.writeAll(data);
    f.close();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try tmp.dir.realpath("bundle.bin", &path_buf);

    const got = try computeBundleHash(allocator, path);
    var expected: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(data, &expected, .{});
    try std.testing.expectEqualSlices(u8, &expected, &got);
}

test "BroadcastOutcome default is ok=false detail empty" {
    const o: BroadcastOutcome = .{};
    try std.testing.expect(!o.ok);
    try std.testing.expectEqual(@as(usize, 0), o.detail.len);
    freeBroadcastOutcome(std.testing.allocator, o);
}

```
