---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/brc77.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.249486+00:00
---

# runtime/semantos-brain/src/brc77.zig

```zig
// D-network-messagebox-first-class — BRC-77 signed message envelope.
//
// Reference: https://brc.dev/77 — "BRC-77: Message Signing & Verification"
//
// Wire format (the signed content is supplied out-of-band — this envelope
// carries the cryptographic proof, not the payload):
//
//   [4B  version:   0x42, 0x42, 0x33, 0x01]
//   [33B signer:    sender's compressed-SEC1 pubkey]
//   [33B verifier:  recipient's compressed-SEC1 pubkey (directed mode)]
//   [32B keyID:     caller-supplied random key identifier]
//   [≤72B DER sig:  ECDSA signature over SHA256d(message) using child key]
//
// Key derivation (BRC-42):
//   invoice    = "2-message signing-" + base64(keyID)
//   child_priv = sender_priv.deriveChild(recipient_pub, invoice)
//
// Signing:
//   sig = child_priv.signHash256(message)   // SHA256d, DER-encoded
//
// Verification:
//   child_pub = recipient_priv.deriveChild(sender_pub, invoice).publicKey()
//   sha256d   = SHA256(SHA256(message))
//   ok        = child_pub.verifyDigest(sha256d, DER_sig)
//
// Scope: directed-mode only (V1).  The "anyone" verifier (0x00 prefix)
// requires a fixed well-known counterparty convention not yet agreed
// across this codebase.  Tracked as TODO-BRC77-ANYONE.

const std = @import("std");
const bsvz = @import("bsvz");

// ─────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────

pub const VERSION: [4]u8 = .{ 0x42, 0x42, 0x33, 0x01 };
pub const KEY_ID_LEN: usize = 32;
pub const PUBKEY_LEN: usize = 33;

/// Fixed header: 4 (version) + 33 (signer) + 33 (verifier) + 32 (keyID) = 102 B.
const HEADER_LEN: usize = 4 + 33 + 33 + 32;
/// Max DER sig length from bsvz (bsvz.crypto.max_der_signature_len = 72).
const MAX_DER_LEN: usize = 72;

/// Maximum total envelope size.
pub const MAX_WIRE_LEN: usize = HEADER_LEN + MAX_DER_LEN;

/// BRC-77 invoice prefix.
const INVOICE_PREFIX: []const u8 = "2-message signing-";
/// Standard base64 of 32 bytes = 44 chars.
const B64_KEY_ID_LEN: usize = 44;
const INVOICE_LEN: usize = INVOICE_PREFIX.len + B64_KEY_ID_LEN;

// ─────────────────────────────────────────────────────────────────────
// Errors
// ─────────────────────────────────────────────────────────────────────

pub const Error = error{
    /// Key or pubkey bytes are invalid secp256k1 scalars / points.
    bad_key,
    /// Wire does not start with BRC-77 version bytes.
    bad_version,
    /// Wire is too short to contain the fixed header.
    wire_too_short,
    /// BRC-42 child key derivation failed (curve arithmetic).
    derivation_failed,
    /// Signature verification failed — message or key mismatch.
    sig_invalid,
    /// DER signature bytes in the wire are malformed.
    bad_der,
    /// Output buffer is smaller than MAX_WIRE_LEN.
    buf_too_small,
};

// ─────────────────────────────────────────────────────────────────────
// Internal helpers
// ─────────────────────────────────────────────────────────────────────

fn buildInvoice(key_id: [KEY_ID_LEN]u8, out_buf: *[INVOICE_LEN]u8) []const u8 {
    @memcpy(out_buf[0..INVOICE_PREFIX.len], INVOICE_PREFIX);
    const b64_len = std.base64.standard.Encoder.calcSize(KEY_ID_LEN);
    _ = std.base64.standard.Encoder.encode(out_buf[INVOICE_PREFIX.len..][0..b64_len], &key_id);
    return out_buf[0 .. INVOICE_PREFIX.len + b64_len];
}

// ─────────────────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────────────────

/// Produce a BRC-77 directed-mode signed envelope and write it to
/// `out_buf`.  Returns the used slice (no allocation).
///
/// Parameters:
///   sender_priv      — sender's 32-byte secp256k1 private key
///   sender_pub_sec1  — sender's 33-byte compressed pubkey
///   recipient_pub    — recipient's 33-byte compressed pubkey
///   key_id           — 32 random bytes (call `randomKeyId()`)
///   message          — raw bytes to sign (not pre-hashed)
///   out_buf          — destination; must be ≥ MAX_WIRE_LEN bytes
pub fn sign(
    sender_priv: [32]u8,
    sender_pub_sec1: [PUBKEY_LEN]u8,
    recipient_pub: [PUBKEY_LEN]u8,
    key_id: [KEY_ID_LEN]u8,
    message: []const u8,
    out_buf: []u8,
) Error![]u8 {
    if (out_buf.len < MAX_WIRE_LEN) return Error.buf_too_small;

    var inv_buf: [INVOICE_LEN]u8 = undefined;
    const invoice = buildInvoice(key_id, &inv_buf);

    const sender = bsvz.primitives.ec.PrivateKey.fromBytes(sender_priv) catch return Error.bad_key;
    const recipient = bsvz.primitives.ec.PublicKey.fromSec1(&recipient_pub) catch return Error.bad_key;
    const child_priv = sender.deriveChild(recipient, invoice) catch return Error.derivation_failed;
    const der_sig = child_priv.signHash256(message) catch return Error.derivation_failed;
    const der_bytes = der_sig.asSlice();

    var pos: usize = 0;
    @memcpy(out_buf[pos..][0..4], &VERSION);
    pos += 4;
    @memcpy(out_buf[pos..][0..PUBKEY_LEN], &sender_pub_sec1);
    pos += PUBKEY_LEN;
    @memcpy(out_buf[pos..][0..PUBKEY_LEN], &recipient_pub);
    pos += PUBKEY_LEN;
    @memcpy(out_buf[pos..][0..KEY_ID_LEN], &key_id);
    pos += KEY_ID_LEN;
    @memcpy(out_buf[pos..][0..der_bytes.len], der_bytes);
    pos += der_bytes.len;

    return out_buf[0..pos];
}

/// Parse and verify a BRC-77 directed-mode envelope.
///
/// Returns the signer's compressed-SEC1 pubkey on success.
/// The caller verifies the signer is who they expect.
///
/// Parameters:
///   wire           — BRC-77 envelope bytes (from `sign`)
///   recipient_priv — recipient's 32-byte private key
///   message        — the original message bytes that were signed
pub fn verify(
    wire: []const u8,
    recipient_priv: [32]u8,
    message: []const u8,
) Error![PUBKEY_LEN]u8 {
    if (wire.len < 4) return Error.wire_too_short;
    if (!std.mem.eql(u8, wire[0..4], &VERSION)) return Error.bad_version;

    if (wire.len < HEADER_LEN + 1) return Error.wire_too_short;

    // Parse fixed header
    var signer_pub: [PUBKEY_LEN]u8 = undefined;
    @memcpy(&signer_pub, wire[4..][0..PUBKEY_LEN]);
    // recipient pubkey (offset 37) — already known from priv, skip it
    var key_id: [KEY_ID_LEN]u8 = undefined;
    @memcpy(&key_id, wire[4 + 33 + 33 ..][0..KEY_ID_LEN]);

    const der_bytes = wire[HEADER_LEN..];
    if (der_bytes.len == 0 or der_bytes.len > MAX_DER_LEN) return Error.wire_too_short;

    var inv_buf: [INVOICE_LEN]u8 = undefined;
    const invoice = buildInvoice(key_id, &inv_buf);

    // Derive child pubkey via the PUBLIC-side BRC-42 path:
    //   sender_pub.deriveChild(recipient_priv, invoice) = sender_pub + h×G
    // This matches the sign path which yields child_pub = sender_pub + h×G,
    // ensuring both sides agree on the same verification key.
    const rpriv = bsvz.primitives.ec.PrivateKey.fromBytes(recipient_priv) catch return Error.bad_key;
    const spub = bsvz.primitives.ec.PublicKey.fromSec1(&signer_pub) catch return Error.bad_key;
    const child_pub = spub.deriveChild(rpriv, invoice) catch return Error.derivation_failed;

    // Parse DER and verify over SHA256d(message)
    const parsed_der = bsvz.crypto.DerSignature.fromDer(der_bytes) catch return Error.bad_der;
    const sha256d = bsvz.crypto.hash.hash256(message);
    const ok = child_pub.verifyDigest(sha256d.bytes, parsed_der) catch return Error.sig_invalid;
    if (!ok) return Error.sig_invalid;

    return signer_pub;
}

/// Generate a random 32-byte keyID.
pub fn randomKeyId() [KEY_ID_LEN]u8 {
    var id: [KEY_ID_LEN]u8 = undefined;
    std.crypto.random.bytes(&id);
    return id;
}

// ─────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────

fn seedKey(seed: []const u8) [32]u8 {
    var k: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(seed, &k, .{});
    return k;
}

fn pubOf(priv_bytes: [32]u8) [PUBKEY_LEN]u8 {
    const k = bsvz.primitives.ec.PrivateKey.fromBytes(priv_bytes) catch unreachable;
    return (k.publicKey() catch unreachable).toCompressedSec1();
}

test "brc77: sign + verify round-trip" {
    const sender_priv = seedKey("brc77-sender-todd-2026");
    const recipient_priv = seedKey("brc77-recipient-bridget-2026");
    const sender_pub = pubOf(sender_priv);
    const recipient_pub = pubOf(recipient_priv);
    const key_id = randomKeyId();
    const message = "Hello Bridget, intent: schedule.task.create";

    var wire_buf: [MAX_WIRE_LEN]u8 = undefined;
    const wire = try sign(sender_priv, sender_pub, recipient_pub, key_id, message, &wire_buf);

    try std.testing.expectEqualSlices(u8, &VERSION, wire[0..4]);

    const recovered = try verify(wire, recipient_priv, message);
    try std.testing.expectEqualSlices(u8, &sender_pub, &recovered);
}

test "brc77: tampered message rejected" {
    const sender_priv = seedKey("brc77-tamper-sender");
    const recipient_priv = seedKey("brc77-tamper-recipient");
    const sender_pub = pubOf(sender_priv);
    const recipient_pub = pubOf(recipient_priv);
    const key_id = randomKeyId();

    var wire_buf: [MAX_WIRE_LEN]u8 = undefined;
    const wire = try sign(sender_priv, sender_pub, recipient_pub, key_id, "authentic", &wire_buf);

    const result = verify(wire, recipient_priv, "tampered");
    try std.testing.expectError(Error.sig_invalid, result);
}

test "brc77: wrong recipient private key rejected" {
    const sender_priv = seedKey("brc77-wrong-sender");
    const recipient_priv = seedKey("brc77-wrong-recipient");
    const interloper_priv = seedKey("brc77-wrong-interloper");
    const sender_pub = pubOf(sender_priv);
    const recipient_pub = pubOf(recipient_priv);
    const key_id = randomKeyId();
    const message = "private message";

    var wire_buf: [MAX_WIRE_LEN]u8 = undefined;
    const wire = try sign(sender_priv, sender_pub, recipient_pub, key_id, message, &wire_buf);

    // Interloper cannot derive the same child pubkey
    const result = verify(wire, interloper_priv, message);
    try std.testing.expectError(Error.sig_invalid, result);
}

test "brc77: bad version rejected" {
    const bad: [4]u8 = .{ 0x00, 0x00, 0x00, 0x00 };
    const result = verify(&bad, seedKey("x"), "");
    try std.testing.expectError(Error.bad_version, result);
}

test "brc77: wire too short rejected" {
    const partial = VERSION;
    const result = verify(&partial, seedKey("x"), "");
    try std.testing.expectError(Error.wire_too_short, result);
}

```
