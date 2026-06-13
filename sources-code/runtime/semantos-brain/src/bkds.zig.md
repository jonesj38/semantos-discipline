---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/bkds.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.234435+00:00
---

# runtime/semantos-brain/src/bkds.zig

```zig
// Phase D-W1 / Phase 1 Part 2 — BKDS leaf derivation for identity_certs.
//
// Reference: docs/design/BRAIN-DISPATCHER-UNIFICATION.md §3 (identity_certs
//            row), §2.5 (carpenter+musician hat isolation argument);
//            docs/spec/protocol-v0.5.md §4.4 (identity DAG), §4.5 (domain
//            flag namespace);
//            BRC-42 invoice-with-counterparty key derivation:
//              https://brc.dev/42 — "BRC-42: BSV Key Derivation Scheme".
//
// What this is: a BRC-42 BKDS that takes the operator's root private key
// and a paired device's compressed-SEC1 public key, plus a deterministic
// invoice (`"BKDS-BRC42-v1" || u8(context_tag) || u32_be(label.len) ||
// label`), and produces the secp256k1 child private key (operator side)
// or compressed child public key (verifier side).  Both endpoints compute
// the same child via ECDH symmetry — the device runs it with
// `device_priv.deriveChild(operator_root_pub, invoice)`, the operator runs
// it with `operator_root_priv.deriveChild(device_pub, invoice)`, and the
// resulting child pubkeys are byte-equal.
//
// Algorithm (mirrors the cell-engine's `host_derive_leaf` path —
// `core/cell-engine/src/host.zig:deriveLeaf`):
//
//   shared      := priv * other_pub                        // ECDH point
//   shared_b    := compressed_sec1(shared)                 // 33 bytes
//   tweak       := HMAC-SHA-256(invoice, key=shared_b)     // 32 bytes
//   child_priv  := scalar_add_mod_n(priv, tweak)
//   child_pub   := basepoint * child_priv
//
// The dispatcher's `issue_child` handler verifies the device-submitted
// `derivation_pubkey` by recomputing the child pubkey from
// `(operator_root_priv, derivation_proof_pubkey, context_tag, label)` and
// constant-time comparing.  A mismatch surfaces as
// `error.derivation_context_mismatch` per the brief's vocabulary.
//
// Why BRC-42 (not the prior HMAC-SHA-512 leaf flavour the TS prototype
// used): BRC-42 is the canonical BSV BKDS, the same primitive bsvz exposes
// via `host_derive_leaf` for the wallet-engine WASM, and what BRC-52 cert
// chains (D-O5p territory) build on.  Locking in BRC-42 here lets D-O5p
// inherit a stable substrate; the TS-side `KeyDerivationService` will
// converge to the same BRC-42 surface in a follow-up.
//
// The "context_tag" exposed to callers is a u8 — covers the Plexus-
// reserved range (0x00–0xFF, see protocol §4.5) and the carpenter (0x10)
// /musician (0x11) canonical example in the dispatcher unification doc.
// It rides into the invoice as a single byte alongside the label so two
// different context tags against the same (root_priv, device_pub, label)
// produce structurally distinct child keys (K3 isolation by construction).
//
// TODO(D-O5p): the operator's root private key currently has no
// production source — `cmdServe` registers the identity_certs handler
// without installing a priv (see identity_certs_handler.zig header).
// D-O5p's "Acceptor side" (sub-deliverable O5p-c, ODDJOBZ-EXTENSION-PLAN
// §3) wires the priv-source as a Plexus derivation recipe (Plexus Tech
// Reqs v1.3 §23) evaluated against a locally-loaded operator seed.
// Until D-O5p lands, only the test path (`setOperatorRootPriv`)
// exercises BRC-42 verification end-to-end.

const std = @import("std");
const bsvz = @import("bsvz");

// ─────────────────────────────────────────────────────────────────────
// Errors
// ─────────────────────────────────────────────────────────────────────

pub const Error = error{
    /// SEC1 pubkey wasn't a 33-byte compressed point on secp256k1.
    bad_pubkey,
    /// Private key wasn't a valid 32-byte secp256k1 scalar.
    bad_privkey,
    /// Label exceeded MAX_LABEL_LEN (the upper bound the static invoice
    /// buffer is sized for; protects callers from runaway invoices).
    label_too_long,
    /// BRC-42 derivation step itself failed (curve-arithmetic /
    /// out-of-range tweak — astronomically unlikely on real inputs but
    /// surfaced rather than asserted away).
    derivation_failed,
    /// The brain recomputed the child pubkey and it did not match the
    /// device-submitted `derivation_pubkey`.  Two distinct paths for
    /// this:
    ///   1. The device-submitted `derivation_proof` (its base/
    ///      counterparty pubkey) doesn't match what the device actually
    ///      holds privately — i.e., a peer that doesn't own the device
    ///      priv can't fake the right counterparty pubkey, because BRC-
    ///      42 with the wrong counterparty produces a different child.
    ///   2. The declared `context_tag` or `label` differs from what the
    ///      device used in its invoice — a context-tag swap (carpenter
    ///      0x10 → musician 0x11) lands here.
    /// The handler maps this to its public `error.derivation_context_
    /// mismatch`.
    proof_mismatch,
};

// ─────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────

/// secp256k1 compressed SEC1 pubkey length.
pub const PUBKEY_LEN: usize = 33;

/// secp256k1 scalar length.
pub const PRIVKEY_LEN: usize = 32;

/// Back-compat alias — older call sites refer to `bkds.KEY_LEN` as the
/// "pubkey shape on the wire and on disk".  Now 33 (compressed SEC1).
pub const KEY_LEN: usize = PUBKEY_LEN;

/// Derivation proof on the wire: the device's compressed-SEC1 base
/// pubkey (its counterparty pubkey from the operator's POV).  The brain
/// uses it to reconstruct the BRC-42 invoice + recompute the child.
pub const PROOF_LEN: usize = PUBKEY_LEN;

/// Invoice domain tag — version-bound so a future wire-format bump
/// doesn't silently produce colliding child keys.
pub const INVOICE_DOMAIN: []const u8 = "BKDS-BRC42-v1";

/// Hard cap on label length.  Static invoice buffer sized for this; a
/// caller exceeding it surfaces `Error.label_too_long` rather than
/// silently truncating.  256 bytes is well past any realistic label
/// ("Todd's iPhone 17 Pro Max — work hat") with comfortable headroom.
pub const MAX_LABEL_LEN: usize = 256;

/// Maximum invoice length: domain (13) + ctx tag (1) + label-len (4) +
/// label (≤ MAX_LABEL_LEN).  Used for the static buffer in
/// `buildInvoice`.
pub const MAX_INVOICE_LEN: usize = INVOICE_DOMAIN.len + 1 + 4 + MAX_LABEL_LEN;

// ─────────────────────────────────────────────────────────────────────
// Invoice encoding
// ─────────────────────────────────────────────────────────────────────

/// Build the BRC-42 invoice bytes for `(context_tag, label)` into
/// `out_buf` and return a slice.  Format:
///
///   "BKDS-BRC42-v1" || u8(context_tag) || u32_be(label.len) || label
///
/// `out_buf` must be at least `MAX_INVOICE_LEN` bytes.  Two invocations
/// with identical `(context_tag, label)` produce identical invoice bytes
/// (deterministic).
pub fn buildInvoice(
    context_tag: u8,
    label: []const u8,
    out_buf: []u8,
) Error![]const u8 {
    if (label.len > MAX_LABEL_LEN) return Error.label_too_long;
    if (out_buf.len < INVOICE_DOMAIN.len + 1 + 4 + label.len) {
        return Error.label_too_long;
    }
    @memcpy(out_buf[0..INVOICE_DOMAIN.len], INVOICE_DOMAIN);
    var off: usize = INVOICE_DOMAIN.len;
    out_buf[off] = context_tag;
    off += 1;
    std.mem.writeInt(u32, out_buf[off..][0..4], @intCast(label.len), .big);
    off += 4;
    @memcpy(out_buf[off..][0..label.len], label);
    off += label.len;
    return out_buf[0..off];
}

// ─────────────────────────────────────────────────────────────────────
// Core derivation — operator side (holds root_priv, knows device_pub)
// ─────────────────────────────────────────────────────────────────────

/// Derive the child SECP256K1 keypair from the operator's root private
/// key + the paired device's compressed-SEC1 public key + an invoice
/// built from `(context_tag, label)`.  Returns the child's compressed-
/// SEC1 public key.  This is what the brain stores in the cert record
/// and what `derivation_pubkey` carries on the wire.
///
/// Errors:
///   - bad_privkey if `root_priv` is not a valid secp256k1 scalar
///   - bad_pubkey  if `device_pub_sec1` isn't a 33-byte compressed
///                 point on secp256k1
///   - label_too_long if `label.len > MAX_LABEL_LEN`
///   - derivation_failed if the tweak ⊕ scalar-add lands outside the
///     curve order (negligible in practice)
pub fn deriveChildPubkey(
    root_priv: [PRIVKEY_LEN]u8,
    device_pub_sec1: [PUBKEY_LEN]u8,
    context_tag: u8,
    label: []const u8,
) Error![PUBKEY_LEN]u8 {
    var inv_buf: [MAX_INVOICE_LEN]u8 = undefined;
    const invoice = try buildInvoice(context_tag, label, &inv_buf);

    const priv = bsvz.primitives.ec.PrivateKey.fromBytes(root_priv) catch return Error.bad_privkey;
    const cp = bsvz.primitives.ec.PublicKey.fromSec1(&device_pub_sec1) catch return Error.bad_pubkey;
    const child_priv = priv.deriveChild(cp, invoice) catch return Error.derivation_failed;
    const child_pub = child_priv.publicKey() catch return Error.derivation_failed;
    return child_pub.toCompressedSec1();
}

/// Symmetric helper — the path the *device* runs at pairing time.
/// Returns the same child compressed-SEC1 pubkey as `deriveChildPubkey`
/// would produce for the matching `(root_priv, device_pub_sec1)`.  This
/// exists to back the ECDH-symmetry conformance test and as a reference
/// for the device-side D-O5p code; the dispatcher itself never holds a
/// device priv key.
pub fn deriveChildPubkeyFromDevice(
    device_priv: [PRIVKEY_LEN]u8,
    root_pub_sec1: [PUBKEY_LEN]u8,
    context_tag: u8,
    label: []const u8,
) Error![PUBKEY_LEN]u8 {
    var inv_buf: [MAX_INVOICE_LEN]u8 = undefined;
    const invoice = try buildInvoice(context_tag, label, &inv_buf);

    const priv = bsvz.primitives.ec.PrivateKey.fromBytes(device_priv) catch return Error.bad_privkey;
    const root_pub = bsvz.primitives.ec.PublicKey.fromSec1(&root_pub_sec1) catch return Error.bad_pubkey;
    const child_pub = root_pub.deriveChild(priv, invoice) catch return Error.derivation_failed;
    return child_pub.toCompressedSec1();
}

// ─────────────────────────────────────────────────────────────────────
// Verification — what the dispatcher's `issue_child` calls
// ─────────────────────────────────────────────────────────────────────

/// Verify that `claimed_child_pub` is the BRC-42 child of
/// `(root_priv, device_pub_sec1, context_tag, label)`.  The brain
/// recomputes the expected child pubkey on its side and constant-time
/// compares.  This is the structural proof-of-derivation under BRC-42:
///
///   • An attacker without `device_priv` cannot supply a `device_pub_
///     sec1` whose ECDH-derived child matches what was registered (the
///     shared secret is keyed by both private halves).
///   • A swap of `context_tag` or `label` (carpenter 0x10 → musician
///     0x11) reshapes the invoice → reshapes the HMAC tweak → reshapes
///     the child.  The recomputation under the declared tag won't
///     match — surfaces as `proof_mismatch`.
///
/// `device_pub_sec1` is the on-the-wire `derivation_proof` field — the
/// device's base/counterparty pubkey, NOT the child.
///
/// `claimed_child_pub` is the on-the-wire `derivation_pubkey` field —
/// the child the device computed via
/// `device_priv.deriveChild(root_pub, invoice).publicKey()`.
pub fn verifyDerivationProof(
    root_priv: [PRIVKEY_LEN]u8,
    device_pub_sec1: [PUBKEY_LEN]u8,
    context_tag: u8,
    label: []const u8,
    claimed_child_pub: [PUBKEY_LEN]u8,
) Error!void {
    const expected = try deriveChildPubkey(root_priv, device_pub_sec1, context_tag, label);
    if (!std.crypto.timing_safe.eql([PUBKEY_LEN]u8, expected, claimed_child_pub)) {
        return Error.proof_mismatch;
    }
}

// ─────────────────────────────────────────────────────────────────────
// Hex helpers (kept local — bearer_tokens.zig has its own copy with the
// same public surface; we avoid cross-module imports for an isolated
// crypto unit).
// ─────────────────────────────────────────────────────────────────────

pub fn hexEncode(bytes: []const u8, out: []u8) void {
    std.debug.assert(out.len == bytes.len * 2);
    const chars = "0123456789abcdef";
    for (bytes, 0..) |b, i| {
        out[i * 2] = chars[b >> 4];
        out[i * 2 + 1] = chars[b & 0x0f];
    }
}

pub fn hexDecode(hex: []const u8, out: []u8) Error!void {
    if (hex.len != out.len * 2) return Error.bad_pubkey;
    var i: usize = 0;
    while (i < out.len) : (i += 1) {
        out[i] = (try parseHexNibble(hex[i * 2]) << 4) | try parseHexNibble(hex[i * 2 + 1]);
    }
}

fn parseHexNibble(c: u8) Error!u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => 10 + (c - 'a'),
        'A'...'F' => 10 + (c - 'A'),
        else => Error.bad_pubkey,
    };
}

// ─────────────────────────────────────────────────────────────────────
// Test helpers — generate deterministic keypairs from a seed
// ─────────────────────────────────────────────────────────────────────

/// Hash a seed string to a 32-byte secp256k1 scalar that is reduced mod
/// curve order.  Deterministic; useful for fixtures and inline tests.
/// Mirrors the seeding convention used by
/// `core/cell-engine/tests/derivation_conformance.zig`.
pub fn privFromSeed(seed: []const u8) [PRIVKEY_LEN]u8 {
    var k: [PRIVKEY_LEN]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(seed, &k, .{});
    // SHA-256 of any input has astronomical odds of being 0 or ≥ n;
    // the bsvz PrivateKey.fromBytes call surfaces edge cases as errors
    // when used.  For test seeds this is fine.
    return k;
}

/// Public-key counterpart for a seed-derived priv.  Returns the
/// compressed-SEC1 pubkey.
pub fn pubFromSeed(seed: []const u8) Error![PUBKEY_LEN]u8 {
    const k = privFromSeed(seed);
    const priv = bsvz.primitives.ec.PrivateKey.fromBytes(k) catch return Error.bad_privkey;
    const pub_key = priv.publicKey() catch return Error.bad_privkey;
    return pub_key.toCompressedSec1();
}

// ─────────────────────────────────────────────────────────────────────
// Tests — unit coverage of the algorithm.  Cross-implementation parity
// is asserted in tests/identity_certs_conformance.zig against the JSON
// fixtures generated from bsvz itself.
// ─────────────────────────────────────────────────────────────────────

test "buildInvoice: deterministic encoding" {
    var buf1: [MAX_INVOICE_LEN]u8 = undefined;
    var buf2: [MAX_INVOICE_LEN]u8 = undefined;
    const inv1 = try buildInvoice(0x10, "carpenter-hat", &buf1);
    const inv2 = try buildInvoice(0x10, "carpenter-hat", &buf2);
    try std.testing.expectEqualSlices(u8, inv1, inv2);
    try std.testing.expectEqual(@as(usize, INVOICE_DOMAIN.len + 1 + 4 + "carpenter-hat".len), inv1.len);
    // Domain prefix
    try std.testing.expectEqualSlices(u8, INVOICE_DOMAIN, inv1[0..INVOICE_DOMAIN.len]);
    // Context tag byte
    try std.testing.expectEqual(@as(u8, 0x10), inv1[INVOICE_DOMAIN.len]);
}

test "buildInvoice: rejects oversized label" {
    var buf: [MAX_INVOICE_LEN]u8 = undefined;
    const big = [_]u8{'a'} ** (MAX_LABEL_LEN + 1);
    try std.testing.expectError(Error.label_too_long, buildInvoice(0x10, &big, &buf));
}

test "deriveChildPubkey: deterministic — same inputs produce same child" {
    const root_priv = privFromSeed("operator-root-todd-2026");
    const device_pub = try pubFromSeed("device-iphone-2026");
    const a = try deriveChildPubkey(root_priv, device_pub, 0x10, "phone");
    const b = try deriveChildPubkey(root_priv, device_pub, 0x10, "phone");
    try std.testing.expectEqualSlices(u8, &a, &b);
}

test "deriveChildPubkey: child differs from operator root pub" {
    const root_priv = privFromSeed("operator-root-todd-2026");
    const root_pub = try pubFromSeed("operator-root-todd-2026");
    const device_pub = try pubFromSeed("device-iphone-2026");
    const child = try deriveChildPubkey(root_priv, device_pub, 0x10, "phone");
    try std.testing.expect(!std.mem.eql(u8, &root_pub, &child));
}

test "deriveChildPubkey: distinct context tags produce distinct child keys (K3 isolation)" {
    // The carpenter+musician case from §2.5 — same root, same device,
    // same label, two different context tags.  Child keys MUST differ.
    const root_priv = privFromSeed("operator-root-todd-2026");
    const device_pub = try pubFromSeed("device-iphone-2026");
    const carpenter = try deriveChildPubkey(root_priv, device_pub, 0x10, "phone");
    const musician = try deriveChildPubkey(root_priv, device_pub, 0x11, "phone");
    try std.testing.expect(!std.mem.eql(u8, &carpenter, &musician));
}

test "deriveChildPubkey: distinct labels produce distinct child keys" {
    const root_priv = privFromSeed("operator-root-todd-2026");
    const device_pub = try pubFromSeed("device-iphone-2026");
    const a = try deriveChildPubkey(root_priv, device_pub, 0x10, "phone");
    const b = try deriveChildPubkey(root_priv, device_pub, 0x10, "laptop");
    try std.testing.expect(!std.mem.eql(u8, &a, &b));
}

test "deriveChildPubkey: distinct counterparties produce distinct children" {
    const root_priv = privFromSeed("operator-root-todd-2026");
    const device_a = try pubFromSeed("device-iphone-2026");
    const device_b = try pubFromSeed("device-laptop-2026");
    const a = try deriveChildPubkey(root_priv, device_a, 0x10, "phone");
    const b = try deriveChildPubkey(root_priv, device_b, 0x10, "phone");
    try std.testing.expect(!std.mem.eql(u8, &a, &b));
}

test "ECDH symmetry: device-side derivation yields same child pubkey as operator-side" {
    // Structural BRC-42 property — both endpoints arrive at the same
    // child without sharing a private half.  This is the security
    // argument behind the "verifier path" in `verifyDerivationProof`:
    // the brain runs `root_priv.deriveChild(device_pub, …)`, the device
    // ran `device_priv.deriveChild(root_pub, …)`, and the resulting
    // child pubkeys MUST be byte-equal.
    const root_priv = privFromSeed("operator-root-todd-2026");
    const root_pub = try pubFromSeed("operator-root-todd-2026");
    const device_priv = privFromSeed("device-iphone-2026");
    const device_pub = try pubFromSeed("device-iphone-2026");

    const op_side = try deriveChildPubkey(root_priv, device_pub, 0x10, "phone");
    const dev_side = try deriveChildPubkeyFromDevice(device_priv, root_pub, 0x10, "phone");
    try std.testing.expectEqualSlices(u8, &op_side, &dev_side);
}

test "verifyDerivationProof: round-trip succeeds" {
    const root_priv = privFromSeed("operator-root-todd-2026");
    const device_pub = try pubFromSeed("device-iphone-2026");
    const child = try deriveChildPubkey(root_priv, device_pub, 0x10, "phone");
    try verifyDerivationProof(root_priv, device_pub, 0x10, "phone", child);
}

test "verifyDerivationProof: tampered child fails" {
    const root_priv = privFromSeed("operator-root-todd-2026");
    const device_pub = try pubFromSeed("device-iphone-2026");
    var child = try deriveChildPubkey(root_priv, device_pub, 0x10, "phone");
    // Flip a non-prefix byte to keep the SEC1 prefix valid (0x02/0x03);
    // this exercises the constant-time-eql path rather than the
    // SEC1-decode path.
    child[5] ^= 0x01;
    try std.testing.expectError(
        Error.proof_mismatch,
        verifyDerivationProof(root_priv, device_pub, 0x10, "phone", child),
    );
}

test "verifyDerivationProof: context-tag swap fails (cross-hat impersonation)" {
    // Compute the child for the carpenter context (0x10), then attempt
    // verification claiming the musician context (0x11).  The verifier
    // recomputes under 0x11, gets a structurally different child, and
    // rejects.  Hat-isolation argument from §2.5.
    const root_priv = privFromSeed("operator-root-todd-2026");
    const device_pub = try pubFromSeed("device-iphone-2026");
    const carpenter_child = try deriveChildPubkey(root_priv, device_pub, 0x10, "phone");
    try std.testing.expectError(
        Error.proof_mismatch,
        verifyDerivationProof(root_priv, device_pub, 0x11, "phone", carpenter_child),
    );
}

test "verifyDerivationProof: wrong counterparty (forged proof) fails" {
    // An attacker submits a `derivation_proof` that doesn't correspond
    // to the device priv they actually hold.  The recomputation under
    // the *submitted* counterparty produces a child that doesn't match
    // what they were able to derive on their side.  Reject.
    const root_priv = privFromSeed("operator-root-todd-2026");
    const honest_dev_pub = try pubFromSeed("device-iphone-2026");
    const forged_dev_pub = try pubFromSeed("device-attacker-2026");

    // Device-side (honest) computes child under root_pub + its own priv.
    // We can't easily simulate "compute child without knowing
    // root_priv" — but the test condition we want is: a child computed
    // under one (counterparty) does not verify when claimed against a
    // different counterparty.
    const honest_child = try deriveChildPubkey(root_priv, honest_dev_pub, 0x10, "phone");
    try std.testing.expectError(
        Error.proof_mismatch,
        verifyDerivationProof(root_priv, forged_dev_pub, 0x10, "phone", honest_child),
    );
}

test "hexEncode + hexDecode round-trip" {
    const orig = [_]u8{ 0xde, 0xad, 0xbe, 0xef };
    var hex: [8]u8 = undefined;
    hexEncode(&orig, &hex);
    try std.testing.expectEqualStrings("deadbeef", &hex);
    var back: [4]u8 = undefined;
    try hexDecode(&hex, &back);
    try std.testing.expectEqualSlices(u8, &orig, &back);
}

```
