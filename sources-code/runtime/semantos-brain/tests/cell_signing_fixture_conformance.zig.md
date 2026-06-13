---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/cell_signing_fixture_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.210335+00:00
---

# runtime/semantos-brain/tests/cell_signing_fixture_conformance.zig

```zig
// D-O5m.followup-8 capture+upload — Cross-language signing fixture
// generator + conformance test.
//
// Reference: apps/semantos/lib/src/identity/cell_signer.dart
//            (the Dart cell signer that asserts byte-for-byte parity
//            against the fixture this test emits);
//            runtime/semantos-brain/tests/fixtures/cell-signing-fixture.json
//            (the committed fixture this test produces + verifies).
//
// What this test does:
//
//   1. Picks a stable {priv, payload} tuple — deterministic seed for
//      both, so the test is byte-for-byte reproducible across builds.
//   2. Computes the signature via bsvz `signCompact` (RFC 6979
//      deterministic-k — no noise).
//   3. Strips the recovery byte (compact bytes [1..65] = r||s) and
//      normalises s to low-s.
//   4. Writes the fixture JSON to disk if missing; otherwise asserts
//      the existing fixture matches byte-for-byte.
//
// The Dart side mirrors this exactly:
//   - Same priv (32 bytes hex)
//   - Same payload bytes (utf8 of the canonical-JSON sample)
//   - Same SHA-256 → ECDSA → low-s normalisation pipeline
//   - Same 64-byte (r || s) output
//
// Without this parity proof, the brain might accept Dart-signed cells
// that brain-signed ones would reject (or vice versa) — the load-bearing
// claim of "phone is a peer node producing signed cells" depends on
// the two implementations agreeing byte-for-byte.

const std = @import("std");
const bsvz = @import("bsvz");

/// Fixture path candidates — cwd-dependent.  `zig build test` runs
/// with cwd = `runtime/semantos-brain/`; ad-hoc invocations may run
/// from the repo root.  Mirrors `identity_certs_conformance.zig`'s
/// readFixture walk.
const FIXTURE_PATH_CANDIDATES = [_][]const u8{
    "tests/fixtures/cell-signing-fixture.json",
    "runtime/semantos-brain/tests/fixtures/cell-signing-fixture.json",
};

/// secp256k1 curve order (n).  Used for low-s normalisation.
/// 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
const SECP256K1_N: u256 = 0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFE_BAAEDCE6_AF48A03B_BFD25E8C_D0364141;
const SECP256K1_HALF_N: u256 = SECP256K1_N >> 1;

fn hexEncode(bytes: []const u8, out: []u8) void {
    std.debug.assert(out.len == bytes.len * 2);
    const chars = "0123456789abcdef";
    for (bytes, 0..) |b, i| {
        out[i * 2] = chars[b >> 4];
        out[i * 2 + 1] = chars[b & 0x0f];
    }
}

fn hexDecode(hex: []const u8, out: []u8) !void {
    if (hex.len != out.len * 2) return error.bad_hex;
    for (out, 0..) |*b, i| {
        const hi = try std.fmt.charToDigit(hex[i * 2], 16);
        const lo = try std.fmt.charToDigit(hex[i * 2 + 1], 16);
        b.* = @intCast(hi * 16 + lo);
    }
}

/// Apply low-s normalisation to the s scalar of a 64-byte compact
/// signature (r || s, big-endian).  Mirrors BIP-62 / SEC1 — if
/// s > n/2 then s = n - s.  Mutates `sig` in place.
fn normaliseLowS(sig: *[64]u8) void {
    const s_be = sig[32..64];
    const s_int = std.mem.readInt(u256, s_be[0..32], .big);
    if (s_int > SECP256K1_HALF_N) {
        const new_s = SECP256K1_N - s_int;
        std.mem.writeInt(u256, s_be[0..32], new_s, .big);
    }
}

/// Compute the cell signature: SHA-256(payload) → signCompact →
/// strip recovery byte → low-s normalise.  Returns the 64-byte (r||s)
/// compact signature.
pub fn signCellPayload(priv_bytes: [32]u8, payload: []const u8) ![64]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(payload, &digest, .{});

    const priv = try bsvz.primitives.ec.PrivateKey.fromBytes(priv_bytes);
    // signCompact returns 65 bytes: [recovery_byte || r || s].
    const compact = try priv.signCompact(digest, true);
    var sig: [64]u8 = undefined;
    @memcpy(&sig, compact[1..65]);
    normaliseLowS(&sig);
    return sig;
}

/// Verify a 64-byte (r||s) signature against `expected_pubkey` (the
/// 33-byte compressed-SEC1 device pubkey).  Mirrors
/// `signed_bundle.zig::verifySignature`'s recovery loop minus the
/// SIG_DOMAIN preimage prefix.
pub fn verifyCellSignature(payload: []const u8, sig: [64]u8, expected_pubkey: [33]u8) !void {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(payload, &digest, .{});

    var candidate: [65]u8 = undefined;
    @memcpy(candidate[1..65], &sig);
    var rec: u8 = 31;
    while (rec <= 34) : (rec += 1) {
        candidate[0] = rec;
        const recovered = bsvz.crypto.compact.recoverCompactDigest256(candidate, digest) catch continue;
        const recovered_sec1 = recovered.pubkey.toCompressedSec1();
        if (std.crypto.timing_safe.eql([33]u8, recovered_sec1, expected_pubkey)) return;
    }
    return error.signature_mismatch;
}

const FixtureBundle = struct {
    priv_hex: []const u8,
    pub_hex: []const u8,
    payload_hex: []const u8,
    payload_utf8: []const u8,
    signature_hex: []const u8,
};

/// Stable input tuple — never change without bumping the fixture
/// version.  Both Zig and Dart hash these to produce byte-identical
/// output.
const FIXTURE_PRIV_HEX = "5ad0e1ff96b4ef3df1ad34e5b97c4c1d8a5fe24ed18793e89d96d4d2e1abf001";
const FIXTURE_PAYLOAD_UTF8 =
    \\{"attachmentId":"00000000-0000-4000-8000-000000000001","capturedAt":"2026-05-15T14:30:00Z","capturedByCertId":"00112233445566778899aabbccddeeff","contentHash":"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad","contentSize":3,"createdAt":"2026-05-15T14:30:01Z","kind":"photo","mimeType":"image/jpeg","visitId":"00000000-0000-4000-8000-000000000002"}
;

fn computePub(priv: [32]u8) ![33]u8 {
    const sk = try bsvz.primitives.ec.PrivateKey.fromBytes(priv);
    const pk = try sk.publicKey();
    return pk.toCompressedSec1();
}

test "cell signing fixture: emit + parity" {
    const allocator = std.testing.allocator;

    var priv_bytes: [32]u8 = undefined;
    try hexDecode(FIXTURE_PRIV_HEX, &priv_bytes);

    const pub_bytes = try computePub(priv_bytes);
    var pub_hex: [66]u8 = undefined;
    hexEncode(&pub_bytes, &pub_hex);

    const sig = try signCellPayload(priv_bytes, FIXTURE_PAYLOAD_UTF8);
    var sig_hex: [128]u8 = undefined;
    hexEncode(&sig, &sig_hex);

    // Verify the signature recovers the expected pubkey end-to-end —
    // belt-and-braces against an accidental low-s bug (verify accepts
    // either branch but the parity test asserts the fixture-pinned
    // form).
    try verifyCellSignature(FIXTURE_PAYLOAD_UTF8, sig, pub_bytes);

    // Also verify a tampered payload fails — the verifier MUST reject
    // a signature over the wrong digest.
    const tampered = "tampered-payload";
    try std.testing.expectError(error.signature_mismatch, verifyCellSignature(tampered, sig, pub_bytes));

    // Build the canonical fixture JSON — sorted keys, 2-space indent
    // for readability, no trailing newline (matches what bun/jq dump
    // by default).
    var payload_hex_buf: std.ArrayList(u8) = .{};
    defer payload_hex_buf.deinit(allocator);
    for (FIXTURE_PAYLOAD_UTF8) |b| {
        try payload_hex_buf.print(allocator, "{x:0>2}", .{b});
    }

    // payload_utf8 contains nested double-quotes — emit it as a JSON-
    // escaped string via std.json.Stringify so the fixture parses
    // cleanly under both bun's JSON.parse and dart:convert's
    // json.decode.
    const payload_json_escaped = try std.json.Stringify.valueAlloc(allocator, FIXTURE_PAYLOAD_UTF8, .{});
    defer allocator.free(payload_json_escaped);

    var json_buf: std.ArrayList(u8) = .{};
    defer json_buf.deinit(allocator);
    try json_buf.print(allocator,
        "{{\n" ++
        "  \"_comment\": \"Generated by runtime/semantos-brain/tests/cell_signing_fixture_conformance.zig — DO NOT EDIT BY HAND.\",\n" ++
        "  \"priv_hex\": \"{s}\",\n" ++
        "  \"pub_hex\": \"{s}\",\n" ++
        "  \"payload_utf8\": {s},\n" ++
        "  \"payload_hex\": \"{s}\",\n" ++
        "  \"signature_hex\": \"{s}\"\n" ++
        "}}\n",
        .{
            FIXTURE_PRIV_HEX,
            pub_hex,
            payload_json_escaped,
            payload_hex_buf.items,
            sig_hex,
        },
    );

    // Try to read the existing fixture — if absent, write it (first-
    // run bootstrap); if present, assert byte-for-byte equality.
    const cwd = std.fs.cwd();
    var opened: ?std.fs.File = null;
    for (FIXTURE_PATH_CANDIDATES) |c| {
        if (cwd.openFile(c, .{})) |f| {
            opened = f;
            break;
        } else |err| switch (err) {
            error.FileNotFound => continue,
            else => return err,
        }
    }
    if (opened) |f| {
        defer f.close();
        const existing = try f.readToEndAlloc(allocator, 64 * 1024);
        defer allocator.free(existing);
        if (!std.mem.eql(u8, existing, json_buf.items)) {
            std.debug.print("\nFIXTURE DRIFT: {s} differs from canonical bytes.\n", .{FIXTURE_PATH_CANDIDATES[0]});
            std.debug.print("Expected:\n{s}\n", .{json_buf.items});
            std.debug.print("Got:\n{s}\n", .{existing});
            return error.FixtureDrift;
        }
    } else {
        // Bootstrap path — write the fixture at the cwd-relative path
        // so subsequent runs (and the Dart parity test) have it.
        const f = try cwd.createFile(FIXTURE_PATH_CANDIDATES[0], .{ .truncate = true });
        defer f.close();
        try f.writeAll(json_buf.items);
    }
}

test "low-s normalisation: applied when s > n/2" {
    var sig: [64]u8 = undefined;
    @memset(sig[0..32], 0); // r doesn't matter for the s-side check
    // s = n - 1 (definitely > n/2)
    const big_s: u256 = SECP256K1_N - 1;
    std.mem.writeInt(u256, sig[32..64], big_s, .big);

    normaliseLowS(&sig);
    const got_s = std.mem.readInt(u256, sig[32..64], .big);
    try std.testing.expectEqual(@as(u256, 1), got_s);
    try std.testing.expect(got_s <= SECP256K1_HALF_N);
}

test "low-s normalisation: no-op when s already low" {
    var sig: [64]u8 = undefined;
    @memset(sig[0..32], 0);
    const small_s: u256 = 42;
    std.mem.writeInt(u256, sig[32..64], small_s, .big);

    normaliseLowS(&sig);
    const got_s = std.mem.readInt(u256, sig[32..64], .big);
    try std.testing.expectEqual(@as(u256, 42), got_s);
}

test "verifyCellSignature: rejects invalid signature" {
    var priv_bytes: [32]u8 = undefined;
    try hexDecode(FIXTURE_PRIV_HEX, &priv_bytes);
    const pub_bytes = try computePub(priv_bytes);
    var bogus_sig: [64]u8 = undefined;
    @memset(&bogus_sig, 0xaa);
    try std.testing.expectError(error.signature_mismatch, verifyCellSignature(FIXTURE_PAYLOAD_UTF8, bogus_sig, pub_bytes));
}

```
