---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests/crypto_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.966448+00:00
---

# core/cell-engine/tests/crypto_conformance.zig

```zig
// Phase 5: Crypto conformance tests
// Verifies SHA256, HASH160, HASH256, CHECKSIG against known Bitcoin test vectors.

const std = @import("std");
const host = @import("host");

// ── SHA256 tests ──

test "SHA256 of empty string" {
    var out: [32]u8 = undefined;
    host.sha256("", &out);
    const expected = [_]u8{
        0xe3, 0xb0, 0xc4, 0x42, 0x98, 0xfc, 0x1c, 0x14,
        0x9a, 0xfb, 0xf4, 0xc8, 0x99, 0x6f, 0xb9, 0x24,
        0x27, 0xae, 0x41, 0xe4, 0x64, 0x9b, 0x93, 0x4c,
        0xa4, 0x95, 0x99, 0x1b, 0x78, 0x52, 0xb8, 0x55,
    };
    try std.testing.expectEqualSlices(u8, &expected, &out);
}

test "SHA256 of 'abc'" {
    var out: [32]u8 = undefined;
    host.sha256("abc", &out);
    const expected = [_]u8{
        0xba, 0x78, 0x16, 0xbf, 0x8f, 0x01, 0xcf, 0xea,
        0x41, 0x41, 0x40, 0xde, 0x5d, 0xae, 0x22, 0x23,
        0xb0, 0x03, 0x61, 0xa3, 0x96, 0x17, 0x7a, 0x9c,
        0xb4, 0x10, 0xff, 0x61, 0xf2, 0x00, 0x15, 0xad,
    };
    try std.testing.expectEqualSlices(u8, &expected, &out);
}

test "SHA256 of known 56-byte input" {
    // "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
    const input = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq";
    var out: [32]u8 = undefined;
    host.sha256(input, &out);
    const expected = [_]u8{
        0x24, 0x8d, 0x6a, 0x61, 0xd2, 0x06, 0x38, 0xb8,
        0xe5, 0xc0, 0x26, 0x93, 0x0c, 0x3e, 0x60, 0x39,
        0xa3, 0x3c, 0xe4, 0x59, 0x64, 0xff, 0x21, 0x67,
        0xf6, 0xec, 0xed, 0xd4, 0x19, 0xdb, 0x06, 0xc1,
    };
    try std.testing.expectEqualSlices(u8, &expected, &out);
}

// ── HASH256 (double SHA256) tests ──

test "HASH256 of empty string" {
    var out: [32]u8 = undefined;
    host.hash256("", &out);
    // SHA256(SHA256(""))
    const expected = [_]u8{
        0x5d, 0xf6, 0xe0, 0xe2, 0x76, 0x13, 0x59, 0xd3,
        0x0a, 0x82, 0x75, 0x05, 0x8e, 0x29, 0x9f, 0xcc,
        0x03, 0x81, 0x53, 0x45, 0x45, 0xf5, 0x5c, 0xf4,
        0x3e, 0x41, 0x98, 0x3f, 0x5d, 0x4c, 0x94, 0x56,
    };
    try std.testing.expectEqualSlices(u8, &expected, &out);
}

test "HASH256 of 'abc'" {
    var out: [32]u8 = undefined;
    host.hash256("abc", &out);
    // Double SHA256 of "abc" — known Bitcoin test vector
    // SHA256("abc") = ba7816bf...
    // SHA256(sha256_abc) = 4f8b42c2...
    const expected = [_]u8{
        0x4f, 0x8b, 0x42, 0xc2, 0x2d, 0xd3, 0x72, 0x9b,
        0x51, 0x9b, 0xa6, 0xf6, 0x8d, 0x2d, 0xa7, 0xcc,
        0x5b, 0x2d, 0x60, 0x6d, 0x05, 0xda, 0xed, 0x5a,
        0xd5, 0x12, 0x8c, 0xc0, 0x3e, 0x6c, 0x63, 0x58,
    };
    try std.testing.expectEqualSlices(u8, &expected, &out);
}

// ── HASH160 tests ──
// Both profiles now have real RIPEMD160:
//   Full profile: BSVZ native
//   Embedded native: pure-Zig ripemd160.zig

test "HASH160 of empty string" {
    var out: [20]u8 = undefined;
    host.hash160("", &out);
    // HASH160("") = RIPEMD160(SHA256(""))
    // SHA256("") = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
    // RIPEMD160(sha256_empty) = b472a266d0bd89c13706a4132ccfb16f7c3b9fcb
    const expected = [_]u8{
        0xb4, 0x72, 0xa2, 0x66, 0xd0, 0xbd, 0x89, 0xc1, 0x37, 0x06,
        0xa4, 0x13, 0x2c, 0xcf, 0xb1, 0x6f, 0x7c, 0x3b, 0x9f, 0xcb,
    };
    try std.testing.expectEqualSlices(u8, &expected, &out);
}

test "HASH160 of 'abc'" {
    var out: [20]u8 = undefined;
    host.hash160("abc", &out);
    // SHA256("abc") = ba7816bf...
    // RIPEMD160(SHA256("abc")) = bb1be98c142444d7a56aa3981c3942a978e4dc33
    const expected = [_]u8{
        0xbb, 0x1b, 0xe9, 0x8c, 0x14, 0x24, 0x44, 0xd7, 0xa5, 0x6a,
        0xa3, 0x98, 0x1c, 0x39, 0x42, 0xa9, 0x78, 0xe4, 0xdc, 0x33,
    };
    try std.testing.expectEqualSlices(u8, &expected, &out);
}

test "HASH160 produces 20-byte non-zero output" {
    var out: [20]u8 = undefined;
    host.hash160("test", &out);
    var all_zero = true;
    for (out) |b| {
        if (b != 0) all_zero = false;
    }
    try std.testing.expect(!all_zero);
}

// ── CHECKSIG tests ──
// Full profile: BSVZ ECDSA verification with real test vectors.
// Embedded native: stub returns false (no secp256k1 without BSVZ).

test "CHECKSIG with empty inputs returns false" {
    const result = host.checksig(&[_]u8{}, &[_]u8{}, &[_]u8{});
    try std.testing.expect(!result);
}

test "CHECKSIG rejects malformed pubkey" {
    var fake_hash: [32]u8 = undefined;
    @memset(&fake_hash, 0xAB);
    var fake_sig: [73]u8 = undefined;
    @memset(&fake_sig, 0x30);
    fake_sig[72] = 0x01; // sighash ALL

    const result = host.checksig(&[_]u8{ 0x04, 0x00 }, &fake_hash, &fake_sig);
    try std.testing.expect(!result);
}

test "CHECKSIG rejects too-short signature" {
    var fake_hash: [32]u8 = undefined;
    @memset(&fake_hash, 0xAB);
    // Minimum compressed pubkey (33 bytes)
    var fake_pk: [33]u8 = undefined;
    fake_pk[0] = 0x02;
    @memset(fake_pk[1..], 0x01);

    // Sig too short (only 1 byte)
    const result = host.checksig(&fake_pk, &fake_hash, &[_]u8{0x01});
    try std.testing.expect(!result);
}

```
