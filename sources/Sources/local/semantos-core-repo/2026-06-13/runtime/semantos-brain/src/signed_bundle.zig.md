---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/signed_bundle.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.259439+00:00
---

# runtime/semantos-brain/src/signed_bundle.zig

```zig
// Phase D-W1 / Phase 4 — SignedBundle codec for the mesh transport.
//
// Reference: docs/design/BRAIN-DISPATCHER-UNIFICATION.md §5.4 (mesh
//            transport: mobile Flutter peer + federated tenant nodes
//            send SignedBundle envelopes; the receiving brain decodes
//            the envelope, verifies the cert chain, constructs a
//            DispatchContext with auth.cert = <peer's cert>, calls
//            the dispatcher); §8 Phase 4.
//
//            core/protocol-types/src/identity.ts (canonical TS shape;
//            Brc52Cert + cert-id derivation + canonicalCertPreimage).
//            runtime/session-protocol/src/bundle-envelope.ts (the
//            pre-existing envelope shape; recipient/sender/signature
//            semantics).
//
// What this is — a JSON codec for the Phase 4 wire envelope plus
// signature + cert-chain verification.
//
//   SignedBundle ::=
//     {
//       "v": 1,
//       "sender_cert_chain": [<CertRef>],   # leaf-first; root last
//       "recipient_cert_id": "<32-hex>",    # null = broadcast
//                                          (rejected on receive — we
//                                          enforce addressed-bundle
//                                          posture for v0.1 mesh
//                                          transport)
//       "payload_type":      "<dotted-name>",  # e.g. "dispatch.request"
//       "payload":           "<base64-or-raw-json>",  # opaque to codec
//       "signature":         "<128-hex>",   # 64-byte compact (r||s)
//       "signature_metadata": {
//         "algorithm": "ecdsa-secp256k1-sha256",
//         "nonce_hex": "<32-hex>",          # anti-replay
//         "timestamp_unix": <integer>       # seconds since epoch
//       }
//     }
//
//   CertRef ::=
//     {
//       "cert_id":   "<32-hex>",
//       "pubkey":    "<66-hex>",          # 33-byte compressed SEC1
//       "context_tag": <u8 0-255>,        # carpenter=0x10, musician=0x11,
//                                          0 for the root
//       "parent_cert_id": "<32-hex>" | null  # null only for the root
//     }
//
// Why a new module rather than extending wire.zig: the existing
// wire.zig envelopes are dispatch Request/Response shapes; the
// SignedBundle has more structure (cert chain, sender/recipient
// routing, signature, signature_metadata).  Phase 4 keeps wire.zig
// pure (it's the inner-payload codec) and lives the Phase-4-specific
// shape here.
//
// What this codec does NOT do:
//   • SPV-walk the cert chain against an external lookup (BKDS proofs
//     ride elsewhere — see verifyCertChain below; the v0.1 brain
//     verifies the LEAF cert is registered in its local CertStore +
//     trusts the chain prefix that produced it).
//   • Replay protection (the receive seam in transport/signed_bundle.zig
//     owns the nonce LRU).
//
// Cross-language conformance:
//   The TS sender helper at cartridges/oddjobz/brain/tools/send-bundle.ts
//   produces the same on-the-wire JSON shape this decoder accepts.
//   The signature preimage is byte-identical across Zig + TS (canonical
//   sorted-key JSON of the bundle minus `signature`).

const std = @import("std");
const bsvz = @import("bsvz");
const identity_certs = @import("identity_certs");
const bkds = @import("bkds");

// ─────────────────────────────────────────────────────────────────────
// Constants + errors
// ─────────────────────────────────────────────────────────────────────

/// Schema version of the SignedBundle envelope itself.  Bumped only on
/// breaking-wire-shape changes.  v0.1 = 1.
pub const ENVELOPE_VERSION: u8 = 1;

/// The signature preimage's canonical-JSON encoding includes a leading
/// magic byte sequence to prevent cross-protocol signature reuse — a
/// sig over a bundle preimage is meaningfully distinct from a sig over
/// a cell-engine envelope or a publish-tx digest.
pub const SIG_DOMAIN: []const u8 = "BRAIN-SIGNED-BUNDLE-v1";

/// Compact ECDSA signature length (r || s, 32+32 bytes).
pub const SIG_LEN: usize = 64;

/// 32-hex-char cert id length (matches identity_certs.CERT_ID_HEX_LEN).
pub const CERT_ID_HEX_LEN: usize = 32;

/// 33-byte compressed SEC1 pubkey, hex-encoded length.
pub const PUBKEY_HEX_LEN: usize = 66;

/// 32-byte nonce, hex-encoded length.
pub const NONCE_HEX_LEN: usize = 64;

/// Maximum sender_cert_chain length.  Bounded so a malformed envelope
/// can't OOM the brain by claiming a 10000-cert chain.  Real chains
/// are 2-3 deep (root → context-hat → device).
pub const MAX_CHAIN_LEN: usize = 16;

/// Maximum payload byte length.  v0.1 ceiling — the dispatch Request
/// envelopes that ride inside are well under this; an extension that
/// needs more bumps the cap explicitly.
pub const MAX_PAYLOAD_LEN: usize = 1024 * 1024;

pub const Error = error{
    invalid_json,
    not_an_object,
    missing_field,
    wrong_type,
    unsupported_version,
    chain_too_long,
    chain_empty,
    payload_too_long,
    bad_hex,
    bad_signature_length,
    bad_pubkey_length,
    bad_cert_id_length,
    bad_nonce_length,
    out_of_memory,
    /// The leaf cert (sender_cert_chain[0]) is not registered in the
    /// brain's CertStore.  Surfaces as 401 at the HTTP wrapper.
    leaf_cert_unknown,
    /// The signature did not verify against the leaf cert's pubkey.
    signature_mismatch,
    /// A non-leaf cert in the chain claimed a parent_cert_id that
    /// doesn't match the actual parent's cert id.
    chain_parent_mismatch,
    /// A non-leaf cert is not present in the brain's CertStore — the
    /// chain claims to ride through a cert the brain has never seen.
    chain_intermediate_unknown,
    /// The signing algorithm field was absent or carried a value we
    /// don't recognise.  v0.1 only accepts "ecdsa-secp256k1-sha256".
    unknown_algorithm,
    /// `recipient_cert_id` was null/missing — addressed-bundle
    /// production posture rejects broadcast.
    recipient_missing,
    /// `recipient_cert_id` did not match the brain's own root cert id.
    recipient_mismatch,
};

// ─────────────────────────────────────────────────────────────────────
// Wire shapes
// ─────────────────────────────────────────────────────────────────────

/// One link in the cert chain.  `cert_id` is the canonical 32-hex form
/// derived from `pubkey` (matches `identity_certs.certIdFromPubkey`).
/// `parent_cert_id` is null only for the root.
pub const CertRef = struct {
    cert_id: [CERT_ID_HEX_LEN]u8,
    pubkey: [bkds.KEY_LEN]u8,
    context_tag: u8 = 0,
    parent_cert_id: ?[CERT_ID_HEX_LEN]u8 = null,
};

/// The signature_metadata sub-object.  Carries the anti-replay nonce +
/// the wall-clock timestamp the sender stamped at signing time.  The
/// receive seam compares the timestamp against a configurable freshness
/// window and the nonce against an LRU.
pub const SignatureMetadata = struct {
    /// Currently the only value is `"ecdsa-secp256k1-sha256"`.
    algorithm: []const u8 = "ecdsa-secp256k1-sha256",
    /// 32-byte hex nonce.  Bound on the wire as a fixed-size array so
    /// the bundle is copyable without the OwnedBundle's allocator.
    nonce_hex: [NONCE_HEX_LEN]u8,
    /// Sender's timestamp at sign time.  Receive seam clamps freshness.
    timestamp_unix: i64,
};

/// The decoded envelope.  Slices are allocator-owned; caller frees via
/// `OwnedBundle.deinit`.
pub const SignedBundle = struct {
    v: u8 = ENVELOPE_VERSION,
    sender_cert_chain: []CertRef,
    recipient_cert_id: ?[CERT_ID_HEX_LEN]u8,
    payload_type: []const u8,
    /// Raw payload bytes.  The codec stores them verbatim — e.g. a
    /// dispatch Request envelope's JSON ride here as bytes.  No
    /// encoding/decoding step.
    payload: []const u8,
    signature: [SIG_LEN]u8,
    signature_metadata: SignatureMetadata,
};

/// Owned-decode wrapper.  Holds the allocator-borrowed slices that
/// outlive the JSON parser; caller calls `deinit`.
pub const OwnedBundle = struct {
    bundle: SignedBundle,
    allocator: std.mem.Allocator,
    /// All allocator-owned bufs we tracked during decode; freed on deinit.
    bufs: std.ArrayList([]u8),

    pub fn deinit(self: *OwnedBundle) void {
        for (self.bufs.items) |b| self.allocator.free(b);
        self.bufs.deinit(self.allocator);
        if (self.bundle.sender_cert_chain.len > 0) {
            self.allocator.free(self.bundle.sender_cert_chain);
        }
    }
};

// ─────────────────────────────────────────────────────────────────────
// Encode
// ─────────────────────────────────────────────────────────────────────

/// Encode a SignedBundle to JSON bytes.  The output is canonical-sorted-
/// key — i.e. byte-identical for byte-identical inputs across runs.  The
/// signature preimage (see `canonicalSignaturePreimage`) is the same
/// shape minus the `signature` field.
pub fn encode(allocator: std.mem.Allocator, b: SignedBundle) ![]u8 {
    var out: std.ArrayList(u8) = .{};
    errdefer out.deinit(allocator);
    try writeBundleJson(allocator, &out, b, .{ .include_signature = true });
    return out.toOwnedSlice(allocator);
}

/// Build the canonical signature preimage bytes for `b`.  Identical
/// shape on the TS sender side.  The signature is computed as
/// `ECDSA(SHA-256(SIG_DOMAIN || canonical_preimage))`.
pub fn canonicalSignaturePreimage(allocator: std.mem.Allocator, b: SignedBundle) ![]u8 {
    var out: std.ArrayList(u8) = .{};
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, SIG_DOMAIN);
    try writeBundleJson(allocator, &out, b, .{ .include_signature = false });
    return out.toOwnedSlice(allocator);
}

/// Compute the SHA-256 digest of the canonical signature preimage.
pub fn computeSignDigest(allocator: std.mem.Allocator, b: SignedBundle) ![32]u8 {
    const preimage = try canonicalSignaturePreimage(allocator, b);
    defer allocator.free(preimage);
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(preimage, &digest, .{});
    return digest;
}

const WriteOpts = struct {
    include_signature: bool,
};

fn writeBundleJson(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    b: SignedBundle,
    opts: WriteOpts,
) !void {
    try out.append(allocator, '{');
    try writeKey(allocator, out, "payload");
    try writeJsonString(allocator, out, b.payload);
    try out.append(allocator, ',');
    try writeKey(allocator, out, "payload_type");
    try writeJsonString(allocator, out, b.payload_type);
    try out.append(allocator, ',');
    try writeKey(allocator, out, "recipient_cert_id");
    if (b.recipient_cert_id) |rid| {
        try writeJsonStringFixed(allocator, out, rid[0..]);
    } else {
        try out.appendSlice(allocator, "null");
    }
    try out.append(allocator, ',');
    try writeKey(allocator, out, "sender_cert_chain");
    try writeChain(allocator, out, b.sender_cert_chain);
    if (opts.include_signature) {
        try out.append(allocator, ',');
        try writeKey(allocator, out, "signature");
        try writeSignatureHex(allocator, out, b.signature);
    }
    try out.append(allocator, ',');
    try writeKey(allocator, out, "signature_metadata");
    try writeSignatureMetadata(allocator, out, b.signature_metadata);
    try out.append(allocator, ',');
    try writeKey(allocator, out, "v");
    try writeU8(allocator, out, b.v);
    try out.append(allocator, '}');
}

fn writeKey(allocator: std.mem.Allocator, out: *std.ArrayList(u8), key: []const u8) !void {
    try writeJsonString(allocator, out, key);
    try out.append(allocator, ':');
}

fn writeChain(allocator: std.mem.Allocator, out: *std.ArrayList(u8), chain: []const CertRef) !void {
    try out.append(allocator, '[');
    for (chain, 0..) |link, i| {
        if (i != 0) try out.append(allocator, ',');
        try writeCertRef(allocator, out, link);
    }
    try out.append(allocator, ']');
}

fn writeCertRef(allocator: std.mem.Allocator, out: *std.ArrayList(u8), c: CertRef) !void {
    try out.append(allocator, '{');
    try writeKey(allocator, out, "cert_id");
    try writeJsonStringFixed(allocator, out, c.cert_id[0..]);
    try out.append(allocator, ',');
    try writeKey(allocator, out, "context_tag");
    try writeU8(allocator, out, c.context_tag);
    try out.append(allocator, ',');
    try writeKey(allocator, out, "parent_cert_id");
    if (c.parent_cert_id) |pid| {
        try writeJsonStringFixed(allocator, out, pid[0..]);
    } else {
        try out.appendSlice(allocator, "null");
    }
    try out.append(allocator, ',');
    try writeKey(allocator, out, "pubkey");
    var pub_hex: [PUBKEY_HEX_LEN]u8 = undefined;
    bkds.hexEncode(&c.pubkey, &pub_hex);
    try writeJsonStringFixed(allocator, out, pub_hex[0..]);
    try out.append(allocator, '}');
}

fn writeSignatureMetadata(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    m: SignatureMetadata,
) !void {
    try out.append(allocator, '{');
    try writeKey(allocator, out, "algorithm");
    try writeJsonString(allocator, out, m.algorithm);
    try out.append(allocator, ',');
    try writeKey(allocator, out, "nonce_hex");
    try writeJsonStringFixed(allocator, out, m.nonce_hex[0..]);
    try out.append(allocator, ',');
    try writeKey(allocator, out, "timestamp_unix");
    var buf: [32]u8 = undefined;
    const slice = try std.fmt.bufPrint(&buf, "{d}", .{m.timestamp_unix});
    try out.appendSlice(allocator, slice);
    try out.append(allocator, '}');
}

fn writeSignatureHex(allocator: std.mem.Allocator, out: *std.ArrayList(u8), sig: [SIG_LEN]u8) !void {
    var hex: [SIG_LEN * 2]u8 = undefined;
    bkds.hexEncode(&sig, &hex);
    try writeJsonStringFixed(allocator, out, hex[0..]);
}

fn writeJsonString(allocator: std.mem.Allocator, out: *std.ArrayList(u8), s: []const u8) !void {
    const encoded = try std.json.Stringify.valueAlloc(allocator, s, .{});
    defer allocator.free(encoded);
    try out.appendSlice(allocator, encoded);
}

fn writeJsonStringFixed(allocator: std.mem.Allocator, out: *std.ArrayList(u8), s: []const u8) !void {
    return writeJsonString(allocator, out, s);
}

fn writeU8(allocator: std.mem.Allocator, out: *std.ArrayList(u8), n: u8) !void {
    var buf: [4]u8 = undefined;
    const slice = try std.fmt.bufPrint(&buf, "{d}", .{n});
    try out.appendSlice(allocator, slice);
}

// ─────────────────────────────────────────────────────────────────────
// Decode
// ─────────────────────────────────────────────────────────────────────

pub fn decode(allocator: std.mem.Allocator, json: []const u8) Error!OwnedBundle {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, json, .{}) catch
        return Error.invalid_json;
    defer parsed.deinit();
    if (parsed.value != .object) return Error.not_an_object;
    const obj = parsed.value.object;

    var bufs: std.ArrayList([]u8) = .{};
    errdefer {
        for (bufs.items) |b| allocator.free(b);
        bufs.deinit(allocator);
    }

    // v
    const v_val = obj.get("v") orelse return Error.missing_field;
    if (v_val != .integer) return Error.wrong_type;
    if (v_val.integer != ENVELOPE_VERSION) return Error.unsupported_version;

    // payload_type
    const pt_v = obj.get("payload_type") orelse return Error.missing_field;
    if (pt_v != .string) return Error.wrong_type;
    const payload_type = try dupTracked(allocator, &bufs, pt_v.string);

    // payload (string)
    const pl_v = obj.get("payload") orelse return Error.missing_field;
    if (pl_v != .string) return Error.wrong_type;
    if (pl_v.string.len > MAX_PAYLOAD_LEN) return Error.payload_too_long;
    const payload = try dupTracked(allocator, &bufs, pl_v.string);

    // recipient_cert_id (string | null)
    var recipient_cert_id: ?[CERT_ID_HEX_LEN]u8 = null;
    if (obj.get("recipient_cert_id")) |rv| switch (rv) {
        .null => {},
        .string => |s| {
            if (s.len != CERT_ID_HEX_LEN) return Error.bad_cert_id_length;
            var buf: [CERT_ID_HEX_LEN]u8 = undefined;
            @memcpy(&buf, s);
            recipient_cert_id = buf;
        },
        else => return Error.wrong_type,
    };

    // sender_cert_chain ([])
    const chain_v = obj.get("sender_cert_chain") orelse return Error.missing_field;
    if (chain_v != .array) return Error.wrong_type;
    if (chain_v.array.items.len == 0) return Error.chain_empty;
    if (chain_v.array.items.len > MAX_CHAIN_LEN) return Error.chain_too_long;
    const chain = allocator.alloc(CertRef, chain_v.array.items.len) catch return Error.out_of_memory;
    errdefer allocator.free(chain);
    for (chain_v.array.items, 0..) |item, i| {
        chain[i] = try decodeCertRef(item);
    }

    // signature
    const sig_v = obj.get("signature") orelse return Error.missing_field;
    if (sig_v != .string) return Error.wrong_type;
    if (sig_v.string.len != SIG_LEN * 2) return Error.bad_signature_length;
    var sig: [SIG_LEN]u8 = undefined;
    bkds.hexDecode(sig_v.string, &sig) catch return Error.bad_hex;

    // signature_metadata
    const meta_v = obj.get("signature_metadata") orelse return Error.missing_field;
    if (meta_v != .object) return Error.wrong_type;
    const meta_obj = meta_v.object;
    const alg_v = meta_obj.get("algorithm") orelse return Error.missing_field;
    if (alg_v != .string) return Error.wrong_type;
    const algorithm = try dupTracked(allocator, &bufs, alg_v.string);
    const nonce_v = meta_obj.get("nonce_hex") orelse return Error.missing_field;
    if (nonce_v != .string) return Error.wrong_type;
    if (nonce_v.string.len != NONCE_HEX_LEN) return Error.bad_nonce_length;
    var nonce_arr: [NONCE_HEX_LEN]u8 = undefined;
    @memcpy(&nonce_arr, nonce_v.string);
    const ts_v = meta_obj.get("timestamp_unix") orelse return Error.missing_field;
    if (ts_v != .integer) return Error.wrong_type;

    return OwnedBundle{
        .bundle = .{
            .v = ENVELOPE_VERSION,
            .sender_cert_chain = chain,
            .recipient_cert_id = recipient_cert_id,
            .payload_type = payload_type,
            .payload = payload,
            .signature = sig,
            .signature_metadata = .{
                .algorithm = algorithm,
                .nonce_hex = nonce_arr,
                .timestamp_unix = ts_v.integer,
            },
        },
        .allocator = allocator,
        .bufs = bufs,
    };
}

fn decodeCertRef(v: std.json.Value) Error!CertRef {
    if (v != .object) return Error.wrong_type;
    const obj = v.object;
    const id_v = obj.get("cert_id") orelse return Error.missing_field;
    if (id_v != .string) return Error.wrong_type;
    if (id_v.string.len != CERT_ID_HEX_LEN) return Error.bad_cert_id_length;
    var cert_id: [CERT_ID_HEX_LEN]u8 = undefined;
    @memcpy(&cert_id, id_v.string);

    const pub_v = obj.get("pubkey") orelse return Error.missing_field;
    if (pub_v != .string) return Error.wrong_type;
    if (pub_v.string.len != PUBKEY_HEX_LEN) return Error.bad_pubkey_length;
    var pubkey: [bkds.KEY_LEN]u8 = undefined;
    bkds.hexDecode(pub_v.string, &pubkey) catch return Error.bad_hex;

    const ctx_v = obj.get("context_tag") orelse return Error.missing_field;
    if (ctx_v != .integer) return Error.wrong_type;
    if (ctx_v.integer < 0 or ctx_v.integer > 255) return Error.wrong_type;
    const context_tag: u8 = @intCast(ctx_v.integer);

    var parent_cert_id: ?[CERT_ID_HEX_LEN]u8 = null;
    if (obj.get("parent_cert_id")) |pv| switch (pv) {
        .null => {},
        .string => |s| {
            if (s.len != CERT_ID_HEX_LEN) return Error.bad_cert_id_length;
            var buf: [CERT_ID_HEX_LEN]u8 = undefined;
            @memcpy(&buf, s);
            parent_cert_id = buf;
        },
        else => return Error.wrong_type,
    };

    return .{
        .cert_id = cert_id,
        .pubkey = pubkey,
        .context_tag = context_tag,
        .parent_cert_id = parent_cert_id,
    };
}

fn dupTracked(allocator: std.mem.Allocator, bufs: *std.ArrayList([]u8), s: []const u8) Error![]u8 {
    const buf = allocator.dupe(u8, s) catch return Error.out_of_memory;
    bufs.append(allocator, buf) catch {
        allocator.free(buf);
        return Error.out_of_memory;
    };
    return buf;
}

// ─────────────────────────────────────────────────────────────────────
// Verification
// ─────────────────────────────────────────────────────────────────────

/// Verify the bundle's ECDSA signature against `expected_pubkey` (the
/// 33-byte compressed SEC1 pubkey of the leaf cert).  Tries the four
/// recovery bytes (compressed range 31..34) and surfaces success on
/// match.  Algorithm mirrors `extension_publish.verifySignature`.
pub fn verifySignature(
    allocator: std.mem.Allocator,
    b: SignedBundle,
    expected_pubkey: [bkds.KEY_LEN]u8,
) !void {
    if (!std.mem.eql(u8, b.signature_metadata.algorithm, "ecdsa-secp256k1-sha256")) {
        return Error.unknown_algorithm;
    }
    const digest = try computeSignDigest(allocator, b);
    var candidate: [65]u8 = undefined;
    @memcpy(candidate[1..65], &b.signature);
    var rec: u8 = 31;
    while (rec <= 34) : (rec += 1) {
        candidate[0] = rec;
        const recovered = bsvz.crypto.compact.recoverCompactDigest256(candidate, digest) catch continue;
        const recovered_sec1 = recovered.pubkey.toCompressedSec1();
        if (std.crypto.timing_safe.eql([bkds.KEY_LEN]u8, recovered_sec1, expected_pubkey)) return;
    }
    return Error.signature_mismatch;
}

/// Sign an unsigned bundle.  `out_bundle.signature` is filled in with
/// the 64-byte compact signature.  Used by tests + the future Zig-side
/// signer (today the production sender is the TS helper).
pub fn signBundle(
    allocator: std.mem.Allocator,
    b: *SignedBundle,
    signing_priv: [bkds.PRIVKEY_LEN]u8,
) !void {
    const digest = try computeSignDigest(allocator, b.*);
    const priv = bsvz.primitives.ec.PrivateKey.fromBytes(signing_priv) catch
        return Error.signature_mismatch;
    const compact = priv.signCompact(digest, true) catch return Error.signature_mismatch;
    @memcpy(&b.signature, compact[1..65]);
}

/// What `verifyCertChain` returns: the leaf cert's resolved capability
/// set + a CertRef the dispatcher can stash on its DispatchContext.
pub const VerifiedSender = struct {
    /// 32-hex-char cert id of the leaf (the entity that signed).
    leaf_cert_id: [CERT_ID_HEX_LEN]u8,
    /// 33-byte compressed-SEC1 pubkey of the leaf.
    leaf_pubkey: [bkds.KEY_LEN]u8,
    /// Owned slice of capability strings; freed via `deinit`.
    capabilities: []const []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *VerifiedSender) void {
        for (self.capabilities) |c| self.allocator.free(@constCast(c));
        if (self.capabilities.len > 0) self.allocator.free(@constCast(self.capabilities));
        self.capabilities = &.{};
    }
};

/// Walk the cert chain back to the brain's root.  Three checks per
/// link, top-down:
///
///   1. The cert id on the wire matches `certIdFromPubkey(link.pubkey)`
///      (catches a forged claim that "this pubkey owns this cert id").
///   2. The cert is registered in the brain's CertStore (the brain's
///      authoritative view of who has paired with it; revoked certs
///      have been pruned from the index — see identity_certs.zig).
///   3. For non-leaf links, `link.parent_cert_id` matches the actual
///      parent's `cert_id`.
///
/// On success, the leaf's capability set (CertStore-recorded) is
/// duplicated into the returned `VerifiedSender`.
pub fn verifyCertChain(
    allocator: std.mem.Allocator,
    b: SignedBundle,
    store: *identity_certs.CertStore,
) !VerifiedSender {
    if (b.sender_cert_chain.len == 0) return Error.chain_empty;

    const leaf = b.sender_cert_chain[0];

    // Per-link integrity + store membership.
    var i: usize = 0;
    while (i < b.sender_cert_chain.len) : (i += 1) {
        const link = b.sender_cert_chain[i];
        // (1) cert_id ↔ pubkey binding.
        const expected_id = identity_certs.certIdFromPubkey(link.pubkey);
        if (!std.mem.eql(u8, link.cert_id[0..], expected_id[0..])) {
            return Error.chain_intermediate_unknown;
        }
        // (2) store membership.
        const stored = store.get(link.cert_id[0..]) catch {
            // The leaf and intermediates both must be registered; we
            // don't trust the wire's chain alone.
            return if (i == 0) Error.leaf_cert_unknown else Error.chain_intermediate_unknown;
        };
        // The pubkey we stored at issuance must match the wire claim
        // (defence: a forger could supply a different pubkey alongside
        // a real cert id; this check rejects).
        if (!std.crypto.timing_safe.eql([bkds.KEY_LEN]u8, stored.pubkey, link.pubkey)) {
            return if (i == 0) Error.leaf_cert_unknown else Error.chain_intermediate_unknown;
        }
        // (3) parent linkage.  Skip for the root (parent_cert_id null
        // on wire AND on the stored record).
        if (link.parent_cert_id) |claimed_parent| {
            // The stored record must have the same parent.
            if (!stored.has_parent) return Error.chain_parent_mismatch;
            if (!std.mem.eql(u8, stored.parent_cert_id[0..], claimed_parent[0..])) {
                return Error.chain_parent_mismatch;
            }
        } else {
            // Wire claims root; store must agree.
            if (stored.has_parent) return Error.chain_parent_mismatch;
        }
    }

    // Resolve the leaf's caps.  Borrow the strings from the store and
    // dupe into the returned struct so the caller's lifetime is not
    // tied to the store's mutex / churn.
    const leaf_record = try store.get(leaf.cert_id[0..]);
    const caps_dst = allocator.alloc([]const u8, leaf_record.capabilities.len) catch
        return Error.out_of_memory;
    var built: usize = 0;
    errdefer {
        var k: usize = 0;
        while (k < built) : (k += 1) allocator.free(@constCast(caps_dst[k]));
        if (caps_dst.len > 0) allocator.free(caps_dst);
    }
    while (built < leaf_record.capabilities.len) : (built += 1) {
        const owned = allocator.dupe(u8, leaf_record.capabilities[built]) catch
            return Error.out_of_memory;
        caps_dst[built] = owned;
    }

    return .{
        .leaf_cert_id = leaf.cert_id,
        .leaf_pubkey = leaf.pubkey,
        .capabilities = caps_dst,
        .allocator = allocator,
    };
}

// ─────────────────────────────────────────────────────────────────────
// Tests — round-trip + signature property.  Full conformance lives in
// tests/signed_bundle_codec_conformance.zig.
// ─────────────────────────────────────────────────────────────────────

test "encode + decode round-trip" {
    const allocator = std.testing.allocator;
    var chain = [_]CertRef{
        .{
            .cert_id = "0123456789abcdef0123456789abcdef".*,
            .pubkey = blk: {
                const seed = try bkds.pubFromSeed("device-seed-encode");
                break :blk seed;
            },
            .context_tag = 0x10,
            .parent_cert_id = "fedcba9876543210fedcba9876543210".*,
        },
    };
    var nonce: [NONCE_HEX_LEN]u8 = undefined;
    @memcpy(&nonce, "abcdef00112233445566778899aabbccddeeff00112233445566778899aabbcc");
    const recipient: [CERT_ID_HEX_LEN]u8 = "11111111111111111111111111111111".*;
    const b = SignedBundle{
        .sender_cert_chain = chain[0..],
        .recipient_cert_id = recipient,
        .payload_type = "dispatch.request",
        .payload = "{\"v\":1,\"resource\":\"bearer_tokens\",\"cmd\":\"list\",\"args\":null,\"request_id\":\"req-1\"}",
        .signature = [_]u8{0xaa} ** SIG_LEN,
        .signature_metadata = .{
            .nonce_hex = nonce,
            .timestamp_unix = 1_700_000_000,
        },
    };
    const encoded = try encode(allocator, b);
    defer allocator.free(encoded);
    var owned = try decode(allocator, encoded);
    defer owned.deinit();

    try std.testing.expectEqual(@as(u8, ENVELOPE_VERSION), owned.bundle.v);
    try std.testing.expectEqualSlices(u8, "dispatch.request", owned.bundle.payload_type);
    try std.testing.expectEqualSlices(u8, b.payload, owned.bundle.payload);
    try std.testing.expectEqual(@as(usize, 1), owned.bundle.sender_cert_chain.len);
    try std.testing.expectEqualSlices(u8, b.sender_cert_chain[0].cert_id[0..], owned.bundle.sender_cert_chain[0].cert_id[0..]);
    try std.testing.expectEqual(@as(u8, 0x10), owned.bundle.sender_cert_chain[0].context_tag);
    try std.testing.expect(owned.bundle.recipient_cert_id != null);
    try std.testing.expectEqualSlices(u8, recipient[0..], owned.bundle.recipient_cert_id.?[0..]);
    try std.testing.expectEqualSlices(u8, b.signature[0..], owned.bundle.signature[0..]);
    try std.testing.expectEqual(@as(i64, 1_700_000_000), owned.bundle.signature_metadata.timestamp_unix);
}

test "decode rejects unsupported version" {
    const allocator = std.testing.allocator;
    const json =
        \\{"v":99,"sender_cert_chain":[],"recipient_cert_id":null,"payload_type":"x","payload":"x","signature":"00","signature_metadata":{"algorithm":"x","nonce_hex":"00","timestamp_unix":0}}
    ;
    try std.testing.expectError(Error.unsupported_version, decode(allocator, json));
}

test "decode rejects empty chain" {
    const allocator = std.testing.allocator;
    var nonce: [NONCE_HEX_LEN]u8 = undefined;
    @memset(&nonce, '0');
    const json_template =
        \\{"v":1,"sender_cert_chain":[],"recipient_cert_id":null,"payload_type":"x","payload":"x","signature":"
    ++ "00" ** 64 ++ "\",\"signature_metadata\":{\"algorithm\":\"ecdsa-secp256k1-sha256\",\"nonce_hex\":\""
    ++ "0" ** 64 ++ "\",\"timestamp_unix\":0}}";
    try std.testing.expectError(Error.chain_empty, decode(allocator, json_template));
}

test "signBundle + verifySignature round-trip" {
    const allocator = std.testing.allocator;
    const seed = "signed-bundle-codec-roundtrip-2026";
    const priv = bkds.privFromSeed(seed);
    const pubkey = try bkds.pubFromSeed(seed);
    var chain = [_]CertRef{
        .{
            .cert_id = identity_certs.certIdFromPubkey(pubkey),
            .pubkey = pubkey,
            .context_tag = 0x10,
            .parent_cert_id = null,
        },
    };
    var nonce: [NONCE_HEX_LEN]u8 = undefined;
    @memset(&nonce, 'a');
    const recipient: [CERT_ID_HEX_LEN]u8 = "11111111111111111111111111111111".*;
    var b = SignedBundle{
        .sender_cert_chain = chain[0..],
        .recipient_cert_id = recipient,
        .payload_type = "dispatch.request",
        .payload = "{\"v\":1,\"resource\":\"bearer_tokens\",\"cmd\":\"list\",\"args\":null}",
        .signature = [_]u8{0} ** SIG_LEN,
        .signature_metadata = .{
            .nonce_hex = nonce,
            .timestamp_unix = 1_700_000_000,
        },
    };
    try signBundle(allocator, &b, priv);
    try verifySignature(allocator, b, pubkey);

    // Tamper detection — flipping a payload byte breaks the sig.
    var tampered = b;
    tampered.payload = "{\"v\":1,\"resource\":\"bearer_tokens\",\"cmd\":\"revoke\",\"args\":null}";
    try std.testing.expectError(Error.signature_mismatch, verifySignature(allocator, tampered, pubkey));
}

test "canonicalSignaturePreimage excludes signature field" {
    const allocator = std.testing.allocator;
    const seed = "preimage-excludes-sig";
    const pubkey = try bkds.pubFromSeed(seed);
    var chain = [_]CertRef{
        .{
            .cert_id = identity_certs.certIdFromPubkey(pubkey),
            .pubkey = pubkey,
            .context_tag = 0,
            .parent_cert_id = null,
        },
    };
    var nonce: [NONCE_HEX_LEN]u8 = undefined;
    @memset(&nonce, 'b');
    var b = SignedBundle{
        .sender_cert_chain = chain[0..],
        .recipient_cert_id = null,
        .payload_type = "x",
        .payload = "y",
        .signature = [_]u8{0} ** SIG_LEN,
        .signature_metadata = .{
            .nonce_hex = nonce,
            .timestamp_unix = 0,
        },
    };
    const pre1 = try canonicalSignaturePreimage(allocator, b);
    defer allocator.free(pre1);
    b.signature = [_]u8{0xff} ** SIG_LEN;
    const pre2 = try canonicalSignaturePreimage(allocator, b);
    defer allocator.free(pre2);
    try std.testing.expectEqualSlices(u8, pre1, pre2);
}

comptime {
    _ = bsvz;
}

```
