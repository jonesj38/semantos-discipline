---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/hat_bkds.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.231656+00:00
---

# runtime/semantos-brain/src/hat_bkds.zig

```zig
// D-DOG.1.0c Phase 4 — BKDS per-cell signing primitive.
//
// Reference: docs/prd/D-DOG-1.0c-LAYER-1-PROMOTION-MATRIX.md §2 (revised
//            2026-05-04 signing model) + §4 Phase 4 row B.1;
//            runtime/semantos-brain/src/bkds.zig (the existing BRC-42 BKDS leaf
//            derivation this module reuses);
//            BRC-42: https://brc.dev/42 — "BSV Key Derivation Scheme".
//
// What this is: a thin wrapper around the operator's hat-key root that
// produces a fresh per-cell signing key via BRC-42 BKDS, signs the
// canonical cell payload with it, and discards the key.  The derived
// public key is what gets recorded in the cell's `signedBy` field; the
// signature (compact 64-byte r||s) goes in `signature`.
//
// Derivation scope (per the matrix §2 specification):
//
//   protocolID  := "semantos.cell-sign/v1"    // substrate default scope
//                                              // (cartridge-neutral; a
//                                              // cartridge passes its own
//                                              // via signCellScoped)
//   keyID       := SHA-256(canonical_cell_payload)  // 32-byte content hash
//   segment     := buildInvoice(CONTEXT_TAG_CELL_SIGN,
//                               protocolID + "|" + hex(keyID))
//
// The derivation segment is built from
//   `(context_tag = CONTEXT_TAG_CELL_SIGN, label = protocolID + "|" + hex(keyID))`
// — so two cells with different content produce different derived
// keys, and the same cell content always rederives to the same key
// (idempotent re-signing).
//
// kdf-v2 (CW Lift L11; docs/prd/CW-LIFT-ROADMAP.md §2.2): this is a
// UNILATERAL key tree — the operator derives its OWN signing keys with
// no counterparty — so the canonical primitive is EP3259724B1
// `deriveSegment` (child = parent + SHA-256(segment) mod n), NOT BRC-42.
// BRC-42 is the BILATERAL specialisation (segment = HMAC(ECDH-shared,
// invoice)); the v0 here used it with the operator's own pubkey as the
// counterparty — a degenerate self-ECDH that deriveSegment replaces:
//
//   • deriveSegment is deterministic and curve-arithmetic-grounded; the
//     derived pubkey is structurally distinct from the root pubkey, so
//     the unlinkability property holds (third parties cannot cluster
//     cells by signing key without the root).
//   • The verifier re-derives with deriveSegmentPub (priv↔pub symmetric),
//     and under v2 needs only root_pub — no root_priv — to reconstruct
//     the expected `signedBy` (see hat_bkds_verifier.zig).
//   • Compromise of one derived signing key compromises only that
//     one cell (the matrix §2 "blast radius" argument).
//
// Clean cutover: the brain holds no spendable/persisted v0-signed cells
// that must stay verifiable, so v2 is the sole algorithm here (no version
// gate) — unlike the Plexus SDK, which retains v1 for stored test trees.
//
// Threat-model boundary: this module assumes the root_priv is loaded
// into RAM by an upper layer (`HatBkds.init`).  Encryption-at-rest of
// the root under the wallet KEK is the caller's responsibility.  In
// dogfood / smoke-test paths the caller passes a dev-seed-derived priv
// directly; in production the daemon's wallet boot loads it from the
// KEK-encrypted slot store before constructing the HatBkds.

const std = @import("std");
const bkds = @import("bkds");
const bsvz = @import("bsvz");
const derive_segment = @import("derive_segment");
const constants = @import("constants");

/// Canonical domain flag for hat cell-signing keys (L11.5, kdf-v3). Bound into
/// the derivation tweak so a hat signing key is cryptographically scoped to the
/// HAT_SIGNING domain. Source of truth: core/constants/constants.json
/// (`domainFlags.HAT_SIGNING`) → generated into cell-engine constants.zig.
/// Re-exported here so the verifier derives the pub side under the same flag.
pub const DOMAIN_FLAG_HAT_SIGNING: u32 = constants.DOMAIN_FLAG_HAT_SIGNING;

// ─────────────────────────────────────────────────────────────────────
// Errors
// ─────────────────────────────────────────────────────────────────────

pub const Error = error{
    /// Root private key wasn't a valid 32-byte secp256k1 scalar.
    bad_root_priv,
    /// Derivation step failed (BRC-42 leaf derivation surfaced an
    /// underlying curve-arithmetic / out-of-range tweak).
    derivation_failed,
    /// Signing step failed (the bsvz signDigest256 path returned an
    /// error — astronomically unlikely on real inputs but surfaced
    /// rather than asserted away).
    sign_failed,
    /// The derived signing key is still cached / pinned somewhere; the
    /// caller asked to discard it but a guard fired.  Reserved for a
    /// future hardening pass.
    key_not_discarded,
};

// ─────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────

/// BRC-42 invoice context tag for the substrate's DEFAULT cell-signing
/// scope.  Distinct from the carpenter (0x10) / musician (0x11) tags
/// D-O5p uses for hat isolation, so a default cell-sign derivation
/// cannot collide with an identity-cert derivation under the same root
/// + label.  Cartridge-neutral: a cartridge that needs its own
/// derivation family passes a distinct tag to signCellScoped /
/// verifyCellScoped rather than reusing this default (which keeps
/// cross-cartridge cell traces unlinkable).
pub const CONTEXT_TAG_CELL_SIGN: u8 = 0x20;

/// Substrate DEFAULT derivation-scope protocol ID.  Cartridge-neutral:
/// the wallet primitive holds no cartridge-specific scope — a cartridge
/// that wants its own family passes an explicit protocol_id (e.g.
/// "<cartridge>.cell-sign/v1") to signCellScoped / verifyCellScoped.
/// Bumping versions (v1 → v2) is a coordinated change: previously-signed
/// cells stay verifiable under whatever scope they were signed with.
pub const PROTOCOL_ID: []const u8 = "semantos.cell-sign/v1";

/// Compressed-SEC1 pubkey length (re-export from bkds for callers).
pub const PUBKEY_LEN: usize = bkds.PUBKEY_LEN; // 33

/// Compact (r || s) signature length.  Distinct from BSV-checksig DER
/// — we store the 64-byte raw form in the cell's `signature` field,
/// matching the matrix §4 row B.1's `[64]u8` type.
pub const SIGNATURE_LEN: usize = 64;

// ─────────────────────────────────────────────────────────────────────
// Cell-payload content-hashing
// ─────────────────────────────────────────────────────────────────────

/// SHA-256 of the canonical cell payload.  This is the BKDS keyID.
/// Two cells with byte-identical canonical payloads produce identical
/// content hashes, which means identical derivations, which means
/// identical signatures — the idempotent re-sign property.
pub fn computeContentHash(canonical_payload: []const u8) [32]u8 {
    var out: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(canonical_payload, &out, .{});
    return out;
}

/// Build the BKDS label string for a given content hash:
///   `<protocolID>|<hex(content_hash)>`
///
/// Caller frees.  Stable byte shape across calls — same hash always
/// produces the same label, which is the foundation of recoverable
/// re-derivation.
pub fn buildLabel(allocator: std.mem.Allocator, content_hash: [32]u8) ![]u8 {
    const hex = std.fmt.bytesToHex(content_hash, .lower);
    return std.fmt.allocPrint(allocator, "{s}|{s}", .{ PROTOCOL_ID, hex });
}

// ─────────────────────────────────────────────────────────────────────
// HatBkds — root storage + sign primitive
// ─────────────────────────────────────────────────────────────────────

/// Output of a single signCell call.
pub const SignedCell = struct {
    /// 33-byte compressed-SEC1 derived public key.  Goes in the cell's
    /// `signedBy` field.  Distinct from the root pubkey — the
    /// unlinkability property.
    derived_pubkey: [PUBKEY_LEN]u8,
    /// 64-byte compact signature (r || s).  Goes in the cell's
    /// `signature` field.
    signature: [SIGNATURE_LEN]u8,
};

/// In-memory representation of the hat-key root + cached
/// counterparty (the operator's own root pubkey).  The encrypted-on-
/// disk shape is the caller's concern; this struct holds the decrypted
/// scalar for the duration of `brain serve`.  `deinit` zeroises the
/// scalar before freeing.
pub const HatBkds = struct {
    /// 32-byte secp256k1 scalar — the operator's root private key.
    /// Held for the daemon's lifetime.  Zeroed on deinit.
    root_priv: [bkds.PRIVKEY_LEN]u8,
    /// 33-byte compressed-SEC1 — the operator's root public key.  Used
    /// as the BRC-42 counterparty for self-derivation.  Cached to
    /// avoid re-deriving on every signCell call.
    root_pub: [PUBKEY_LEN]u8,

    /// Construct from a 32-byte raw scalar.  Validates that the scalar
    /// is a valid secp256k1 priv (rejects 0 / ≥ n) and pre-computes
    /// the matching pubkey.
    pub fn initFromRoot(root_priv: [bkds.PRIVKEY_LEN]u8) Error!HatBkds {
        const priv = bsvz.primitives.ec.PrivateKey.fromBytes(root_priv) catch return Error.bad_root_priv;
        const pub_key = priv.publicKey() catch return Error.bad_root_priv;
        return .{
            .root_priv = root_priv,
            .root_pub = pub_key.toCompressedSec1(),
        };
    }

    /// Construct from a deterministic seed string — useful for tests
    /// and for the dogfood smoke-test path where the operator's
    /// production root isn't yet wired in.  The seed is hashed to
    /// SHA-256(seed) and used as the scalar; the same seed always
    /// produces the same root.  Production callers MUST use
    /// `initFromRoot` with a wallet-KEK-decrypted scalar instead.
    pub fn initFromSeed(seed: []const u8) Error!HatBkds {
        const root = bkds.privFromSeed(seed);
        return initFromRoot(root);
    }

    /// Zeroise the in-memory root scalar.  Best-effort — Zig has no
    /// way to guarantee the compiler doesn't keep a copy on the stack
    /// of an inlined caller.  But the explicit @memset prevents the
    /// scalar from being readable in a post-deinit memory dump along
    /// the typical execution path.
    pub fn deinit(self: *HatBkds) void {
        std.crypto.secureZero(u8, &self.root_priv);
        std.crypto.secureZero(u8, &self.root_pub);
    }

    /// Return the operator's root pubkey (33-byte compressed-SEC1).
    /// The verifier needs this to re-derive the expected signing key
    /// from a recorded `signedBy` value.
    pub fn rootPubkey(self: *const HatBkds) [PUBKEY_LEN]u8 {
        return self.root_pub;
    }

    /// Sign a canonical cell payload.  Produces a fresh derived
    /// signing key via BRC-42 BKDS, signs SHA-256(payload) with it,
    /// and discards the key (the local stack copy goes out of scope at
    /// function return; the explicit @memset is a defence-in-depth
    /// guard against optimisations that keep it live).
    ///
    /// `cell_payload` is the canonical-JSON-encoded bytes of the
    /// cell's load-bearing fields.  `cell_header` is reserved for a
    /// future tier where the header (typeHash + cellId) is signed
    /// separately from the payload — for v0 it's accepted but unused
    /// (the canonical-JSON payload is the sole signing input).  The
    /// matrix §4 row B.1's API takes both for forward compatibility
    /// without forcing a Phase 5 schema change.
    ///
    /// Returns the (derived_pubkey, signature) pair.  The derived
    /// pubkey goes in the cell's `signedBy` field; the signature in
    /// `signature`.
    ///
    /// Idempotency: calling signCell twice with byte-identical
    /// `cell_payload` produces byte-identical (derived_pubkey,
    /// signature) outputs.  This is what backs the resign-pending
    /// admin verb's safety property — a re-sign of an already-signed
    /// cell is a no-op modulo the log-line append, and a re-sign of
    /// an unsigned cell with the same canonical bytes that a previous
    /// run would have produced reaches the same (pubkey, signature)
    /// pair.
    pub fn signCell(
        self: *HatBkds,
        cell_payload: []const u8,
        cell_header: []const u8,
    ) Error!SignedCell {
        // Convenience wrapper — signs under the substrate DEFAULT scope
        // (cartridge-neutral PROTOCOL_ID + CONTEXT_TAG_CELL_SIGN).  Any
        // cartridge that wants its own derivation family goes through
        // cell_signer.CellSigner, which routes to signCellScoped with a
        // cartridge-specific scope.
        return self.signCellScoped(
            cell_payload,
            cell_header,
            PROTOCOL_ID,
            CONTEXT_TAG_CELL_SIGN,
        );
    }

    /// Generic scoped signing — the cartridge-aware variant of
    /// signCell.  `protocol_id` and `context_tag` together define the
    /// derivation scope: two cartridges signing the same canonical
    /// payload under different scopes produce different derived keys.
    /// This is the foundation of "generic but under hats relevant to
    /// the cartridge" — the brain holds one hat (the operator's root
    /// scalar), but each cartridge derives a distinct family of signing
    /// keys under its own scope so cross-cartridge cell traces stay
    /// unlinkable.
    ///
    /// The verifier (hat_bkds_verifier.zig) needs to be called with
    /// matching scope to re-derive the same expected derived pubkey;
    /// scope mismatch yields a different derived key and the verify
    /// fails.  CellSigner records the scope it used in the audit log so
    /// the verifier path can replay it (planned task — not yet wired).
    pub fn signCellScoped(
        self: *HatBkds,
        cell_payload: []const u8,
        cell_header: []const u8,
        protocol_id: []const u8,
        context_tag: u8,
    ) Error!SignedCell {
        _ = cell_header; // reserved for future use; see doc comment above

        // 1. Compute the BKDS keyID = SHA-256(canonical payload).
        const content_hash = computeContentHash(cell_payload);

        // 2. Build the BRC-42 invoice label = protocolID + "|" + hex(keyID).
        // protocol_id is borrowed; we copy into a stack buffer sized
        // dynamically off the protocol_id length so no allocator is
        // needed.  Caps via bkds.MAX_LABEL_LEN.
        const hex_chars = std.fmt.bytesToHex(content_hash, .lower);
        const label_len = protocol_id.len + 1 + hex_chars.len;
        if (label_len > bkds.MAX_LABEL_LEN) return Error.derivation_failed;
        var label_buf: [bkds.MAX_LABEL_LEN]u8 = undefined;
        @memcpy(label_buf[0..protocol_id.len], protocol_id);
        label_buf[protocol_id.len] = '|';
        @memcpy(label_buf[protocol_id.len + 1 .. label_len], hex_chars[0..]);

        // 3. Derive the child *private* key — we need the priv to
        //    actually sign, not just the pubkey.  This is the symmetric
        //    counterpart of bkds.deriveChildPubkey: same invoice, same
        //    inputs, same child scalar.  We re-implement it here
        //    inline (rather than exposing a deriveChildPriv from
        //    bkds.zig) to keep the derived priv from leaking into a
        //    public API surface that other callers might misuse.
        const child_priv_bytes = self.deriveChildPrivScoped(
            label_buf[0..label_len],
            context_tag,
        ) catch return Error.derivation_failed;
        // Stack copy — discarded on return via the @memset below.
        var child_priv = child_priv_bytes;
        defer std.crypto.secureZero(u8, &child_priv);

        // 4. Sign SHA-256(payload) with the derived priv.  Bsvz's
        //    `signDigest256` actually applies SHA-256d (double-SHA);
        //    for our purposes any deterministic-output hash works as
        //    long as the verifier uses the same one.  We pass the
        //    raw SHA-256 of the payload as the "digest" so the verifier
        //    can recompute it without ambiguity.  std.crypto's ECDSA
        //    `signPrehashed` signs the digest directly without further
        //    hashing — that's the contract we want.
        const Scheme = std.crypto.sign.ecdsa.EcdsaSecp256k1Sha256;
        const secret_key = Scheme.SecretKey.fromBytes(child_priv) catch
            return Error.sign_failed;
        const key_pair = Scheme.KeyPair.fromSecretKey(secret_key) catch
            return Error.sign_failed;

        // The "digest" we sign is SHA-256(payload) (NOT SHA-256d) so
        // the verifier can reach the same bytes from
        // `computeContentHash(payload)`.
        const digest = content_hash;

        const sig_obj = key_pair.signPrehashed(digest, null) catch
            return Error.sign_failed;
        const sig_bytes = sig_obj.toBytes();

        // 5. Compute the derived pubkey (33-byte compressed-SEC1) so
        //    callers can record it in the cell's `signedBy` field.
        //    The verifier re-derives this independently from
        //    (root_priv, root_pub, content_hash) — see hat_bkds_verifier.zig.
        const derived_pubkey = key_pair.public_key.toCompressedSec1();

        return .{
            .derived_pubkey = derived_pubkey,
            .signature = sig_bytes,
        };
    }

    /// Derive the BRC-42 child private key under an explicit context
    /// tag.  Internal — exposed only via signCellScoped so the priv
    /// never escapes this module's API.
    fn deriveChildPrivScoped(
        self: *const HatBkds,
        label: []const u8,
        context_tag: u8,
    ) !([bkds.PRIVKEY_LEN]u8) {
        // Build the derivation segment (invoice) — same context tag + label
        // shape the verifier rebuilds, so both sides hash identical bytes.
        var inv_buf: [bkds.MAX_INVOICE_LEN]u8 = undefined;
        const invoice = try bkds.buildInvoice(
            context_tag,
            label,
            &inv_buf,
        );

        // kdf-v3 (CW Lift L11.5): UNILATERAL, DOMAIN-SEPARATED node derivation
        // via EP3259724B1 `deriveDomainSegment`
        //   child = parent + SHA-256(u32_be(HAT_SIGNING) || invoice) mod n.
        // The operator derives its OWN per-cell signing key (no counterparty —
        // the v0 self-ECDH was a degenerate BRC-42 misuse; v2 dropped the flag).
        // Folding HAT_SIGNING into the tweak binds the key to its domain. The
        // verifier mirrors this with deriveDomainSegmentPub under the same flag
        // (priv↔pub symmetric). See src/derive_segment.zig +
        // docs/canon/domainflag-tag-unification.md.
        const priv = try bsvz.primitives.ec.PrivateKey.fromBytes(self.root_priv);
        const child_priv = try derive_segment.deriveDomainSegment(priv, DOMAIN_FLAG_HAT_SIGNING, invoice);
        return child_priv.toBytes();
    }
};

// ─────────────────────────────────────────────────────────────────────
// Tests — local algorithm-level coverage.  Cross-module conformance
// (sign/verify round-trip, idempotency under restart, recoverability
// from root + cellID) lives in tests/hat_bkds_conformance.zig.
// ─────────────────────────────────────────────────────────────────────

test "computeContentHash: deterministic" {
    const payload = "{\"cellId\":\"deadbeef\",\"foo\":\"bar\"}";
    const a = computeContentHash(payload);
    const b = computeContentHash(payload);
    try std.testing.expectEqualSlices(u8, &a, &b);
    try std.testing.expectEqual(@as(usize, 32), a.len);
}

test "computeContentHash: distinct payloads → distinct hashes" {
    const a = computeContentHash("{\"a\":1}");
    const b = computeContentHash("{\"a\":2}");
    try std.testing.expect(!std.mem.eql(u8, &a, &b));
}

test "buildLabel: shape is `<protocolID>|<hex(content_hash)>`" {
    const allocator = std.testing.allocator;
    var hash: [32]u8 = undefined;
    @memset(&hash, 0xab);
    const label = try buildLabel(allocator, hash);
    defer allocator.free(label);
    try std.testing.expectEqualStrings(
        "semantos.cell-sign/v1|abababababababababababababababababababababababababababababababab",
        label,
    );
}

test "HatBkds: signCell is deterministic for same payload" {
    var hat = try HatBkds.initFromSeed("test-root-2026");
    defer hat.deinit();
    const payload = "{\"cellId\":\"abc\",\"name\":\"jane\"}";
    const a = try hat.signCell(payload, "");
    const b = try hat.signCell(payload, "");
    try std.testing.expectEqualSlices(u8, &a.derived_pubkey, &b.derived_pubkey);
    try std.testing.expectEqualSlices(u8, &a.signature, &b.signature);
}

test "HatBkds: distinct payloads produce distinct derived pubkeys" {
    var hat = try HatBkds.initFromSeed("test-root-2026");
    defer hat.deinit();
    const a = try hat.signCell("{\"a\":1}", "");
    const b = try hat.signCell("{\"a\":2}", "");
    try std.testing.expect(!std.mem.eql(u8, &a.derived_pubkey, &b.derived_pubkey));
    try std.testing.expect(!std.mem.eql(u8, &a.signature, &b.signature));
}

test "HatBkds: derived pubkey is structurally distinct from root pubkey" {
    var hat = try HatBkds.initFromSeed("test-root-2026");
    defer hat.deinit();
    const root = hat.rootPubkey();
    const signed = try hat.signCell("{\"x\":1}", "");
    try std.testing.expect(!std.mem.eql(u8, &root, &signed.derived_pubkey));
}

test "HatBkds: distinct roots produce distinct signatures for same payload" {
    var hat_a = try HatBkds.initFromSeed("operator-a");
    defer hat_a.deinit();
    var hat_b = try HatBkds.initFromSeed("operator-b");
    defer hat_b.deinit();
    const payload = "{\"shared\":1}";
    const a = try hat_a.signCell(payload, "");
    const b = try hat_b.signCell(payload, "");
    try std.testing.expect(!std.mem.eql(u8, &a.derived_pubkey, &b.derived_pubkey));
    try std.testing.expect(!std.mem.eql(u8, &a.signature, &b.signature));
}

```
