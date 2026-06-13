---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/session_addr.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.251716+00:00
---

# runtime/semantos-brain/src/session_addr.zig

```zig
// D-network-ipv6-session-keys — BRC-42 ECDH → /128 address derivation.
//
// Maps a (my_priv, peer_pub) keypair to a deterministic 128-bit IPv6
// address inside a given /56 (or any prefix length ≤ 64).  Both sides
// can compute the same address independently with no out-of-band
// signalling.
//
// Three tiers with increasing forward-secrecy guarantees:
//
//   T1 — static_contact
//     key material:  long-term operator keypair (stable across restarts)
//     IID derivation: HMAC-SHA256(ECDH(my_priv, peer_pub).compressed(), "brain-v6-t1")
//     lifetime:       assigned at brain startup, removed at shutdown
//     use case:       stable per-contact inbox address; no URL exchange needed
//
//   T2 — session_ephemeral
//     key material:  ephemeral keypair generated per session
//     IID derivation: HMAC-SHA256(ECDH(ephemeral_priv, peer_pub).compressed(),
//                                 "brain-v6-t2/" || session_nonce_hex)
//     lifetime:       session duration (minutes to hours)
//     use case:       forward secrecy — network log correlation across sessions
//                     is computationally infeasible
//
//   T3 — rendezvous
//     key material:  my own long-term pubkey (unilateral — no ECDH)
//     IID derivation: SHA256("brain-v6-t3/" || my_pubkey_compressed)[0..8]
//     lifetime:       stable across restarts (same as pubkey)
//     use case:       well-known discovery address for new-session handshakes;
//                     published in BRC-52 cert as brain_ipv6_rendezvous
//
// Wire flow:
//   1. brain serve --ipv6-prefix 2404:9400:17e5:1e00:: --ipv6-iface eth0
//   2. At startup: derive T1 /128 per contact → assign to interface via ipv6_iface
//   3. Brain listens on each assigned address; contact brain computes same IID
//      from ECDH(contact_priv, my_pub) → reaches us with no URL discovery
//   4. On shutdown: remove all assigned /128s

const std = @import("std");
const bsvz = @import("bsvz");

// ── Address types ─────────────────────────────────────────────────────────

/// A 128-bit IPv6 address as raw bytes (network byte order).
pub const V6Addr = [16]u8;

/// An 8-byte interface identifier (IID) — the low half of a /128.
pub const Iid = [8]u8;

// ── Tier labels ───────────────────────────────────────────────────────────

const T1_INFO = "brain-v6-t1";
const T2_INFO_PREFIX = "brain-v6-t2/";
const T3_INFO = "brain-v6-t3/";

// ── Core derivation ───────────────────────────────────────────────────────

/// Tier 1 — derive a stable IID from the long-term ECDH shared secret.
///
/// Both brains can compute the same IID:
///   Brain A: deriveIidT1(A.priv, B.pub)
///   Brain B: deriveIidT1(B.priv, A.pub)
///   → identical (ECDH is symmetric)
pub fn deriveIidT1(my_priv_bytes: [32]u8, peer_pub_hex: []const u8) !Iid {
    return deriveIidEcdh(my_priv_bytes, peer_pub_hex, T1_INFO);
}

/// Tier 2 — derive a per-session ephemeral IID.
///
/// `session_nonce_hex` is a 32-char hex string unique to this session
/// (e.g. hex of 16 random bytes).  The peer must learn the ephemeral
/// pubkey via the T3 rendezvous handshake before it can compute the address.
pub fn deriveIidT2(
    ephemeral_priv_bytes: [32]u8,
    peer_pub_hex: []const u8,
    session_nonce_hex: []const u8,
) !Iid {
    // Build info string: "brain-v6-t2/<nonce_hex>"
    var info_buf: [T2_INFO_PREFIX.len + 64]u8 = undefined;
    const info = std.fmt.bufPrint(&info_buf, "{s}{s}", .{ T2_INFO_PREFIX, session_nonce_hex }) catch
        return error.NonceTooLong;
    return deriveIidEcdh(ephemeral_priv_bytes, peer_pub_hex, info);
}

/// Tier 3 — derive a stable rendezvous IID from our own pubkey only.
///
/// Unilateral: no peer pubkey needed.  Published in BRC-52 cert as
/// `brain_ipv6_rendezvous` so any contact can reach us for a T2 handshake.
pub fn deriveIidT3(my_pub_compressed: [33]u8) Iid {
    var h = std.crypto.hash.sha2.Sha256.init(.{});
    h.update(T3_INFO);
    h.update(&my_pub_compressed);
    var digest: [32]u8 = undefined;
    h.final(&digest);
    return digest[0..8].*;
}

// ── Address assembly ──────────────────────────────────────────────────────

/// Combine an 8-byte /56 prefix with an 8-byte IID to form a /128.
pub fn buildAddr(prefix: [8]u8, iid: Iid) V6Addr {
    var addr: V6Addr = undefined;
    @memcpy(addr[0..8], &prefix);
    @memcpy(addr[8..16], &iid);
    return addr;
}

/// Parse the network prefix from a text-form IPv6 address.
/// Accepts "2404:9400:17e5:1e00::" or "2404:9400:17e5:1e00::0" etc.
/// Returns the first 8 bytes (suitable for /56 or /64 prefixes).
pub fn parsePrefix(text: []const u8) ![8]u8 {
    // Append enough groups to make it a parseable full IPv6 address.
    var buf: [64]u8 = undefined;
    // Strip trailing ':' if any, then ensure it ends with '::'
    var s = std.mem.trimRight(u8, text, ":");
    if (!std.mem.endsWith(u8, s, "::")) {
        const n = std.fmt.bufPrint(&buf, "{s}::", .{s}) catch return error.PrefixTooLong;
        s = n;
    }
    const addr = std.net.Address.parseIp6(s, 0) catch return error.InvalidPrefix;
    return addr.in6.sa.addr[0..8].*;
}

/// Format a V6Addr as a colon-delimited hex string (no brackets).
/// `buf` must be at least 39 bytes.
pub fn fmtAddr(addr: V6Addr, buf: []u8) []u8 {
    return std.fmt.bufPrint(buf,
        "{x:0>4}:{x:0>4}:{x:0>4}:{x:0>4}:{x:0>4}:{x:0>4}:{x:0>4}:{x:0>4}",
        .{
            @as(u16, addr[0])  << 8 | addr[1],
            @as(u16, addr[2])  << 8 | addr[3],
            @as(u16, addr[4])  << 8 | addr[5],
            @as(u16, addr[6])  << 8 | addr[7],
            @as(u16, addr[8])  << 8 | addr[9],
            @as(u16, addr[10]) << 8 | addr[11],
            @as(u16, addr[12]) << 8 | addr[13],
            @as(u16, addr[14]) << 8 | addr[15],
        },
    ) catch unreachable; // 39 bytes is always enough
}

// ── Internal helpers ──────────────────────────────────────────────────────

fn deriveIidEcdh(
    my_priv_bytes: [32]u8,
    peer_pub_hex: []const u8,
    info: []const u8,
) !Iid {
    const my_priv = try bsvz.primitives.ec.PrivateKey.fromBytes(my_priv_bytes);
    const peer_pub = try bsvz.primitives.ec.PublicKey.fromHex(peer_pub_hex);
    const shared_point = try my_priv.deriveSharedSecret(peer_pub);
    const shared_bytes = shared_point.toCompressedSec1(); // 33 bytes

    var mac: std.crypto.auth.hmac.sha2.HmacSha256 = undefined;
    mac = std.crypto.auth.hmac.sha2.HmacSha256.init(&shared_bytes);
    mac.update(info);
    var digest: [32]u8 = undefined;
    mac.final(&digest);

    return digest[0..8].*;
}

/// Convenience: derive T3 rendezvous IID directly from a raw private key.
pub fn deriveIidT3FromPriv(priv_bytes: [32]u8) !Iid {
    const priv = try bsvz.primitives.ec.PrivateKey.fromBytes(priv_bytes);
    const pub_comp = (try priv.publicKey()).toCompressedSec1();
    return deriveIidT3(pub_comp);
}

// ── Tests ─────────────────────────────────────────────────────────────────

test "session_addr: T1 IID is symmetric (both sides get same address)" {
    // Use test vectors: two known keypairs.
    // A's priv = 0x01 * 32, B's priv = 0x02 * 32.
    const a_priv_bytes = [_]u8{0x01} ** 32;
    const b_priv_bytes = [_]u8{0x02} ** 32;

    const bsvz_ec = bsvz.primitives.ec;
    const a_priv = try bsvz_ec.PrivateKey.fromBytes(a_priv_bytes);
    const b_priv = try bsvz_ec.PrivateKey.fromBytes(b_priv_bytes);

    const a_pub = try a_priv.publicKey();
    const b_pub = try b_priv.publicKey();

    // Format pubkeys as 66-char hex.
    const a_comp = a_pub.toCompressedSec1();
    const b_comp = b_pub.toCompressedSec1();
    const a_pub_hex = std.fmt.bytesToHex(a_comp, .lower);
    const b_pub_hex = std.fmt.bytesToHex(b_comp, .lower);

    // A derives IID using B's pubkey; B derives IID using A's pubkey.
    const iid_from_a = try deriveIidT1(a_priv_bytes, &b_pub_hex);
    const iid_from_b = try deriveIidT1(b_priv_bytes, &a_pub_hex);

    // ECDH symmetry: both must be identical.
    try std.testing.expectEqualSlices(u8, &iid_from_a, &iid_from_b);
}

test "session_addr: T3 rendezvous IID is deterministic" {
    const bsvz_ec = bsvz.primitives.ec;
    const priv = try bsvz_ec.PrivateKey.fromBytes([_]u8{0x03} ** 32);
    const pub_key = try priv.publicKey();
    const pub_comp = pub_key.toCompressedSec1();

    const iid1 = deriveIidT3(pub_comp);
    const iid2 = deriveIidT3(pub_comp);
    try std.testing.expectEqualSlices(u8, &iid1, &iid2);
}

test "session_addr: parsePrefix round-trips" {
    const prefix = try parsePrefix("2404:9400:17e5:1e00::");
    try std.testing.expectEqual(@as(u8, 0x24), prefix[0]);
    try std.testing.expectEqual(@as(u8, 0x04), prefix[1]);
    try std.testing.expectEqual(@as(u8, 0x94), prefix[2]);
    try std.testing.expectEqual(@as(u8, 0x00), prefix[3]);
    try std.testing.expectEqual(@as(u8, 0x17), prefix[4]);
    try std.testing.expectEqual(@as(u8, 0xe5), prefix[5]);
    try std.testing.expectEqual(@as(u8, 0x1e), prefix[6]);
    try std.testing.expectEqual(@as(u8, 0x00), prefix[7]);
}

test "session_addr: fmtAddr formats correctly" {
    const addr = V6Addr{
        0x24, 0x04, 0x94, 0x00, 0x17, 0xe5, 0x1e, 0x00,
        0xde, 0xad, 0xbe, 0xef, 0xca, 0xfe, 0x00, 0x01,
    };
    var buf: [39]u8 = undefined;
    const s = fmtAddr(addr, &buf);
    try std.testing.expectEqualStrings("2404:9400:17e5:1e00:dead:beef:cafe:0001", s);
}

test "session_addr: T1 IID changes with different peers" {
    const a_priv_bytes = [_]u8{0x01} ** 32;
    const bsvz_ec = bsvz.primitives.ec;
    const b_priv = try bsvz_ec.PrivateKey.fromBytes([_]u8{0x02} ** 32);
    const c_priv = try bsvz_ec.PrivateKey.fromBytes([_]u8{0x03} ** 32);
    const b_pub = try b_priv.publicKey();
    const c_pub = try c_priv.publicKey();
    const b_comp = b_pub.toCompressedSec1();
    const c_comp = c_pub.toCompressedSec1();
    const b_hex = std.fmt.bytesToHex(b_comp, .lower);
    const c_hex = std.fmt.bytesToHex(c_comp, .lower);

    const iid_b = try deriveIidT1(a_priv_bytes, &b_hex);
    const iid_c = try deriveIidT1(a_priv_bytes, &c_hex);
    // Different peers → different IIDs.
    try std.testing.expect(!std.mem.eql(u8, &iid_b, &iid_c));
}

```
