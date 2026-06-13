---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/node/src/wss.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.304473+00:00
---

# runtime/node/src/wss.zig

```zig
// Phase W6 — Minimal RFC 6455 WebSocket server for the BRC-100 endpoint
// at `wss://node.semantos.{tld}/wallet` (design §10.2, §11 Q6).
//
// ─── TLS strategy ─────────────────────────────────────────────────────
//
// **TLS termination is Caddy's job** (per W6 task brief and design §10.2:
// "Caddy (TLS) → semantos-node (Zig)"). This module speaks plain
// WebSocket (RFC 6455) on a TCP socket bound to localhost:port; Caddy
// reverse-proxies WSS → WS. The on-the-wire framing here is identical
// to what Caddy will send us — just with TLS decrypted.
//
// ─── Scope (v0.1) ─────────────────────────────────────────────────────
//
//   • Server-side handshake (Sec-WebSocket-Accept computation)
//   • Text frames (opcode 0x1) only
//   • Frames up to 64 KiB payload (BRC-100 envelopes are ≤ a few KB)
//   • No fragmentation (RFC 6455 §5.4 — single FIN=1 frame in/out)
//   • No deflate/permessage extensions
//   • One connection per accepted TCP — request-then-close pattern;
//     a dApp connection lifecycle is "open → handshake → 1+ envelopes
//     → close-frame → close". The handler runs synchronously on the
//     accept thread for v0.1; v0.2 promotes to a per-connection worker.
//
// ─── Per-frame failure-atomicity ──────────────────────────────────────
//
// The engine's peek-then-mutate convention (`OP_SIGN`, `LocalSlotStore.vPut`)
// carries through here: on a malformed envelope we close the WS frame
// with status 1002 (protocol error) without touching wallet state. The
// `brc100.zig` dispatcher returns a structured `Reject` envelope that
// the caller writes back as a single text frame.

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
const WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

/// Read the HTTP request line + headers from the stream. Returns the
/// Sec-WebSocket-Key value (caller-owned slice into the supplied buffer).
/// On any failure, the error variant is loud — the caller should close
/// the socket without writing a response (or write 400 — both are
/// valid behaviors per RFC 6455 §4.2.2).
pub fn readHandshakeRequest(
    stream: std.net.Stream,
    buf: []u8,
) HandshakeError![]const u8 {
    var total: usize = 0;
    var have_terminator: bool = false;
    // Read until we see "\r\n\r\n" (HTTP header terminator).
    while (total < buf.len) {
        const n = stream.read(buf[total..]) catch return error.ReadFailed;
        if (n == 0) return error.Eof;
        total += n;
        if (total >= 4) {
            // Cheap scan; max header size is bounded by `buf.len`.
            if (std.mem.indexOf(u8, buf[0..total], "\r\n\r\n") != null) {
                have_terminator = true;
                break;
            }
        }
    }
    if (!have_terminator) return error.HeadersTooLarge;

    const headers = buf[0..total];

    // Grep for required headers. We don't validate the request line beyond
    // requiring a "GET " prefix — Caddy's already routed the request, so we
    // trust the path. But for direct-connect dev / tests we still want to
    // reject obviously-wrong methods.
    if (!std.mem.startsWith(u8, headers, "GET ")) return error.BadRequest;

    if (findHeaderValue(headers, "Upgrade") == null) return error.NoUpgradeHeader;
    const upgrade = findHeaderValue(headers, "Upgrade").?;
    if (!asciiEqualsCaseInsensitive(upgrade, "websocket")) return error.NoUpgradeHeader;

    const conn = findHeaderValue(headers, "Connection") orelse return error.NoConnectionUpgrade;
    if (!asciiContainsCaseInsensitive(conn, "Upgrade")) return error.NoConnectionUpgrade;

    const key = findHeaderValue(headers, "Sec-WebSocket-Key") orelse return error.NoSecKey;
    return key;
}

/// Compute Sec-WebSocket-Accept from a client Sec-WebSocket-Key.
/// `out` is a base64-encoded 28-char buffer (SHA-1 → 20 bytes →
/// base64 → 28 chars without padding-bytes-loss).
pub fn computeAccept(client_key: []const u8, out: *[28]u8) void {
    var ctx = std.crypto.hash.Sha1.init(.{});
    ctx.update(client_key);
    ctx.update(WS_GUID);
    var sha: [20]u8 = undefined;
    ctx.final(&sha);
    _ = std.base64.standard.Encoder.encode(out, &sha);
}

/// Write the 101 Switching Protocols response.
pub fn writeHandshakeResponse(stream: std.net.Stream, accept: *const [28]u8) HandshakeError!void {
    var buf: [256]u8 = undefined;
    const resp = std.fmt.bufPrint(
        &buf,
        "HTTP/1.1 101 Switching Protocols\r\n" ++
            "Upgrade: websocket\r\n" ++
            "Connection: Upgrade\r\n" ++
            "Sec-WebSocket-Accept: {s}\r\n\r\n",
        .{accept},
    ) catch return error.WriteFailed;
    stream.writeAll(resp) catch return error.WriteFailed;
}

/// Convenience: full server-side handshake. On success the connection
/// is upgraded and ready for text frames in either direction.
pub fn handshake(stream: std.net.Stream) HandshakeError!void {
    var buf: [4096]u8 = undefined;
    const key = try readHandshakeRequest(stream, &buf);
    var accept_b64: [28]u8 = undefined;
    computeAccept(key, &accept_b64);
    try writeHandshakeResponse(stream, &accept_b64);
}

// ─── Frame I/O ───────────────────────────────────────────────────────

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
    /// Allocator-owned bytes. Caller must `allocator.free`.
    payload: []u8,
};

/// Read one client→server frame. Per RFC 6455 §5.3, all client frames
/// MUST be masked; we enforce that (close 1002 on violation is the
/// caller's responsibility).
///
/// `max_payload` caps the accepted payload size; oversized frames return
/// `PayloadTooLarge` so the caller can close 1009.
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
    // Reserved bits (RSV1/2/3) must be zero — we don't negotiate any
    // extensions. RFC 6455 §5.2.
    if ((hdr[0] & 0x70) != 0) return error.UnsupportedOpcode;

    if (!masked) return error.NotMasked;

    // Resolve extended payload length per RFC 6455 §5.2.
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

/// Write one server→client frame. Per RFC 6455 §5.3 server frames
/// MUST NOT be masked. `payload` must already be the unmasked plaintext.
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

/// Convenience: write a Close frame (opcode 0x8) with status code +
/// optional UTF-8 reason. Per RFC 6455 §5.5.1.
pub fn writeClose(stream: std.net.Stream, status: u16, reason: []const u8) FrameError!void {
    var buf: [125]u8 = undefined; // close payload max
    if (reason.len > buf.len - 2) return error.PayloadTooLarge;
    std.mem.writeInt(u16, buf[0..2], status, .big);
    @memcpy(buf[2 .. 2 + reason.len], reason);
    return writeFrame(stream, .close, buf[0 .. 2 + reason.len]);
}

// ─── Client-side helpers (used only by tests) ────────────────────────

/// Issue a client handshake against a freshly-connected stream. Hardcodes
/// a deterministic Sec-WebSocket-Key (`abcdefghijklmnopqrstuv==` →
/// 16 bytes once base64-decoded) — fine for tests and never used by
/// production code.
pub fn clientHandshake(stream: std.net.Stream, host: []const u8, path: []const u8) !void {
    var buf: [512]u8 = undefined;
    const req = try std.fmt.bufPrint(
        &buf,
        "GET {s} HTTP/1.1\r\n" ++
            "Host: {s}\r\n" ++
            "Upgrade: websocket\r\n" ++
            "Connection: Upgrade\r\n" ++
            "Sec-WebSocket-Key: AAAAAAAAAAAAAAAAAAAAAA==\r\n" ++
            "Sec-WebSocket-Version: 13\r\n\r\n",
        .{ path, host },
    );
    try stream.writeAll(req);

    // Slurp 101 + headers, then drop them — we trust the server here.
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

    // Deterministic mask `0xA5A5A5A5` for ease of debugging; production
    // would use std.crypto.random.
    const mask = [4]u8{ 0xA5, 0xA5, 0xA5, 0xA5 };
    @memcpy(hdr_buf[hdr_len .. hdr_len + 4], &mask);
    hdr_len += 4;

    try stream.writeAll(hdr_buf[0..hdr_len]);

    // Mask payload in chunks. Allocate-free: write a small scratch buffer.
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

/// Find an HTTP header value by name (case-insensitive on the key,
/// trimmed of leading whitespace on the value). Returns `null` if the
/// header is absent. The returned slice points into the input.
fn findHeaderValue(headers: []const u8, name: []const u8) ?[]const u8 {
    var line_start: usize = 0;
    var i: usize = 0;
    while (i < headers.len) : (i += 1) {
        if (i + 1 < headers.len and headers[i] == '\r' and headers[i + 1] == '\n') {
            const line = headers[line_start..i];
            if (line.len > name.len + 1) {
                if (asciiEqualsCaseInsensitive(line[0..name.len], name) and line[name.len] == ':') {
                    var v_start: usize = name.len + 1;
                    while (v_start < line.len and (line[v_start] == ' ' or line[v_start] == '\t')) {
                        v_start += 1;
                    }
                    return line[v_start..];
                }
            }
            line_start = i + 2;
            i += 1;
        }
    }
    return null;
}

fn asciiToLower(c: u8) u8 {
    return if (c >= 'A' and c <= 'Z') c + 32 else c;
}

fn asciiEqualsCaseInsensitive(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| if (asciiToLower(x) != asciiToLower(y)) return false;
    return true;
}

fn asciiContainsCaseInsensitive(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (haystack.len < needle.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (asciiEqualsCaseInsensitive(haystack[i .. i + needle.len], needle)) return true;
    }
    return false;
}

// ─── Tests ────────────────────────────────────────────────────────────

test "computeAccept matches RFC 6455 example" {
    // RFC 6455 §1.3 worked example.
    var out: [28]u8 = undefined;
    computeAccept("dGhlIHNhbXBsZSBub25jZQ==", &out);
    try std.testing.expectEqualSlices(u8, "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=", &out);
}

test "findHeaderValue case insensitive" {
    const h = "GET /wallet HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: abc==\r\n\r\n";
    const upgrade = findHeaderValue(h, "Upgrade").?;
    try std.testing.expectEqualSlices(u8, "websocket", upgrade);
    const key = findHeaderValue(h, "sec-websocket-key").?;
    try std.testing.expectEqualSlices(u8, "abc==", key);
}

```
