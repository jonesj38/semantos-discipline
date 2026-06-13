---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/wss_codec_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.196694+00:00
---

# runtime/semantos-brain/tests/wss_codec_conformance.zig

```zig
// Phase Brain 4.5 — wss_codec conformance tests.
//
// Reference: docs/design/WALLET-SHELL-VPS-SUBSTRATE.md §3 (Brain 4 — WSS).
//
// These tests run the codec entirely in-process — no real socket. They
// exercise:
//
//   • computeAccept against the RFC 6455 §1.3 worked example
//   • round-trip text frames over a localhost socketpair
//   • masked client→server enforcement
//   • close-frame status code encoding
//   • payload size limits (one byte over the cap returns PayloadTooLarge)
//
// Larger end-to-end tests (full handshake + JSON-RPC dispatch) live in
// wss_wallet_conformance.zig and use a localhost listener + client.

const std = @import("std");
const wss_codec = @import("wss_codec");

test "computeAccept matches RFC 6455 §1.3 worked example" {
    var out: [28]u8 = undefined;
    wss_codec.computeAccept("dGhlIHNhbXBsZSBub25jZQ==", &out);
    try std.testing.expectEqualSlices(u8, "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=", &out);
}

test "round-trip text frame over a socketpair" {
    const allocator = std.testing.allocator;

    // Bring up a listener on 127.0.0.1:<random> and connect to it.
    const addr = try std.net.Address.parseIp4("127.0.0.1", 0);
    var listener = try addr.listen(.{ .reuse_address = true });
    defer listener.deinit();

    const bound = listener.listen_address;
    const client = try std.net.tcpConnectToAddress(bound);
    defer client.close();

    const accepted = try listener.accept();
    defer accepted.stream.close();

    // Client writes a masked frame (matches what a real WS client would
    // send post-handshake).
    const payload = "{\"hello\":\"world\"}";
    try wss_codec.writeClientFrame(client, .text, payload);

    // Server reads and unmasks.
    const frame = try wss_codec.readFrame(allocator, accepted.stream, 64 * 1024);
    defer allocator.free(frame.payload);
    try std.testing.expect(frame.opcode == .text);
    try std.testing.expectEqualSlices(u8, payload, frame.payload);

    // Server replies with an unmasked frame.
    const reply = "{\"ok\":true}";
    try wss_codec.writeFrame(accepted.stream, .text, reply);

    // Client reads it.
    const got = try wss_codec.readClientFrame(allocator, client, 64 * 1024);
    defer allocator.free(got.payload);
    try std.testing.expect(got.opcode == .text);
    try std.testing.expectEqualSlices(u8, reply, got.payload);
}

test "unmasked client frame rejected" {
    const allocator = std.testing.allocator;
    const addr = try std.net.Address.parseIp4("127.0.0.1", 0);
    var listener = try addr.listen(.{ .reuse_address = true });
    defer listener.deinit();
    const client = try std.net.tcpConnectToAddress(listener.listen_address);
    defer client.close();
    const accepted = try listener.accept();
    defer accepted.stream.close();

    // Send an UNMASKED text frame using the server-side writer (which
    // doesn't mask) — the server's readFrame must reject it.
    try wss_codec.writeFrame(client, .text, "x");

    const result = wss_codec.readFrame(allocator, accepted.stream, 64);
    try std.testing.expectError(error.NotMasked, result);
}

test "payload too large returns PayloadTooLarge" {
    const allocator = std.testing.allocator;
    const addr = try std.net.Address.parseIp4("127.0.0.1", 0);
    var listener = try addr.listen(.{ .reuse_address = true });
    defer listener.deinit();
    const client = try std.net.tcpConnectToAddress(listener.listen_address);
    defer client.close();
    const accepted = try listener.accept();
    defer accepted.stream.close();

    // 200-byte masked client frame; cap at 100.
    var big = [_]u8{'A'} ** 200;
    try wss_codec.writeClientFrame(client, .text, &big);

    const result = wss_codec.readFrame(allocator, accepted.stream, 100);
    try std.testing.expectError(error.PayloadTooLarge, result);
}

test "writeClose encodes status code in payload" {
    const allocator = std.testing.allocator;
    const addr = try std.net.Address.parseIp4("127.0.0.1", 0);
    var listener = try addr.listen(.{ .reuse_address = true });
    defer listener.deinit();
    const client = try std.net.tcpConnectToAddress(listener.listen_address);
    defer client.close();
    const accepted = try listener.accept();
    defer accepted.stream.close();

    try wss_codec.writeClose(accepted.stream, 1000, "bye");
    const got = try wss_codec.readClientFrame(allocator, client, 64);
    defer allocator.free(got.payload);
    try std.testing.expect(got.opcode == .close);
    try std.testing.expect(got.payload.len == 5);
    const code = std.mem.readInt(u16, got.payload[0..2], .big);
    try std.testing.expectEqual(@as(u16, 1000), code);
    try std.testing.expectEqualSlices(u8, "bye", got.payload[2..]);
}

```
