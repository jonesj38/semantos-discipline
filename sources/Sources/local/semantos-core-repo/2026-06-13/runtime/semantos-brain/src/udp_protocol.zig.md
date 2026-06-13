---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/udp_protocol.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.263456+00:00
---

# runtime/semantos-brain/src/udp_protocol.zig

```zig
// udp_protocol.zig — Datagram wire-format constants and types for Phase U.2
//
// Reference: docs/prd/UDP-DATAGRAM-DISPATCH-BRIEF.md §Step 2
//            docs/prd/UDP-MESH-DIRECTION.md §2.1, §5.1
//
// WHY THIS FILE EXISTS
// --------------------
// The semantos-brain UDP reactor (udp_dispatcher.zig) and its conformance tests share
// a single source of truth for:
//
//   1. Datagram framing layout (byte offsets, field sizes)
//   2. Datagram type codes
//   3. Max payload constants
//   4. The `PeerSharedSecretLookup` interface (stub in U.2; ECDH derivation
//      in U.3 via the contacts cell-DAG — CONTACTS-BOOK-PKI-BRIEF.md)
//
// WIRE FORMAT (big-endian, fixed-width fields):
//
//   Offset  Length  Field
//   ------  ------  -----
//   0       1       datagram type (DatagramType enum)
//   1       16      nonce (random bytes; unique per datagram)
//   17      32      sender peer cellId (SHA-256 content hash)
//   49      N       payload (≤ MAX_PAYLOAD bytes, type-specific encoding)
//   49+N    32      HMAC-SHA-256 over bytes 0..(49+N-1), keyed by ECDH-
//                   derived shared secret from the contacts cell-DAG
//
// Total header overhead: 1 + 16 + 32 = 49 bytes prefix + 32 bytes HMAC suffix
// = 81 bytes total framing.
// Max payload for v1 (one Ethernet-MTU datagram, no fragmentation):
//   1472 - 81 = 1391 bytes.
//
// FRAGMENTATION
// -------------
// v1 supports payloads ≤ MAX_PAYLOAD (1391 bytes) per datagram. Fragmentation
// is deferred to a later phase. PDF/voice attachments continue to flow via
// brain HTTPS.
//
// NAT TRAVERSAL
// -------------
// v1 supports same-network UDP only (no NAT traversal). Cross-network falls
// back to brain-relayed flow. Hole-punching deferred — its own phase if scale
// demands.
//
// ANTI-REPLAY
// -----------
// The 16-byte nonce is random and per-datagram. The AntiReplayCache (in
// udp_dispatcher.zig) tracks recently-seen nonces per peer to detect and
// drop replays. The window is 5 seconds (configurable).
//
// U.3 NOTE
// --------
// PeerSharedSecretLookup is intentionally a function pointer interface so
// U.3 (CONTACTS-BOOK-PKI-BRIEF.md) can replace the v1 stub with the real
// ECDH derivation from the contacts cell-DAG without changing the dispatcher.
//
// HOW TO REVERT
// -------------
// This file is new — delete it. Also delete udp_dispatcher.zig and its
// conformance test. Revert the event_loop.zig + site_server.zig changes via
// their RIP-OUT-MARKER comments.
//
// RIP-OUT-MARKER (Phase U.2, commit SHA to be set after first push):
//   Delete udp_protocol.zig + udp_dispatcher.zig + tests/udp_dispatcher_conformance.zig
//   and revert the UDP fields in event_loop.zig + site_server.zig.

const std = @import("std");

// ── Datagram framing constants ────────────────────────────────────────────

/// Maximum raw UDP datagram bytes usable after IP + UDP header overhead.
/// Ethernet MTU 1500 − 20 (IPv4) − 8 (UDP) = 1472.
pub const UDP_MAX_DATAGRAM: usize = 1472;

/// Number of bytes in the datagram type field.
pub const TYPE_LEN: usize = 1;

/// Number of bytes in the nonce field.
pub const NONCE_LEN: usize = 16;

/// Number of bytes in the sender peer cellId field.
pub const CELL_ID_LEN: usize = 32;

/// Number of bytes in the HMAC-SHA-256 tail.
pub const HMAC_LEN: usize = 32;

/// Total framing overhead: type + nonce + cellId + HMAC.
pub const HEADER_OVERHEAD: usize = TYPE_LEN + NONCE_LEN + CELL_ID_LEN + HMAC_LEN;

/// Maximum payload size for v1 (no fragmentation).
/// = UDP_MAX_DATAGRAM − HEADER_OVERHEAD = 1391 bytes.
pub const MAX_PAYLOAD: usize = UDP_MAX_DATAGRAM - HEADER_OVERHEAD;

// ── Byte offsets within a datagram ───────────────────────────────────────

pub const OFFSET_TYPE: usize = 0;
pub const OFFSET_NONCE: usize = TYPE_LEN; // 1
pub const OFFSET_CELL_ID: usize = OFFSET_NONCE + NONCE_LEN; // 17
pub const OFFSET_PAYLOAD: usize = OFFSET_CELL_ID + CELL_ID_LEN; // 49

/// Minimum datagram size: header prefix (no payload) + HMAC.
/// A datagram shorter than this is malformed and MUST be dropped silently.
pub const MIN_DATAGRAM_LEN: usize = OFFSET_PAYLOAD + HMAC_LEN; // 81

// ── Datagram type codes ───────────────────────────────────────────────────

/// Datagram type identifiers (1 byte, at offset 0).
///
/// Values are stable and must not be renumbered — they appear on the wire.
///
/// CELL_SYNC      0x01 — sender is pushing a cell-DAG entry to the peer.
///                       Receiver appends if novel; emits ACK datagram.
/// TOPIC_BROADCAST 0x02 — sender is publishing a topic event. Receiver
///                       delivers to local pub/sub broker.
/// HEARTBEAT      0x03 — sender announces its current IP:port for mesh
///                       discovery. Receiver updates lastSeenAddr in the
///                       contacts cell-DAG entry.
/// REPLY          0x04 — response to a previous CELL_SYNC or request,
///                       correlated by nonce echo.
pub const DatagramType = enum(u8) {
    cell_sync = 0x01,
    topic_broadcast = 0x02,
    heartbeat = 0x03,
    reply = 0x04,

    /// Return the type value, or null if the byte is not a recognised type.
    pub fn fromByte(b: u8) ?DatagramType {
        return switch (b) {
            0x01 => .cell_sync,
            0x02 => .topic_broadcast,
            0x03 => .heartbeat,
            0x04 => .reply,
            else => null,
        };
    }
};

// ── Parsed datagram header ────────────────────────────────────────────────

/// Structured view of a received datagram after parsing.
/// All slices point into the original datagram buffer — caller owns it.
pub const ParsedDatagram = struct {
    datagram_type: DatagramType,
    /// 16-byte random nonce.
    nonce: []const u8,
    /// 32-byte sender peer cellId (SHA-256 content hash).
    sender_cell_id: []const u8,
    /// Variable-length payload (≤ MAX_PAYLOAD).
    payload: []const u8,
    /// 32-byte HMAC-SHA-256 tail.
    hmac: []const u8,
    /// Bytes covered by the HMAC (everything before the HMAC tail).
    authenticated_bytes: []const u8,
};

/// Parse a raw datagram buffer into its constituent fields.
///
/// Returns error.TooShort if `buf` is shorter than MIN_DATAGRAM_LEN.
/// Returns error.UnknownType if the type byte is not a recognized DatagramType.
/// Does NOT verify the HMAC — that is the dispatcher's responsibility.
pub fn parse(buf: []const u8) error{ TooShort, UnknownType }!ParsedDatagram {
    if (buf.len < MIN_DATAGRAM_LEN) return error.TooShort;

    const datagram_type = DatagramType.fromByte(buf[OFFSET_TYPE]) orelse
        return error.UnknownType;

    // Payload length = everything between OFFSET_PAYLOAD and the HMAC tail.
    const payload_end = buf.len - HMAC_LEN;
    const payload = buf[OFFSET_PAYLOAD..payload_end];

    return .{
        .datagram_type = datagram_type,
        .nonce = buf[OFFSET_NONCE .. OFFSET_NONCE + NONCE_LEN],
        .sender_cell_id = buf[OFFSET_CELL_ID .. OFFSET_CELL_ID + CELL_ID_LEN],
        .payload = payload,
        .hmac = buf[payload_end .. payload_end + HMAC_LEN],
        .authenticated_bytes = buf[0..payload_end],
    };
}

// ── PeerSharedSecretLookup interface ──────────────────────────────────────

/// Callback interface for looking up the ECDH-derived shared secret for a
/// given peer (identified by their cellId).
///
/// v1 (Phase U.2) — a stub that returns a hardcoded test secret so
/// conformance tests work without the contacts cell-DAG.
///
/// v2 (Phase U.3 — CONTACTS-BOOK-PKI-BRIEF.md) — the real implementation
/// reads the contacts cell-DAG, derives the shared secret via ECDH
/// (operator_priv × peer_pub, same as bkds.zig's BRC-42 pattern), and
/// returns the 32-byte symmetric key.
///
/// Signature:
///   fn(peer_cell_id: [CELL_ID_LEN]u8, ud: *anyopaque) ?[32]u8
///
///   Returns null if the peer is unknown (not in contacts).
///   Returns the 32-byte shared key if found.
pub const SharedSecretLookupFn = *const fn (
    peer_cell_id: *const [CELL_ID_LEN]u8,
    ud: *anyopaque,
) ?[32]u8;

/// Convenience struct bundling the lookup function + its userdata pointer.
pub const PeerSharedSecretLookup = struct {
    lookup_fn: SharedSecretLookupFn,
    ud: *anyopaque,

    /// Look up the shared secret for `peer_cell_id`.
    pub fn lookup(self: PeerSharedSecretLookup, peer_cell_id: *const [CELL_ID_LEN]u8) ?[32]u8 {
        return self.lookup_fn(peer_cell_id, self.ud);
    }
};

// ── HMAC-SHA-256 helpers ──────────────────────────────────────────────────

/// Compute HMAC-SHA-256 over `data` using `key`.
/// Used by the dispatcher to verify incoming datagrams and by tests to build
/// valid test vectors.
pub fn hmacSha256(key: []const u8, data: []const u8) [32]u8 {
    var hmac: std.crypto.auth.hmac.sha2.HmacSha256 = undefined;
    hmac = std.crypto.auth.hmac.sha2.HmacSha256.init(key);
    hmac.update(data);
    var out: [32]u8 = undefined;
    hmac.final(&out);
    return out;
}

/// Build a complete outbound datagram in `buf`.
///
/// `buf` must be at least OFFSET_PAYLOAD + payload.len + HMAC_LEN bytes.
/// Returns the slice of `buf` that was written (the complete datagram).
pub fn buildDatagram(
    buf: []u8,
    dtype: DatagramType,
    nonce: *const [NONCE_LEN]u8,
    sender_cell_id: *const [CELL_ID_LEN]u8,
    payload: []const u8,
    shared_key: []const u8,
) []u8 {
    std.debug.assert(payload.len <= MAX_PAYLOAD);
    const total = OFFSET_PAYLOAD + payload.len + HMAC_LEN;
    std.debug.assert(buf.len >= total);

    buf[OFFSET_TYPE] = @intFromEnum(dtype);
    @memcpy(buf[OFFSET_NONCE .. OFFSET_NONCE + NONCE_LEN], nonce);
    @memcpy(buf[OFFSET_CELL_ID .. OFFSET_CELL_ID + CELL_ID_LEN], sender_cell_id);
    @memcpy(buf[OFFSET_PAYLOAD .. OFFSET_PAYLOAD + payload.len], payload);

    const authenticated = buf[0 .. OFFSET_PAYLOAD + payload.len];
    const hmac = hmacSha256(shared_key, authenticated);
    @memcpy(buf[OFFSET_PAYLOAD + payload.len .. total], &hmac);

    return buf[0..total];
}

// ── Embedded unit tests ───────────────────────────────────────────────────

const testing = std.testing;

test "udp_protocol: parse round-trips a HEARTBEAT datagram" {
    const key: [32]u8 = .{0xAB} ** 32;
    const nonce: [NONCE_LEN]u8 = .{0x01} ** NONCE_LEN;
    const cell_id: [CELL_ID_LEN]u8 = .{0x02} ** CELL_ID_LEN;
    const payload = "hello-heartbeat";

    var buf: [UDP_MAX_DATAGRAM]u8 = undefined;
    const dgram = buildDatagram(&buf, .heartbeat, &nonce, &cell_id, payload, &key);

    const parsed = try parse(dgram);
    try testing.expectEqual(DatagramType.heartbeat, parsed.datagram_type);
    try testing.expectEqualSlices(u8, &nonce, parsed.nonce);
    try testing.expectEqualSlices(u8, &cell_id, parsed.sender_cell_id);
    try testing.expectEqualSlices(u8, payload, parsed.payload);

    // Verify HMAC matches
    const expected_hmac = hmacSha256(&key, parsed.authenticated_bytes);
    try testing.expectEqualSlices(u8, &expected_hmac, parsed.hmac);
}

test "udp_protocol: parse rejects TooShort datagram" {
    var short: [MIN_DATAGRAM_LEN - 1]u8 = undefined;
    @memset(&short, 0);
    try testing.expectError(error.TooShort, parse(&short));
}

test "udp_protocol: parse rejects UnknownType datagram" {
    var buf: [MIN_DATAGRAM_LEN]u8 = undefined;
    @memset(&buf, 0);
    buf[OFFSET_TYPE] = 0xFF; // unknown type
    try testing.expectError(error.UnknownType, parse(&buf));
}

test "udp_protocol: DatagramType.fromByte covers all types" {
    try testing.expectEqual(DatagramType.cell_sync, DatagramType.fromByte(0x01).?);
    try testing.expectEqual(DatagramType.topic_broadcast, DatagramType.fromByte(0x02).?);
    try testing.expectEqual(DatagramType.heartbeat, DatagramType.fromByte(0x03).?);
    try testing.expectEqual(DatagramType.reply, DatagramType.fromByte(0x04).?);
    try testing.expect(DatagramType.fromByte(0x00) == null);
    try testing.expect(DatagramType.fromByte(0x05) == null);
}

test "udp_protocol: MAX_PAYLOAD is 1391" {
    try testing.expectEqual(@as(usize, 1391), MAX_PAYLOAD);
}

test "udp_protocol: MIN_DATAGRAM_LEN is 81" {
    try testing.expectEqual(@as(usize, 81), MIN_DATAGRAM_LEN);
}

```
