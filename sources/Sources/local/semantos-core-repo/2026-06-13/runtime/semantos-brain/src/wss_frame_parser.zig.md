---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/wss_frame_parser.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.253992+00:00
---

# runtime/semantos-brain/src/wss_frame_parser.zig

```zig
// wss_frame_parser.zig — Resumable RFC 6455 WebSocket frame parser
//
// WHY THIS FILE EXISTS
// --------------------
// `wss_codec.readFrame` does blocking reads via `readExact()` — it cannot
// be used with non-blocking sockets. This module provides the same
// semantics in a byte-driven state machine that can be suspended and
// resumed as bytes arrive across multiple poll cycles.
//
// ARCHITECTURAL MODEL
// -------------------
// `FrameParser.feed()` accepts arbitrary byte chunks and advances through
// these states:
//
//   need_hdr2  → need_ext_len16 / need_ext_len64 → need_mask → need_payload → complete
//
// When a state needs more bytes than are available, it records progress and
// returns `.incomplete`. The caller feeds more bytes next poll cycle.
//
// The parser reuses the existing `wss_codec.Opcode` and `wss_codec.Frame`
// types so the rest of the codebase remains unchanged.
//
// SCOPE (v1)
// ----------
//   • Client→server frames with MASK bit set (RFC 6455 §5.3)
//   • Text, binary, close, ping, pong opcodes
//   • Payload up to MAX_PAYLOAD (64 KiB — same as wss_codec)
//   • No fragmentation (FIN=1 required — fragmentation not needed by brain v0.1)
//   • RSV bits must be zero (no extensions negotiated)
//
// HOW TO REVERT
// -------------
// This file is new. Delete it along with event_loop.zig, connection_state.zig,
// http_parser.zig to revert the entire reactor change.
//
// RIP-OUT-MARKER (brain-wedge B-pragmatic, 2026-05-07):
//   Part of the reactor wedge fix. Not present before this change.
//   See docs/prd/BRAIN-WEDGE-STEP0-AUDIT.md.

const std = @import("std");
const wss_codec = @import("wss_codec");

/// Maximum payload bytes — matches wss_wallet.MAX_PAYLOAD_BYTES.
pub const MAX_PAYLOAD: usize = 64 * 1024;

pub const FrameParseError = error{
    Fragmented,
    UnsupportedOpcode,
    NotMasked,
    PayloadTooLarge,
    OutOfMemory,
};

/// Parse result for one call to `FrameParser.feed()`.
pub const FrameParseResult = union(enum) {
    /// Need more bytes.
    incomplete,
    /// A complete frame is ready in `parser.frame` + `parser.payload_buf`.
    /// `bytes_consumed` is how many bytes from the input were consumed.
    complete: struct { bytes_consumed: usize },
    /// Unrecoverable protocol error. Close the connection.
    err: FrameParseError,
};

/// Per-connection WebSocket frame parser. Zero heap allocation — uses a
/// fixed-size payload buffer and a 14-byte header accumulator.
pub const FrameParser = struct {
    // ── Header accumulation (up to 14 bytes: 2 base + 8 ext_len + 4 mask) ──
    hdr_buf: [14]u8,
    hdr_len: usize, // bytes written to hdr_buf so far

    // ── State machine ──
    state: State,

    // ── Decoded frame metadata (set once header is complete) ──
    opcode: wss_codec.Opcode,
    fin: bool,
    masked: bool,
    payload_len: usize,
    mask: [4]u8,

    // ── Payload buffer (allocated once per frame) ──
    payload_buf: [MAX_PAYLOAD]u8,
    payload_written: usize,

    const State = enum {
        /// Waiting for the 2-byte base header.
        need_hdr2,
        /// Waiting for the 2-byte extended length (payload_len == 126).
        need_ext_len16,
        /// Waiting for the 8-byte extended length (payload_len == 127).
        need_ext_len64,
        /// Waiting for the 4-byte mask key.
        need_mask,
        /// Waiting for payload bytes.
        need_payload,
        /// Frame complete — caller must call `reset()` before next frame.
        complete,
    };

    pub fn init() FrameParser {
        return .{
            .hdr_buf = undefined,
            .hdr_len = 0,
            .state = .need_hdr2,
            .opcode = .text,
            .fin = false,
            .masked = false,
            .payload_len = 0,
            .mask = .{ 0, 0, 0, 0 },
            .payload_buf = undefined,
            .payload_written = 0,
        };
    }

    pub fn reset(self: *FrameParser) void {
        self.hdr_len = 0;
        self.state = .need_hdr2;
        self.payload_written = 0;
        self.payload_len = 0;
    }

    /// Feed a chunk of bytes. Returns the parse result.
    /// On `complete`, the caller reads the frame via `getFrame()`.
    /// The returned frame's payload slice borrows from `self.payload_buf`
    /// and is valid until the next `reset()`.
    ///
    /// `bytes_consumed` in the `complete` variant tells the caller how
    /// many bytes from this particular `new_bytes` slice were consumed —
    /// the rest may be the start of the next frame.
    pub fn feed(self: *FrameParser, new_bytes: []const u8) FrameParseResult {
        var pos: usize = 0;

        while (pos < new_bytes.len) {
            switch (self.state) {
                .need_hdr2 => {
                    const need = 2 - self.hdr_len;
                    const avail = new_bytes.len - pos;
                    const take = @min(need, avail);
                    @memcpy(self.hdr_buf[self.hdr_len..][0..take], new_bytes[pos..][0..take]);
                    self.hdr_len += take;
                    pos += take;

                    if (self.hdr_len < 2) return .incomplete;

                    // Decode the 2-byte base header.
                    const b0 = self.hdr_buf[0];
                    const b1 = self.hdr_buf[1];
                    self.fin = (b0 & 0x80) != 0;
                    const rsv = b0 & 0x70;
                    const opcode_raw: u4 = @intCast(b0 & 0x0F);
                    self.opcode = @enumFromInt(opcode_raw);
                    self.masked = (b1 & 0x80) != 0;
                    const len7: u7 = @intCast(b1 & 0x7F);

                    if (!self.fin) return .{ .err = error.Fragmented };
                    if (rsv != 0) return .{ .err = error.UnsupportedOpcode };
                    if (!self.masked) return .{ .err = error.NotMasked };

                    if (len7 == 126) {
                        self.state = .need_ext_len16;
                        self.hdr_len = 0; // reuse hdr_buf for the 2 ext bytes
                    } else if (len7 == 127) {
                        self.state = .need_ext_len64;
                        self.hdr_len = 0;
                    } else {
                        self.payload_len = @intCast(len7);
                        if (self.payload_len > MAX_PAYLOAD) return .{ .err = error.PayloadTooLarge };
                        self.state = .need_mask;
                        self.hdr_len = 0;
                    }
                },

                .need_ext_len16 => {
                    const need = 2 - self.hdr_len;
                    const avail = new_bytes.len - pos;
                    const take = @min(need, avail);
                    @memcpy(self.hdr_buf[self.hdr_len..][0..take], new_bytes[pos..][0..take]);
                    self.hdr_len += take;
                    pos += take;

                    if (self.hdr_len < 2) return .incomplete;

                    self.payload_len = @intCast(std.mem.readInt(u16, self.hdr_buf[0..2], .big));
                    if (self.payload_len > MAX_PAYLOAD) return .{ .err = error.PayloadTooLarge };
                    self.state = .need_mask;
                    self.hdr_len = 0;
                },

                .need_ext_len64 => {
                    const need = 8 - self.hdr_len;
                    const avail = new_bytes.len - pos;
                    const take = @min(need, avail);
                    @memcpy(self.hdr_buf[self.hdr_len..][0..take], new_bytes[pos..][0..take]);
                    self.hdr_len += take;
                    pos += take;

                    if (self.hdr_len < 8) return .incomplete;

                    const len64 = std.mem.readInt(u64, self.hdr_buf[0..8], .big);
                    if (len64 > MAX_PAYLOAD) return .{ .err = error.PayloadTooLarge };
                    self.payload_len = @intCast(len64);
                    self.state = .need_mask;
                    self.hdr_len = 0;
                },

                .need_mask => {
                    const need = 4 - self.hdr_len;
                    const avail = new_bytes.len - pos;
                    const take = @min(need, avail);
                    @memcpy(self.hdr_buf[self.hdr_len..][0..take], new_bytes[pos..][0..take]);
                    self.hdr_len += take;
                    pos += take;

                    if (self.hdr_len < 4) return .incomplete;

                    @memcpy(&self.mask, self.hdr_buf[0..4]);
                    self.state = .need_payload;
                    self.payload_written = 0;

                    // Zero-payload frame: immediately complete.
                    if (self.payload_len == 0) {
                        self.state = .complete;
                        return .{ .complete = .{ .bytes_consumed = pos } };
                    }
                },

                .need_payload => {
                    const remaining_payload = self.payload_len - self.payload_written;
                    const avail = new_bytes.len - pos;
                    const take = @min(remaining_payload, avail);
                    @memcpy(self.payload_buf[self.payload_written..][0..take], new_bytes[pos..][0..take]);
                    self.payload_written += take;
                    pos += take;

                    if (self.payload_written >= self.payload_len) {
                        // Unmask in-place.
                        for (self.payload_buf[0..self.payload_len], 0..) |b, i| {
                            self.payload_buf[i] = b ^ self.mask[i & 3];
                        }
                        self.state = .complete;
                        return .{ .complete = .{ .bytes_consumed = pos } };
                    }
                    return .incomplete;
                },

                .complete => {
                    // Should not be called when already complete — caller
                    // must reset() between frames.
                    return .{ .complete = .{ .bytes_consumed = 0 } };
                },
            }
        }

        return .incomplete;
    }

    /// Return a Frame view of the parsed data. Only valid after
    /// `feed()` returns `.complete` and before the next `reset()`.
    pub fn getFrame(self: *FrameParser) wss_codec.Frame {
        return .{
            .opcode = self.opcode,
            .payload = self.payload_buf[0..self.payload_len],
        };
    }
};

// ─── Tests ───────────────────────────────────────────────────────────

/// Build a masked client→server frame in `buf`. Returns the bytes written.
fn buildMaskedFrame(opcode: wss_codec.Opcode, payload: []const u8, mask: [4]u8, buf: []u8) usize {
    var pos: usize = 0;
    buf[pos] = 0x80 | @as(u8, @intFromEnum(opcode)); // FIN | opcode
    pos += 1;

    if (payload.len < 126) {
        buf[pos] = 0x80 | @as(u8, @intCast(payload.len)); // MASK | len
        pos += 1;
    } else if (payload.len <= 0xFFFF) {
        buf[pos] = 0x80 | 126;
        pos += 1;
        std.mem.writeInt(u16, buf[pos..][0..2], @intCast(payload.len), .big);
        pos += 2;
    } else {
        buf[pos] = 0x80 | 127;
        pos += 1;
        std.mem.writeInt(u64, buf[pos..][0..8], @as(u64, payload.len), .big);
        pos += 8;
    }

    // Mask key
    @memcpy(buf[pos..][0..4], &mask);
    pos += 4;

    // Masked payload
    for (payload, 0..) |b, i| {
        buf[pos + i] = b ^ mask[i & 3];
    }
    pos += payload.len;
    return pos;
}

test "wss_frame_parser: simple text frame all at once" {
    const payload = "hello";
    const mask = [4]u8{ 0xAB, 0xCD, 0xEF, 0x01 };
    var frame_buf: [256]u8 = undefined;
    const frame_len = buildMaskedFrame(.text, payload, mask, &frame_buf);

    var parser = FrameParser.init();
    const result = parser.feed(frame_buf[0..frame_len]);
    try std.testing.expect(result == .complete);
    const frame = parser.getFrame();
    try std.testing.expect(frame.opcode == .text);
    try std.testing.expectEqualStrings(payload, frame.payload);
}

test "wss_frame_parser: bytes arrive one at a time" {
    const payload = "world";
    const mask = [4]u8{ 0x12, 0x34, 0x56, 0x78 };
    var frame_buf: [256]u8 = undefined;
    const frame_len = buildMaskedFrame(.text, payload, mask, &frame_buf);

    var parser = FrameParser.init();
    var done = false;
    for (frame_buf[0..frame_len], 0..) |_, i| {
        const chunk = frame_buf[i .. i + 1];
        const r = parser.feed(chunk);
        if (r == .complete) {
            done = true;
            break;
        }
        try std.testing.expect(r == .incomplete);
    }
    try std.testing.expect(done);
    const frame = parser.getFrame();
    try std.testing.expectEqualStrings(payload, frame.payload);
}

test "wss_frame_parser: close frame" {
    // Close frame: opcode 0x8, payload = 2-byte status code.
    const status_payload = [2]u8{ 0x03, 0xE8 }; // 1000 in big-endian
    const mask = [4]u8{ 0xAA, 0xBB, 0xCC, 0xDD };
    var frame_buf: [64]u8 = undefined;
    const frame_len = buildMaskedFrame(.close, &status_payload, mask, &frame_buf);

    var parser = FrameParser.init();
    const r = parser.feed(frame_buf[0..frame_len]);
    try std.testing.expect(r == .complete);
    const frame = parser.getFrame();
    try std.testing.expect(frame.opcode == .close);
    try std.testing.expectEqual(@as(usize, 2), frame.payload.len);
    // After unmasking, status code = 0x03E8 = 1000.
    const unmasked_status = std.mem.readInt(u16, frame.payload[0..2], .big);
    try std.testing.expectEqual(@as(u16, 1000), unmasked_status);
}

test "wss_frame_parser: ping frame zero payload" {
    const mask = [4]u8{ 0, 0, 0, 0 };
    var frame_buf: [64]u8 = undefined;
    const frame_len = buildMaskedFrame(.ping, &.{}, mask, &frame_buf);

    var parser = FrameParser.init();
    const r = parser.feed(frame_buf[0..frame_len]);
    try std.testing.expect(r == .complete);
    const frame = parser.getFrame();
    try std.testing.expect(frame.opcode == .ping);
    try std.testing.expectEqual(@as(usize, 0), frame.payload.len);
}

test "wss_frame_parser: 126-byte extended length" {
    var big_payload: [126]u8 = undefined;
    for (&big_payload, 0..) |*b, i| b.* = @intCast(i & 0xFF);

    const mask = [4]u8{ 0x01, 0x02, 0x03, 0x04 };
    var frame_buf: [256]u8 = undefined;
    const frame_len = buildMaskedFrame(.binary, &big_payload, mask, &frame_buf);

    var parser = FrameParser.init();
    const r = parser.feed(frame_buf[0..frame_len]);
    try std.testing.expect(r == .complete);
    const frame = parser.getFrame();
    try std.testing.expect(frame.opcode == .binary);
    try std.testing.expectEqual(@as(usize, 126), frame.payload.len);
}

test "wss_frame_parser: unmasked frame → error.NotMasked" {
    // Build an unmasked frame manually.
    var buf: [8]u8 = undefined;
    buf[0] = 0x81; // FIN | text
    buf[1] = 0x02; // NOT masked, len=2
    buf[2] = 'h';
    buf[3] = 'i';

    var parser = FrameParser.init();
    const r = parser.feed(buf[0..4]);
    try std.testing.expect(r == .err);
}

test "wss_frame_parser: fragmented frame → error.Fragmented" {
    // Build a frame with FIN=0.
    var buf: [8]u8 = undefined;
    buf[0] = 0x01; // FIN=0 | opcode=text
    buf[1] = 0x82; // MASK | len=2
    buf[2] = 0; buf[3] = 0; buf[4] = 0; buf[5] = 0; // mask
    buf[6] = 'x'; buf[7] = 'y'; // masked payload

    var parser = FrameParser.init();
    const r = parser.feed(buf[0..8]);
    try std.testing.expect(r == .err);
}

test "wss_frame_parser: reset between frames" {
    const payload = "abc";
    const mask = [4]u8{ 0x11, 0x22, 0x33, 0x44 };
    var frame_buf: [64]u8 = undefined;
    const frame_len = buildMaskedFrame(.text, payload, mask, &frame_buf);

    var parser = FrameParser.init();

    // First frame.
    var r = parser.feed(frame_buf[0..frame_len]);
    try std.testing.expect(r == .complete);
    var frame = parser.getFrame();
    try std.testing.expectEqualStrings(payload, frame.payload);

    // Reset and parse second (identical) frame.
    parser.reset();
    r = parser.feed(frame_buf[0..frame_len]);
    try std.testing.expect(r == .complete);
    frame = parser.getFrame();
    try std.testing.expectEqualStrings(payload, frame.payload);
}

test "wss_frame_parser: two frames in one chunk — only first consumed" {
    const p1 = "first";
    const p2 = "second";
    const mask = [4]u8{ 0xDE, 0xAD, 0xBE, 0xEF };
    var buf: [256]u8 = undefined;
    const len1 = buildMaskedFrame(.text, p1, mask, &buf);
    const len2 = buildMaskedFrame(.text, p2, mask, buf[len1..]);

    var parser = FrameParser.init();
    const r1 = parser.feed(buf[0 .. len1 + len2]);
    switch (r1) {
        .complete => |c| {
            // Should have consumed exactly the first frame.
            try std.testing.expectEqual(len1, c.bytes_consumed);
        },
        else => try std.testing.expect(false),
    }
    const frame1 = parser.getFrame();
    try std.testing.expectEqualStrings(p1, frame1.payload);

    // Second frame.
    parser.reset();
    const r2 = parser.feed(buf[len1 .. len1 + len2]);
    try std.testing.expect(r2 == .complete);
    const frame2 = parser.getFrame();
    try std.testing.expectEqualStrings(p2, frame2.payload);
}

```
