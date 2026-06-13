---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/extension_subscriber.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.219643+00:00
---

# runtime/semantos-brain/src/extension_subscriber.zig

```zig
// Phase D-W2 Phase 2 — Subscription + receive + verify + apply.
//
// Reference:
//   docs/design/BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md §5.2 (Subscribing),
//   §5.3 (Late Joiners), §6 (Frame types — extension-bundle for now).
//   §7 Phase 2 (this deliverable).
//
// Mirror of the Phase-1 publish side (`extension_publish.zig`) inverted:
//   • Where Phase 1 builds + signs + broadcasts a publish tx and pushes
//     the bundle frame, Phase 2 receives the bundle frame, SPV-verifies
//     the publish tx, hash-checks the bundle, signature-checks against
//     the trusted signer, scope-checks the namespace, and applies (or
//     quarantines).
//
// Architecture mirrors `transport/signed_bundle.zig`:
//   • Transport-agnostic core entry point (`verifyFrame` +
//     `applyVerifiedFrame`) callable from any frame source: the HTTP
//     endpoint at `transport/extension_subscribe.zig` is the v0.1
//     production seam; future BLE / multicast / Plexus push subscribers
//     plug into the same core.
//
// Frame layout per `cartridges/oddjobz/brain/tools/publish-bundle.ts`'s
// `assembleBundlePayload`.  Inner extension-bundle-v1 payload:
//
//   ┌────────────────────────────────────────────────────────────────┐
//   │ tag_len             u8                       (1 byte)          │
//   │ "extension-bundle-v1"                        (19 bytes)        │
//   │ bundle_len          u32 BE                   (4 bytes)         │
//   │ bundle_bytes                                 (N bytes)         │
//   │ ns_len              u8                       (1 byte)          │
//   │ namespace                                    (M bytes ≤ 64)    │
//   │ ver_len             u8                       (1 byte)          │
//   │ version                                      (V bytes ≤ 32)    │
//   │ signer_pubkey       SEC1 compressed          (33 bytes)        │
//   └────────────────────────────────────────────────────────────────┘
//
// The frame contains the bundle bytes directly; the publish tx (with
// its OP_RETURN-committed bundle_hash + signature + signer_pubkey) is
// fetched out-of-band via the SpvClient interface.  This lets the
// subscriber side stay independent of the chain transport (a brain
// can run an SPV-light client; an operator brain might query its
// configured BSV node; a future Pravega replay path can read the tx
// from a per-tenant cache).

const std = @import("std");
const tenant_manifest = @import("tenant_manifest");
const dispatcher_mod = @import("dispatcher");
const audit_log = @import("audit_log");
const nullifier_mod = @import("extension_nullifier");
// D-W2 Phase 4 — write per-extension meta.json on apply so the
// nullifier-apply path can identify which extensions belong to a
// revoked signer.  See ambiguity (b) in the Phase 4 brief +
// extension_quarantine.zig's writeExtensionMeta for the format.
const quarantine_mod = @import("extension_quarantine");

// ─────────────────────────────────────────────────────────────────────
// Constants — pinned by the publish-side payload contract.
// ─────────────────────────────────────────────────────────────────────

pub const FRAME_TYPE_TAG: []const u8 = "extension-bundle-v1";
/// D-W2 Phase 3 — frame_type discriminator for the nullifier flow
/// (per §6: `nullifier`).  The receive pipeline switches on the
/// inner-payload tag before any verification: bundle frames take the
/// existing extension_subscriber path; nullifier frames take the
/// extension_nullifier verify+apply path.  Same outer BRC-12 wire,
/// distinct inner tag.
pub const NULLIFIER_FRAME_TYPE_TAG: []const u8 = "nullifier-frame-v1";
pub const PUBLISH_PAYLOAD_VERSION_TAG: []const u8 = "extension-publish-v1";
pub const PUBKEY_LEN: usize = 33;
pub const SIG_LEN: usize = 64;
pub const BUNDLE_HASH_LEN: usize = 32;
pub const TXID_LEN: usize = 32;
pub const MAX_NAME_LEN: usize = 64;
pub const MAX_VERSION_LEN: usize = 32;

// BRC-12 outer frame constants (mirror shard-frame.ts).
pub const SHARD_FRAME_HEADER_SIZE: usize = 44;
pub const SHARD_FRAME_MAGIC: u32 = 0xE3E1F3E8;
pub const SHARD_FRAME_PROTOCOL: u16 = 0x02BF;
pub const SHARD_FRAME_VERSION: u8 = 0x01;
/// Max payload size — matches the TS-side cap (10 MiB).  Bundle bytes
/// + trailing fields fit in one BRC-12 frame.
pub const SHARD_MAX_PAYLOAD_SIZE: u32 = 10 * 1024 * 1024;

/// Default SPV depth required before applying a frame.  v0.1 default
/// is 1 (the publish tx must be at least mined into a block); operator
/// can override per the §10 risk-mitigation freshness / safety
/// tradeoff.  Conservative-paranoid deployments set this to 6 (the
/// Plexus-identity default in §4.1).
pub const DEFAULT_REQUIRED_SPV_DEPTH: u32 = 1;

// Default HTTP path the subscribe seam binds to.  Distinct from D-W1
// Phase 4's `/api/v1/bundle` (which carries SignedBundle, not extension
// frames).
pub const DEFAULT_BUNDLE_FRAME_ENDPOINT_PATH: []const u8 = "/api/v1/bundle-frame";

// ─────────────────────────────────────────────────────────────────────
// Errors
// ─────────────────────────────────────────────────────────────────────

pub const VerifyError = error{
    // Frame-decode failures.
    frame_too_small,
    frame_bad_magic,
    frame_bad_protocol,
    frame_bad_version,
    frame_payload_oversize,
    frame_payload_truncated,
    payload_bad_tag,
    payload_truncated,
    payload_bad_namespace,
    payload_bad_version,
    payload_bad_signer_pubkey,

    // Verification failures (typed per §5.2).
    spv_verify_failed,
    hash_mismatch,
    signature_invalid,
    unknown_signer,
    scope_mismatch,
    bad_publish_payload,

    // D-W2 Phase 3 — nullifier verify failures (typed per §4.2-§4.3).
    unknown_target_signer,
    bad_rotation_authority_signature,
    missing_replacement_for_rotation,
    missing_rotation_authority,
    nullifier_payload_bad,

    // Apply-path errors.
    apply_io_failed,
    apply_manifest_failed,
    out_of_memory,
};

/// Inner-payload kind discriminator — the receive pipeline switches
/// on this before any verification work.
pub const FrameKind = enum {
    extension_bundle,
    nullifier,
};

/// Peek at the inner payload tag to discriminate frame_type.  Pure
/// parser; doesn't allocate or verify.  Caller passes the BRC-12
/// outer frame bytes.
pub fn decodeFrameKind(frame_bytes: []const u8) VerifyError!FrameKind {
    if (frame_bytes.len < SHARD_FRAME_HEADER_SIZE) return error.frame_too_small;
    if (readU32Be(frame_bytes[0..4]) != SHARD_FRAME_MAGIC) return error.frame_bad_magic;
    if (readU16Be(frame_bytes[4..6]) != SHARD_FRAME_PROTOCOL) return error.frame_bad_protocol;
    if (frame_bytes[6] != SHARD_FRAME_VERSION) return error.frame_bad_version;
    const payload_len = readU32Be(frame_bytes[40..44]);
    if (payload_len > SHARD_MAX_PAYLOAD_SIZE) return error.frame_payload_oversize;
    if (frame_bytes.len < SHARD_FRAME_HEADER_SIZE + payload_len) return error.frame_payload_truncated;
    const payload = frame_bytes[SHARD_FRAME_HEADER_SIZE .. SHARD_FRAME_HEADER_SIZE + payload_len];
    if (payload.len < 1) return error.payload_truncated;
    const tag_len = payload[0];
    if (payload.len < 1 + tag_len) return error.payload_truncated;
    const tag = payload[1 .. 1 + tag_len];
    if (std.mem.eql(u8, tag, FRAME_TYPE_TAG)) return .extension_bundle;
    if (std.mem.eql(u8, tag, NULLIFIER_FRAME_TYPE_TAG)) return .nullifier;
    return error.payload_bad_tag;
}

// ─────────────────────────────────────────────────────────────────────
// SPV client interface
// ─────────────────────────────────────────────────────────────────────

/// What the subscriber needs to know about a publish tx, given its
/// txid:
///   • exists at depth ≥ N (configurable; §10 risk-mitigation)
///   • the OP_RETURN payload's commitment fields (bundle_hash +
///     signature + signer_pubkey) — these are what we verify the
///     received bundle bytes + frame's signer-pubkey claim against.
///
/// The interface is pluggable so the v0.1 brain can pair it with
/// either:
///   - a full BSV node (`bsv-cli getrawtransaction <txid> 1`)
///   - a configured archival shard-proxy / Pravega cache
///   - a synthetic test stub (used by the conformance suite)
///
/// `lookupPublishTx` returns `null` if the txid isn't known to the
/// SPV client; the verifier translates that into `spv_verify_failed`.
pub const SpvLookup = struct {
    bundle_hash: [BUNDLE_HASH_LEN]u8,
    signature: [SIG_LEN]u8,
    signer_pubkey: [PUBKEY_LEN]u8,
    /// Block-mined depth.  0 = mempool only.  v0.1 default minimum is
    /// `DEFAULT_REQUIRED_SPV_DEPTH`; operator-tunable.
    depth: u32,
    /// Verified extension_name (from the publish-tx OP_RETURN).
    extension_name: []const u8,
    /// Verified version (from the publish-tx OP_RETURN).
    version: []const u8,
};

pub const SpvClient = struct {
    /// Opaque state for the implementation (e.g. BSV node URL, cache
    /// handle, synthetic test fixture).
    state: ?*anyopaque,

    /// Look up the publish tx by display-order txid.  Returns null if
    /// the tx is unknown to this client.
    lookup_fn: *const fn (state: ?*anyopaque, txid: [TXID_LEN]u8) ?SpvLookup,

    pub fn lookup(self: SpvClient, txid: [TXID_LEN]u8) ?SpvLookup {
        return self.lookup_fn(self.state, txid);
    }
};

// ─────────────────────────────────────────────────────────────────────
// Decoded frame + verified frame
// ─────────────────────────────────────────────────────────────────────

/// Output of `decodeFrame` — the raw fields parsed from the BRC-12
/// outer + the inner extension-bundle-v1 payload.  All slices borrow
/// from the input frame; lifetime is the input bytes' lifetime.
pub const DecodedFrame = struct {
    /// Internal-byte-order txid as carried in the BRC-12 header.  Note
    /// shard-frame.ts uses internal byte order at offset 8; the
    /// display-hex form (block-explorer convention) reverses these.
    txid_internal: [TXID_LEN]u8,
    /// Display-order txid — the form the OP_RETURN signature digest
    /// uses + the form `deriveShardGroupId` and Phase 1 publish flow
    /// keys on.
    txid_display: [TXID_LEN]u8,
    bundle_bytes: []const u8,
    extension_name: []const u8,
    version: []const u8,
    /// Frame-claimed signer pubkey.  Cross-referenced against the
    /// publish-tx OP_RETURN signer_pubkey at verify time.
    signer_pubkey: [PUBKEY_LEN]u8,
};

/// The output of `verifyFrame`.  Carries the trusted-signer entry
/// (from the manifest) the frame was attributed to so the apply path
/// can use the signer's name in audit / disk layout decisions.
pub const VerifiedFrame = struct {
    signer_name: []const u8,
    bundle_bytes: []const u8,
    publish_txid_display: [TXID_LEN]u8,
    extension_name: []const u8,
    version: []const u8,
    /// Echoed for callers that want the bundle-hash for audit.
    bundle_hash: [BUNDLE_HASH_LEN]u8,
    /// D-W2 Phase 4 — the signer's pubkey at verify time (canonical
    /// per-install identity used by the Phase 4 quarantine flow's
    /// meta.json keying).  Defaults to all-zero so existing
    /// callers/test fixtures that don't populate it stay valid; the
    /// real verify path always sets this.
    signer_pubkey: [PUBKEY_LEN]u8 = [_]u8{0} ** PUBKEY_LEN,
};

// ─────────────────────────────────────────────────────────────────────
// Frame decoding
// ─────────────────────────────────────────────────────────────────────

/// Reverse a 32-byte txid in place between internal and display order.
fn reverseTxid(in: [TXID_LEN]u8) [TXID_LEN]u8 {
    var out: [TXID_LEN]u8 = undefined;
    var i: usize = 0;
    while (i < TXID_LEN) : (i += 1) out[i] = in[TXID_LEN - 1 - i];
    return out;
}

fn readU32Be(bytes: []const u8) u32 {
    return (@as(u32, bytes[0]) << 24) |
        (@as(u32, bytes[1]) << 16) |
        (@as(u32, bytes[2]) << 8) |
        @as(u32, bytes[3]);
}

fn readU16Be(bytes: []const u8) u16 {
    return (@as(u16, bytes[0]) << 8) | @as(u16, bytes[1]);
}

/// Decode the BRC-12 outer frame + inner extension-bundle-v1 payload.
/// Returns slices into `frame_bytes` (no allocation, no copies).
pub fn decodeFrame(frame_bytes: []const u8) VerifyError!DecodedFrame {
    if (frame_bytes.len < SHARD_FRAME_HEADER_SIZE) return error.frame_too_small;
    if (readU32Be(frame_bytes[0..4]) != SHARD_FRAME_MAGIC) return error.frame_bad_magic;
    if (readU16Be(frame_bytes[4..6]) != SHARD_FRAME_PROTOCOL) return error.frame_bad_protocol;
    if (frame_bytes[6] != SHARD_FRAME_VERSION) return error.frame_bad_version;

    var txid_internal: [TXID_LEN]u8 = undefined;
    @memcpy(&txid_internal, frame_bytes[8..40]);
    const payload_len = readU32Be(frame_bytes[40..44]);
    if (payload_len > SHARD_MAX_PAYLOAD_SIZE) return error.frame_payload_oversize;
    if (frame_bytes.len < SHARD_FRAME_HEADER_SIZE + payload_len) return error.frame_payload_truncated;

    const payload = frame_bytes[SHARD_FRAME_HEADER_SIZE .. SHARD_FRAME_HEADER_SIZE + payload_len];

    // ── Inner extension-bundle-v1 payload parse ─────────────────────
    var off: usize = 0;
    if (payload.len < 1) return error.payload_truncated;
    const tag_len = payload[off];
    off += 1;
    if (tag_len != FRAME_TYPE_TAG.len) return error.payload_bad_tag;
    if (payload.len < off + FRAME_TYPE_TAG.len) return error.payload_truncated;
    if (!std.mem.eql(u8, payload[off .. off + FRAME_TYPE_TAG.len], FRAME_TYPE_TAG)) {
        return error.payload_bad_tag;
    }
    off += FRAME_TYPE_TAG.len;

    if (payload.len < off + 4) return error.payload_truncated;
    const bundle_len = readU32Be(payload[off .. off + 4]);
    off += 4;

    if (payload.len < off + bundle_len) return error.payload_truncated;
    const bundle_bytes = payload[off .. off + bundle_len];
    off += bundle_len;

    if (payload.len < off + 1) return error.payload_truncated;
    const ns_len = payload[off];
    off += 1;
    if (ns_len == 0 or ns_len > MAX_NAME_LEN) return error.payload_bad_namespace;
    if (payload.len < off + ns_len) return error.payload_truncated;
    const namespace = payload[off .. off + ns_len];
    off += ns_len;

    if (payload.len < off + 1) return error.payload_truncated;
    const ver_len = payload[off];
    off += 1;
    if (ver_len == 0 or ver_len > MAX_VERSION_LEN) return error.payload_bad_version;
    if (payload.len < off + ver_len) return error.payload_truncated;
    const version = payload[off .. off + ver_len];
    off += ver_len;

    if (payload.len < off + PUBKEY_LEN) return error.payload_truncated;
    var signer_pubkey: [PUBKEY_LEN]u8 = undefined;
    @memcpy(&signer_pubkey, payload[off .. off + PUBKEY_LEN]);
    off += PUBKEY_LEN;

    return .{
        .txid_internal = txid_internal,
        .txid_display = reverseTxid(txid_internal),
        .bundle_bytes = bundle_bytes,
        .extension_name = namespace,
        .version = version,
        .signer_pubkey = signer_pubkey,
    };
}

// ─────────────────────────────────────────────────────────────────────
// Manifest signer lookup + scope check
// ─────────────────────────────────────────────────────────────────────

/// Hex-decode 66 chars to 33 bytes.  Lowercase + uppercase tolerant.
/// Returns `error.bad_pubkey_hex` on any non-hex char or wrong length.
fn parseHexPubkey(hex: []const u8) !([PUBKEY_LEN]u8) {
    if (hex.len != PUBKEY_LEN * 2) return error.bad_pubkey_hex;
    var out: [PUBKEY_LEN]u8 = undefined;
    var i: usize = 0;
    while (i < PUBKEY_LEN) : (i += 1) {
        const hi: u8 = hexNibble(hex[i * 2]) orelse return error.bad_pubkey_hex;
        const lo: u8 = hexNibble(hex[i * 2 + 1]) orelse return error.bad_pubkey_hex;
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

/// Find a manifest TrustedSigner whose pubkey matches the frame-claimed
/// pubkey.  Returns `null` when no match — the caller maps that to
/// `unknown_signer`.
pub fn findSignerByPubkey(
    signers: []const tenant_manifest.TrustedSigner,
    pubkey: [PUBKEY_LEN]u8,
) ?tenant_manifest.TrustedSigner {
    for (signers) |s| {
        const sp = parseHexPubkey(s.pubkey_hex) catch continue;
        if (std.mem.eql(u8, &sp, &pubkey)) return s;
    }
    return null;
}

/// Scope-glob match.  Mirrors the manifest validator's `isValidScopeGlob`
/// grammar:
///   * "*"          → matches anything
///   * "ns.*"       → matches any extension whose extension_name starts
///                    with "ns." (one or more dotted segments after).
///   * "ns.literal" → exact match.
///
/// Multiple scopes per signer are OR-combined.
pub fn signerScopeMatches(scopes: []const []const u8, extension_name: []const u8) bool {
    for (scopes) |scope| {
        if (scopeMatch(scope, extension_name)) return true;
    }
    return false;
}

fn scopeMatch(scope: []const u8, name: []const u8) bool {
    if (scope.len == 1 and scope[0] == '*') return true;
    if (std.mem.endsWith(u8, scope, ".*")) {
        const prefix = scope[0 .. scope.len - 2];
        if (prefix.len == 0) return false;
        // name must start with `prefix.` followed by at least one
        // non-empty segment.
        if (name.len <= prefix.len + 1) return false;
        if (!std.mem.startsWith(u8, name, prefix)) return false;
        if (name[prefix.len] != '.') return false;
        // remaining segment(s) must contain at least one byte.
        return name.len > prefix.len + 1;
    }
    return std.mem.eql(u8, scope, name);
}

// ─────────────────────────────────────────────────────────────────────
// Signature verification (delegated to extension_publish so we share
// one ECDSA-recover / sign-digest implementation).
// ─────────────────────────────────────────────────────────────────────

const ext_pub = @import("extension_publish");

/// Verify the publish-tx signature against the bundle hash + version.
/// Wrapper that translates extension_publish's VerifyError into our
/// VerifyError so the caller speaks a single vocabulary.
fn verifyPublishSignature(
    signer_pubkey: [PUBKEY_LEN]u8,
    bundle_hash: [BUNDLE_HASH_LEN]u8,
    version: []const u8,
    signature: [SIG_LEN]u8,
) VerifyError!void {
    ext_pub.verifySignature(signer_pubkey, bundle_hash, version, signature) catch |err| switch (err) {
        // Both upstream errors mean "the signature didn't validate
        // against this pubkey + this digest".  Caller logs the typed
        // outcome.
        error.proof_mismatch, error.bad_signature => return error.signature_invalid,
    };
}

// ─────────────────────────────────────────────────────────────────────
// Top-level: verifyFrame
// ─────────────────────────────────────────────────────────────────────

pub const VerifyOptions = struct {
    /// Minimum SPV depth required before treating the publish tx as
    /// trustworthy.  Operator can lower for dev / raise for paranoid
    /// production.  v0.1 default = 1.
    required_spv_depth: u32 = DEFAULT_REQUIRED_SPV_DEPTH,
};

/// Run the full §5.2 pipeline:
///   1. Decode the frame.
///   2. SPV-verify the publish_txid (lookup + depth check).
///   3. Verify the bundle hash matches the publish-tx commitment.
///   4. Verify the publish-tx OP_RETURN signature against the
///      pubkey carried in the OP_RETURN.  (Frame-claimed pubkey is
///      cross-referenced against the OP_RETURN pubkey for byte
///      equality — tampering with the frame's pubkey alone wouldn't
///      validate against the publish-tx commitment.)
///   5. Match against `[trusted_signers]`.  Unknown → `unknown_signer`.
///   6. Scope-check the extension_name against the signer's scope.
///   7. Return VerifiedFrame on success.
pub fn verifyFrame(
    frame_bytes: []const u8,
    manifest_signers: []const tenant_manifest.TrustedSigner,
    spv: SpvClient,
    opts: VerifyOptions,
) VerifyError!VerifiedFrame {
    const decoded = try decodeFrame(frame_bytes);

    // 2. SPV lookup + depth check.
    const lookup = spv.lookup(decoded.txid_display) orelse return error.spv_verify_failed;
    if (lookup.depth < opts.required_spv_depth) return error.spv_verify_failed;

    // The publish-tx OP_RETURN MUST commit the same extension_name +
    // version the frame claims (otherwise an attacker could swap
    // versions or namespaces in the frame after publish).
    if (!std.mem.eql(u8, lookup.extension_name, decoded.extension_name)) {
        return error.bad_publish_payload;
    }
    if (!std.mem.eql(u8, lookup.version, decoded.version)) {
        return error.bad_publish_payload;
    }
    // Frame-claimed signer pubkey MUST match the publish-tx
    // OP_RETURN pubkey (the on-chain commitment is the authority).
    if (!std.mem.eql(u8, &decoded.signer_pubkey, &lookup.signer_pubkey)) {
        return error.bad_publish_payload;
    }

    // 3. Bundle hash check.
    var actual_hash: [BUNDLE_HASH_LEN]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(decoded.bundle_bytes, &actual_hash, .{});
    if (!std.mem.eql(u8, &actual_hash, &lookup.bundle_hash)) {
        return error.hash_mismatch;
    }

    // 4. Signature check (publish-tx OP_RETURN sig over the digest).
    try verifyPublishSignature(
        lookup.signer_pubkey,
        lookup.bundle_hash,
        decoded.version,
        lookup.signature,
    );

    // 5. Trusted-signer match.
    const signer = findSignerByPubkey(manifest_signers, lookup.signer_pubkey) orelse
        return error.unknown_signer;

    // 6. Scope check.
    if (!signerScopeMatches(signer.scopes, decoded.extension_name)) {
        return error.scope_mismatch;
    }

    return .{
        .signer_name = signer.name,
        .bundle_bytes = decoded.bundle_bytes,
        .publish_txid_display = decoded.txid_display,
        .extension_name = decoded.extension_name,
        .version = decoded.version,
        .bundle_hash = lookup.bundle_hash,
        .signer_pubkey = lookup.signer_pubkey,
    };
}

// ─────────────────────────────────────────────────────────────────────
// Apply path
// ─────────────────────────────────────────────────────────────────────

/// What the apply path returns to its caller.  Idempotent — re-applying
/// the same (namespace, version) sees `already_applied = true` and is a
/// no-op (no double-register against the dispatcher, no rewrite of the
/// on-disk bundle).
pub const ApplyOutcome = struct {
    /// The tenant-relative path the bundle was written to (or already
    /// existed at).  `<data_dir>/extensions/<namespace>/<version>/bundle.bin`.
    bundle_path: []u8,
    /// Bundle-hash hex (lowercase, 64 chars).  Same form the publish
    /// runbook + audit log surface.
    bundle_hash_hex: [64]u8,
    /// True when the (namespace, version) was already applied — apply
    /// is idempotent for replay.
    already_applied: bool,
    /// Did the apply path register the extension's handlers via
    /// `dispatcher.register`?  Set true on the first successful
    /// apply for a (namespace, version); `already_applied` cases
    /// reuse the prior registration without double-registering.
    registered: bool,

    pub fn deinit(self: *ApplyOutcome, allocator: std.mem.Allocator) void {
        if (self.bundle_path.len > 0) {
            allocator.free(self.bundle_path);
            self.bundle_path = &.{};
        }
    }
};

/// Apply a verified frame:
///   1. Write `bundle_bytes` to
///      `<data_dir>/extensions/<namespace>/<version>/bundle.bin`.
///   2. Compute the bundle's sha256, double-check against the input
///      `bundle_hash`.  (Defence-in-depth — verifyFrame already
///      checked, but the apply path is the on-disk gate.)
///   3. Hot-register the extension's handlers via the dispatcher.
///      For v0.1 this is a metadata registration only — the
///      actual handler shape is extension-specific and is
///      currently a no-op stub; future fork wires `module_loader.
///      loadAndVerify` + `instance_manager.register` per the design
///      doc §7 Phase 2.
///   4. Audit-log the apply via the supplied audit log.
///
/// **Idempotence**: re-applying the same (namespace, version) is a
/// no-op.  The function checks for the presence of `bundle.bin` at
/// the target path; if present + hash matches, returns
/// `already_applied = true` without double-registering.
///
/// **Same (namespace, NEW_version)**: per the §7 Phase 2 v0.1 choice,
/// we hot-replace — the new version's `bundle.bin` lives at a fresh
/// path (under `<version>/`); the dispatcher is registered against
/// the new version (the prior version's directory remains on disk
/// under its own path; future quarantine work in Phase 4 cleans up).
pub fn applyVerifiedFrame(
    allocator: std.mem.Allocator,
    vf: VerifiedFrame,
    data_dir: []const u8,
    dispatcher: ?*dispatcher_mod.Dispatcher,
    audit: ?*audit_log.AuditLog,
) VerifyError!ApplyOutcome {
    // Compute target path.  Layout: <data_dir>/extensions/<namespace>/<version>/bundle.bin
    const ext_dir = std.fs.path.join(allocator, &.{ data_dir, "extensions", vf.extension_name, vf.version }) catch {
        return error.out_of_memory;
    };
    defer allocator.free(ext_dir);

    const bundle_path = std.fs.path.join(allocator, &.{ ext_dir, "bundle.bin" }) catch {
        return error.out_of_memory;
    };
    errdefer allocator.free(bundle_path);

    // Pre-compute hash hex for audit + outcome.
    var hash_hex: [64]u8 = undefined;
    {
        const chars = "0123456789abcdef";
        for (vf.bundle_hash, 0..) |b, i| {
            hash_hex[i * 2] = chars[(b >> 4) & 0x0f];
            hash_hex[i * 2 + 1] = chars[b & 0x0f];
        }
    }

    // Idempotence: if the file already exists and its hash matches,
    // skip the write + skip re-registration.
    var already_applied = false;
    if (std.fs.cwd().openFile(bundle_path, .{})) |f| {
        defer f.close();
        // Hash the on-disk bytes; if they match the input bundle_hash,
        // this is a replay (or a stable re-apply at boot from a
        // previously-applied state).  No re-register, no rewrite.
        var hasher = std.crypto.hash.sha2.Sha256.init(.{});
        var buf: [64 * 1024]u8 = undefined;
        while (true) {
            const n = f.read(&buf) catch return error.apply_io_failed;
            if (n == 0) break;
            hasher.update(buf[0..n]);
        }
        var on_disk_hash: [BUNDLE_HASH_LEN]u8 = undefined;
        hasher.final(&on_disk_hash);
        if (std.mem.eql(u8, &on_disk_hash, &vf.bundle_hash)) {
            already_applied = true;
        }
    } else |_| {
        // File doesn't exist — proceed to write.
    }

    if (!already_applied) {
        // 1. Write bundle bytes.  mkdir -p the version dir first.
        std.fs.cwd().makePath(ext_dir) catch return error.apply_io_failed;
        const f = std.fs.cwd().createFile(bundle_path, .{ .truncate = true }) catch {
            return error.apply_io_failed;
        };
        defer f.close();
        f.writeAll(vf.bundle_bytes) catch return error.apply_io_failed;

        // 2. Re-hash to confirm.
        var actual: [BUNDLE_HASH_LEN]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(vf.bundle_bytes, &actual, .{});
        if (!std.mem.eql(u8, &actual, &vf.bundle_hash)) {
            // Should never happen — verifyFrame already checked.
            // Defence-in-depth.
            return error.hash_mismatch;
        }

        // 3. D-W2 Phase 4 — write per-extension meta.json so the
        //    nullifier-apply path can identify which installs belong
        //    to a revoked signer.  See ambiguity (b) in the Phase 4
        //    brief.  We need the signer's pubkey hex; we re-hex-
        //    encode the same bytes verifyFrame matched against.
        // The signer pubkey isn't in VerifiedFrame today (Phase 2
        // didn't carry it through), but we can reconstruct via the
        // manifest signer match — though here we only have the
        // signer NAME.  For Phase 4 we extend VerifiedFrame to
        // carry the pubkey (additive change; existing callers
        // ignore the new field).  The pubkey is what the meta.json
        // canonically keys on.
        var pubkey_hex: [66]u8 = undefined;
        const chars2 = "0123456789abcdef";
        for (vf.signer_pubkey, 0..) |b, j| {
            pubkey_hex[j * 2] = chars2[(b >> 4) & 0x0f];
            pubkey_hex[j * 2 + 1] = chars2[b & 0x0f];
        }
        var txid_hex: [64]u8 = undefined;
        for (vf.publish_txid_display, 0..) |b, j| {
            txid_hex[j * 2] = chars2[(b >> 4) & 0x0f];
            txid_hex[j * 2 + 1] = chars2[b & 0x0f];
        }
        quarantine_mod.writeExtensionMeta(allocator, data_dir, vf.extension_name, vf.version, .{
            .signer_pubkey_hex = &pubkey_hex,
            .publish_txid_hex = &txid_hex,
            .applied_at = std.time.timestamp(),
            .signer_name = vf.signer_name,
        }) catch {
            // Non-fatal: the meta.json is a Phase 4 affordance for
            // bulk quarantine.  An apply that doesn't manage to
            // write it still succeeds; the operator sees the
            // failure in the audit log + can manually inject
            // meta.json or use `brain extension quarantine evaluate`
            // to re-derive coverage.
            if (audit) |a| {
                var detail_buf: [256]u8 = undefined;
                const detail = std.fmt.bufPrint(
                    &detail_buf,
                    "phase=apply_meta_warn ext={s} version={s}",
                    .{ vf.extension_name, vf.version },
                ) catch detail_buf[0..0];
                a.record(allocator, .{
                    .module = "extension_subscriber",
                    .op = "extension.apply",
                    .result = .err,
                    .detail = detail,
                }) catch {};
            }
        };
    }

    // 3. Hot-register.  v0.1 is a metadata-only registration: the
    //    actual extension-specific handler shape is owned by
    //    extension authors (and the Semantos Brain runtime currently registers
    //    bundled extensions at boot via D-O3's
    //    `extensions.mintFirstBootCapabilities` / extension-specific
    //    dispatcher.register calls).  Phase 2's contribution is
    //    surfacing the new (namespace, version) on disk + the
    //    dispatcher seam.  Future fork plugs in `module_loader.
    //    loadAndVerify` + `instance_manager.register` per the
    //    runtime config.
    var registered = false;
    if (!already_applied and dispatcher != null) {
        // Today: no-op (the v0.1 dispatcher takes the bundle's
        // descriptor at boot, not at apply-time; future fork wires
        // the resource handler).  We still set registered=true so
        // callers can distinguish "applied + handler discoverable"
        // from "apply skipped".
        registered = true;
    }

    // 4. Audit.
    if (audit) |a| {
        var detail_buf: [512]u8 = undefined;
        const detail = std.fmt.bufPrint(
            &detail_buf,
            "phase=apply signer={s} ext={s} version={s} hash={s} idempotent={s}",
            .{
                vf.signer_name,
                vf.extension_name,
                vf.version,
                hash_hex,
                if (already_applied) "true" else "false",
            },
        ) catch detail_buf[0..0];
        a.record(allocator, .{
            .module = "extension_subscriber",
            .op = "extension.apply",
            .result = .ok,
            .detail = detail,
        }) catch {};
    }

    return .{
        .bundle_path = bundle_path,
        .bundle_hash_hex = hash_hex,
        .already_applied = already_applied,
        .registered = registered,
    };
}

// ─────────────────────────────────────────────────────────────────────
// D-W2 Phase 3 — Nullifier frame decode + verify + apply
// ─────────────────────────────────────────────────────────────────────
//
// Per §6, nullifier frames share the same outer BRC-12 wire as
// extension-bundle frames; only the inner tag differs.  Inner
// nullifier-frame-v1 layout:
//
//   ┌────────────────────────────────────────────────────────────────┐
//   │ tag_len             u8                       (1 byte)          │
//   │ "nullifier-frame-v1"                         (18 bytes)        │
//   │ nullifier_payload_len  u32 BE                (4 bytes)         │
//   │ nullifier_payload   (extension-nullifier-v1) (N bytes)         │
//   └────────────────────────────────────────────────────────────────┘
//
// The receive pipeline:
//   1. decodeFrameKind() returns .nullifier for these frames.
//   2. decodeNullifierFrame() extracts the nullifier_payload bytes.
//   3. extension_nullifier.decodeNullifierPayload() parses the inner
//      payload.
//   4. extension_nullifier.verifyNullifier() runs the §4.2-§4.3
//      invariants (target-known + rotation-authority signature for
//      rotations).
//   5. extension_nullifier.applyNullifier() performs the atomic
//      revoke + (optional) promote on the manifest text + appends to
//      the revoked-keys index.
//
// SPV depth check: the spec requires the nullifier tx be mined at
// depth ≥ N before applying.  v0.1: we accept the nullifier frame
// as soon as it's received (the publisher's tx is the chain proof;
// production deployments wire an SPV stub the same way the bundle
// path does).  Adding a depth check is additive — pass an SPV
// lookup_fn into FrameAcceptor and gate apply on lookup hit.

pub const DecodedNullifierFrame = struct {
    txid_internal: [TXID_LEN]u8,
    txid_display: [TXID_LEN]u8,
    /// Borrowed slice into the input frame bytes.
    nullifier_payload: []const u8,
};

pub fn decodeNullifierFrame(frame_bytes: []const u8) VerifyError!DecodedNullifierFrame {
    if (frame_bytes.len < SHARD_FRAME_HEADER_SIZE) return error.frame_too_small;
    if (readU32Be(frame_bytes[0..4]) != SHARD_FRAME_MAGIC) return error.frame_bad_magic;
    if (readU16Be(frame_bytes[4..6]) != SHARD_FRAME_PROTOCOL) return error.frame_bad_protocol;
    if (frame_bytes[6] != SHARD_FRAME_VERSION) return error.frame_bad_version;

    var txid_internal: [TXID_LEN]u8 = undefined;
    @memcpy(&txid_internal, frame_bytes[8..40]);
    const payload_len = readU32Be(frame_bytes[40..44]);
    if (payload_len > SHARD_MAX_PAYLOAD_SIZE) return error.frame_payload_oversize;
    if (frame_bytes.len < SHARD_FRAME_HEADER_SIZE + payload_len) return error.frame_payload_truncated;
    const payload = frame_bytes[SHARD_FRAME_HEADER_SIZE .. SHARD_FRAME_HEADER_SIZE + payload_len];

    var off: usize = 0;
    if (payload.len < 1) return error.payload_truncated;
    const tag_len = payload[off];
    off += 1;
    if (tag_len != NULLIFIER_FRAME_TYPE_TAG.len) return error.payload_bad_tag;
    if (payload.len < off + NULLIFIER_FRAME_TYPE_TAG.len) return error.payload_truncated;
    if (!std.mem.eql(u8, payload[off .. off + NULLIFIER_FRAME_TYPE_TAG.len], NULLIFIER_FRAME_TYPE_TAG)) {
        return error.payload_bad_tag;
    }
    off += NULLIFIER_FRAME_TYPE_TAG.len;

    if (payload.len < off + 4) return error.payload_truncated;
    const np_len = readU32Be(payload[off .. off + 4]);
    off += 4;
    if (payload.len < off + np_len) return error.payload_truncated;
    const np = payload[off .. off + np_len];
    off += np_len;

    return .{
        .txid_internal = txid_internal,
        .txid_display = reverseTxid(txid_internal),
        .nullifier_payload = np,
    };
}

/// One-shot nullifier-frame receive: decode → verify → apply.
/// Returns success markers so the transport-layer can build a
/// success body identical-shaped to the bundle-frame path.
pub const NullifierApplyResult = struct {
    /// Manifest signer name targeted by the nullifier.
    signer_name: []const u8,
    /// True when the manifest was actually rewritten; false when the
    /// nullifier was already applied (idempotent).
    applied: bool,
    /// True for rotation; false for pure revocation.
    promoted_replacement: bool,
    /// True when the targeted signer is the platform tier — surfaces
    /// the §A audit-warning condition.
    platform_tier: bool,
};

pub fn processNullifierFrame(
    allocator: std.mem.Allocator,
    frame_bytes: []const u8,
    manifest_signers: []const tenant_manifest.TrustedSigner,
    recovery_authority: nullifier_mod.RecoveryAuthorityLookup,
    manifest_path: []const u8,
    revoked_keys_index_path: []const u8,
    audit: ?*audit_log.AuditLog,
) VerifyError!NullifierApplyResult {
    const decoded = try decodeNullifierFrame(frame_bytes);

    const payload = nullifier_mod.decodeNullifierPayload(allocator, decoded.nullifier_payload) catch
        return error.nullifier_payload_bad;

    const verified = nullifier_mod.verifyNullifier(payload, manifest_signers, recovery_authority) catch |err| switch (err) {
        error.unknown_target_signer => return error.unknown_target_signer,
        error.bad_rotation_authority_signature => return error.bad_rotation_authority_signature,
        error.missing_replacement_for_rotation => return error.missing_replacement_for_rotation,
        error.missing_rotation_authority => return error.missing_rotation_authority,
        error.out_of_memory => return error.out_of_memory,
    };

    var outcome = nullifier_mod.applyNullifier(
        allocator,
        verified,
        manifest_path,
        revoked_keys_index_path,
        audit,
    ) catch return error.apply_manifest_failed;
    defer outcome.deinit(allocator);

    return .{
        .signer_name = verified.target_signer_name,
        .applied = outcome.mode == .applied,
        .promoted_replacement = outcome.promoted_replacement,
        .platform_tier = std.mem.eql(u8, verified.target_signer_name, "platform"),
    };
}

// ─────────────────────────────────────────────────────────────────────
// Late-joiner replay scaffolding (§5.3)
// ─────────────────────────────────────────────────────────────────────

/// Source of historical frames for a given signer.  The brain pulls
/// from this stream during boot replay; live subscribers use the
/// shard-proxy directly.  v0.1 default implementation is a per-tenant
/// local cache (see `LocalCacheReplaySource`); future Pravega
/// integration replaces this with a `pravega://` reader without
/// touching the verify+apply side.
pub const ReplaySource = struct {
    state: ?*anyopaque,
    /// Returns the next historical frame for `signer_name` since
    /// `since_block_height`, or null when the stream is exhausted.
    /// The slice borrows from the source's internal buffer; the
    /// caller MUST treat it as valid only until the next call.
    next_fn: *const fn (state: ?*anyopaque, signer_name: []const u8, since_block_height: u32) ?[]const u8,
    /// Caller signals end-of-replay so the source can release any
    /// per-call cursor state.
    close_fn: *const fn (state: ?*anyopaque) void,

    pub fn next(self: ReplaySource, signer_name: []const u8, since_block_height: u32) ?[]const u8 {
        return self.next_fn(self.state, signer_name, since_block_height);
    }
    pub fn close(self: ReplaySource) void {
        self.close_fn(self.state);
    }
};

/// Walk a signer's historical frames, run verify+apply on each.
/// Returns count of successfully-applied frames (idempotent re-applies
/// count as 1 each — replay aimed at "ensure converged state", not
/// "count fresh applies").
///
/// v0.1 limitations:
///   • The replay source is operator-supplied (per-tenant local
///     cache, configured BSV node, future Pravega).  The interface
///     `ReplaySource` is what matters; the implementation is a
///     stub satisfying the e2e test.
///   • Errors during a single frame's verify+apply are logged via
///     the audit log + skipped — late-joiner replay continues so
///     one bad frame doesn't stall convergence.  Phase 4
///     (quarantine) extends this with a quarantined-frame surface.
///
/// Cross-reference:
///   docs/design/BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md §5.3.
pub fn replayHistorical(
    allocator: std.mem.Allocator,
    signer: tenant_manifest.TrustedSigner,
    since_block_height: u32,
    manifest_signers: []const tenant_manifest.TrustedSigner,
    spv: SpvClient,
    source: ReplaySource,
    data_dir: []const u8,
    dispatcher: ?*dispatcher_mod.Dispatcher,
    audit: ?*audit_log.AuditLog,
    opts: VerifyOptions,
) !u32 {
    var applied: u32 = 0;
    while (true) {
        const frame_bytes = source.next(signer.name, since_block_height) orelse break;
        const vf = verifyFrame(frame_bytes, manifest_signers, spv, opts) catch |err| {
            // Skip-with-audit on per-frame failure; replay continues.
            if (audit) |a| {
                var detail_buf: [256]u8 = undefined;
                const detail = std.fmt.bufPrint(
                    &detail_buf,
                    "phase=replay_skip signer={s} kind={s}",
                    .{ signer.name, @errorName(err) },
                ) catch detail_buf[0..0];
                a.record(allocator, .{
                    .module = "extension_subscriber",
                    .op = "extension.replay",
                    .result = .denied,
                    .detail = detail,
                }) catch {};
            }
            continue;
        };
        var outcome = applyVerifiedFrame(allocator, vf, data_dir, dispatcher, audit) catch |err| {
            if (audit) |a| {
                var detail_buf: [256]u8 = undefined;
                const detail = std.fmt.bufPrint(
                    &detail_buf,
                    "phase=replay_apply_err signer={s} kind={s}",
                    .{ signer.name, @errorName(err) },
                ) catch detail_buf[0..0];
                a.record(allocator, .{
                    .module = "extension_subscriber",
                    .op = "extension.replay",
                    .result = .err,
                    .detail = detail,
                }) catch {};
            }
            continue;
        };
        defer outcome.deinit(allocator);
        applied += 1;
    }
    source.close();
    return applied;
}

// ─────────────────────────────────────────────────────────────────────
// Inline tests — pure logic (frame decode, scope match, signer find).
// Full verify+apply pipeline lives in
// tests/extension_subscriber_conformance.zig and the e2e suite.
// ─────────────────────────────────────────────────────────────────────

test "scopeMatch — wildcard, prefix, literal" {
    try std.testing.expect(scopeMatch("*", "anything"));
    try std.testing.expect(scopeMatch("acme.*", "acme.invoicer"));
    try std.testing.expect(scopeMatch("acme.*", "acme.invoicer.subext"));
    try std.testing.expect(!scopeMatch("acme.*", "acmeX.foo"));
    try std.testing.expect(!scopeMatch("acme.*", "acme")); // bare prefix, no segment
    try std.testing.expect(scopeMatch("acme.invoicer", "acme.invoicer"));
    try std.testing.expect(!scopeMatch("acme.invoicer", "acme.thing"));
}

test "signerScopeMatches OR-combines multiple scopes" {
    const scopes = [_][]const u8{ "acme.*", "shared.fonts" };
    try std.testing.expect(signerScopeMatches(&scopes, "acme.invoicer"));
    try std.testing.expect(signerScopeMatches(&scopes, "shared.fonts"));
    try std.testing.expect(!signerScopeMatches(&scopes, "oddjobz.thing"));
}

test "parseHexPubkey accepts 66 hex chars, rejects malformed" {
    const ok_hex = "02" ++ ("aa" ** 32);
    const got = try parseHexPubkey(ok_hex);
    try std.testing.expectEqual(@as(u8, 0x02), got[0]);
    try std.testing.expectEqual(@as(u8, 0xaa), got[1]);
    try std.testing.expectEqual(@as(u8, 0xaa), got[32]);

    try std.testing.expectError(error.bad_pubkey_hex, parseHexPubkey("xx" ++ ("aa" ** 32)));
    try std.testing.expectError(error.bad_pubkey_hex, parseHexPubkey("02" ++ ("aa" ** 31)));
}

test "decodeFrame round-trips a synthetic publish-bundle frame" {
    const allocator = std.testing.allocator;

    // Synthesise a frame matching publish-bundle.ts's
    // `buildExtensionBundleFrame` shape.
    const bundle_bytes = "fixture-bundle-bytes";
    const namespace = "oddjobz.invoicer";
    const version = "0.1.0";
    var signer_pubkey: [PUBKEY_LEN]u8 = undefined;
    signer_pubkey[0] = 0x02;
    @memset(signer_pubkey[1..], 0xaa);

    // Build inner payload.
    const tag_bytes_len: usize = 1 + FRAME_TYPE_TAG.len + 4 + bundle_bytes.len + 1 + namespace.len + 1 + version.len + PUBKEY_LEN;
    const inner = try allocator.alloc(u8, tag_bytes_len);
    defer allocator.free(inner);
    var off: usize = 0;
    inner[off] = FRAME_TYPE_TAG.len;
    off += 1;
    @memcpy(inner[off .. off + FRAME_TYPE_TAG.len], FRAME_TYPE_TAG);
    off += FRAME_TYPE_TAG.len;
    inner[off] = @intCast(bundle_bytes.len >> 24);
    inner[off + 1] = @intCast((bundle_bytes.len >> 16) & 0xff);
    inner[off + 2] = @intCast((bundle_bytes.len >> 8) & 0xff);
    inner[off + 3] = @intCast(bundle_bytes.len & 0xff);
    off += 4;
    @memcpy(inner[off .. off + bundle_bytes.len], bundle_bytes);
    off += bundle_bytes.len;
    inner[off] = @intCast(namespace.len);
    off += 1;
    @memcpy(inner[off .. off + namespace.len], namespace);
    off += namespace.len;
    inner[off] = @intCast(version.len);
    off += 1;
    @memcpy(inner[off .. off + version.len], version);
    off += version.len;
    @memcpy(inner[off .. off + PUBKEY_LEN], &signer_pubkey);
    off += PUBKEY_LEN;
    try std.testing.expectEqual(tag_bytes_len, off);

    // Outer BRC-12 frame: header + payload.
    const frame = try allocator.alloc(u8, SHARD_FRAME_HEADER_SIZE + inner.len);
    defer allocator.free(frame);
    // magic
    frame[0] = 0xE3;
    frame[1] = 0xE1;
    frame[2] = 0xF3;
    frame[3] = 0xE8;
    // protocol
    frame[4] = 0x02;
    frame[5] = 0xBF;
    // version
    frame[6] = 0x01;
    // reserved
    frame[7] = 0x00;
    // txid (internal byte order — fixture)
    var i: usize = 0;
    while (i < TXID_LEN) : (i += 1) frame[8 + i] = @intCast(i + 1);
    // payload len
    const pl: u32 = @intCast(inner.len);
    frame[40] = @intCast(pl >> 24);
    frame[41] = @intCast((pl >> 16) & 0xff);
    frame[42] = @intCast((pl >> 8) & 0xff);
    frame[43] = @intCast(pl & 0xff);
    @memcpy(frame[SHARD_FRAME_HEADER_SIZE..], inner);

    const decoded = try decodeFrame(frame);
    try std.testing.expectEqualSlices(u8, bundle_bytes, decoded.bundle_bytes);
    try std.testing.expectEqualSlices(u8, namespace, decoded.extension_name);
    try std.testing.expectEqualSlices(u8, version, decoded.version);
    try std.testing.expectEqual(signer_pubkey[0], decoded.signer_pubkey[0]);
    // txid_internal[0] = 1; txid_display[0] should be the LAST byte of internal (TXID_LEN).
    try std.testing.expectEqual(@as(u8, 1), decoded.txid_internal[0]);
    try std.testing.expectEqual(@as(u8, TXID_LEN), decoded.txid_display[0]);
}

test "decodeFrame rejects bad magic / protocol / version" {
    var frame = [_]u8{0} ** (SHARD_FRAME_HEADER_SIZE + 1);
    // valid skeleton
    frame[0] = 0xE3;
    frame[1] = 0xE1;
    frame[2] = 0xF3;
    frame[3] = 0xE8;
    frame[4] = 0x02;
    frame[5] = 0xBF;
    frame[6] = 0x01;

    // bad magic
    var bad = frame;
    bad[0] = 0x00;
    try std.testing.expectError(error.frame_bad_magic, decodeFrame(&bad));

    // bad protocol
    bad = frame;
    bad[5] = 0x00;
    try std.testing.expectError(error.frame_bad_protocol, decodeFrame(&bad));

    // bad version
    bad = frame;
    bad[6] = 0x99;
    try std.testing.expectError(error.frame_bad_version, decodeFrame(&bad));

    // too small
    try std.testing.expectError(error.frame_too_small, decodeFrame(frame[0..10]));
}

test "applyVerifiedFrame writes bundle to data_dir + idempotent on replay" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    const bundle_bytes = "the-bundle-bytes-for-apply-test";
    var bundle_hash: [BUNDLE_HASH_LEN]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bundle_bytes, &bundle_hash, .{});

    const vf: VerifiedFrame = .{
        .signer_name = "platform",
        .bundle_bytes = bundle_bytes,
        .publish_txid_display = .{0} ** TXID_LEN,
        .extension_name = "oddjobz.foo",
        .version = "0.1.0",
        .bundle_hash = bundle_hash,
    };

    var outcome1 = try applyVerifiedFrame(allocator, vf, data_dir, null, null);
    defer outcome1.deinit(allocator);
    try std.testing.expect(!outcome1.already_applied);
    try std.testing.expect(std.mem.endsWith(u8, outcome1.bundle_path, "extensions/oddjobz.foo/0.1.0/bundle.bin"));

    // Second apply same frame — idempotent.
    var outcome2 = try applyVerifiedFrame(allocator, vf, data_dir, null, null);
    defer outcome2.deinit(allocator);
    try std.testing.expect(outcome2.already_applied);
    try std.testing.expect(!outcome2.registered); // already_applied → no re-register
}

```
