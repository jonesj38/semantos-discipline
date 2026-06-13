---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/device_pair_recovery_roundtrip_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.202493+00:00
---

# runtime/semantos-brain/tests/device_pair_recovery_roundtrip_conformance.zig

```zig
// Phase D-O5p — §9.4 recovery round-trip.
//
// Reference: docs/design/ODDJOBZ-EXTENSION-PLAN.md §9 acceptance
// gate #4 ("Recovery round-trip: encrypt extension state, encode in
// recovery payload, decode, decrypt — bytes match").
//
// What this asserts:
//
//   • A cert chain (operator root + N paired children) can be
//     exported as a canonical JSON byte-stream.
//   • The exported bytes can be encrypted under an operator-derived
//     symmetric key + encoded in a recovery payload envelope.
//   • The recovery payload decodes + decrypts to byte-identical
//     bytes vs. the input.
//
// ── Scope of the recovery surface this test covers ──
//
// The full Plexus recovery flow (BRC-100 cert challenge, Shamir
// share reconstruction across recovery enrolment shards, RECOVERY-
// SHARE-MANAGER reassembly) is out of scope for this PR — that
// machinery sits in `core/protocol-types/src/identity-adapters/local/`
// and is exercised by its own test suite.  D-O5p just needs the §9
// acceptance gate that asserts: given the cert chain bytes, a
// closed encrypt → encode → decode → decrypt loop is lossless.
//
// The test below uses ChaCha20-Poly1305 (the same AEAD brain's wallet
// recovery uses for at-rest seed encryption) keyed off a 32-byte
// operator-derived symmetric key.  Authentic shape; doesn't claim to
// be the production recovery codec.
//
// TODO(D-O5p+1): when the Plexus recovery service exposes a
// dedicated cert-chain payload type (separate from the
// resource_registrations table the wallet recovery flow uses),
// migrate this test to drive that surface directly.  Tracked at
// packages/recovery/src/export-payload.ts — currently only the
// resource registration shape is covered.

const std = @import("std");
const bkds = @import("bkds");
const identity_certs = @import("identity_certs");

const TestRoot = struct {
    privkey: [bkds.PRIVKEY_LEN]u8,
    pubkey: [bkds.PUBKEY_LEN]u8,
};

fn pinnedClock() i64 {
    return 1_700_000_000;
}

fn makeTestRoot(seed: []const u8) !TestRoot {
    return .{
        .privkey = bkds.privFromSeed(seed),
        .pubkey = try bkds.pubFromSeed(seed),
    };
}

/// Build a synthetic cert chain in `data_dir`: an operator root
/// plus 3 child certs spread across context tags 0x10, 0x11, 0x12.
/// Returns the on-disk bytes of identity-certs.log.
fn seedCertChain(allocator: std.mem.Allocator, data_dir: []const u8) ![]u8 {
    const root = try makeTestRoot("operator-D-O5p-recovery");
    var store = try identity_certs.CertStore.init(allocator, data_dir, struct {
        fn t() i64 {
            return 1_700_000_000;
        }
    }.t);
    defer store.deinit();
    const root_rec = try store.issueRoot(root.pubkey, "operator");

    inline for (.{ "iPhone", "iPad", "MacBook" }, .{ 0x10, 0x11, 0x12 }, .{ "device-A", "device-B", "device-C" }) |label, ctx, dseed| {
        const dpriv_obj = try @import("bsvz").primitives.ec.PrivateKey.fromBytes(bkds.privFromSeed(dseed));
        const dpub_obj = try dpriv_obj.publicKey();
        const dpub = dpub_obj.toCompressedSec1();
        const child_pub = try bkds.deriveChildPubkey(root.privkey, dpub, ctx, label);
        const caps = [_][]const u8{ "cap.attach.photo", "cap.attach.gps" };
        _ = try store.issueChild(&root_rec.id, ctx, child_pub, &caps, label);
    }

    // Read the raw on-disk log bytes — that's what the recovery
    // payload encrypts.
    const log_path = try std.fs.path.join(allocator, &.{ data_dir, "identity-certs.log" });
    defer allocator.free(log_path);
    const f = try std.fs.cwd().openFile(log_path, .{});
    defer f.close();
    const stat = try f.stat();
    const buf = try allocator.alloc(u8, stat.size);
    _ = try f.readAll(buf);
    return buf;
}

// ── ChaCha20-Poly1305 envelope ────────────────────────────────────────
//
// 12-byte nonce + ciphertext + 16-byte tag.  Wraps the inner JSON
// payload bytes byte-for-byte.

const NONCE_LEN: usize = 12;
const TAG_LEN: usize = 16;

const ChaCha = std.crypto.aead.chacha_poly.ChaCha20Poly1305;

fn encrypt(allocator: std.mem.Allocator, key: [32]u8, plaintext: []const u8) ![]u8 {
    const out = try allocator.alloc(u8, NONCE_LEN + plaintext.len + TAG_LEN);
    errdefer allocator.free(out);
    // Fixed nonce for determinism in the round-trip test (production
    // generates a fresh nonce per recovery payload).
    @memset(out[0..NONCE_LEN], 0xA5);
    var tag: [TAG_LEN]u8 = undefined;
    ChaCha.encrypt(
        out[NONCE_LEN..][0..plaintext.len],
        &tag,
        plaintext,
        &.{},
        out[0..NONCE_LEN].*,
        key,
    );
    @memcpy(out[NONCE_LEN + plaintext.len ..][0..TAG_LEN], &tag);
    return out;
}

fn decrypt(allocator: std.mem.Allocator, key: [32]u8, ciphertext: []const u8) ![]u8 {
    if (ciphertext.len < NONCE_LEN + TAG_LEN) return error.bad_envelope;
    const ct_len = ciphertext.len - NONCE_LEN - TAG_LEN;
    const out = try allocator.alloc(u8, ct_len);
    errdefer allocator.free(out);
    var nonce: [NONCE_LEN]u8 = undefined;
    @memcpy(&nonce, ciphertext[0..NONCE_LEN]);
    var tag: [TAG_LEN]u8 = undefined;
    @memcpy(&tag, ciphertext[NONCE_LEN + ct_len ..][0..TAG_LEN]);
    try ChaCha.decrypt(
        out,
        ciphertext[NONCE_LEN..][0..ct_len],
        tag,
        &.{},
        nonce,
        key,
    );
    return out;
}

// ─────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────

test "D-O5p §9.4 recovery round-trip — cert chain bytes survive encrypt → decode → decrypt" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);

    const cert_chain_bytes = try seedCertChain(allocator, real);
    defer allocator.free(cert_chain_bytes);

    // Sanity: chain has root + 3 children → at least 4 lines.
    var line_count: usize = 0;
    for (cert_chain_bytes) |c| if (c == '\n') {
        line_count += 1;
    };
    try std.testing.expect(line_count >= 4);

    // Operator-derived symmetric key (the production recovery
    // surface derives this from a Shamir-share reassembly; here we
    // pin a deterministic 32 bytes from a known seed).
    var rec_key: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash("D-O5p-recovery-key-seed", &rec_key, .{});

    // Encrypt → encode → decode → decrypt.
    const enc = try encrypt(allocator, rec_key, cert_chain_bytes);
    defer allocator.free(enc);

    // Wrap in a recovery payload envelope (JSON shape mirroring the
    // wallet recovery v0 format: domain + version + base64url body).
    var env_buf: std.ArrayList(u8) = .{};
    defer env_buf.deinit(allocator);
    const b64_enc = std.base64.url_safe_no_pad.Encoder;
    const b64_size = b64_enc.calcSize(enc.len);
    const b64_buf = try allocator.alloc(u8, b64_size);
    defer allocator.free(b64_buf);
    _ = b64_enc.encode(b64_buf, enc);
    try env_buf.print(allocator,
        "{{\"domain\":\"brain-cert-chain-recovery-v0\",\"v\":0,\"body\":\"{s}\"}}",
        .{b64_buf});

    // Decode envelope.
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, env_buf.items, .{});
    defer parsed.deinit();
    const body_v = parsed.value.object.get("body").?;
    try std.testing.expectEqualStrings(parsed.value.object.get("domain").?.string, "brain-cert-chain-recovery-v0");
    try std.testing.expectEqual(@as(i64, 0), parsed.value.object.get("v").?.integer);

    const b64_dec = std.base64.url_safe_no_pad.Decoder;
    const dec_size = try b64_dec.calcSizeForSlice(body_v.string);
    const dec_buf = try allocator.alloc(u8, dec_size);
    defer allocator.free(dec_buf);
    try b64_dec.decode(dec_buf, body_v.string);

    // Decrypt.
    const decrypted = try decrypt(allocator, rec_key, dec_buf);
    defer allocator.free(decrypted);

    // Bytes match — the §9.4 acceptance.
    try std.testing.expectEqualSlices(u8, cert_chain_bytes, decrypted);
}

test "D-O5p §9.4 recovery round-trip — wrong key fails authentication" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);
    const cert_chain_bytes = try seedCertChain(allocator, real);
    defer allocator.free(cert_chain_bytes);

    var rec_key: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash("D-O5p-recovery-key-seed", &rec_key, .{});
    const enc = try encrypt(allocator, rec_key, cert_chain_bytes);
    defer allocator.free(enc);

    // Decrypt with a different key — Poly1305 tag check fires.
    var wrong_key: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash("D-O5p-recovery-WRONG-key-seed", &wrong_key, .{});
    try std.testing.expectError(error.AuthenticationFailed, decrypt(allocator, wrong_key, enc));
}

test "D-O5p §9.4 recovery round-trip — empty chain still encodes losslessly" {
    const allocator = std.testing.allocator;
    var rec_key: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash("D-O5p-empty-seed", &rec_key, .{});
    const empty: []const u8 = "";
    const enc = try encrypt(allocator, rec_key, empty);
    defer allocator.free(enc);
    const dec = try decrypt(allocator, rec_key, enc);
    defer allocator.free(dec);
    try std.testing.expectEqualSlices(u8, empty, dec);
}

```
