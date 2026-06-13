---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/wss_codec.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.259133+00:00
---

# runtime/semantos-brain/src/wss_codec.zig

```zig
// Phase Brain 4.5 — minimal RFC 6455 WebSocket codec for brain's wallet endpoint.
//
// Reference: docs/design/WALLET-SHELL-VPS-SUBSTRATE.md §3 (Brain 4 — WSS).
//
// Mirrors the codec in runtime/node/src/wss.zig (the W6 sovereign-node
// browser-backend's wallet endpoint) — same handshake math, same frame
// rules. Kept as a separate file in brain's tree to avoid cross-runtime
// build-graph coupling; the two should converge into a shared module
// in core/cell-engine once both runtimes are stable. (Consolidation
// tracked under Brain 4.6 → "shared wss codec".)
//
// ─── Scope (v0.1) ─────────────────────────────────────────────────────
//
//   • Server-side handshake (Sec-WebSocket-Accept computation)
//   • Text frames (opcode 0x1) only
//   • Frames up to 64 KiB payload — BRC-100 envelopes are ≤ a few KB
//   • No fragmentation (single FIN=1 frame in/out per RFC 6455 §5.4)
//   • No deflate / permessage extensions
//   • One WS session per accepted TCP connection — request-then-close;
//     the client opens, exchanges 1+ JSON-RPC messages, sends a close
//     frame, and the server closes
//
// ─── TLS strategy ────────────────────────────────────────────────────
//
// TLS termination is the operator's reverse-proxy job (Caddy in the
// recommended deploy). This module speaks plain WS on the same port as
// the HTTP REPL (8080 by default); Caddy fronts both with TLS so the
// client URL is `wss://<domain>/api/v1/wallet`.

const std = @import("std");

pub const HandshakeError = error{
    BadRequest,
    NoUpgradeHeader,
    NoConnectionUpgrade,
    NoSecKey,
    HeadersTooLarge,
    Eof,
    WriteFailed,
    ReadFailed,
};

/// RFC 6455 magic GUID — concatenated with the client's Sec-WebSocket-Key,
/// SHA-1 hashed, base64-encoded → server's Sec-WebSocket-Accept value.
pub const WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

/// Compute Sec-WebSocket-Accept from a client Sec-WebSocket-Key.
/// `out` receives a 28-byte base64-encoded SHA-1 (no trailing padding
/// loss — SHA-1's 20-byte output base64-encodes to exactly 28 chars).
pub fn computeAccept(client_key: []const u8, out: *[28]u8) void {
    var ctx = std.crypto.hash.Sha1.init(.{});
    ctx.update(client_key);
    ctx.update(WS_GUID);
    var sha: [20]u8 = undefined;
    ctx.final(&sha);
    _ = std.base64.standard.Encoder.encode(out, &sha);
}

// ─── Frame I/O over std.net.Stream ───────────────────────────────────

pub const FrameError = error{
    Eof,
    ReadFailed,
    WriteFailed,
    UnsupportedOpcode,
    Fragmented,
    PayloadTooLarge,
    NotMasked,
    OutOfMemory,
};

pub const Opcode = enum(u4) {
    continuation = 0x0,
    text = 0x1,
    binary = 0x2,
    close = 0x8,
    ping = 0x9,
    pong = 0xA,
    _,
};

pub const Frame = struct {
    opcode: Opcode,
    /// Allocator-owned bytes. Caller must `allocator.free` after use.
    payload: []u8,
};

/// Read one client→server frame. Per RFC 6455 §5.3 client frames MUST
/// be masked; we enforce it. Oversized payloads return PayloadTooLarge
/// so the caller can close with status 1009.
pub fn readFrame(
    allocator: std.mem.Allocator,
    stream: std.net.Stream,
    max_payload: usize,
) FrameError!Frame {
    var hdr: [2]u8 = undefined;
    try readExact(stream, &hdr);

    const fin = (hdr[0] & 0x80) != 0;
    const opcode_raw: u4 = @intCast(hdr[0] & 0x0F);
    const opcode: Opcode = @enumFromInt(opcode_raw);
    const masked = (hdr[1] & 0x80) != 0;
    const len7: u7 = @intCast(hdr[1] & 0x7F);

    if (!fin) return error.Fragmented;
    // RSV1/2/3 must be zero — we don't negotiate any extensions
    // (RFC 6455 §5.2).
    if ((hdr[0] & 0x70) != 0) return error.UnsupportedOpcode;

    if (!masked) return error.NotMasked;

    var payload_len: u64 = len7;
    if (len7 == 126) {
        var ext: [2]u8 = undefined;
        try readExact(stream, &ext);
        payload_len = std.mem.readInt(u16, &ext, .big);
    } else if (len7 == 127) {
        var ext: [8]u8 = undefined;
        try readExact(stream, &ext);
        payload_len = std.mem.readInt(u64, &ext, .big);
    }

    if (payload_len > max_payload) return error.PayloadTooLarge;

    var mask: [4]u8 = undefined;
    try readExact(stream, &mask);

    const payload = allocator.alloc(u8, @intCast(payload_len)) catch return error.OutOfMemory;
    errdefer allocator.free(payload);

    try readExact(stream, payload);
    // Unmask in place per RFC 6455 §5.3.
    for (payload, 0..) |b, i| payload[i] = b ^ mask[i & 3];

    return .{ .opcode = opcode, .payload = payload };
}

/// Write one server→client frame. Per RFC 6455 §5.3 server frames MUST
/// NOT be masked. `payload` is the unmasked plaintext.
pub fn writeFrame(stream: std.net.Stream, opcode: Opcode, payload: []const u8) FrameError!void {
    var hdr_buf: [10]u8 = undefined;
    var hdr_len: usize = 2;
    hdr_buf[0] = 0x80 | @as(u8, @intFromEnum(opcode)); // FIN | opcode

    if (payload.len < 126) {
        hdr_buf[1] = @intCast(payload.len);
    } else if (payload.len <= 0xFFFF) {
        hdr_buf[1] = 126;
        std.mem.writeInt(u16, hdr_buf[2..4], @intCast(payload.len), .big);
        hdr_len = 4;
    } else {
        hdr_buf[1] = 127;
        std.mem.writeInt(u64, hdr_buf[2..10], @as(u64, payload.len), .big);
        hdr_len = 10;
    }

    stream.writeAll(hdr_buf[0..hdr_len]) catch return error.WriteFailed;
    if (payload.len > 0) stream.writeAll(payload) catch return error.WriteFailed;
}

/// Write a Close frame (opcode 0x8) with status code + optional UTF-8
/// reason. Per RFC 6455 §5.5.1.
pub fn writeClose(stream: std.net.Stream, status: u16, reason: []const u8) FrameError!void {
    var buf: [125]u8 = undefined; // Close payload max
    if (reason.len > buf.len - 2) return error.PayloadTooLarge;
    std.mem.writeInt(u16, buf[0..2], status, .big);
    @memcpy(buf[2 .. 2 + reason.len], reason);
    return writeFrame(stream, .close, buf[0 .. 2 + reason.len]);
}

// ─── Client-side helpers (used only by tests) ───────────────────────

/// Issue a client handshake against a freshly-connected stream. Hardcodes
/// a deterministic Sec-WebSocket-Key — fine for tests, never used by
/// production code.
pub fn clientHandshake(stream: std.net.Stream, host: []const u8, path: []const u8, extra_headers: []const u8) !void {
    var buf: [1024]u8 = undefined;
    const req = try std.fmt.bufPrint(
        &buf,
        "GET {s} HTTP/1.1\r\n" ++
            "Host: {s}\r\n" ++
            "Upgrade: websocket\r\n" ++
            "Connection: Upgrade\r\n" ++
            "Sec-WebSocket-Key: AAAAAAAAAAAAAAAAAAAAAA==\r\n" ++
            "Sec-WebSocket-Version: 13\r\n" ++
            "{s}" ++
            "\r\n",
        .{ path, host, extra_headers },
    );
    try stream.writeAll(req);

    // Slurp the 101 response + headers; just trust the server.
    var resp_buf: [4096]u8 = undefined;
    var total: usize = 0;
    while (total < resp_buf.len) {
        const n = try stream.read(resp_buf[total..]);
        if (n == 0) return error.Eof;
        total += n;
        if (std.mem.indexOf(u8, resp_buf[0..total], "\r\n\r\n") != null) return;
    }
    return error.HeadersTooLarge;
}

/// Write a masked client→server frame. RFC 6455 §5.3 — clients must mask.
pub fn writeClientFrame(stream: std.net.Stream, opcode: Opcode, payload: []const u8) !void {
    var hdr_buf: [14]u8 = undefined;
    var hdr_len: usize = 2;
    hdr_buf[0] = 0x80 | @as(u8, @intFromEnum(opcode));

    if (payload.len < 126) {
        hdr_buf[1] = 0x80 | @as(u8, @intCast(payload.len));
    } else if (payload.len <= 0xFFFF) {
        hdr_buf[1] = 0x80 | 126;
        std.mem.writeInt(u16, hdr_buf[2..4], @intCast(payload.len), .big);
        hdr_len = 4;
    } else {
        hdr_buf[1] = 0x80 | 127;
        std.mem.writeInt(u64, hdr_buf[2..10], @as(u64, payload.len), .big);
        hdr_len = 10;
    }

    // Deterministic mask `0xA5A5A5A5` for ease of test debugging;
    // production WS clients use std.crypto.random.
    const mask = [4]u8{ 0xA5, 0xA5, 0xA5, 0xA5 };
    @memcpy(hdr_buf[hdr_len .. hdr_len + 4], &mask);
    hdr_len += 4;

    try stream.writeAll(hdr_buf[0..hdr_len]);

    var off: usize = 0;
    var chunk: [256]u8 = undefined;
    while (off < payload.len) {
        const take = @min(payload.len - off, chunk.len);
        for (0..take) |i| chunk[i] = payload[off + i] ^ mask[(off + i) & 3];
        try stream.writeAll(chunk[0..take]);
        off += take;
    }
}

/// Read one server→client frame (no mask expected).
pub fn readClientFrame(
    allocator: std.mem.Allocator,
    stream: std.net.Stream,
    max_payload: usize,
) !Frame {
    var hdr: [2]u8 = undefined;
    try readExact(stream, &hdr);
    const fin = (hdr[0] & 0x80) != 0;
    const opcode: Opcode = @enumFromInt(@as(u4, @intCast(hdr[0] & 0x0F)));
    const masked = (hdr[1] & 0x80) != 0;
    const len7: u7 = @intCast(hdr[1] & 0x7F);
    if (!fin) return error.Fragmented;
    if (masked) return error.UnsupportedOpcode; // server frames must not be masked

    var payload_len: u64 = len7;
    if (len7 == 126) {
        var ext: [2]u8 = undefined;
        try readExact(stream, &ext);
        payload_len = std.mem.readInt(u16, &ext, .big);
    } else if (len7 == 127) {
        var ext: [8]u8 = undefined;
        try readExact(stream, &ext);
        payload_len = std.mem.readInt(u64, &ext, .big);
    }
    if (payload_len > max_payload) return error.PayloadTooLarge;

    const payload = try allocator.alloc(u8, @intCast(payload_len));
    errdefer allocator.free(payload);
    try readExact(stream, payload);
    return .{ .opcode = opcode, .payload = payload };
}

// ─── Helpers ─────────────────────────────────────────────────────────

fn readExact(stream: std.net.Stream, buf: []u8) FrameError!void {
    var total: usize = 0;
    while (total < buf.len) {
        const n = stream.read(buf[total..]) catch return error.ReadFailed;
        if (n == 0) return error.Eof;
        total += n;
    }
}

// ─── DLBA.1b-integration step 1 — subprotocol header parsing ────────
//
// RFC 6455 §4.1 — client MAY send `Sec-WebSocket-Protocol: <name>` (or
// a comma-separated list) during the handshake; the server picks one
// and echoes it back in the 101 response. Brain-core didn't parse this
// header until now because there was nothing to route to — wss_wallet.zig
// and events_stream_handler.zig do their own handshakes and never
// inspected subprotocol claims.
//
// This helper is the parsing primitive that future handshake call sites
// (centralized routing layer or per-endpoint hooks) consult to decide
// whether to route to a registered subprotocol handler via
// `wss_subprotocol_registry.lookup()`. The actual routing decision is
// out of scope for this module — wss_codec.zig stays pure RFC 6455.
//
// Contract:
//   • Input: raw HTTP request bytes (the full handshake request through
//     the trailing `\r\n\r\n`).
//   • Output: the first claimed subprotocol name as a slice into the
//     input (caller copies if needed past the request's lifetime), or
//     null if no header / empty value / malformed.
//   • Header matching is case-insensitive per RFC 7230 §3.2 (HTTP field
//     names).
//   • Comma-separated lists return the FIRST claim (matches the
//     "server picks one" RFC 6455 §4.1 pattern — first-fit suits a
//     deny-by-default registry lookup).
//   • Whitespace is trimmed from the returned slice.

/// Max accepted subprotocol-name length. Matches wss_subprotocol_registry
/// MAX_NAME_LEN. Longer claims are treated as malformed (return null).
pub const MAX_SUBPROTOCOL_NAME_LEN: usize = 64;

/// Parse the first claimed Sec-WebSocket-Protocol value from a raw HTTP
/// request bytes slice. Returns the value as a slice into `req` (no
/// allocation) or null if absent / empty / malformed.
pub fn parseRequestedSubprotocol(req: []const u8) ?[]const u8 {
    const header_name = "sec-websocket-protocol";
    // Walk line by line; case-insensitive header-name compare.
    var line_start: usize = 0;
    while (line_start < req.len) {
        const nl = std.mem.indexOfScalarPos(u8, req, line_start, '\n') orelse req.len;
        // Trim trailing \r if present.
        const line_end = if (nl > 0 and req[nl - 1] == '\r') nl - 1 else nl;
        const line = req[line_start..line_end];
        line_start = nl + 1;

        // Find ':' delimiting name from value.
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const name = line[0..colon];
        if (name.len != header_name.len) continue;

        // Case-insensitive name compare.
        var match = true;
        for (name, header_name) |a, b| {
            const al = if (a >= 'A' and a <= 'Z') a + 32 else a;
            if (al != b) {
                match = false;
                break;
            }
        }
        if (!match) continue;

        // Found Sec-WebSocket-Protocol. Take first comma-separated value.
        var value = line[colon + 1 ..];
        const comma = std.mem.indexOfScalar(u8, value, ',') orelse value.len;
        value = value[0..comma];

        // Trim leading/trailing whitespace.
        var start: usize = 0;
        while (start < value.len and (value[start] == ' ' or value[start] == '\t')) start += 1;
        var end: usize = value.len;
        while (end > start and (value[end - 1] == ' ' or value[end - 1] == '\t')) end -= 1;
        const trimmed = value[start..end];

        if (trimmed.len == 0) return null;
        if (trimmed.len > MAX_SUBPROTOCOL_NAME_LEN) return null;
        return trimmed;
    }
    return null;
}

// ─── Tests ───────────────────────────────────────────────────────────

test "computeAccept matches RFC 6455 worked example" {
    // RFC 6455 §1.3 worked example.
    var out: [28]u8 = undefined;
    computeAccept("dGhlIHNhbXBsZSBub25jZQ==", &out);
    try std.testing.expectEqualSlices(u8, "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=", &out);
}

// ─── DLBA.1b-integration tests — parseRequestedSubprotocol ──────────

test "parseRequestedSubprotocol: returns null when header absent" {
    const req =
        "GET /api/v1/wallet HTTP/1.1\r\n" ++
        "Host: localhost:8080\r\n" ++
        "Upgrade: websocket\r\n" ++
        "Connection: Upgrade\r\n" ++
        "Sec-WebSocket-Key: AAAAAAAAAAAAAAAAAAAAAA==\r\n" ++
        "Sec-WebSocket-Version: 13\r\n\r\n";
    try std.testing.expect(parseRequestedSubprotocol(req) == null);
}

test "parseRequestedSubprotocol: extracts single subprotocol claim" {
    const req =
        "GET / HTTP/1.1\r\n" ++
        "Sec-WebSocket-Protocol: wallet.v1\r\n\r\n";
    const got = parseRequestedSubprotocol(req) orelse return error.NotFound;
    try std.testing.expectEqualStrings("wallet.v1", got);
}

test "parseRequestedSubprotocol: comma-separated list returns first claim" {
    const req =
        "GET / HTTP/1.1\r\n" ++
        "Sec-WebSocket-Protocol: wallet.v1, jam.v1, fallback.v0\r\n\r\n";
    const got = parseRequestedSubprotocol(req) orelse return error.NotFound;
    try std.testing.expectEqualStrings("wallet.v1", got);
}

test "parseRequestedSubprotocol: case-insensitive header name match" {
    const req =
        "GET / HTTP/1.1\r\n" ++
        "sec-websocket-protocol: wallet.v1\r\n\r\n";
    const got = parseRequestedSubprotocol(req) orelse return error.NotFound;
    try std.testing.expectEqualStrings("wallet.v1", got);

    const req2 =
        "GET / HTTP/1.1\r\n" ++
        "SEC-WEBSOCKET-PROTOCOL: wallet.v1\r\n\r\n";
    const got2 = parseRequestedSubprotocol(req2) orelse return error.NotFound;
    try std.testing.expectEqualStrings("wallet.v1", got2);
}

test "parseRequestedSubprotocol: trims surrounding whitespace from value" {
    const req =
        "GET / HTTP/1.1\r\n" ++
        "Sec-WebSocket-Protocol:    wallet.v1   \r\n\r\n";
    const got = parseRequestedSubprotocol(req) orelse return error.NotFound;
    try std.testing.expectEqualStrings("wallet.v1", got);
}

test "parseRequestedSubprotocol: empty value returns null" {
    const req =
        "GET / HTTP/1.1\r\n" ++
        "Sec-WebSocket-Protocol:   \r\n\r\n";
    try std.testing.expect(parseRequestedSubprotocol(req) == null);
}

test "parseRequestedSubprotocol: oversized value returns null" {
    // 65 chars — one past MAX_SUBPROTOCOL_NAME_LEN.
    const req =
        "GET / HTTP/1.1\r\n" ++
        "Sec-WebSocket-Protocol: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\r\n\r\n";
    try std.testing.expect(parseRequestedSubprotocol(req) == null);
}

test "parseRequestedSubprotocol: handles \\n-only line endings" {
    const req =
        "GET / HTTP/1.1\n" ++
        "Sec-WebSocket-Protocol: jam.v1\n\n";
    const got = parseRequestedSubprotocol(req) orelse return error.NotFound;
    try std.testing.expectEqualStrings("jam.v1", got);
}

test "parseRequestedSubprotocol: V1 path preserved — non-subprotocol-aware handshakes still return null" {
    // The exact handshake shape wss_wallet.zig serves today: no
    // Sec-WebSocket-Protocol header. Verifies the V1 production path
    // (no subprotocol claimed → operator-auth gate) is unchanged after
    // this parsing primitive lands.
    const req =
        "GET /api/v1/wallet HTTP/1.1\r\n" ++
        "Host: localhost:8080\r\n" ++
        "Upgrade: websocket\r\n" ++
        "Connection: Upgrade\r\n" ++
        "Sec-WebSocket-Key: AAAAAAAAAAAAAAAAAAAAAA==\r\n" ++
        "Sec-WebSocket-Version: 13\r\n" ++
        "Authorization: Bearer token-xyz\r\n\r\n";
    try std.testing.expect(parseRequestedSubprotocol(req) == null);
}

```
