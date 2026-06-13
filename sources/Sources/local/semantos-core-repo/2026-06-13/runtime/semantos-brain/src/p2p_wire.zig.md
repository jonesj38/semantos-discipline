---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/p2p_wire.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.223468+00:00
---

# runtime/semantos-brain/src/p2p_wire.zig

```zig
// Phase BRAIN-Headers (Brain 4-headers) — BSV P2P wire protocol — minimum subset
// for header sync.
//
// Reference: BSV protocol mirrors the Bitcoin P2P wire protocol with the
// magic number changed.  Spec: https://en.bitcoin.it/wiki/Protocol_documentation
//
// Scope for v0.1: just enough to drive `brain headers sync` against a
// peer that speaks BSV mainnet wire:
//
//   • Message envelope: magic + 12-byte command + payload_size (u32 LE)
//     + checksum (first 4 bytes of sha256d(payload)) + payload bytes.
//   • Encode/decode: `version`, `verack`, `getheaders`, `headers`,
//     `ping`, `pong`.
//   • The locator-and-headers pair is what sync needs; ping/pong is the
//     keepalive a long-running peer expects.  `inv` is intentionally
//     out-of-scope — tip subscription is WH-Producer Phase 2.
//
// The module is reader/writer-agnostic — `readMessage` / `writeMessage`
// take `std.io.Reader` / `std.io.Writer`.  Tests pass fixed-buffer
// streams; production passes a TCP socket adapter.

const std = @import("std");
const headers_mod = @import("headers");

/// BSV mainnet network magic (4 bytes).
pub const MAGIC_MAINNET: [4]u8 = .{ 0xe3, 0xe1, 0xf3, 0xe8 };
/// BSV testnet network magic.  Reserved — we only sync mainnet at v0.1.
pub const MAGIC_TESTNET: [4]u8 = .{ 0xf4, 0xe5, 0xf3, 0xf4 };
/// Regtest network magic — used by the loopback peer test fixture.
pub const MAGIC_REGTEST: [4]u8 = .{ 0xda, 0xb5, 0xbf, 0xfa };

/// Protocol version we speak.  70015 is the bottom of the modern
/// `getheaders` (variant 2) era; mainnet peers up to BSV's current node
/// software accept this.
pub const PROTOCOL_VERSION: i32 = 70015;

/// Service flags advertised in `version`.
pub const SERVICES_NONE: u64 = 0;
/// NODE_NETWORK — peer can serve full blocks.  Required by most BSV
/// nodes for any incoming connection; advertising 0 gets us
/// disconnected immediately.  We don't actually serve blocks at v0.1
/// but the convention is "willing to peer / can respond to getdata".
pub const SERVICES_NODE_NETWORK: u64 = 1;
/// NODE_BITCOIN_CASH — BSV-fork tag (bit 5).  Some BSV peers filter
/// peers without it set; safe to advertise alongside NODE_NETWORK.
pub const SERVICES_NODE_BITCOIN_CASH: u64 = 1 << 5;
/// Default services flags for outbound BSV mainnet sync.  Peers that
/// gate on NODE_NETWORK alone should accept us; the BSV bit is a
/// convention courtesy.
pub const SERVICES_DEFAULT: u64 = SERVICES_NODE_NETWORK | SERVICES_NODE_BITCOIN_CASH;

pub const WireError = error{
    bad_magic,
    bad_command,
    bad_payload_size,
    bad_checksum,
    short_read,
    short_write,
    encode_overflow,
    decode_overflow,
    out_of_memory,
};

/// Maximum payload size we'll accept on the wire — tightens the
/// per-message attack surface.  Real spec is 32 MiB; we cap at 4 MiB
/// since `getheaders → headers` returns at most 2000 × 81 = 162 KB.
pub const MAX_PAYLOAD: u32 = 4 * 1024 * 1024;

/// Standard envelope is 24 bytes; payload follows.
pub const HEADER_BYTES: usize = 4 + 12 + 4 + 4;

// ─────────────────────────────────────────────────────────────────────
// Envelope encode / decode
// ─────────────────────────────────────────────────────────────────────

/// Build the 24-byte message header for `(magic, command, payload)`.
/// `command` is at most 12 ASCII bytes; longer is `bad_command`.
/// `payload` length is u32 LE; checksum is sha256d(payload)[..4].
pub fn encodeHeader(magic: [4]u8, command: []const u8, payload: []const u8, out: *[HEADER_BYTES]u8) WireError!void {
    if (command.len > 12) return error.bad_command;
    if (payload.len > MAX_PAYLOAD) return error.encode_overflow;
    @memcpy(out[0..4], &magic);
    @memset(out[4..16], 0);
    @memcpy(out[4 .. 4 + command.len], command);
    std.mem.writeInt(u32, out[16..20], @intCast(payload.len), .little);
    const cs = headers_mod.sha256d(payload);
    @memcpy(out[20..24], cs[0..4]);
}

pub const ParsedHeader = struct {
    magic: [4]u8,
    command: [12]u8,
    payload_size: u32,
    checksum: [4]u8,

    pub fn commandTrimmed(self: *const ParsedHeader) []const u8 {
        // ASCII-null-terminated.  Find the first 0 to slice off the
        // padding before string-comparing.
        var end: usize = 12;
        for (self.command, 0..) |c, i| {
            if (c == 0) {
                end = i;
                break;
            }
        }
        return self.command[0..end];
    }
};

pub fn parseHeader(bytes: *const [HEADER_BYTES]u8) ParsedHeader {
    var ph: ParsedHeader = undefined;
    @memcpy(&ph.magic, bytes[0..4]);
    @memcpy(&ph.command, bytes[4..16]);
    ph.payload_size = std.mem.readInt(u32, bytes[16..20], .little);
    @memcpy(&ph.checksum, bytes[20..24]);
    return ph;
}

/// Verify `parsed.checksum` against `payload` via sha256d.
pub fn verifyChecksum(parsed: *const ParsedHeader, payload: []const u8) bool {
    const cs = headers_mod.sha256d(payload);
    return std.mem.eql(u8, &parsed.checksum, cs[0..4]);
}

// ─────────────────────────────────────────────────────────────────────
// VarInt — Bitcoin-style variable-length integer
// ─────────────────────────────────────────────────────────────────────

/// Encode a VarInt at `out` starting at `*pos`. Bumps `*pos` by the
/// bytes written.  Bitcoin VarInts: <0xfd inline; 0xfd+u16 LE;
/// 0xfe+u32 LE; 0xff+u64 LE.
pub fn writeVarInt(out: []u8, pos: *usize, n: u64) WireError!void {
    if (n < 0xfd) {
        if (out.len < pos.* + 1) return error.encode_overflow;
        out[pos.*] = @intCast(n);
        pos.* += 1;
    } else if (n <= 0xffff) {
        if (out.len < pos.* + 3) return error.encode_overflow;
        out[pos.*] = 0xfd;
        std.mem.writeInt(u16, out[pos.* + 1 ..][0..2], @intCast(n), .little);
        pos.* += 3;
    } else if (n <= 0xffffffff) {
        if (out.len < pos.* + 5) return error.encode_overflow;
        out[pos.*] = 0xfe;
        std.mem.writeInt(u32, out[pos.* + 1 ..][0..4], @intCast(n), .little);
        pos.* += 5;
    } else {
        if (out.len < pos.* + 9) return error.encode_overflow;
        out[pos.*] = 0xff;
        std.mem.writeInt(u64, out[pos.* + 1 ..][0..8], n, .little);
        pos.* += 9;
    }
}

pub fn readVarInt(bytes: []const u8, pos: *usize) WireError!u64 {
    if (bytes.len < pos.* + 1) return error.decode_overflow;
    const first = bytes[pos.*];
    pos.* += 1;
    if (first < 0xfd) return first;
    if (first == 0xfd) {
        if (bytes.len < pos.* + 2) return error.decode_overflow;
        const v = std.mem.readInt(u16, bytes[pos.*..][0..2], .little);
        pos.* += 2;
        return v;
    }
    if (first == 0xfe) {
        if (bytes.len < pos.* + 4) return error.decode_overflow;
        const v = std.mem.readInt(u32, bytes[pos.*..][0..4], .little);
        pos.* += 4;
        return v;
    }
    if (bytes.len < pos.* + 8) return error.decode_overflow;
    const v = std.mem.readInt(u64, bytes[pos.*..][0..8], .little);
    pos.* += 8;
    return v;
}

// ─────────────────────────────────────────────────────────────────────
// `version` payload — minimal shape.  We're a leaf consumer (not a
// service), so we set `services = 0` and don't advertise an addr.
// ─────────────────────────────────────────────────────────────────────

pub const VERSION_MIN_BYTES: usize = 4 + 8 + 8 + 26 + 26 + 8 + 1 + 4 + 1; // ≥86 (no user_agent body)

/// Encode a `version` payload to `out`.  Returns the number of bytes
/// written.  `nonce` should be random per-connection; tests pass a
/// deterministic value.  `user_agent` is e.g. "/brain:0.1.0/".
pub fn encodeVersion(
    out: []u8,
    nonce: u64,
    user_agent: []const u8,
    start_height: i32,
    timestamp: i64,
) WireError!usize {
    return encodeVersionWithServices(out, SERVICES_DEFAULT, nonce, user_agent, start_height, timestamp);
}

/// Variant of encodeVersion that lets the caller pick service flags.
/// Production sync uses `SERVICES_DEFAULT`; the loopback tests pass
/// `SERVICES_NONE` since the peer doesn't gate on it.
pub fn encodeVersionWithServices(
    out: []u8,
    services: u64,
    nonce: u64,
    user_agent: []const u8,
    start_height: i32,
    timestamp: i64,
) WireError!usize {
    if (user_agent.len > 0xfc) return error.encode_overflow;
    const need = VERSION_MIN_BYTES + user_agent.len;
    if (out.len < need) return error.encode_overflow;
    var pos: usize = 0;

    // protocol_version (i32 LE)
    std.mem.writeInt(i32, out[pos..][0..4], PROTOCOL_VERSION, .little);
    pos += 4;
    // services (u64 LE)
    std.mem.writeInt(u64, out[pos..][0..8], services, .little);
    pos += 8;
    // timestamp (i64 LE)
    std.mem.writeInt(i64, out[pos..][0..8], timestamp, .little);
    pos += 8;
    // addr_recv (26 bytes — 8 services + 16 IP + 2 port).  Zeros are
    // legal here for an outbound version.
    @memset(out[pos .. pos + 26], 0);
    pos += 26;
    // addr_from (26 bytes — same shape, zeros).
    @memset(out[pos .. pos + 26], 0);
    pos += 26;
    // nonce
    std.mem.writeInt(u64, out[pos..][0..8], nonce, .little);
    pos += 8;
    // user_agent (var-string)
    out[pos] = @intCast(user_agent.len);
    pos += 1;
    @memcpy(out[pos .. pos + user_agent.len], user_agent);
    pos += user_agent.len;
    // start_height
    std.mem.writeInt(i32, out[pos..][0..4], start_height, .little);
    pos += 4;
    // relay flag
    out[pos] = 0;
    pos += 1;
    return pos;
}

// ─────────────────────────────────────────────────────────────────────
// `getheaders` payload — version + locator + stop_hash.
//
//   protocol_version: u32 LE
//   hash_count:       VarInt
//   locator_hashes:   [hash_count][32]u8 (most-recent first)
//   stop_hash:        [32]u8 (zeros = no stop)
//
// Locator hashes must be in internal byte order (= SHA256d output order,
// same as computeHash() returns).  HeaderStore stores hashes in internal
// order, so we copy them straight to the wire without any reversal.
// ─────────────────────────────────────────────────────────────────────

pub fn encodeGetheaders(
    out: []u8,
    locator: []const [32]u8,
    stop_hash: [32]u8,
) WireError!usize {
    if (locator.len > 2000) return error.encode_overflow; // sanity
    const max_varint: usize = if (locator.len < 0xfd) 1 else if (locator.len <= 0xffff) 3 else 5;
    const need = 4 + max_varint + locator.len * 32 + 32;
    if (out.len < need) return error.encode_overflow;
    var pos: usize = 0;

    std.mem.writeInt(u32, out[pos..][0..4], @intCast(PROTOCOL_VERSION), .little);
    pos += 4;
    try writeVarInt(out, &pos, @intCast(locator.len));
    for (locator) |h| {
        @memcpy(out[pos .. pos + 32], &h);
        pos += 32;
    }
    @memcpy(out[pos .. pos + 32], &stop_hash);
    pos += 32;
    return pos;
}

// ─────────────────────────────────────────────────────────────────────
// `headers` payload — count + (header || tx_count_varint=0)
//   count: VarInt
//   for each: 80-byte raw header + VarInt tx_count (always 0 for headers)
//
// Returns the parsed raw headers (each 80 bytes).  Caller validates
// per-header via cell-engine `validateHeader`.
// ─────────────────────────────────────────────────────────────────────

pub fn parseHeaders(allocator: std.mem.Allocator, payload: []const u8) ![]headers_mod.Header {
    var pos: usize = 0;
    const count = try readVarInt(payload, &pos);
    if (count > 2000) return error.decode_overflow; // BSV peer limit
    if (count == 0) return &[_]headers_mod.Header{};

    var out = try allocator.alloc(headers_mod.Header, @intCast(count));
    errdefer allocator.free(out);

    for (0..@intCast(count)) |i| {
        if (payload.len < pos + headers_mod.HEADER_BYTES) return error.decode_overflow;
        const raw_ptr: *const [80]u8 = @ptrCast(payload[pos .. pos + 80].ptr);
        out[i] = headers_mod.Header.parseRaw(raw_ptr);
        pos += 80;
        // Each header is followed by a VarInt tx_count, which is always
        // 0 in a `headers` message.  Read + ignore.
        _ = try readVarInt(payload, &pos);
    }
    return out;
}

/// Encode a `headers` payload from a slice of raw 80-byte headers.
/// Used by the loopback peer test fixture.  Each header is followed by
/// a VarInt tx_count = 0.
pub fn encodeHeaders(out: []u8, raw_headers: []const [80]u8) WireError!usize {
    if (raw_headers.len > 2000) return error.encode_overflow;
    var pos: usize = 0;
    try writeVarInt(out, &pos, @intCast(raw_headers.len));
    for (raw_headers) |h| {
        if (out.len < pos + 80 + 1) return error.encode_overflow;
        @memcpy(out[pos .. pos + 80], &h);
        pos += 80;
        out[pos] = 0; // VarInt 0 for tx_count
        pos += 1;
    }
    return pos;
}

// ─────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────

test "BRAIN-Headers wire: envelope round-trips with valid checksum" {
    var hdr_buf: [HEADER_BYTES]u8 = undefined;
    const payload = "test-payload";
    try encodeHeader(MAGIC_MAINNET, "verack", payload, &hdr_buf);

    const parsed = parseHeader(&hdr_buf);
    try std.testing.expectEqualSlices(u8, &MAGIC_MAINNET, &parsed.magic);
    try std.testing.expectEqualStrings("verack", parsed.commandTrimmed());
    try std.testing.expectEqual(@as(u32, payload.len), parsed.payload_size);
    try std.testing.expect(verifyChecksum(&parsed, payload));
}

test "BRAIN-Headers wire: rejects oversized command" {
    var hdr_buf: [HEADER_BYTES]u8 = undefined;
    try std.testing.expectError(
        error.bad_command,
        encodeHeader(MAGIC_MAINNET, "thirteen____x", "", &hdr_buf),
    );
}

test "BRAIN-Headers wire: VarInt round-trips across all 4 widths" {
    var buf: [16]u8 = undefined;
    inline for (.{ 0, 0xfc, 0xfd, 0xffff, 0x10000, 0xffffffff, 0x100000000 }) |n| {
        var pos: usize = 0;
        try writeVarInt(&buf, &pos, n);
        var rpos: usize = 0;
        const got = try readVarInt(&buf, &rpos);
        try std.testing.expectEqual(@as(u64, n), got);
        try std.testing.expectEqual(pos, rpos);
    }
}

test "BRAIN-Headers wire: encodeVersion produces a parseable payload" {
    var buf: [256]u8 = undefined;
    const ua = "/brain:0.1.0/";
    const n = try encodeVersion(&buf, 0xdeadbeef, ua, 0, 1_700_000_000);
    try std.testing.expectEqual(VERSION_MIN_BYTES + ua.len, n);
    // Spot-check a few fields.
    try std.testing.expectEqual(PROTOCOL_VERSION, std.mem.readInt(i32, buf[0..4], .little));
    try std.testing.expectEqual(SERVICES_DEFAULT, std.mem.readInt(u64, buf[4..12], .little));
    try std.testing.expectEqual(@as(i64, 1_700_000_000), std.mem.readInt(i64, buf[12..20], .little)); // timestamp
}

test "BRAIN-Headers wire: getheaders encodes locator verbatim (internal byte order)" {
    var buf: [128]u8 = undefined;
    const locator: [1][32]u8 = .{[_]u8{0x11} ** 32}; // internal-order hash, sent as-is to wire
    var stop: [32]u8 = undefined;
    @memset(&stop, 0);
    const n = try encodeGetheaders(&buf, &locator, stop);
    try std.testing.expectEqual(@as(usize, 4 + 1 + 32 + 32), n);
    try std.testing.expectEqual(@as(u32, @intCast(PROTOCOL_VERSION)), std.mem.readInt(u32, buf[0..4], .little));
    try std.testing.expectEqual(@as(u8, 1), buf[4]); // VarInt = 1
    // Locator hash bytes: all 0x11 in either order.
    for (buf[5..37]) |b| try std.testing.expectEqual(@as(u8, 0x11), b);
    // Stop hash bytes: all 0x00.
    for (buf[37..69]) |b| try std.testing.expectEqual(@as(u8, 0x00), b);
}

test "BRAIN-Headers wire: parseHeaders round-trips through encodeHeaders" {
    const allocator = std.testing.allocator;

    // Build two synthetic 80-byte headers.  The bytes' validity isn't
    // exercised here (parseRaw is unconditional); cell-engine's
    // validateHeader is the gate the sync orchestrator uses.
    var raw1: [80]u8 = undefined;
    var raw2: [80]u8 = undefined;
    @memset(&raw1, 0xaa);
    @memset(&raw2, 0xbb);
    const inputs: [2][80]u8 = .{ raw1, raw2 };

    var buf: [1024]u8 = undefined;
    const n = try encodeHeaders(&buf, &inputs);
    try std.testing.expectEqual(@as(usize, 1 + 2 * 81), n);

    const parsed = try parseHeaders(allocator, buf[0..n]);
    defer allocator.free(parsed);
    try std.testing.expectEqual(@as(usize, 2), parsed.len);
}

test "BRAIN-Headers wire: parseHeaders rejects > 2000 count" {
    const allocator = std.testing.allocator;
    // VarInt 0xfd + 0x01 + 0x10 = 0x1001 = 4097.
    var buf: [3]u8 = .{ 0xfd, 0x01, 0x10 };
    try std.testing.expectError(
        error.decode_overflow,
        parseHeaders(allocator, &buf),
    );
}

```
