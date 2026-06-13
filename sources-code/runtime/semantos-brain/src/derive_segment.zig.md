---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/derive_segment.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.241393+00:00
---

# runtime/semantos-brain/src/derive_segment.zig

```zig
//! deriveSegment — EP3259724B1 unilateral node-derivation primitive (kdf-v2).
//!
//! The Zig mirror of `core/plexus-vendor-sdk/src/crypto.ts` `deriveSegment` /
//! `deriveSegmentPub`. Byte-identical across languages (cross-language KAT
//! below — vectors generated from the proven @bsv/sdk TS path).
//!
//! This is the canonical primitive for UNILATERAL key trees — those with no
//! counterparty: hat-internal signing keys, cell anchors, wallet change. BRC-42
//! (`ec.PrivateKey.deriveChild`) is the BILATERAL specialisation of the SAME
//! shape, with `segment = HMAC(ECDH-shared-secret, invoice)` instead of
//! `SHA-256(segment)`. Keep deriveChild for edges/payments; use this for nodes.
//!
//!   child_priv = (parent_priv + SHA-256(segment)) mod n
//!   child_pub  = parent_pub + SHA-256(segment)·G
//!
//! Composed ONLY from exposed bsvz primitives (Secp256k1.params/.scalarBaseMult,
//! PublicKey.add/.fromAffineBytes32) — the pinned bsvz dependency is unmodified.
//!
//! Reference: CW Lift L11; docs/prd/CW-LIFT-ROADMAP.md §2.2; docs/canon/brc-mapping.yml.

const std = @import("std");
const bsvz = @import("bsvz");
const ec = bsvz.primitives.ec;
const hash = bsvz.crypto.hash;

/// Algorithm-version marker for provenance/debuggability. The brain/wallet trees
/// cut over to v2 wholesale (no legacy artefacts to recover), so there is no
/// per-tree replay machinery here — unlike the Plexus SDK, which retains v1 for
/// stored test trees.
pub const KDF_VERSION = "plexus-kdf-v2";

/// (a + b) mod n over the secp256k1 group order. Mirrors bsvz ec.zig's private
/// `scalarAddModOrder` (which `deriveChild` uses) — reproduced here because it
/// is not exported. Not constant-time; matches the existing bsvz posture for
/// this derivation layer.
fn scalarAddModOrder(a: [32]u8, b: [32]u8) [32]u8 {
    const n = @as(u512, std.mem.readInt(u256, &ec.Secp256k1.params().n, .big));
    const aa = @as(u512, std.mem.readInt(u256, &a, .big));
    const bb = @as(u512, std.mem.readInt(u256, &b, .big));
    const sum: u256 = @intCast((aa + bb) % n);
    var out: [32]u8 = undefined;
    std.mem.writeInt(u256, &out, sum, .big);
    return out;
}

/// Derive a hierarchical node private key — UNILATERAL (no counterparty).
pub fn deriveSegment(parent: ec.PrivateKey, segment: []const u8) !ec.PrivateKey {
    const h = hash.sha256(segment).bytes;
    return ec.PrivateKey.fromBytes(scalarAddModOrder(parent.toBytes(), h));
}

/// Public-key side of `deriveSegment` — symmetric (verifier path).
pub fn deriveSegmentPub(parent: ec.PublicKey, segment: []const u8) !ec.PublicKey {
    const h = hash.sha256(segment).bytes;
    const hp = try ec.Secp256k1.scalarBaseMult(h);
    const h_pub = try ec.PublicKey.fromAffineBytes32(hp.x, hp.y);
    return parent.add(h_pub);
}

// ── L11.5: domain-separated derivation (kdf-v3) ──────────────────────────────
//
//   child_priv = (parent_priv + SHA-256(u32_be(domainFlag) ‖ segment)) mod n
//   child_pub  = parent_pub  + SHA-256(u32_be(domainFlag) ‖ segment)·G
//
// Folds the canonical u32 domain flag (core/constants/constants.json — the SAME
// value the cell header carries and OP_CHECKDOMAINFLAG asserts) into the tweak
// as a 4-byte big-endian domain-separation tag. This is prof-faustus/
// bsv-universal-sdk's pay-to-contract `H(tag ‖ m)` with tag = u32_be(domainFlag),
// m = segment. Byte-identical to the TS SDK `deriveDomainSegment`.
// Reference: docs/canon/domainflag-tag-unification.md.

pub const KDF_VERSION_DOMAIN = "plexus-kdf-v3";

/// SHA-256( u32_be(domainFlag) ‖ segment ). Streaming, allocation-free.
fn domainTweak(domain_flag: u32, segment: []const u8) [32]u8 {
    var tag: [4]u8 = undefined;
    std.mem.writeInt(u32, &tag, domain_flag, .big);
    var h = std.crypto.hash.sha2.Sha256.init(.{});
    h.update(&tag);
    h.update(segment);
    var out: [32]u8 = undefined;
    h.final(&out);
    return out;
}

/// Derive a domain-separated unilateral node private key (kdf-v3).
pub fn deriveDomainSegment(parent: ec.PrivateKey, domain_flag: u32, segment: []const u8) !ec.PrivateKey {
    return ec.PrivateKey.fromBytes(scalarAddModOrder(parent.toBytes(), domainTweak(domain_flag, segment)));
}

/// Public-key side of `deriveDomainSegment` — symmetric (verifier path).
pub fn deriveDomainSegmentPub(parent: ec.PublicKey, domain_flag: u32, segment: []const u8) !ec.PublicKey {
    const hp = try ec.Secp256k1.scalarBaseMult(domainTweak(domain_flag, segment));
    const h_pub = try ec.PublicKey.fromAffineBytes32(hp.x, hp.y);
    return parent.add(h_pub);
}

// ── Cross-language KAT ──────────────────────────────────────────────────────
// Vectors generated from the proven TS SDK (deriveSegment/deriveSegmentPub).
// If these pass, the Zig primitive is byte-identical to the SDK foundation.

fn hex32(comptime text: []const u8) [32]u8 {
    var out: [32]u8 = undefined;
    _ = std.fmt.hexToBytes(&out, text) catch unreachable;
    return out;
}

const KatVec = struct { seg: []const u8, priv: []const u8, pub_compressed: []const u8 };

const PARENT_HEX = "e9873d79c6d87dc0fb6a5778633389f4453213303da61f20bd67fc233aa33262";

const KATS = [_]KatVec{
    .{ .seg = "res:1:0", .priv = "e7305a9e1014cb111039fec24ac49f9cc11b6625d802e68db2e6c0105f392e9b", .pub_compressed = "03bc8adbbf9b8251bed5c7d84492672e4263feee451a7740cefad1247852231f54" },
    .{ .seg = "cartridge:oddjobz:6:0", .priv = "974cac64468d013c2183780de2ca84cff8d667515f6530e5dec7172a399864f4", .pub_compressed = "026caf257f8bfc45220038d27360dbabacda69a4bb3e2042aaf8c1d0d306fb626d" },
    .{ .seg = "hat/work/key/0", .priv = "43e03561d5ddb7e6c454079fa3376bf70d02af0b8b55b550b7fb13cf5d2275a9", .pub_compressed = "03e88a5352238e44424440051fdc730db3975bb64d61a76598b5abb3fc114e464d" },
};

test "deriveSegment priv side is byte-identical to the TS SDK" {
    const parent = try ec.PrivateKey.fromBytes(hex32(PARENT_HEX));
    for (KATS) |kat| {
        const child = try deriveSegment(parent, kat.seg);
        var expected: [32]u8 = undefined;
        _ = try std.fmt.hexToBytes(&expected, kat.priv);
        try std.testing.expectEqualSlices(u8, &expected, &child.toBytes());
    }
}

test "deriveSegmentPub matches deriveSegment(priv).publicKey() and the TS SDK" {
    const parent = try ec.PrivateKey.fromBytes(hex32(PARENT_HEX));
    const parent_pub = try parent.publicKey();
    for (KATS) |kat| {
        // priv↔pub symmetry
        const from_priv = (try deriveSegment(parent, kat.seg)).publicKey() catch unreachable;
        const from_pub = try deriveSegmentPub(parent_pub, kat.seg);
        try std.testing.expect(from_priv.eql(from_pub));
        // and byte-equal to the TS SDK's compressed pubkey
        var expected: [33]u8 = undefined;
        _ = try std.fmt.hexToBytes(&expected, kat.pub_compressed);
        try std.testing.expectEqualSlices(u8, &expected, &from_pub.toCompressedSec1());
    }
}

test "deriveSegment is deterministic and segment-sensitive" {
    const parent = try ec.PrivateKey.fromBytes(hex32(PARENT_HEX));
    const a1 = try deriveSegment(parent, "x");
    const a2 = try deriveSegment(parent, "x");
    const b = try deriveSegment(parent, "y");
    try std.testing.expectEqualSlices(u8, &a1.toBytes(), &a2.toBytes());
    try std.testing.expect(!std.mem.eql(u8, &a1.toBytes(), &b.toBytes()));
}

// ── L11.5 cross-language KAT (kdf-v3) ────────────────────────────────────────
// Same vectors as core/plexus-vendor-sdk/src/__tests__/derive-domain-segment.test.ts.
// flag is a canonical u32 from core/constants/constants.json.

const KatDomainVec = struct { flag: u32, seg: []const u8, priv: []const u8, pub_compressed: []const u8 };

const DOMAIN_KATS = [_]KatDomainVec{
    .{ .flag = 0x0001FE02, .seg = "cell-anchor:proto:0", .priv = "516161dcf39159f3a623ebf8f407bf41fba035659ab5abe3f43c0387fbeab001", .pub_compressed = "02845fdac3eb00a50701436ec29b59d76d44e34257918c5bef0c89777b27117bcc" },
    .{ .flag = 0x00000002, .seg = "hat/work/key/0", .priv = "b19514d3fb750ab7beb418ae18e414862248cfbd480922b1094ae20921a8e64b", .pub_compressed = "03ed612f2956a557a6dd15854f48e02e605af3647558848588f05bf0243f1127cb" },
    .{ .flag = 0x0001FE03, .seg = "scg:rel:42", .priv = "118d5b01a891d8f266eb5a9184ce6b38f1b2f77fc7b4f3f5ff9210d16b73802a", .pub_compressed = "027d197769b53b3b68588015395a2082d3e69ab6d8ad8952bf0c379b94ef06b95d" },
};

test "deriveDomainSegment priv side is byte-identical to the TS SDK (kdf-v3)" {
    const parent = try ec.PrivateKey.fromBytes(hex32(PARENT_HEX));
    for (DOMAIN_KATS) |kat| {
        const child = try deriveDomainSegment(parent, kat.flag, kat.seg);
        var expected: [32]u8 = undefined;
        _ = try std.fmt.hexToBytes(&expected, kat.priv);
        try std.testing.expectEqualSlices(u8, &expected, &child.toBytes());
    }
}

test "deriveDomainSegmentPub matches priv side and the TS SDK (kdf-v3)" {
    const parent = try ec.PrivateKey.fromBytes(hex32(PARENT_HEX));
    const parent_pub = try parent.publicKey();
    for (DOMAIN_KATS) |kat| {
        const from_priv = (try deriveDomainSegment(parent, kat.flag, kat.seg)).publicKey() catch unreachable;
        const from_pub = try deriveDomainSegmentPub(parent_pub, kat.flag, kat.seg);
        try std.testing.expect(from_priv.eql(from_pub));
        var expected: [33]u8 = undefined;
        _ = try std.fmt.hexToBytes(&expected, kat.pub_compressed);
        try std.testing.expectEqualSlices(u8, &expected, &from_pub.toCompressedSec1());
    }
}

test "deriveDomainSegment is domain-sensitive and differs from v2" {
    const parent = try ec.PrivateKey.fromBytes(hex32(PARENT_HEX));
    // same segment, different flag → different key
    const a = try deriveDomainSegment(parent, 1, "same");
    const b = try deriveDomainSegment(parent, 2, "same");
    try std.testing.expect(!std.mem.eql(u8, &a.toBytes(), &b.toBytes()));
    // v3 (flag-bound) differs from v2 (bare segment)
    const v2 = try deriveSegment(parent, "hat/work/key/0");
    const v3 = try deriveDomainSegment(parent, 0x00000002, "hat/work/key/0");
    try std.testing.expect(!std.mem.eql(u8, &v2.toBytes(), &v3.toBytes()));
}

// ── L11.5 native-anchor cross-language KAT (consumer 5) ──────────────────────
// Proves the NATIVE wallet anchor derivation (src/ffi/wallet_exports.zig +
// cartridges/bsv-anchor-bundle/.../wallet_op_http.zig, which inline this exact
// formula) is byte-identical to the TS cell-anchor.ts `deriveCellAnchorSk`.
//
// Vector generated from TS deriveCellAnchorSk (= cell-anchor.spec.ts KAT):
//   identitySk = 0x11×32
//   typeHash   = abcdef0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d
//   anchorIndex= 3
//   domainFlag = domainFlagFromTypeHash(typeHash)            = 0x00abcdef
//   protocolHash = SHA-256(hex(typeHash))[0:16]              = c050b5684f1750fdb5d0ce2ff3210fb1
//   invoice    = protocolHash(16) || anchorIndex_le8(8)
//             = c050b5684f1750fdb5d0ce2ff3210fb10300000000000000
const ANCHOR_KAT_FLAG: u32 = 0x00abcdef;
const ANCHOR_KAT_INVOICE_HEX = "c050b5684f1750fdb5d0ce2ff3210fb10300000000000000";
const ANCHOR_KAT_PRIV = "43a4d19e66e3f6660e4a810ea658e8129174da32fdadbcd2eae96be0899c1f48";
const ANCHOR_KAT_PUB = "026886c959e0d53f111c2841cd850a789906a420e30fa3364a0461b16783d434c5";

test "native anchor derivation is byte-identical to TS deriveCellAnchorSk (kdf-v3)" {
    const parent = try ec.PrivateKey.fromBytes(hex32("1111111111111111111111111111111111111111111111111111111111111111"));
    var invoice: [24]u8 = undefined;
    _ = try std.fmt.hexToBytes(&invoice, ANCHOR_KAT_INVOICE_HEX);
    const child = try deriveDomainSegment(parent, ANCHOR_KAT_FLAG, &invoice);
    var expected_priv: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&expected_priv, ANCHOR_KAT_PRIV);
    try std.testing.expectEqualSlices(u8, &expected_priv, &child.toBytes());
    var expected_pub: [33]u8 = undefined;
    _ = try std.fmt.hexToBytes(&expected_pub, ANCHOR_KAT_PUB);
    const child_pub = try child.publicKey();
    try std.testing.expectEqualSlices(u8, &expected_pub, &child_pub.toCompressedSec1());
}

```
