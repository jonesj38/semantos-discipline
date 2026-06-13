---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/wss_frame_parser_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.205065+00:00
---

# runtime/semantos-brain/tests/wss_frame_parser_conformance.zig

```zig
// wss_frame_parser_conformance.zig — WSS frame parser conformance tests
//
// Exercises wss_frame_parser through the build system's module imports.
// The unit tests in wss_frame_parser.zig cover the core cases; these
// add conformance cases matching real iOS client behaviour.

const std = @import("std");
const wss_codec = @import("wss_codec");
const wss_frame_parser = @import("wss_frame_parser");

const FrameParser = wss_frame_parser.FrameParser;

/// Build a masked frame using wss_codec.writeClientFrame via a pipe.
/// Returns the raw bytes written.
fn buildClientFrame(payload: []const u8, opcode: wss_codec.Opcode, out: []u8) !usize {
    // Use a fixed mask for determinism.
    const mask = [4]u8{ 0xA5, 0xA5, 0xA5, 0xA5 };
    var pos: usize = 0;
    out[pos] = 0x80 | @as(u8, @intFromEnum(opcode));
    pos += 1;

    if (payload.len < 126) {
        out[pos] = 0x80 | @as(u8, @intCast(payload.len));
        pos += 1;
    } else if (payload.len <= 0xFFFF) {
        out[pos] = 0x80 | 126;
        pos += 1;
        std.mem.writeInt(u16, out[pos..][0..2], @intCast(payload.len), .big);
        pos += 2;
    }

    @memcpy(out[pos..][0..4], &mask);
    pos += 4;

    for (payload, 0..) |b, i| out[pos + i] = b ^ mask[i & 3];
    pos += payload.len;
    return pos;
}

test "wss_frame_parser_conformance: JSON-RPC wallet.getVersion frame" {
    const json = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"wallet.getVersion\",\"params\":{}}";
    var frame_buf: [256]u8 = undefined;
    const n = try buildClientFrame(json, .text, &frame_buf);

    var parser = FrameParser.init();
    const r = parser.feed(frame_buf[0..n]);
    try std.testing.expect(r == .complete);
    const frame = parser.getFrame();
    try std.testing.expect(frame.opcode == .text);
    try std.testing.expectEqualStrings(json, frame.payload);
}

test "wss_frame_parser_conformance: close frame with 1000 status" {
    // Status 1000 big-endian.
    const payload = [2]u8{ 0x03, 0xE8 };
    const mask = [4]u8{ 0x01, 0x02, 0x03, 0x04 };
    var buf: [16]u8 = undefined;
    buf[0] = 0x88; // FIN | close
    buf[1] = 0x82; // MASK | len=2
    @memcpy(buf[2..6], &mask);
    buf[6] = payload[0] ^ mask[0];
    buf[7] = payload[1] ^ mask[1];

    var parser = FrameParser.init();
    const r = parser.feed(buf[0..8]);
    try std.testing.expect(r == .complete);
    const frame = parser.getFrame();
    try std.testing.expect(frame.opcode == .close);
    // Unmasked payload should be the original status bytes.
    try std.testing.expectEqual(@as(u8, 0x03), frame.payload[0]);
    try std.testing.expectEqual(@as(u8, 0xE8), frame.payload[1]);
}

test "wss_frame_parser_conformance: ping followed by text — parser handles both" {
    const ping_mask = [4]u8{ 0, 0, 0, 0 };
    const text_msg = "hello";
    const text_mask = [4]u8{ 0xFF, 0xFF, 0xFF, 0xFF };

    var buf: [256]u8 = undefined;
    // Build ping frame.
    buf[0] = 0x89; // FIN | ping
    buf[1] = 0x80; // MASK | len=0
    @memcpy(buf[2..6], &ping_mask);
    const ping_len: usize = 6;

    // Build text frame after ping.
    var pos: usize = ping_len;
    buf[pos] = 0x81; // FIN | text
    pos += 1;
    buf[pos] = 0x80 | @as(u8, @intCast(text_msg.len)); // MASK | len
    pos += 1;
    @memcpy(buf[pos..][0..4], &text_mask);
    pos += 4;
    for (text_msg, 0..) |b, i| buf[pos + i] = b ^ text_mask[i & 3];
    pos += text_msg.len;

    var parser = FrameParser.init();

    // Parse ping.
    const r1 = parser.feed(buf[0..pos]);
    switch (r1) {
        .complete => |c| {
            try std.testing.expectEqual(ping_len, c.bytes_consumed);
            const frame = parser.getFrame();
            try std.testing.expect(frame.opcode == .ping);
            // Parse text frame with remaining bytes.
            parser.reset();
            const r2 = parser.feed(buf[ping_len..pos]);
            try std.testing.expect(r2 == .complete);
            const text_frame = parser.getFrame();
            try std.testing.expect(text_frame.opcode == .text);
            try std.testing.expectEqualStrings(text_msg, text_frame.payload);
        },
        else => try std.testing.expect(false),
    }
}

```
