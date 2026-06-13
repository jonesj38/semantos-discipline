---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/brc78.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.260920+00:00
---

# runtime/semantos-brain/src/brc78.zig

```zig
// D-network-messagebox-first-class — BRC-78 encrypted message envelope.
//
// Reference: https://brc.dev/78 — "BRC-78: Encrypted Message Format"
//
// Wire format:
//
//   [4B  version:    0x10, 0x33, 0x42, 0x42]
//   [33B sender:     sender's compressed-SEC1 pubkey]
//   [33B recipient:  recipient's compressed-SEC1 pubkey]
//   [32B keyID:      caller-supplied random key identifier]
//   [32B iv:         AES-256-GCM nonce (random per message)]
//   [N B ciphertext: AES-256-GCM encrypted payload]
//   [16B tag:        AES-256-GCM authentication tag]
//
// Key derivation:
//   invoice   = "2-message encryption-" + base64(keyID)
//   ecdh      = senderPriv.deriveSharedSecret(recipientPub)
//   aes_key   = SHA256(ecdh.x || ecdh.y)
//
// The BRC-42 invoice isn't used for key derivation here — BRC-78 uses
// the raw ECDH shared point (x, y) hashed with SHA-256 as the AES key.
// The invoice could be used for a future "keyed ECIES" variant, but the
// current spec uses the raw ECDH point.
//
// Note: the 32-byte IV is non-standard for AES-GCM (standard = 12 B);
// bsvz.primitives.aesgcm handles arbitrary nonce lengths via GHASH-based
// J0 computation, which matches the reference @bsv/sdk behaviour.

const std = @import("std");
const bsvz = @import("bsvz");

// ─────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────

pub const VERSION: [4]u8 = .{ 0x10, 0x33, 0x42, 0x42 };
pub const KEY_ID_LEN: usize = 32;
pub const PUBKEY_LEN: usize = 33;
pub const IV_LEN: usize = 32;
pub const TAG_LEN: usize = 16;
pub const AES_KEY_LEN: usize = 32;

/// Fixed header before the ciphertext:
///   4 (version) + 33 (sender) + 33 (recipient) + 32 (keyID) + 32 (iv) = 134 B
pub const HEADER_LEN: usize = 4 + 33 + 33 + 32 + 32;
/// Minimum wire length: header + 0 B ciphertext + 16 B tag = 150 B.
pub const MIN_WIRE_LEN: usize = HEADER_LEN + TAG_LEN;

// ─────────────────────────────────────────────────────────────────────
// Errors
// ─────────────────────────────────────────────────────────────────────

pub const Error = error{
    /// Key or pubkey bytes are invalid.
    bad_key,
    /// Wire does not start with BRC-78 version bytes.
    bad_version,
    /// Wire is too short for the minimum header + tag.
    wire_too_short,
    /// ECDH shared secret derivation failed.
    derivation_failed,
    /// AES-256-GCM decryption / authentication failed.
    decryption_failed,
    /// Allocation failure.
    out_of_memory,
};

// ─────────────────────────────────────────────────────────────────────
// Internal helpers
// ─────────────────────────────────────────────────────────────────────

/// Derive the 32-byte AES key: SHA256(ecdh_point.x || ecdh_point.y).
fn deriveAesKey(
    sender_priv: bsvz.primitives.ec.PrivateKey,
    recipient_pub: bsvz.primitives.ec.PublicKey,
) Error![AES_KEY_LEN]u8 {
    const shared_pub = sender_priv.deriveSharedSecret(recipient_pub) catch return Error.derivation_failed;
    // Uncompressed SEC1 = 0x04 || x (32 B) || y (32 B)
    const uncompressed = shared_pub.toUncompressedSec1();
    var xy: [64]u8 = undefined;
    @memcpy(&xy, uncompressed[1..65]);
    var key: [AES_KEY_LEN]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(&xy, &key, .{});
    return key;
}

// ─────────────────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────────────────

/// Encrypt `plaintext` as a BRC-78 envelope.  Returns a heap-allocated
/// slice; caller must `allocator.free` it.
///
/// Parameters:
///   allocator        — for ciphertext allocation
///   sender_priv      — sender's 32-byte secp256k1 private key
///   sender_pub_sec1  — sender's 33-byte compressed pubkey
///   recipient_pub    — recipient's 33-byte compressed pubkey
///   key_id           — 32 random bytes (call `randomKeyId()`)
///   iv               — 32 random bytes (call `randomIv()`)
///   plaintext        — raw bytes to encrypt
pub fn encrypt(
    allocator: std.mem.Allocator,
    sender_priv: [32]u8,
    sender_pub_sec1: [PUBKEY_LEN]u8,
    recipient_pub_sec1: [PUBKEY_LEN]u8,
    key_id: [KEY_ID_LEN]u8,
    iv: [IV_LEN]u8,
    plaintext: []const u8,
) Error![]u8 {
    const spriv = bsvz.primitives.ec.PrivateKey.fromBytes(sender_priv) catch return Error.bad_key;
    const rpub = bsvz.primitives.ec.PublicKey.fromSec1(&recipient_pub_sec1) catch return Error.bad_key;
    const aes_key = try deriveAesKey(spriv, rpub);

    const gcm = bsvz.primitives.aesgcm.aesGcmEncrypt(
        allocator,
        plaintext,
        &aes_key,
        &iv,
        "", // no additional data in BRC-78
    ) catch return Error.out_of_memory;
    defer allocator.free(gcm.ciphertext);

    // Wire = HEADER_LEN + ciphertext + TAG_LEN
    const wire_len = HEADER_LEN + gcm.ciphertext.len + TAG_LEN;
    const wire = allocator.alloc(u8, wire_len) catch return Error.out_of_memory;
    errdefer allocator.free(wire);

    var pos: usize = 0;
    @memcpy(wire[pos..][0..4], &VERSION);
    pos += 4;
    @memcpy(wire[pos..][0..PUBKEY_LEN], &sender_pub_sec1);
    pos += PUBKEY_LEN;
    @memcpy(wire[pos..][0..PUBKEY_LEN], &recipient_pub_sec1);
    pos += PUBKEY_LEN;
    @memcpy(wire[pos..][0..KEY_ID_LEN], &key_id);
    pos += KEY_ID_LEN;
    @memcpy(wire[pos..][0..IV_LEN], &iv);
    pos += IV_LEN;
    @memcpy(wire[pos..][0..gcm.ciphertext.len], gcm.ciphertext);
    pos += gcm.ciphertext.len;
    @memcpy(wire[pos..][0..TAG_LEN], &gcm.tag);
    pos += TAG_LEN;
    std.debug.assert(pos == wire_len);

    return wire;
}

/// Decrypt a BRC-78 envelope.  Returns a heap-allocated plaintext slice;
/// caller must `allocator.free` it.
///
/// Parameters:
///   allocator        — for plaintext allocation
///   wire             — BRC-78 envelope bytes (from `encrypt`)
///   recipient_priv   — recipient's 32-byte private key
pub fn decrypt(
    allocator: std.mem.Allocator,
    wire: []const u8,
    recipient_priv: [32]u8,
) Error![]u8 {
    if (wire.len < 4) return Error.wire_too_short;
    if (!std.mem.eql(u8, wire[0..4], &VERSION)) return Error.bad_version;
    if (wire.len < MIN_WIRE_LEN) return Error.wire_too_short;

    // Parse sender pubkey (offset 4)
    var sender_pub_bytes: [PUBKEY_LEN]u8 = undefined;
    @memcpy(&sender_pub_bytes, wire[4..][0..PUBKEY_LEN]);

    // recipient pub at offset 37 — skip (we have priv)
    // keyID at offset 70 — skip (not needed for decryption)

    // IV at offset 102
    var iv: [IV_LEN]u8 = undefined;
    @memcpy(&iv, wire[4 + 33 + 33 + 32 ..][0..IV_LEN]);

    // Ciphertext + tag
    const ct_and_tag = wire[HEADER_LEN..];
    if (ct_and_tag.len < TAG_LEN) return Error.wire_too_short;
    const ciphertext = ct_and_tag[0 .. ct_and_tag.len - TAG_LEN];
    var tag: [TAG_LEN]u8 = undefined;
    @memcpy(&tag, ct_and_tag[ct_and_tag.len - TAG_LEN ..]);

    // Derive AES key: recipient_priv × sender_pub (ECDH symmetric)
    const rpriv = bsvz.primitives.ec.PrivateKey.fromBytes(recipient_priv) catch return Error.bad_key;
    const spub = bsvz.primitives.ec.PublicKey.fromSec1(&sender_pub_bytes) catch return Error.bad_key;
    const aes_key = try deriveAesKey(rpriv, spub);

    const plaintext = bsvz.primitives.aesgcm.aesGcmDecrypt(
        allocator,
        ciphertext,
        &aes_key,
        &iv,
        "", // no additional data
        tag,
    ) catch return Error.decryption_failed;

    return plaintext;
}

/// Generate a random 32-byte keyID.
pub fn randomKeyId() [KEY_ID_LEN]u8 {
    var id: [KEY_ID_LEN]u8 = undefined;
    std.crypto.random.bytes(&id);
    return id;
}

/// Generate a random 32-byte IV.
pub fn randomIv() [IV_LEN]u8 {
    var iv: [IV_LEN]u8 = undefined;
    std.crypto.random.bytes(&iv);
    return iv;
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

test "brc78: encrypt + decrypt round-trip" {
    const allocator = std.testing.allocator;
    const sender_priv = seedKey("brc78-sender-todd-2026");
    const recipient_priv = seedKey("brc78-recipient-bridget-2026");
    const sender_pub = pubOf(sender_priv);
    const recipient_pub = pubOf(recipient_priv);
    const key_id = randomKeyId();
    const iv = randomIv();
    const plaintext = "Hello Bridget, this is an encrypted intent: schedule.task.create";

    const wire = try encrypt(allocator, sender_priv, sender_pub, recipient_pub, key_id, iv, plaintext);
    defer allocator.free(wire);

    // Wire must start with version bytes
    try std.testing.expectEqualSlices(u8, &VERSION, wire[0..4]);
    // Wire is bigger than the plaintext
    try std.testing.expect(wire.len > plaintext.len);

    const decrypted = try decrypt(allocator, wire, recipient_priv);
    defer allocator.free(decrypted);

    try std.testing.expectEqualSlices(u8, plaintext, decrypted);
}

test "brc78: wrong recipient key fails" {
    const allocator = std.testing.allocator;
    const sender_priv = seedKey("brc78-sender-wrong");
    const recipient_priv = seedKey("brc78-recipient-wrong");
    const interloper_priv = seedKey("brc78-interloper-wrong");
    const sender_pub = pubOf(sender_priv);
    const recipient_pub = pubOf(recipient_priv);
    const key_id = randomKeyId();
    const iv = randomIv();

    const wire = try encrypt(allocator, sender_priv, sender_pub, recipient_pub, key_id, iv, "secret");
    defer allocator.free(wire);

    // Interloper cannot derive the same AES key
    const result = decrypt(allocator, wire, interloper_priv);
    try std.testing.expectError(Error.decryption_failed, result);
}

test "brc78: bad version rejected" {
    const wire = [4]u8{ 0x00, 0x00, 0x00, 0x00 };
    const result = decrypt(std.testing.allocator, &wire, seedKey("x"));
    try std.testing.expectError(Error.bad_version, result);
}

test "brc78: wire too short rejected" {
    const wire = VERSION;
    const result = decrypt(std.testing.allocator, &wire, seedKey("x"));
    try std.testing.expectError(Error.wire_too_short, result);
}

test "brc78: tampered ciphertext fails authentication" {
    const allocator = std.testing.allocator;
    const sender_priv = seedKey("brc78-tamper-sender");
    const recipient_priv = seedKey("brc78-tamper-recipient");
    const sender_pub = pubOf(sender_priv);
    const recipient_pub = pubOf(recipient_priv);
    const key_id = randomKeyId();
    const iv = randomIv();

    var wire = try encrypt(allocator, sender_priv, sender_pub, recipient_pub, key_id, iv, "authentic payload");
    defer allocator.free(wire);

    // Flip a byte in the ciphertext region
    if (wire.len > HEADER_LEN + 1) wire[HEADER_LEN] ^= 0xFF;

    const result = decrypt(allocator, wire, recipient_priv);
    try std.testing.expectError(Error.decryption_failed, result);
}

```
