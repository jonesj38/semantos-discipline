---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/extension_nullifier.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.240525+00:00
---

# runtime/semantos-brain/src/extension_nullifier.zig

```zig
// Phase D-W2 Phase 3 — Extension nullifier: revoke-and-promote.
//
// Reference: docs/design/BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md
//   §4.2 (Nullifier Publication), §4.3 (Rotation Authority),
//   §6 (frame types — `nullifier`), §7 Phase 3 (this deliverable).
//
// Two halves:
//
//   • Half A — Publishing.  Operator builds + signs + broadcasts a
//     Plexus nullifier transaction whose OP_RETURN payload commits the
//     pubkey being revoked + (optionally) a replacement pubkey signed
//     by the rotation-authority key registered in the original
//     identity-registration's `recovery_enrolment_id`.  Atomic
//     revoke-and-promote when a replacement is included.
//
//   • Half B — Receiving.  Subscribers (every brain in the trusted-
//     signer's shard group) receive nullifier frames, verify the
//     §4.2-§4.3 invariants, then apply the atomic revoke (+ optional
//     promote) to the local manifest + a `revoked_keys` index.
//
// OP_RETURN payload byte layout — pinned by tests:
//
//   ┌─────────────────────────────────────────────────────────────┐
//   │ extension-nullifier-v1                        (22 bytes)    │
//   │ revoked_pubkey                SEC1 compressed (33 bytes)    │
//   │ reason_code                   u8              (1  byte)     │
//   │ timestamp                     u64-be          (8  bytes)    │
//   │ has_replacement               u8 (0|1)        (1  byte)     │
//   │ replacement_pubkey            SEC1 compressed (33 bytes; only│
//   │                                                when has=1)  │
//   │ rotation_authority_signature  compact r||s    (64 bytes; only│
//   │                                                when has=1)  │
//   └─────────────────────────────────────────────────────────────┘
//
//   Total payload:
//     pure-revocation: 22 + 33 + 1 + 8 + 1 = 65 bytes
//     rotation:        22 + 33 + 1 + 8 + 1 + 33 + 64 = 162 bytes
//   Both fit a single PUSHDATA1 slot (prefix 0x4c + u8 length).
//
// rotation_authority_signature: ECDSA-secp256k1 over compact-r||s
// (matches Phase 1's bundle-signing primitive).  The signed digest is
// sha256d(revoked_pubkey || replacement_pubkey || timestamp_be) — same
// double-hash convention Phase 1 uses for the (bundle_hash || version)
// digest.  Verified via the same recover-pubkey path as
// extension_publish.verifySignature.
//
// Replay protection: per the spec footer, the publish-tx-id is the
// natural replay key (same nullifier tx = same revocation; idempotent
// re-application).  applyNullifier is idempotent — re-applying the
// same revoked_pubkey is a no-op.

const std = @import("std");
const tenant_manifest = @import("tenant_manifest");
const ext_pub = @import("extension_publish");
const audit_log = @import("audit_log");
// D-W2 Phase 4 — the apply path drives bulk quarantine on every
// installed extension that belongs to the revoked signer.  See
// extension_quarantine.zig for the state model + transitions.
const quarantine_mod = @import("extension_quarantine");
const dispatcher_mod = @import("dispatcher");

// ─────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────

pub const PAYLOAD_VERSION_TAG: []const u8 = "extension-nullifier-v1";
pub const SHARD_GROUP_PREFIX: []const u8 = "extension-nullifier:";
pub const PUBKEY_LEN: usize = 33;
pub const SIG_LEN: usize = 64;
pub const TXID_LEN: usize = 32;

/// The hard maximum a payload can grow to (rotation case).  Pinned so
/// callers can reject oversized OP_RETURN reads before allocating.
pub const MAX_PAYLOAD_LEN: usize = PAYLOAD_VERSION_TAG.len + PUBKEY_LEN + 1 + 8 + 1 + PUBKEY_LEN + SIG_LEN;
/// The minimum a payload can be (pure-revocation case).
pub const MIN_PAYLOAD_LEN: usize = PAYLOAD_VERSION_TAG.len + PUBKEY_LEN + 1 + 8 + 1;

// ─────────────────────────────────────────────────────────────────────
// Errors
// ─────────────────────────────────────────────────────────────────────

pub const CodecError = error{
    payload_too_small,
    payload_too_large,
    payload_bad_tag,
    payload_truncated,
    payload_bad_reason_code,
    payload_bad_replacement_flag,
    out_of_memory,
};

pub const VerifyError = error{
    unknown_target_signer,
    bad_rotation_authority_signature,
    missing_replacement_for_rotation,
    missing_rotation_authority,
    out_of_memory,
};

pub const ApplyError = error{
    manifest_open_failed,
    manifest_read_failed,
    manifest_write_failed,
    manifest_signer_not_found,
    revoked_index_io_failed,
    bad_manifest_text,
    out_of_memory,
};

// ─────────────────────────────────────────────────────────────────────
// Reason codes
// ─────────────────────────────────────────────────────────────────────

/// The four reason codes from §4.2.  Wire byte:
///   0 = compromised
///   1 = superseded
///   2 = voluntary
///   3 = breach
/// Adding a new code is an additive wire change; subscribers tolerate
/// unknown codes by surfacing them as `payload_bad_reason_code` so a
/// forwards-incompat operator-side payload can't slip in unobserved.
pub const ReasonCode = enum(u8) {
    compromised = 0,
    superseded = 1,
    voluntary = 2,
    breach = 3,

    pub fn fromByte(b: u8) ?ReasonCode {
        return switch (b) {
            0 => .compromised,
            1 => .superseded,
            2 => .voluntary,
            3 => .breach,
            else => null,
        };
    }

    pub fn name(self: ReasonCode) []const u8 {
        return switch (self) {
            .compromised => "compromised",
            .superseded => "superseded",
            .voluntary => "voluntary",
            .breach => "breach",
        };
    }
};

pub fn parseReasonCode(s: []const u8) ?ReasonCode {
    if (std.mem.eql(u8, s, "compromised")) return .compromised;
    if (std.mem.eql(u8, s, "superseded")) return .superseded;
    if (std.mem.eql(u8, s, "voluntary")) return .voluntary;
    if (std.mem.eql(u8, s, "breach")) return .breach;
    return null;
}

// ─────────────────────────────────────────────────────────────────────
// Types
// ─────────────────────────────────────────────────────────────────────

pub const NullifierPayload = struct {
    revoked_pubkey: [PUBKEY_LEN]u8,
    reason_code: ReasonCode,
    /// Operator-supplied wall-clock seconds since UNIX epoch.  Carried
    /// big-endian in the OP_RETURN.  Used in the rotation-authority
    /// signed-message preimage so a replay of an old (revoked,
    /// replacement) pair against the same authority key is
    /// distinguishable from a fresh rotation.
    timestamp: u64,
    /// Empty-optional when this is a pure revocation.
    replacement_pubkey: ?[PUBKEY_LEN]u8 = null,
    /// Required when `replacement_pubkey` is non-null; absent
    /// otherwise.  ECDSA-secp256k1 compact-r||s over the digest
    /// `sha256d(revoked || replacement || timestamp_be)`.
    rotation_authority_signature: ?[SIG_LEN]u8 = null,

    pub fn isRotation(self: NullifierPayload) bool {
        return self.replacement_pubkey != null;
    }
};

/// What `verifyNullifier` returns when the §4.2-§4.3 invariants pass.
/// Carries the resolved trusted-signer entry (by name) so the apply
/// path can target the right manifest section.
pub const VerifiedNullifier = struct {
    payload: NullifierPayload,
    /// Manifest signer name (e.g. "platform", "acme_extensions") whose
    /// pubkey matched `payload.revoked_pubkey`.
    target_signer_name: []const u8,
    /// Hex-encoded rotation_authority pubkey actually consulted at
    /// verify time — surfaced for the audit log.  Empty when this is
    /// a pure revocation (no rotation authority needed).
    rotation_authority_label: []const u8 = "",
};

/// The lookup function the verifier consults to map a signer's
/// `recovery_enrolment_id` to the SEC1-compressed pubkey of the
/// rotation authority on-chain.  In production this consults the
/// Plexus identity-registration registry (the same table Phase 1
/// uses for `plexus_identity_tx`); in tests we plug a stub.
///
/// Returns null if the recovery_enrolment_id is unknown (verifier
/// translates that to `missing_rotation_authority`).
pub const RecoveryAuthorityLookup = struct {
    state: ?*anyopaque,
    lookup_fn: *const fn (state: ?*anyopaque, recovery_enrolment_id: []const u8) ?[PUBKEY_LEN]u8,

    pub fn lookup(self: RecoveryAuthorityLookup, recovery_enrolment_id: []const u8) ?[PUBKEY_LEN]u8 {
        return self.lookup_fn(self.state, recovery_enrolment_id);
    }
};

// ─────────────────────────────────────────────────────────────────────
// Codec
// ─────────────────────────────────────────────────────────────────────

fn writeU64Be(buf: *[8]u8, v: u64) void {
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        buf[i] = @intCast((v >> @intCast(8 * (7 - i))) & 0xff);
    }
}

fn readU64Be(bytes: *const [8]u8) u64 {
    var v: u64 = 0;
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        v = (v << 8) | @as(u64, bytes[i]);
    }
    return v;
}

/// Encode a NullifierPayload as the §4.2-§4.3 wire layout.  Caller
/// frees the returned slice.
pub fn encodeNullifierPayload(
    allocator: std.mem.Allocator,
    p: NullifierPayload,
) CodecError![]u8 {
    const has_replacement = p.replacement_pubkey != null;
    if (has_replacement and p.rotation_authority_signature == null) {
        // Same-shape error: the encoder rejects malformed input
        // upfront.  Decoder mirrors with payload_bad_replacement_flag.
        return error.payload_bad_replacement_flag;
    }
    const total: usize = if (has_replacement) MAX_PAYLOAD_LEN else MIN_PAYLOAD_LEN;
    const buf = allocator.alloc(u8, total) catch return error.out_of_memory;
    errdefer allocator.free(buf);

    var i: usize = 0;
    @memcpy(buf[i .. i + PAYLOAD_VERSION_TAG.len], PAYLOAD_VERSION_TAG);
    i += PAYLOAD_VERSION_TAG.len;
    @memcpy(buf[i .. i + PUBKEY_LEN], &p.revoked_pubkey);
    i += PUBKEY_LEN;
    buf[i] = @intFromEnum(p.reason_code);
    i += 1;
    var ts_buf: [8]u8 = undefined;
    writeU64Be(&ts_buf, p.timestamp);
    @memcpy(buf[i .. i + 8], &ts_buf);
    i += 8;
    buf[i] = if (has_replacement) 1 else 0;
    i += 1;
    if (has_replacement) {
        @memcpy(buf[i .. i + PUBKEY_LEN], &p.replacement_pubkey.?);
        i += PUBKEY_LEN;
        @memcpy(buf[i .. i + SIG_LEN], &p.rotation_authority_signature.?);
        i += SIG_LEN;
    }
    std.debug.assert(i == total);
    return buf;
}

/// Decode a NullifierPayload from the §4.2-§4.3 wire layout.
pub fn decodeNullifierPayload(
    allocator: std.mem.Allocator,
    bytes: []const u8,
) CodecError!NullifierPayload {
    _ = allocator;
    if (bytes.len < MIN_PAYLOAD_LEN) return error.payload_too_small;
    if (bytes.len > MAX_PAYLOAD_LEN) return error.payload_too_large;

    var off: usize = 0;
    if (!std.mem.eql(u8, bytes[off .. off + PAYLOAD_VERSION_TAG.len], PAYLOAD_VERSION_TAG)) {
        return error.payload_bad_tag;
    }
    off += PAYLOAD_VERSION_TAG.len;

    var revoked: [PUBKEY_LEN]u8 = undefined;
    @memcpy(&revoked, bytes[off .. off + PUBKEY_LEN]);
    off += PUBKEY_LEN;

    const reason = ReasonCode.fromByte(bytes[off]) orelse return error.payload_bad_reason_code;
    off += 1;

    var ts_buf: [8]u8 = undefined;
    @memcpy(&ts_buf, bytes[off .. off + 8]);
    const ts = readU64Be(&ts_buf);
    off += 8;

    const has = bytes[off];
    if (has != 0 and has != 1) return error.payload_bad_replacement_flag;
    off += 1;

    if (has == 0) {
        // Pure revocation — payload should be exactly MIN_PAYLOAD_LEN.
        if (bytes.len != MIN_PAYLOAD_LEN) return error.payload_truncated;
        return .{
            .revoked_pubkey = revoked,
            .reason_code = reason,
            .timestamp = ts,
        };
    }

    // Rotation — payload should be exactly MAX_PAYLOAD_LEN.
    if (bytes.len != MAX_PAYLOAD_LEN) return error.payload_truncated;
    var replacement: [PUBKEY_LEN]u8 = undefined;
    @memcpy(&replacement, bytes[off .. off + PUBKEY_LEN]);
    off += PUBKEY_LEN;
    var sig: [SIG_LEN]u8 = undefined;
    @memcpy(&sig, bytes[off .. off + SIG_LEN]);
    off += SIG_LEN;
    std.debug.assert(off == bytes.len);

    return .{
        .revoked_pubkey = revoked,
        .reason_code = reason,
        .timestamp = ts,
        .replacement_pubkey = replacement,
        .rotation_authority_signature = sig,
    };
}

// ─────────────────────────────────────────────────────────────────────
// Rotation-authority signing
// ─────────────────────────────────────────────────────────────────────

/// The signed-message digest for the rotation-authority signature.
/// `sha256d(revoked || replacement || timestamp_be)`.
///
/// Pure function; tests pin the bytes against a fixture.
pub fn rotationAuthoritySignDigest(
    revoked: [PUBKEY_LEN]u8,
    replacement: [PUBKEY_LEN]u8,
    timestamp: u64,
) [32]u8 {
    var ts_buf: [8]u8 = undefined;
    writeU64Be(&ts_buf, timestamp);
    var first: [32]u8 = undefined;
    {
        var h = std.crypto.hash.sha2.Sha256.init(.{});
        h.update(&revoked);
        h.update(&replacement);
        h.update(&ts_buf);
        h.final(&first);
    }
    var second: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(&first, &second, .{});
    return second;
}

const bsvz = @import("bsvz");

/// Sign the rotation-authority preimage with `authority_priv`.
/// Returns the 64-byte compact (r||s) form — same primitive Phase 1
/// uses for bundle signing.
pub fn signRotationAuthority(
    authority_priv: [32]u8,
    revoked: [PUBKEY_LEN]u8,
    replacement: [PUBKEY_LEN]u8,
    timestamp: u64,
) ext_pub.PublishError![SIG_LEN]u8 {
    const digest = rotationAuthoritySignDigest(revoked, replacement, timestamp);
    const priv = bsvz.primitives.ec.PrivateKey.fromBytes(authority_priv) catch return error.bad_priv_key;
    const compact = priv.signCompact(digest, true) catch return error.sign_failed;
    var out: [SIG_LEN]u8 = undefined;
    @memcpy(&out, compact[1..65]);
    return out;
}

/// Verify the rotation-authority signature against the registered
/// authority pubkey.  Tries all four recovery bytes; if any
/// reproduces the expected pubkey, the sig is valid.
pub fn verifyRotationAuthoritySignature(
    authority_pubkey: [PUBKEY_LEN]u8,
    revoked: [PUBKEY_LEN]u8,
    replacement: [PUBKEY_LEN]u8,
    timestamp: u64,
    signature: [SIG_LEN]u8,
) VerifyError!void {
    const digest = rotationAuthoritySignDigest(revoked, replacement, timestamp);
    var candidate: [65]u8 = undefined;
    @memcpy(candidate[1..65], &signature);
    var rec_byte: u8 = 31;
    while (rec_byte <= 34) : (rec_byte += 1) {
        candidate[0] = rec_byte;
        if (recoverPubkey(candidate, digest)) |recovered| {
            if (std.crypto.timing_safe.eql([PUBKEY_LEN]u8, recovered, authority_pubkey)) return;
        }
    }
    rec_byte = 27;
    while (rec_byte <= 30) : (rec_byte += 1) {
        candidate[0] = rec_byte;
        if (recoverPubkey(candidate, digest)) |recovered| {
            if (std.crypto.timing_safe.eql([PUBKEY_LEN]u8, recovered, authority_pubkey)) return;
        }
    }
    return error.bad_rotation_authority_signature;
}

fn recoverPubkey(candidate: [65]u8, digest: [32]u8) ?[PUBKEY_LEN]u8 {
    const recovered = bsvz.crypto.compact.recoverCompactDigest256(candidate, digest) catch return null;
    return recovered.pubkey.toCompressedSec1();
}

// ─────────────────────────────────────────────────────────────────────
// Tx construction
// ─────────────────────────────────────────────────────────────────────
//
// Mirrors `extension_publish.buildPublishTx` shape: 1 input → 2
// outputs (OP_RETURN with the nullifier payload + change to the
// signer).  Caller passes the funding UTXO + change address.
//
// The nullifier payload is wrapped in OP_RETURN || OP_PUSHDATA1 ||
// u8(len) || payload — same wrapping as the publish-tx OP_RETURN.
// The pure-revocation payload (65 bytes) and the rotation payload
// (162 bytes) both fit a single PUSHDATA1 slot.

pub const FundingUtxo = ext_pub.FundingUtxo;
pub const BuiltTx = ext_pub.BuiltTx;
pub const freeBuiltTx = ext_pub.freeBuiltTx;
pub const BroadcastOutcome = ext_pub.BroadcastOutcome;
pub const freeBroadcastOutcome = ext_pub.freeBroadcastOutcome;
pub const broadcastViaArc = ext_pub.broadcastViaArc;
pub const DEFAULT_ARC_URL = ext_pub.DEFAULT_ARC_URL;

fn wrapPushdata1(allocator: std.mem.Allocator, payload: []const u8) ext_pub.PublishError![]u8 {
    if (payload.len > 255) return error.payload_too_large;
    const out = allocator.alloc(u8, 3 + payload.len) catch return error.out_of_memory;
    out[0] = 0x6a; // OP_RETURN
    out[1] = 0x4c; // OP_PUSHDATA1
    out[2] = @intCast(payload.len);
    @memcpy(out[3..], payload);
    return out;
}

/// Construct + sign a Plexus nullifier transaction.
///
/// Output 0 — OP_RETURN with the encoded nullifier payload, 0 sats.
/// Output 1 — change to `change_address_text`.
///
/// `signer_priv` funds the tx (the operator's UTXO).  For pure
/// revocation, this can be the operator's root key; for rotation,
/// either the rotation-authority key (typical operator workflow —
/// the rotation-authority key can also fund the tx) or any
/// adequately-funded operator UTXO.  The funding key has no
/// cryptographic relationship with the rotation-authority signature
/// inside the OP_RETURN — they're separate.
///
/// Returns BuiltTx; caller frees via `freeBuiltTx`.
pub fn buildNullifierTx(
    allocator: std.mem.Allocator,
    payload: NullifierPayload,
    signer_priv: [32]u8,
    utxo: FundingUtxo,
    change_address_text: []const u8,
    fee_sats_per_kb_opt: u64,
) ext_pub.PublishError!BuiltTx {
    const fee_sats_per_kb = if (fee_sats_per_kb_opt == 0) @as(u64, 50) else fee_sats_per_kb_opt;

    const op_return_payload = encodeNullifierPayload(allocator, payload) catch |e| switch (e) {
        error.out_of_memory => return error.out_of_memory,
        else => return error.serialize_failed,
    };
    errdefer allocator.free(op_return_payload);

    const op_return_script = try wrapPushdata1(allocator, op_return_payload);
    defer allocator.free(op_return_script);

    const priv_inner = bsvz.crypto.PrivateKey.fromBytes(signer_priv) catch return error.bad_priv_key;

    var builder = bsvz.transaction.Builder.init(allocator);
    defer builder.deinit();

    const input_outpoint: bsvz.transaction.OutPoint = .{
        .txid = .{ .bytes = utxo.txid },
        .index = utxo.vout,
    };
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

    const op_return_output = bsvz.transaction.Output{
        .satoshis = 0,
        .locking_script = bsvz.script.Script.init(op_return_script),
    };
    builder.addOutput(op_return_output) catch |err| switch (err) {
        error.OutOfMemory => return error.out_of_memory,
    };

    builder.payToAddress(change_address_text, @intCast(utxo.satoshis)) catch |err| switch (err) {
        error.OutOfMemory => return error.out_of_memory,
        else => return error.bad_change_address,
    };
    builder.outputs.items[1].change = true;

    const fee_model = bsvz.transaction.fee_model.SatoshisPerKilobyte{ .satoshis = fee_sats_per_kb };
    builder.applyFee(fee_model, .equal) catch |err| switch (err) {
        error.OutOfMemory => return error.out_of_memory,
        error.Overflow => return error.insufficient_funds,
        else => return error.serialize_failed,
    };

    const keys = [_]bsvz.crypto.PrivateKey{priv_inner};
    builder.signAllP2pkh(&keys) catch |err| switch (err) {
        error.OutOfMemory => return error.out_of_memory,
        else => return error.sign_failed,
    };

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
        .op_return_payload = op_return_payload,
        .change_satoshis = change_sats,
        .fee_satoshis = fee,
    };
}

// ─────────────────────────────────────────────────────────────────────
// Top-level verify
// ─────────────────────────────────────────────────────────────────────

/// Run the §4.2-§4.3 invariants:
///
///   1. The revoked_pubkey targets a known trusted-signer in the
///      manifest.  Otherwise → `unknown_target_signer`.
///   2. For rotation: the rotation_authority_signature MUST validate
///      against the pubkey resolved by `recovery_authority_lookup`
///      from the targeted signer's `recovery_enrolment_id`.
///      Otherwise → `bad_rotation_authority_signature` /
///      `missing_rotation_authority` / `missing_replacement_for_rotation`.
///   3. Pure revocations skip the rotation-authority check (no
///      replacement key to authorise).
///
/// Returns a VerifiedNullifier on success.
pub fn verifyNullifier(
    payload: NullifierPayload,
    manifest_signers: []const tenant_manifest.TrustedSigner,
    recovery_authority: RecoveryAuthorityLookup,
) VerifyError!VerifiedNullifier {
    // 1. Find the signer whose pubkey matches the revoked pubkey.
    const target_signer = findSignerByPubkey(manifest_signers, payload.revoked_pubkey) orelse
        return error.unknown_target_signer;

    // 2. Pure-revocation short-circuit.
    if (payload.replacement_pubkey == null) {
        // The codec layer enforces "rotation flag ⇒ both replacement +
        // sig present"; here we re-check the consistency at the
        // semantic layer.
        if (payload.rotation_authority_signature != null) {
            // A signature without a replacement pubkey is malformed.
            return error.missing_replacement_for_rotation;
        }
        return .{
            .payload = payload,
            .target_signer_name = target_signer.name,
        };
    }

    // 3. Rotation — the signature is required + must verify.
    const sig = payload.rotation_authority_signature orelse
        return error.missing_replacement_for_rotation;

    if (target_signer.recovery_enrolment_id.len == 0) {
        // The signer didn't register a rotation authority — rotation
        // is impossible (only pure revocation).  Treat as a
        // configuration error so the operator sees a clear surface.
        return error.missing_rotation_authority;
    }

    const authority_pubkey = recovery_authority.lookup(target_signer.recovery_enrolment_id) orelse
        return error.missing_rotation_authority;

    try verifyRotationAuthoritySignature(
        authority_pubkey,
        payload.revoked_pubkey,
        payload.replacement_pubkey.?,
        payload.timestamp,
        sig,
    );

    return .{
        .payload = payload,
        .target_signer_name = target_signer.name,
        .rotation_authority_label = target_signer.recovery_enrolment_id,
    };
}

fn findSignerByPubkey(
    signers: []const tenant_manifest.TrustedSigner,
    pubkey: [PUBKEY_LEN]u8,
) ?tenant_manifest.TrustedSigner {
    for (signers) |s| {
        const sp = parseHexPubkey(s.pubkey_hex) catch continue;
        if (std.mem.eql(u8, &sp, &pubkey)) return s;
    }
    return null;
}

fn parseHexPubkey(hex: []const u8) !([PUBKEY_LEN]u8) {
    if (hex.len != PUBKEY_LEN * 2) return error.bad_pubkey_hex;
    var out: [PUBKEY_LEN]u8 = undefined;
    var i: usize = 0;
    while (i < PUBKEY_LEN) : (i += 1) {
        const hi = hexNibble(hex[i * 2]) orelse return error.bad_pubkey_hex;
        const lo = hexNibble(hex[i * 2 + 1]) orelse return error.bad_pubkey_hex;
        out[i] = (hi << 4) | lo;
    }
    return out;
}

fn hexNibble(c: u8) ?u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => null,
    };
}

fn hexEncode(bytes: []const u8, out: []u8) void {
    std.debug.assert(out.len == bytes.len * 2);
    const chars = "0123456789abcdef";
    for (bytes, 0..) |b, i| {
        out[i * 2] = chars[b >> 4];
        out[i * 2 + 1] = chars[b & 0x0f];
    }
}

// ─────────────────────────────────────────────────────────────────────
// Apply
// ─────────────────────────────────────────────────────────────────────

pub const ApplyMode = enum {
    /// `applyNullifier` actually rewrote the manifest + appended to
    /// the revoked-keys index.
    applied,
    /// The nullifier had already been applied (revoked pubkey already
    /// in the revoked-keys index, or — for rotation — the signer's
    /// pubkey already matches the replacement).  No-op; idempotent.
    already_applied,
};

pub const ApplyOutcome = struct {
    mode: ApplyMode,
    /// True for rotation; false for pure revocation.
    promoted_replacement: bool,
    /// The signer's name in the manifest.  Borrowed.
    signer_name: []const u8,
    /// New manifest text written to disk on `applied`; empty otherwise.
    /// Caller frees with `allocator.free` when non-empty.
    new_manifest_text: []u8 = &.{},
    /// D-W2 Phase 4 — count of extensions transitioned to
    /// quarantine (or hard-removed when `quarantine_on_revoke =
    /// false`) by the post-mutation hook.  Zero unless the caller
    /// invoked `applyNullifierWithQuarantine`.
    quarantined: u32 = 0,

    pub fn deinit(self: *ApplyOutcome, allocator: std.mem.Allocator) void {
        if (self.new_manifest_text.len > 0) {
            allocator.free(self.new_manifest_text);
            self.new_manifest_text = &.{};
        }
    }
};

/// Apply a verified nullifier to the local state:
///
///   1. Append the revoked_pubkey to the revoked-keys index at
///      `revoked_keys_index_path`.  File format is JSON-lines (one
///      `{"pubkey":"...","reason":"...","timestamp":N,"signer":"..."}`
///      per line).  Idempotent — same pubkey twice = no-op.
///   2. Atomic in-place rewrite of the manifest text:
///      - Pure revocation: removes the `[trusted_signers.<name>]`
///        section + appends a comment recording the revocation.
///      - Rotation: rewrites the section's `pubkey = "..."` line to
///        the replacement pubkey (hex-encoded compressed-SEC1) +
///        appends a `previous_pubkey_chain = [...]` line carrying the
///        old pubkey hex (extending an existing chain when present).
///   3. Returns ApplyOutcome describing what changed.
///
/// For v0.1 we take the simplest robust approach: read the manifest
/// file as text, perform a section-aware text mutation, write the
/// result back atomically (via a tmp file + rename).  The structured
/// parser stays out of the loop — this avoids round-trip data loss
/// for fields the parser doesn't model (e.g. comments).
pub fn applyNullifier(
    allocator: std.mem.Allocator,
    vn: VerifiedNullifier,
    manifest_path: []const u8,
    revoked_keys_index_path: []const u8,
    audit: ?*audit_log.AuditLog,
) ApplyError!ApplyOutcome {
    // 1. Idempotence check via the revoked-keys index.
    const already = try revokedKeysIndexContains(allocator, revoked_keys_index_path, vn.payload.revoked_pubkey);
    if (already) {
        if (audit) |a| {
            var detail_buf: [256]u8 = undefined;
            const detail = std.fmt.bufPrint(
                &detail_buf,
                "phase=apply_skip kind=idempotent signer={s} reason={s}",
                .{ vn.target_signer_name, vn.payload.reason_code.name() },
            ) catch detail_buf[0..0];
            a.record(allocator, .{
                .module = "extension_nullifier",
                .op = "extension.nullifier_apply",
                .result = .ok,
                .detail = detail,
            }) catch {};
        }
        return .{
            .mode = .already_applied,
            .promoted_replacement = false,
            .signer_name = vn.target_signer_name,
        };
    }

    // 2. Read the current manifest text.
    const manifest_text = readFileAlloc(allocator, manifest_path, 256 * 1024) catch
        return error.manifest_open_failed;
    defer allocator.free(manifest_text);

    // 3. Rewrite according to the operation kind.
    const rewrite = if (vn.payload.replacement_pubkey) |rp|
        rewriteForRotation(allocator, manifest_text, vn.target_signer_name, rp) catch |e| return mapRewriteErr(e)
    else
        rewriteForRevocation(allocator, manifest_text, vn.target_signer_name) catch |e| return mapRewriteErr(e);
    errdefer allocator.free(rewrite);

    // 4. Atomic write — tmp + rename.
    try writeFileAtomic(allocator, manifest_path, rewrite);

    // 5. Append to revoked-keys index.
    try appendRevokedKey(allocator, revoked_keys_index_path, vn);

    // 6. Audit.
    if (audit) |a| {
        var detail_buf: [256]u8 = undefined;
        const detail = std.fmt.bufPrint(
            &detail_buf,
            "phase=apply mode={s} signer={s} reason={s} ts={d}",
            .{
                if (vn.payload.replacement_pubkey != null) "rotation" else "revocation",
                vn.target_signer_name,
                vn.payload.reason_code.name(),
                vn.payload.timestamp,
            },
        ) catch detail_buf[0..0];
        a.record(allocator, .{
            .module = "extension_nullifier",
            .op = "extension.nullifier_apply",
            .result = .ok,
            .detail = detail,
        }) catch {};
        // Per §A nuance: pure revocation of the platform tier logs a
        // CRITICAL audit warning.  The on-chain nullifier is the
        // legitimate path (the operator's own rotation authority must
        // have signed it; the manifest validator's CHECK ON OPERATOR-
        // EDIT path that refuses platform-tier drops is for hand-
        // edits, NOT chain-published nullifiers).
        if (std.mem.eql(u8, vn.target_signer_name, "platform")) {
            var crit_buf: [256]u8 = undefined;
            const crit = std.fmt.bufPrint(
                &crit_buf,
                "phase=critical kind=platform_tier_revocation signer=platform reason={s} replacement_present={s}",
                .{
                    vn.payload.reason_code.name(),
                    if (vn.payload.replacement_pubkey != null) "true" else "false",
                },
            ) catch crit_buf[0..0];
            a.record(allocator, .{
                .module = "extension_nullifier",
                .op = "extension.platform_tier_revoked",
                .result = .denied,
                .detail = crit,
            }) catch {};
        }
    }

    return .{
        .mode = .applied,
        .promoted_replacement = vn.payload.replacement_pubkey != null,
        .signer_name = vn.target_signer_name,
        .new_manifest_text = rewrite,
    };
}

/// D-W2 Phase 4 — apply with the post-mutation quarantine hook.
///
/// Wraps `applyNullifier`, then walks `<data_dir>/extensions/` and
/// transitions every install whose `meta.json.signer_pubkey` matches
/// the revoked pubkey.  Behaviour gated on `quarantine_on_revoke`:
///
///   • `true` (default per §3): each affected install transitions
///     `active → quarantined`.  Bundle bytes preserved.  Dispatcher
///     marks the handler quarantined; subsequent dispatch calls
///     return `error.handler_quarantined`.
///
///   • `false`: each affected install is hard-removed (bundle file
///     deleted; dispatcher entry unmarked; `removed` record appended
///     to the index).  Reserved for paranoid deployments per the
///     §10 risks tradeoff.
///
/// Returns the same ApplyOutcome with `quarantined` populated.
/// `already_applied` short-circuits BEFORE the quarantine walk —
/// idempotent re-application doesn't re-quarantine (the install was
/// already quarantined on the first apply).
pub fn applyNullifierWithQuarantine(
    allocator: std.mem.Allocator,
    vn: VerifiedNullifier,
    manifest_path: []const u8,
    revoked_keys_index_path: []const u8,
    data_dir: []const u8,
    dispatcher: ?*dispatcher_mod.Dispatcher,
    quarantine_on_revoke: bool,
    audit: ?*audit_log.AuditLog,
) ApplyError!ApplyOutcome {
    var outcome = try applyNullifier(allocator, vn, manifest_path, revoked_keys_index_path, audit);
    if (outcome.mode == .already_applied) return outcome;

    // Hex-encode the revoked pubkey for the meta.json comparison.
    var revoked_hex: [PUBKEY_LEN * 2]u8 = undefined;
    hexEncode(&vn.payload.revoked_pubkey, &revoked_hex);

    const affected = quarantine_mod.quarantineExtensionsBySigner(
        allocator,
        data_dir,
        &revoked_hex,
        vn.target_signer_name,
        quarantine_on_revoke,
        dispatcher,
        audit,
    ) catch |err| switch (err) {
        // The quarantine walk is best-effort — a failure here
        // shouldn't roll back the manifest mutation (which is
        // already on disk).  Audit-log + return outcome with
        // quarantined=0.
        else => {
            if (audit) |a| {
                var detail_buf: [256]u8 = undefined;
                const detail = std.fmt.bufPrint(
                    &detail_buf,
                    "phase=apply_quarantine_warn signer={s} err={s}",
                    .{ vn.target_signer_name, @errorName(err) },
                ) catch detail_buf[0..0];
                a.record(allocator, .{
                    .module = "extension_nullifier",
                    .op = "extension.quarantine_walk",
                    .result = .err,
                    .detail = detail,
                }) catch {};
            }
            return outcome;
        },
    };

    outcome.quarantined = affected;

    // Audit the count.
    if (audit) |a| {
        var detail_buf: [256]u8 = undefined;
        const detail = std.fmt.bufPrint(
            &detail_buf,
            "phase=apply_quarantine signer={s} affected={d} mode={s}",
            .{
                vn.target_signer_name,
                affected,
                if (quarantine_on_revoke) "quarantine" else "hard_remove",
            },
        ) catch detail_buf[0..0];
        a.record(allocator, .{
            .module = "extension_nullifier",
            .op = "extension.quarantine_walk",
            .result = .ok,
            .detail = detail,
        }) catch {};
    }

    return outcome;
}

fn mapRewriteErr(e: anyerror) ApplyError {
    return switch (e) {
        error.signer_not_found => error.manifest_signer_not_found,
        error.bad_manifest_text => error.bad_manifest_text,
        error.OutOfMemory => error.out_of_memory,
        else => error.bad_manifest_text,
    };
}

const RewriteError = error{
    signer_not_found,
    bad_manifest_text,
    OutOfMemory,
};

/// Manifest text mutation — pure revocation.
///
/// Locates the `[trusted_signers.<name>]` header and removes the entire
/// section (header + the consecutive non-blank, non-section-header
/// lines that follow).  Appends a `# revoked: trusted_signers.<name>`
/// audit comment at the bottom of the file so the on-disk file
/// preserves a trail.
fn rewriteForRevocation(
    allocator: std.mem.Allocator,
    text: []const u8,
    signer_name: []const u8,
) RewriteError![]u8 {
    const section = try findSignerSection(text, signer_name);
    if (section == null) return error.signer_not_found;
    const range = section.?;

    // Build the result: prefix + suffix + comment.
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(allocator);

    try buf.appendSlice(allocator, text[0..range.start]);
    try buf.appendSlice(allocator, text[range.end..]);

    // Trim trailing whitespace, then append the comment.
    while (buf.items.len > 0 and (buf.items[buf.items.len - 1] == '\n' or buf.items[buf.items.len - 1] == ' ')) {
        _ = buf.pop();
    }
    try buf.appendSlice(allocator, "\n\n# nullifier-applied: revoked trusted_signers.");
    try buf.appendSlice(allocator, signer_name);
    try buf.appendSlice(allocator, " (pure revocation)\n");

    return buf.toOwnedSlice(allocator);
}

/// Manifest text mutation — rotation.
///
/// Locates the `[trusted_signers.<name>]` section, rewrites its
/// `pubkey = "..."` line to the replacement pubkey hex, and appends
/// a `previous_pubkey_chain = ["<old>", ...]` field within the same
/// section — preserving any existing chain (parsed from a previously-
/// rotated manifest) by prepending the old pubkey to it.
fn rewriteForRotation(
    allocator: std.mem.Allocator,
    text: []const u8,
    signer_name: []const u8,
    replacement_pubkey: [PUBKEY_LEN]u8,
) RewriteError![]u8 {
    const section = try findSignerSection(text, signer_name);
    if (section == null) return error.signer_not_found;
    const range = section.?;

    // Within the section, find the `pubkey = "..."` line.
    const section_text = text[range.start..range.end];
    const pubkey_line = findPubkeyLine(section_text) orelse return error.bad_manifest_text;
    const old_pubkey_hex = pubkey_line.value;

    var new_pubkey_hex_buf: [PUBKEY_LEN * 2]u8 = undefined;
    hexEncode(&replacement_pubkey, &new_pubkey_hex_buf);

    // Look for an existing previous_pubkey_chain — if present, we
    // PREPEND the old pubkey; if absent, we APPEND a new chain field.
    const chain_line = findChainLine(section_text);

    var new_section: std.ArrayList(u8) = .empty;
    errdefer new_section.deinit(allocator);

    // Emit prefix up to the pubkey line.
    try new_section.appendSlice(allocator, section_text[0..pubkey_line.start]);
    // Replacement pubkey line.
    try new_section.appendSlice(allocator, "pubkey = \"");
    try new_section.appendSlice(allocator, &new_pubkey_hex_buf);
    try new_section.appendSlice(allocator, "\"\n");

    // Existing chain handling.
    if (chain_line) |cl| {
        // Emit text between pubkey-line and chain-line.
        try new_section.appendSlice(allocator, section_text[pubkey_line.end..cl.start]);
        // Rewrite the chain field with old pubkey prepended.
        try new_section.appendSlice(allocator, "previous_pubkey_chain = [\"");
        try new_section.appendSlice(allocator, old_pubkey_hex);
        try new_section.appendSlice(allocator, "\"");
        // Re-emit existing chain entries after the prepend.
        for (cl.entries) |entry| {
            try new_section.appendSlice(allocator, ", \"");
            try new_section.appendSlice(allocator, entry);
            try new_section.appendSlice(allocator, "\"");
        }
        try new_section.appendSlice(allocator, "]\n");
        // Tail after chain.
        try new_section.appendSlice(allocator, section_text[cl.end..]);
    } else {
        // Tail after pubkey-line.
        try new_section.appendSlice(allocator, section_text[pubkey_line.end..]);
        // Trim any trailing newlines off the section before appending
        // the chain (so we don't accidentally inject a chain inside
        // the next section).
        while (new_section.items.len > 0 and new_section.items[new_section.items.len - 1] == '\n') {
            _ = new_section.pop();
        }
        try new_section.appendSlice(allocator, "\nprevious_pubkey_chain = [\"");
        try new_section.appendSlice(allocator, old_pubkey_hex);
        try new_section.appendSlice(allocator, "\"]\n");
    }

    // Stitch back: prefix-of-text + new_section + suffix-of-text.
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, text[0..range.start]);
    try out.appendSlice(allocator, new_section.items);
    try out.appendSlice(allocator, text[range.end..]);

    new_section.deinit(allocator);
    return out.toOwnedSlice(allocator);
}

const SectionRange = struct {
    /// Inclusive start of the `[trusted_signers.<name>]` header line.
    start: usize,
    /// Exclusive end (one past the last byte of the section, which is
    /// either the start of the next section header or end-of-file).
    end: usize,
};

fn findSignerSection(text: []const u8, signer_name: []const u8) RewriteError!?SectionRange {
    var header_buf: [256]u8 = undefined;
    if (signer_name.len + 22 > header_buf.len) return error.bad_manifest_text;
    const header = std.fmt.bufPrint(&header_buf, "[trusted_signers.{s}]", .{signer_name}) catch return error.bad_manifest_text;

    // Search for the header at start-of-line.  The TOML parser is
    // permissive about whitespace, but in practice the canonical
    // encoder emits headers at column 0; we match that.
    var search_from: usize = 0;
    while (search_from < text.len) {
        const idx_opt = std.mem.indexOf(u8, text[search_from..], header);
        if (idx_opt == null) return null;
        const idx = search_from + idx_opt.?;
        const at_sol = idx == 0 or text[idx - 1] == '\n';
        if (at_sol) {
            // Find the end-of-section: next `[` at start-of-line, or EOF.
            var scan: usize = idx + header.len;
            while (scan < text.len) {
                const next_opt = std.mem.indexOfScalarPos(u8, text, scan, '\n');
                if (next_opt == null) break;
                const next = next_opt.?;
                // Look at the char AFTER the newline.
                if (next + 1 < text.len and text[next + 1] == '[') {
                    return .{ .start = idx, .end = next + 1 };
                }
                scan = next + 1;
            }
            return .{ .start = idx, .end = text.len };
        }
        search_from = idx + 1;
    }
    return null;
}

const PubkeyLineMatch = struct {
    /// Byte offset within the section where the line starts.
    start: usize,
    /// Byte offset where the line ends (one past the trailing newline).
    end: usize,
    /// The pubkey hex value inside the quotes — borrowed slice into
    /// the section text.
    value: []const u8,
};

fn findPubkeyLine(section_text: []const u8) ?PubkeyLineMatch {
    return findKeyValueLine(section_text, "pubkey", PubkeyLineMatch);
}

const ChainLineMatch = struct {
    start: usize,
    end: usize,
    /// Currently-stored chain entries, parsed from the bracketed
    /// list.  Each entry is a borrowed slice into the section text.
    /// Buffer is a static-capacity local — caller doesn't own.
    entries: [][]const u8,
};

/// Local storage for chain entries.  The chain length is bounded by
/// the manifest's section size; v0.1 caps the parsed list at 32
/// entries (anyone rotating beyond that has bigger problems).
var chain_entries_buf: [32][]const u8 = undefined;

fn findChainLine(section_text: []const u8) ?ChainLineMatch {
    const m = findKeyValueLine(section_text, "previous_pubkey_chain", PubkeyLineMatch) orelse return null;
    // Parse the bracketed-list value.  Format: `["<hex>", "<hex>", ...]`.
    var entries_count: usize = 0;
    var i: usize = 0;
    while (i < m.value.len and entries_count < chain_entries_buf.len) {
        // Skip whitespace + commas + opening bracket.
        while (i < m.value.len and (m.value[i] == ' ' or m.value[i] == ',' or m.value[i] == '[' or m.value[i] == ']')) {
            i += 1;
        }
        if (i >= m.value.len) break;
        if (m.value[i] != '"') break;
        i += 1;
        const start = i;
        while (i < m.value.len and m.value[i] != '"') i += 1;
        if (i >= m.value.len) break;
        chain_entries_buf[entries_count] = m.value[start..i];
        entries_count += 1;
        i += 1;
    }
    return .{
        .start = m.start,
        .end = m.end,
        .entries = chain_entries_buf[0..entries_count],
    };
}

/// Locate `<key> = <value>` line in the section text.  `<value>`
/// captured between the first and last quote (string scalar) OR
/// between matching `[` `]` (string-array).  Permissive whitespace.
fn findKeyValueLine(section_text: []const u8, key: []const u8, comptime _: type) ?PubkeyLineMatch {
    var line_start: usize = 0;
    while (line_start < section_text.len) {
        const nl = std.mem.indexOfScalarPos(u8, section_text, line_start, '\n') orelse section_text.len;
        const line = section_text[line_start..nl];
        const trimmed = std.mem.trim(u8, line, " \t");
        if (std.mem.startsWith(u8, trimmed, key)) {
            const after_key = trimmed[key.len..];
            const after_trim = std.mem.trimLeft(u8, after_key, " \t");
            if (std.mem.startsWith(u8, after_trim, "=")) {
                // Found the line.  Capture the value.
                const value_start = std.mem.indexOfScalar(u8, line, '=').? + 1;
                const value_raw = std.mem.trim(u8, line[value_start..], " \t");
                // Either: "..." (string) or [ ... ] (array).
                if (value_raw.len >= 2 and value_raw[0] == '"' and value_raw[value_raw.len - 1] == '"') {
                    return .{
                        .start = line_start,
                        .end = if (nl == section_text.len) nl else nl + 1,
                        .value = value_raw[1 .. value_raw.len - 1],
                    };
                }
                if (value_raw.len >= 2 and value_raw[0] == '[' and value_raw[value_raw.len - 1] == ']') {
                    return .{
                        .start = line_start,
                        .end = if (nl == section_text.len) nl else nl + 1,
                        .value = value_raw,
                    };
                }
            }
        }
        if (nl == section_text.len) break;
        line_start = nl + 1;
    }
    return null;
}

// ─────────────────────────────────────────────────────────────────────
// Revoked-keys index
// ─────────────────────────────────────────────────────────────────────

fn revokedKeysIndexContains(
    allocator: std.mem.Allocator,
    path: []const u8,
    pubkey: [PUBKEY_LEN]u8,
) ApplyError!bool {
    const f = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return error.revoked_index_io_failed,
    };
    defer f.close();
    const stat = f.stat() catch return error.revoked_index_io_failed;
    if (stat.size > 4 * 1024 * 1024) return error.revoked_index_io_failed;
    const buf = allocator.alloc(u8, stat.size) catch return error.out_of_memory;
    defer allocator.free(buf);
    _ = f.readAll(buf) catch return error.revoked_index_io_failed;

    var hex_buf: [PUBKEY_LEN * 2]u8 = undefined;
    hexEncode(&pubkey, &hex_buf);
    return std.mem.indexOf(u8, buf, &hex_buf) != null;
}

fn appendRevokedKey(
    allocator: std.mem.Allocator,
    path: []const u8,
    vn: VerifiedNullifier,
) ApplyError!void {
    if (std.fs.path.dirname(path)) |parent| {
        std.fs.cwd().makePath(parent) catch {};
    }
    var hex_buf: [PUBKEY_LEN * 2]u8 = undefined;
    hexEncode(&vn.payload.revoked_pubkey, &hex_buf);
    const replacement_hex_owned = if (vn.payload.replacement_pubkey) |rp| blk: {
        const buf = allocator.alloc(u8, PUBKEY_LEN * 2) catch return error.out_of_memory;
        hexEncode(&rp, buf);
        break :blk buf;
    } else "";
    defer if (replacement_hex_owned.len > 0) allocator.free(replacement_hex_owned);

    const line = std.fmt.allocPrint(
        allocator,
        "{{\"pubkey\":\"{s}\",\"reason\":\"{s}\",\"timestamp\":{d},\"signer\":\"{s}\",\"replacement\":\"{s}\"}}\n",
        .{
            hex_buf,
            vn.payload.reason_code.name(),
            vn.payload.timestamp,
            vn.target_signer_name,
            replacement_hex_owned,
        },
    ) catch return error.out_of_memory;
    defer allocator.free(line);

    const f = std.fs.cwd().createFile(path, .{ .read = false, .truncate = false }) catch
        return error.revoked_index_io_failed;
    defer f.close();
    f.seekFromEnd(0) catch return error.revoked_index_io_failed;
    f.writeAll(line) catch return error.revoked_index_io_failed;
}

// ─────────────────────────────────────────────────────────────────────
// File helpers
// ─────────────────────────────────────────────────────────────────────

fn readFileAlloc(
    allocator: std.mem.Allocator,
    path: []const u8,
    max_bytes: usize,
) ![]u8 {
    const f = try std.fs.cwd().openFile(path, .{});
    defer f.close();
    const stat = try f.stat();
    if (stat.size > max_bytes) return error.FileTooBig;
    const buf = try allocator.alloc(u8, stat.size);
    errdefer allocator.free(buf);
    _ = try f.readAll(buf);
    return buf;
}

fn writeFileAtomic(
    allocator: std.mem.Allocator,
    path: []const u8,
    contents: []const u8,
) ApplyError!void {
    const tmp_path = std.fmt.allocPrint(allocator, "{s}.tmp", .{path}) catch return error.out_of_memory;
    defer allocator.free(tmp_path);

    const f = std.fs.cwd().createFile(tmp_path, .{ .truncate = true }) catch
        return error.manifest_write_failed;
    {
        defer f.close();
        f.writeAll(contents) catch return error.manifest_write_failed;
    }
    std.fs.cwd().rename(tmp_path, path) catch return error.manifest_write_failed;
}

// ─────────────────────────────────────────────────────────────────────
// Inline tests — pure-logic only.  Full sign+verify round-trip lives
// in tests/extension_nullifier_conformance.zig (gated on
// enable_wasmtime so the bsvz-free build path stays clean).
// ─────────────────────────────────────────────────────────────────────

test "encode/decode round-trip — pure revocation" {
    const allocator = std.testing.allocator;
    const p = NullifierPayload{
        .revoked_pubkey = .{0x02} ++ [_]u8{0xaa} ** 32,
        .reason_code = .compromised,
        .timestamp = 0x0102030405060708,
    };
    const bytes = try encodeNullifierPayload(allocator, p);
    defer allocator.free(bytes);
    try std.testing.expectEqual(MIN_PAYLOAD_LEN, bytes.len);
    const decoded = try decodeNullifierPayload(allocator, bytes);
    try std.testing.expectEqualSlices(u8, &p.revoked_pubkey, &decoded.revoked_pubkey);
    try std.testing.expectEqual(p.reason_code, decoded.reason_code);
    try std.testing.expectEqual(p.timestamp, decoded.timestamp);
    try std.testing.expect(decoded.replacement_pubkey == null);
    try std.testing.expect(decoded.rotation_authority_signature == null);
}

test "encode/decode round-trip — rotation" {
    const allocator = std.testing.allocator;
    const p = NullifierPayload{
        .revoked_pubkey = .{0x02} ++ [_]u8{0xaa} ** 32,
        .reason_code = .superseded,
        .timestamp = 1_725_000_000,
        .replacement_pubkey = .{0x03} ++ [_]u8{0xbb} ** 32,
        .rotation_authority_signature = .{0xcc} ** 64,
    };
    const bytes = try encodeNullifierPayload(allocator, p);
    defer allocator.free(bytes);
    try std.testing.expectEqual(MAX_PAYLOAD_LEN, bytes.len);
    const decoded = try decodeNullifierPayload(allocator, bytes);
    try std.testing.expect(decoded.replacement_pubkey != null);
    try std.testing.expect(decoded.rotation_authority_signature != null);
    try std.testing.expectEqualSlices(u8, &p.replacement_pubkey.?, &decoded.replacement_pubkey.?);
    try std.testing.expectEqualSlices(u8, &p.rotation_authority_signature.?, &decoded.rotation_authority_signature.?);
}

test "decode rejects bad tag" {
    const allocator = std.testing.allocator;
    var bytes: [MIN_PAYLOAD_LEN]u8 = undefined;
    @memcpy(bytes[0..PAYLOAD_VERSION_TAG.len], PAYLOAD_VERSION_TAG);
    @memset(bytes[PAYLOAD_VERSION_TAG.len..], 0);
    bytes[0] = 'X'; // corrupt the tag
    try std.testing.expectError(error.payload_bad_tag, decodeNullifierPayload(allocator, &bytes));
}

test "decode rejects unknown reason code" {
    const allocator = std.testing.allocator;
    var bytes: [MIN_PAYLOAD_LEN]u8 = undefined;
    @memcpy(bytes[0..PAYLOAD_VERSION_TAG.len], PAYLOAD_VERSION_TAG);
    @memset(bytes[PAYLOAD_VERSION_TAG.len..], 0);
    bytes[PAYLOAD_VERSION_TAG.len + PUBKEY_LEN] = 99; // bogus reason
    try std.testing.expectError(error.payload_bad_reason_code, decodeNullifierPayload(allocator, &bytes));
}

test "decode rejects truncated rotation payload" {
    const allocator = std.testing.allocator;
    // Build a payload with has_replacement=1 but the slice is the
    // pure-revocation length.  Should reject as truncated.
    var bytes: [MIN_PAYLOAD_LEN]u8 = undefined;
    @memcpy(bytes[0..PAYLOAD_VERSION_TAG.len], PAYLOAD_VERSION_TAG);
    @memset(bytes[PAYLOAD_VERSION_TAG.len..], 0);
    bytes[MIN_PAYLOAD_LEN - 1] = 1; // has_replacement = 1
    try std.testing.expectError(error.payload_truncated, decodeNullifierPayload(allocator, &bytes));
}

test "rotationAuthoritySignDigest is sha256d(revoked || replacement || ts_be)" {
    const revoked: [PUBKEY_LEN]u8 = .{0x02} ++ [_]u8{0xaa} ** 32;
    const replacement: [PUBKEY_LEN]u8 = .{0x03} ++ [_]u8{0xbb} ** 32;
    const ts: u64 = 0x0102030405060708;
    const got = rotationAuthoritySignDigest(revoked, replacement, ts);
    var ts_buf: [8]u8 = undefined;
    writeU64Be(&ts_buf, ts);
    var first: [32]u8 = undefined;
    {
        var h = std.crypto.hash.sha2.Sha256.init(.{});
        h.update(&revoked);
        h.update(&replacement);
        h.update(&ts_buf);
        h.final(&first);
    }
    var expected: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(&first, &expected, .{});
    try std.testing.expectEqualSlices(u8, &expected, &got);
}

test "ReasonCode round-trip" {
    try std.testing.expectEqual(@as(?ReasonCode, .compromised), ReasonCode.fromByte(0));
    try std.testing.expectEqual(@as(?ReasonCode, .breach), ReasonCode.fromByte(3));
    try std.testing.expectEqual(@as(?ReasonCode, null), ReasonCode.fromByte(4));
    try std.testing.expectEqualStrings("compromised", ReasonCode.compromised.name());
    try std.testing.expectEqualStrings("breach", ReasonCode.breach.name());
    try std.testing.expectEqual(@as(?ReasonCode, .voluntary), parseReasonCode("voluntary"));
    try std.testing.expectEqual(@as(?ReasonCode, null), parseReasonCode("foo"));
}

test "rewriteForRevocation removes the section + appends an audit comment" {
    const allocator = std.testing.allocator;
    const text =
        \\[tenant]
        \\domain = "x.example"
        \\
        \\[trusted_signers]
        \\require_spv = true
        \\
        \\[trusted_signers.acme]
        \\pubkey = "02aaaa"
        \\plexus_identity_tx = "00ff"
        \\scope = "acme.*"
        \\removable = true
        \\label = "acme"
        \\shard_group = "deadbeef"
        \\
        \\[trusted_signers.platform]
        \\pubkey = "02bbbb"
        \\
    ;
    const out = try rewriteForRevocation(allocator, text, "acme");
    defer allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "[trusted_signers.acme]") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "[trusted_signers.platform]") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "nullifier-applied: revoked trusted_signers.acme") != null);
}

test "rewriteForRotation rewrites pubkey + appends previous_pubkey_chain" {
    const allocator = std.testing.allocator;
    const text =
        \\[tenant]
        \\domain = "x.example"
        \\
        \\[trusted_signers.acme]
        \\pubkey = "02aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        \\plexus_identity_tx = "00ff"
        \\scope = "acme.*"
        \\
    ;
    const replacement: [PUBKEY_LEN]u8 = .{0x03} ++ [_]u8{0xbb} ** 32;
    const out = try rewriteForRotation(allocator, text, "acme", replacement);
    defer allocator.free(out);
    // New pubkey is the replacement.
    try std.testing.expect(std.mem.indexOf(u8, out, "03bb") != null);
    // The OLD pubkey is preserved in previous_pubkey_chain.
    try std.testing.expect(std.mem.indexOf(u8, out, "previous_pubkey_chain") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "02aaaa") != null);
}

test "rewriteForRotation extends an existing chain — old pubkey prepended" {
    const allocator = std.testing.allocator;
    const text =
        \\[trusted_signers.acme]
        \\pubkey = "02bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        \\previous_pubkey_chain = ["02oldoldoldoldoldoldoldoldoldoldoldoldoldoldoldoldoldoldoldoldoldoldoldold"]
        \\scope = "acme.*"
        \\
    ;
    const replacement: [PUBKEY_LEN]u8 = .{0x03} ++ [_]u8{0xcc} ** 32;
    const out = try rewriteForRotation(allocator, text, "acme", replacement);
    defer allocator.free(out);
    // New pubkey present.
    try std.testing.expect(std.mem.indexOf(u8, out, "03cc") != null);
    // Both old keys present in chain.
    try std.testing.expect(std.mem.indexOf(u8, out, "02bbbb") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "02oldold") != null);
}

test "findSignerSection returns null on missing entry" {
    const text = "[tenant]\ndomain = \"x\"\n";
    const r = try findSignerSection(text, "missing");
    try std.testing.expect(r == null);
}

```
