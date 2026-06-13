---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/wss_wallet_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.210624+00:00
---

# runtime/semantos-brain/tests/wss_wallet_conformance.zig

```zig
// Phase Brain 4.5 — wss_wallet conformance tests.
//
// Reference: docs/design/WALLET-SHELL-VPS-SUBSTRATE.md §3 (Brain 4 — WSS).
//
// These tests bring up a real localhost listener, accept one connection,
// and run the full brain wallet endpoint flow against it from a synthetic
// client. They exercise:
//
//   • happy path: handshake → wallet.getVersion → close
//   • bad-bearer: rejected at upgrade with 401
//   • missing-bearer: rejected with 401
//   • method-not-found: returns JSON-RPC -32601
//   • parse-error: returns JSON-RPC -32700
//   • close frame: server echoes close back
//
// The handshake here drives `wss_wallet.tryUpgrade` indirectly via a
// std.http.Server.Request constructed from the client's GET. For
// simplicity we don't run the full `site_server.handleConnection` —
// the dispatch path it adds is straight delegation.

const std = @import("std");
const bearer_tokens = @import("bearer_tokens");
const wss_codec = @import("wss_codec");
const wss_wallet = @import("wss_wallet");
const helm_event_broker = @import("helm_event_broker");

const TokenStore = bearer_tokens.TokenStore;

var pinned_clock: i64 = 1_700_000_000;
fn fixedClock() i64 {
    return pinned_clock;
}

const Bound = struct {
    listener: std.net.Server,
    address: std.net.Address,

    fn deinit(self: *Bound) void {
        self.listener.deinit();
    }
};

fn bindLoopback() !Bound {
    const addr = try std.net.Address.parseIp4("127.0.0.1", 0);
    const listener = try addr.listen(.{ .reuse_address = true });
    return .{ .listener = listener, .address = listener.listen_address };
}

/// Drive one full handshake → JSON-RPC → close session from the server
/// side. Runs to completion (returns when the client closes or we close
/// on protocol violation).
fn serveOne(allocator: std.mem.Allocator, listener: *std.net.Server, backend: *wss_wallet.Backend) !void {
    const conn = try listener.accept();
    defer conn.stream.close();

    var read_buf: [8192]u8 = undefined;
    var write_buf: [16384]u8 = undefined;
    var read_iface = conn.stream.reader(&read_buf);
    var write_iface = conn.stream.writer(&write_buf);
    var server = std.http.Server.init(read_iface.interface(), &write_iface.interface);

    var request = try server.receiveHead();
    var auth_token_id: [32]u8 = undefined;
    const result = try wss_wallet.tryUpgrade(&request, backend, conn.stream, &auth_token_id);
    if (result == .upgraded) {
        wss_wallet.serveSession(allocator, conn.stream, backend) catch {};
    }
}

// ── Helpers for synthesising a 64-hex bearer from a TokenStore-issued raw ──

fn hexEncodeRaw(raw: *const [32]u8, out: *[64]u8) void {
    const hex_chars = "0123456789abcdef";
    for (raw, 0..) |b, i| {
        out[i * 2] = hex_chars[(b >> 4) & 0xF];
        out[i * 2 + 1] = hex_chars[b & 0xF];
    }
}

// ── Tests ─────────────────────────────────────────────────────────────

test "Brain 4.5 happy path: handshake + wallet.getVersion" {
    pinned_clock = 1_700_000_000;
    const allocator = std.testing.allocator;

    // ── Backend setup ──
    const dir = std.testing.tmpDir(.{});
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try dir.dir.realpath(".", &path_buf);
    var tokens = try TokenStore.init(allocator, path, fixedClock);
    defer tokens.deinit();
    const issued = try tokens.issue("test", 0);
    var token_hex: [64]u8 = undefined;
    hexEncodeRaw(&issued.token, &token_hex);

    var backend = wss_wallet.Backend{ .tokens = &tokens };

    // ── Bring up the server in a thread ──
    var bound = try bindLoopback();
    defer bound.deinit();

    const ServerCtx = struct { listener: *std.net.Server, backend: *wss_wallet.Backend, alloc: std.mem.Allocator };
    var ctx = ServerCtx{ .listener = &bound.listener, .backend = &backend, .alloc = allocator };
    const t = try std.Thread.spawn(.{}, struct {
        fn run(c: *ServerCtx) void {
            serveOne(c.alloc, c.listener, c.backend) catch {};
        }
    }.run, .{&ctx});
    defer t.join();

    // ── Client opens the connection + does handshake with bearer ──
    const client = try std.net.tcpConnectToAddress(bound.address);
    defer client.close();

    var auth_buf: [128]u8 = undefined;
    const auth_header = try std.fmt.bufPrint(
        &auth_buf,
        "Authorization: Bearer {s}\r\n",
        .{&token_hex},
    );
    try wss_codec.clientHandshake(client, "127.0.0.1", "/api/v1/wallet", auth_header);

    // ── Send getVersion ──
    const req = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"wallet.getVersion\"}";
    try wss_codec.writeClientFrame(client, .text, req);

    // ── Read response ──
    const got = try wss_codec.readClientFrame(allocator, client, 16 * 1024);
    defer allocator.free(got.payload);
    try std.testing.expect(got.opcode == .text);
    // Quick structural sanity — must be a JSON-RPC result with id=1 and a
    // version field.
    try std.testing.expect(std.mem.indexOf(u8, got.payload, "\"jsonrpc\":\"2.0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, got.payload, "\"id\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, got.payload, "\"result\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, got.payload, "\"version\":\"brain-0.1\"") != null);

    // ── Close cleanly ──
    try wss_codec.writeClientFrame(client, .close, &[_]u8{ 0x03, 0xE8 });
}

test "Brain 4.5 wallet.getNetwork reflects backend network field" {
    pinned_clock = 1_700_000_000;
    const allocator = std.testing.allocator;
    const dir = std.testing.tmpDir(.{});
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try dir.dir.realpath(".", &path_buf);
    var tokens = try TokenStore.init(allocator, path, fixedClock);
    defer tokens.deinit();
    const issued = try tokens.issue("test", 0);
    var token_hex: [64]u8 = undefined;
    hexEncodeRaw(&issued.token, &token_hex);

    var backend = wss_wallet.Backend{ .tokens = &tokens, .network = .testnet };

    var bound = try bindLoopback();
    defer bound.deinit();

    const ServerCtx = struct { listener: *std.net.Server, backend: *wss_wallet.Backend, alloc: std.mem.Allocator };
    var ctx = ServerCtx{ .listener = &bound.listener, .backend = &backend, .alloc = allocator };
    const t = try std.Thread.spawn(.{}, struct {
        fn run(c: *ServerCtx) void {
            serveOne(c.alloc, c.listener, c.backend) catch {};
        }
    }.run, .{&ctx});
    defer t.join();

    const client = try std.net.tcpConnectToAddress(bound.address);
    defer client.close();
    var auth_buf: [128]u8 = undefined;
    const auth_header = try std.fmt.bufPrint(
        &auth_buf,
        "Authorization: Bearer {s}\r\n",
        .{&token_hex},
    );
    try wss_codec.clientHandshake(client, "127.0.0.1", "/api/v1/wallet", auth_header);
    try wss_codec.writeClientFrame(client, .text, "{\"jsonrpc\":\"2.0\",\"id\":42,\"method\":\"wallet.getNetwork\"}");

    const got = try wss_codec.readClientFrame(allocator, client, 16 * 1024);
    defer allocator.free(got.payload);
    try std.testing.expect(std.mem.indexOf(u8, got.payload, "\"network\":\"testnet\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, got.payload, "\"id\":42") != null);

    try wss_codec.writeClientFrame(client, .close, &[_]u8{ 0x03, 0xE8 });
}

test "Brain 4.5 method not found returns JSON-RPC -32601" {
    pinned_clock = 1_700_000_000;
    const allocator = std.testing.allocator;
    const dir = std.testing.tmpDir(.{});
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try dir.dir.realpath(".", &path_buf);
    var tokens = try TokenStore.init(allocator, path, fixedClock);
    defer tokens.deinit();
    const issued = try tokens.issue("test", 0);
    var token_hex: [64]u8 = undefined;
    hexEncodeRaw(&issued.token, &token_hex);

    var backend = wss_wallet.Backend{ .tokens = &tokens };
    var bound = try bindLoopback();
    defer bound.deinit();

    const ServerCtx = struct { listener: *std.net.Server, backend: *wss_wallet.Backend, alloc: std.mem.Allocator };
    var ctx = ServerCtx{ .listener = &bound.listener, .backend = &backend, .alloc = allocator };
    const t = try std.Thread.spawn(.{}, struct {
        fn run(c: *ServerCtx) void {
            serveOne(c.alloc, c.listener, c.backend) catch {};
        }
    }.run, .{&ctx});
    defer t.join();

    const client = try std.net.tcpConnectToAddress(bound.address);
    defer client.close();
    var auth_buf: [128]u8 = undefined;
    const auth_header = try std.fmt.bufPrint(
        &auth_buf,
        "Authorization: Bearer {s}\r\n",
        .{&token_hex},
    );
    try wss_codec.clientHandshake(client, "127.0.0.1", "/api/v1/wallet", auth_header);
    try wss_codec.writeClientFrame(client, .text, "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"wallet.notARealMethod\"}");

    const got = try wss_codec.readClientFrame(allocator, client, 16 * 1024);
    defer allocator.free(got.payload);
    try std.testing.expect(std.mem.indexOf(u8, got.payload, "\"code\":-32601") != null);
    try std.testing.expect(std.mem.indexOf(u8, got.payload, "method not found: wallet.notARealMethod") != null);

    try wss_codec.writeClientFrame(client, .close, &[_]u8{ 0x03, 0xE8 });
}

test "Brain 4.5 parse-error returns JSON-RPC -32700" {
    pinned_clock = 1_700_000_000;
    const allocator = std.testing.allocator;
    const dir = std.testing.tmpDir(.{});
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try dir.dir.realpath(".", &path_buf);
    var tokens = try TokenStore.init(allocator, path, fixedClock);
    defer tokens.deinit();
    const issued = try tokens.issue("test", 0);
    var token_hex: [64]u8 = undefined;
    hexEncodeRaw(&issued.token, &token_hex);

    var backend = wss_wallet.Backend{ .tokens = &tokens };
    var bound = try bindLoopback();
    defer bound.deinit();

    const ServerCtx = struct { listener: *std.net.Server, backend: *wss_wallet.Backend, alloc: std.mem.Allocator };
    var ctx = ServerCtx{ .listener = &bound.listener, .backend = &backend, .alloc = allocator };
    const t = try std.Thread.spawn(.{}, struct {
        fn run(c: *ServerCtx) void {
            serveOne(c.alloc, c.listener, c.backend) catch {};
        }
    }.run, .{&ctx});
    defer t.join();

    const client = try std.net.tcpConnectToAddress(bound.address);
    defer client.close();
    var auth_buf: [128]u8 = undefined;
    const auth_header = try std.fmt.bufPrint(
        &auth_buf,
        "Authorization: Bearer {s}\r\n",
        .{&token_hex},
    );
    try wss_codec.clientHandshake(client, "127.0.0.1", "/api/v1/wallet", auth_header);
    try wss_codec.writeClientFrame(client, .text, "this is { not valid JSON");

    const got = try wss_codec.readClientFrame(allocator, client, 16 * 1024);
    defer allocator.free(got.payload);
    try std.testing.expect(std.mem.indexOf(u8, got.payload, "\"code\":-32700") != null);

    try wss_codec.writeClientFrame(client, .close, &[_]u8{ 0x03, 0xE8 });
}

test "Brain 4.5 missing bearer rejected at upgrade with 401" {
    pinned_clock = 1_700_000_000;
    const allocator = std.testing.allocator;
    const dir = std.testing.tmpDir(.{});
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try dir.dir.realpath(".", &path_buf);
    var tokens = try TokenStore.init(allocator, path, fixedClock);
    defer tokens.deinit();
    var backend = wss_wallet.Backend{ .tokens = &tokens };

    var bound = try bindLoopback();
    defer bound.deinit();

    const ServerCtx = struct { listener: *std.net.Server, backend: *wss_wallet.Backend, alloc: std.mem.Allocator };
    var ctx = ServerCtx{ .listener = &bound.listener, .backend = &backend, .alloc = allocator };
    const t = try std.Thread.spawn(.{}, struct {
        fn run(c: *ServerCtx) void {
            serveOne(c.alloc, c.listener, c.backend) catch {};
        }
    }.run, .{&ctx});
    defer t.join();

    const client = try std.net.tcpConnectToAddress(bound.address);
    defer client.close();

    // Send the WS upgrade request directly — no Authorization header.
    const raw_req =
        "GET /api/v1/wallet HTTP/1.1\r\n" ++
        "Host: 127.0.0.1\r\n" ++
        "Upgrade: websocket\r\n" ++
        "Connection: Upgrade\r\n" ++
        "Sec-WebSocket-Key: AAAAAAAAAAAAAAAAAAAAAA==\r\n" ++
        "Sec-WebSocket-Version: 13\r\n" ++
        "\r\n";
    try client.writeAll(raw_req);

    var resp_buf: [4096]u8 = undefined;
    var total: usize = 0;
    while (total < resp_buf.len) {
        const n = try client.read(resp_buf[total..]);
        if (n == 0) break;
        total += n;
        if (std.mem.indexOf(u8, resp_buf[0..total], "\r\n\r\n") != null) break;
    }
    const status_line = resp_buf[0..@min(total, 16)];
    try std.testing.expect(std.mem.indexOf(u8, status_line, "401") != null);
}

test "Brain 4.5 ?bearer= query string fallback for browser clients" {
    pinned_clock = 1_700_000_000;
    const allocator = std.testing.allocator;
    const dir = std.testing.tmpDir(.{});
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try dir.dir.realpath(".", &path_buf);
    var tokens = try TokenStore.init(allocator, path, fixedClock);
    defer tokens.deinit();
    const issued = try tokens.issue("test", 0);
    var token_hex: [64]u8 = undefined;
    hexEncodeRaw(&issued.token, &token_hex);

    var backend = wss_wallet.Backend{ .tokens = &tokens };
    var bound = try bindLoopback();
    defer bound.deinit();

    const ServerCtx = struct { listener: *std.net.Server, backend: *wss_wallet.Backend, alloc: std.mem.Allocator };
    var ctx = ServerCtx{ .listener = &bound.listener, .backend = &backend, .alloc = allocator };
    const t = try std.Thread.spawn(.{}, struct {
        fn run(c: *ServerCtx) void {
            serveOne(c.alloc, c.listener, c.backend) catch {};
        }
    }.run, .{&ctx});
    defer t.join();

    const client = try std.net.tcpConnectToAddress(bound.address);
    defer client.close();

    var path_buf2: [128]u8 = undefined;
    const ws_path = try std.fmt.bufPrint(&path_buf2, "/api/v1/wallet?bearer={s}", .{&token_hex});
    try wss_codec.clientHandshake(client, "127.0.0.1", ws_path, "");

    try wss_codec.writeClientFrame(client, .text, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"wallet.getVersion\"}");
    const got = try wss_codec.readClientFrame(allocator, client, 16 * 1024);
    defer allocator.free(got.payload);
    try std.testing.expect(std.mem.indexOf(u8, got.payload, "\"version\":\"brain-0.1\"") != null);

    try wss_codec.writeClientFrame(client, .close, &[_]u8{ 0x03, 0xE8 });
}

// ─── D-O5.followup-4 — helm.subscribe / helm.event live-tick stream ──
//
// helm.subscribe registers the WSS connection with the per-process
// broker; subsequent broker.publish calls fan out to every registered
// connection as `helm.event` JSON-RPC notification frames.  These
// tests bring up a real localhost listener with a wired broker and
// drive the round-trip from a synthetic client.

test "Brain 4.5 helm.subscribe round-trip returns subscribed=true + topics" {
    pinned_clock = 1_700_000_000;
    const allocator = std.testing.allocator;
    const dir = std.testing.tmpDir(.{});
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try dir.dir.realpath(".", &path_buf);
    var tokens = try TokenStore.init(allocator, path, fixedClock);
    defer tokens.deinit();
    const issued = try tokens.issue("test", 0);
    var token_hex: [64]u8 = undefined;
    hexEncodeRaw(&issued.token, &token_hex);

    var broker = helm_event_broker.Broker.init(allocator);
    defer broker.deinit();
    var backend = wss_wallet.Backend{ .tokens = &tokens, .helm_broker = &broker };

    var bound = try bindLoopback();
    defer bound.deinit();

    const ServerCtx = struct { listener: *std.net.Server, backend: *wss_wallet.Backend, alloc: std.mem.Allocator };
    var ctx = ServerCtx{ .listener = &bound.listener, .backend = &backend, .alloc = allocator };
    const t = try std.Thread.spawn(.{}, struct {
        fn run(c: *ServerCtx) void {
            serveOne(c.alloc, c.listener, c.backend) catch {};
        }
    }.run, .{&ctx});
    defer t.join();

    const client = try std.net.tcpConnectToAddress(bound.address);
    defer client.close();
    var auth_buf: [128]u8 = undefined;
    const auth_header = try std.fmt.bufPrint(
        &auth_buf,
        "Authorization: Bearer {s}\r\n",
        .{&token_hex},
    );
    try wss_codec.clientHandshake(client, "127.0.0.1", "/api/v1/wallet", auth_header);

    // Issue helm.subscribe with a multi-topic list.
    try wss_codec.writeClientFrame(client, .text,
        \\{"jsonrpc":"2.0","id":42,"method":"helm.subscribe","params":{"topics":["jobs","customers"]}}
    );

    const got = try wss_codec.readClientFrame(allocator, client, 16 * 1024);
    defer allocator.free(got.payload);
    try std.testing.expect(std.mem.indexOf(u8, got.payload, "\"id\":42") != null);
    try std.testing.expect(std.mem.indexOf(u8, got.payload, "\"subscribed\":true") != null);
    // Topics array round-trip preserves both entries in order.
    try std.testing.expect(std.mem.indexOf(u8, got.payload, "\"topics\":[\"jobs\",\"customers\"]") != null);

    try wss_codec.writeClientFrame(client, .close, &[_]u8{ 0x03, 0xE8 });
}

test "Brain 4.5 helm.event notification frame format after broker.publish" {
    pinned_clock = 1_700_000_000;
    const allocator = std.testing.allocator;
    const dir = std.testing.tmpDir(.{});
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try dir.dir.realpath(".", &path_buf);
    var tokens = try TokenStore.init(allocator, path, fixedClock);
    defer tokens.deinit();
    const issued = try tokens.issue("test", 0);
    var token_hex: [64]u8 = undefined;
    hexEncodeRaw(&issued.token, &token_hex);

    var broker = helm_event_broker.Broker.init(allocator);
    defer broker.deinit();
    var backend = wss_wallet.Backend{ .tokens = &tokens, .helm_broker = &broker };

    var bound = try bindLoopback();
    defer bound.deinit();

    const ServerCtx = struct { listener: *std.net.Server, backend: *wss_wallet.Backend, alloc: std.mem.Allocator };
    var ctx = ServerCtx{ .listener = &bound.listener, .backend = &backend, .alloc = allocator };
    const t = try std.Thread.spawn(.{}, struct {
        fn run(c: *ServerCtx) void {
            // Run a longer session so the publish + close window
            // gives the server thread time to flush notifications
            // before the client teardown.  The wss_wallet read loop
            // returns on EOF; the client closes after reading the
            // event frame, which propagates back as EOF here.
            serveOne(c.alloc, c.listener, c.backend) catch {};
        }
    }.run, .{&ctx});
    defer t.join();

    const client = try std.net.tcpConnectToAddress(bound.address);
    defer client.close();
    var auth_buf: [128]u8 = undefined;
    const auth_header = try std.fmt.bufPrint(
        &auth_buf,
        "Authorization: Bearer {s}\r\n",
        .{&token_hex},
    );
    try wss_codec.clientHandshake(client, "127.0.0.1", "/api/v1/wallet", auth_header);

    // Subscribe to the jobs topic.
    try wss_codec.writeClientFrame(client, .text,
        \\{"jsonrpc":"2.0","id":1,"method":"helm.subscribe","params":{"topics":["jobs"]}}
    );
    const sub_resp = try wss_codec.readClientFrame(allocator, client, 16 * 1024);
    defer allocator.free(sub_resp.payload);
    try std.testing.expect(std.mem.indexOf(u8, sub_resp.payload, "\"subscribed\":true") != null);

    // Publish a job.transitioned event.  The server-side callback
    // writes a `helm.event` notification frame on the same stream.
    broker.publish(.{
        .type = "job.transitioned",
        .payload_json =
            \\{"id":"job-001","from":"lead","to":"quoted","transitioned_at":"2026-05-02T14:30:00Z"}
        ,
    });

    const event_frame = try wss_codec.readClientFrame(allocator, client, 16 * 1024);
    defer allocator.free(event_frame.payload);
    try std.testing.expect(event_frame.opcode == .text);
    // JSON-RPC notification — id absent, method=helm.event.
    try std.testing.expect(std.mem.indexOf(u8, event_frame.payload, "\"jsonrpc\":\"2.0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, event_frame.payload, "\"method\":\"helm.event\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, event_frame.payload, "\"type\":\"job.transitioned\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, event_frame.payload, "\"id\":\"job-001\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, event_frame.payload, "\"from\":\"lead\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, event_frame.payload, "\"to\":\"quoted\"") != null);

    try wss_codec.writeClientFrame(client, .close, &[_]u8{ 0x03, 0xE8 });
}

test "Brain 4.5 helm.event filters by topic — non-subscribed topic dropped" {
    pinned_clock = 1_700_000_000;
    const allocator = std.testing.allocator;
    const dir = std.testing.tmpDir(.{});
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try dir.dir.realpath(".", &path_buf);
    var tokens = try TokenStore.init(allocator, path, fixedClock);
    defer tokens.deinit();
    const issued = try tokens.issue("test", 0);
    var token_hex: [64]u8 = undefined;
    hexEncodeRaw(&issued.token, &token_hex);

    var broker = helm_event_broker.Broker.init(allocator);
    defer broker.deinit();
    var backend = wss_wallet.Backend{ .tokens = &tokens, .helm_broker = &broker };

    var bound = try bindLoopback();
    defer bound.deinit();

    const ServerCtx = struct { listener: *std.net.Server, backend: *wss_wallet.Backend, alloc: std.mem.Allocator };
    var ctx = ServerCtx{ .listener = &bound.listener, .backend = &backend, .alloc = allocator };
    const t = try std.Thread.spawn(.{}, struct {
        fn run(c: *ServerCtx) void {
            serveOne(c.alloc, c.listener, c.backend) catch {};
        }
    }.run, .{&ctx});
    defer t.join();

    const client = try std.net.tcpConnectToAddress(bound.address);
    defer client.close();
    var auth_buf: [128]u8 = undefined;
    const auth_header = try std.fmt.bufPrint(
        &auth_buf,
        "Authorization: Bearer {s}\r\n",
        .{&token_hex},
    );
    try wss_codec.clientHandshake(client, "127.0.0.1", "/api/v1/wallet", auth_header);

    // Subscribe to ONLY the customers topic.
    try wss_codec.writeClientFrame(client, .text,
        \\{"jsonrpc":"2.0","id":1,"method":"helm.subscribe","params":{"topics":["customers"]}}
    );
    const sub_resp = try wss_codec.readClientFrame(allocator, client, 16 * 1024);
    defer allocator.free(sub_resp.payload);

    // Publish a job.transitioned event — our connection should NOT
    // receive it because we didn't subscribe to "jobs".  Then publish
    // a customer.created event — our connection SHOULD receive that.
    broker.publish(.{
        .type = "job.transitioned",
        .payload_json = "{\"id\":\"job-001\"}",
    });
    broker.publish(.{
        .type = "customer.created",
        .payload_json = "{\"id\":\"cust-001\"}",
    });

    const event_frame = try wss_codec.readClientFrame(allocator, client, 16 * 1024);
    defer allocator.free(event_frame.payload);
    // The first frame we read MUST be the customer event — the job
    // event was filtered out per the topic mapping.
    try std.testing.expect(std.mem.indexOf(u8, event_frame.payload, "\"type\":\"customer.created\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, event_frame.payload, "\"id\":\"cust-001\"") != null);

    try wss_codec.writeClientFrame(client, .close, &[_]u8{ 0x03, 0xE8 });
}

test "Brain 4.5 helm.subscribe rejects empty/unknown topics with -32602" {
    pinned_clock = 1_700_000_000;
    const allocator = std.testing.allocator;
    const dir = std.testing.tmpDir(.{});
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try dir.dir.realpath(".", &path_buf);
    var tokens = try TokenStore.init(allocator, path, fixedClock);
    defer tokens.deinit();
    const issued = try tokens.issue("test", 0);
    var token_hex: [64]u8 = undefined;
    hexEncodeRaw(&issued.token, &token_hex);

    var broker = helm_event_broker.Broker.init(allocator);
    defer broker.deinit();
    var backend = wss_wallet.Backend{ .tokens = &tokens, .helm_broker = &broker };

    var bound = try bindLoopback();
    defer bound.deinit();

    const ServerCtx = struct { listener: *std.net.Server, backend: *wss_wallet.Backend, alloc: std.mem.Allocator };
    var ctx = ServerCtx{ .listener = &bound.listener, .backend = &backend, .alloc = allocator };
    const t = try std.Thread.spawn(.{}, struct {
        fn run(c: *ServerCtx) void {
            serveOne(c.alloc, c.listener, c.backend) catch {};
        }
    }.run, .{&ctx});
    defer t.join();

    const client = try std.net.tcpConnectToAddress(bound.address);
    defer client.close();
    var auth_buf: [128]u8 = undefined;
    const auth_header = try std.fmt.bufPrint(
        &auth_buf,
        "Authorization: Bearer {s}\r\n",
        .{&token_hex},
    );
    try wss_codec.clientHandshake(client, "127.0.0.1", "/api/v1/wallet", auth_header);

    // Unknown topic.
    try wss_codec.writeClientFrame(client, .text,
        \\{"jsonrpc":"2.0","id":7,"method":"helm.subscribe","params":{"topics":["nonsense"]}}
    );
    const got = try wss_codec.readClientFrame(allocator, client, 16 * 1024);
    defer allocator.free(got.payload);
    try std.testing.expect(std.mem.indexOf(u8, got.payload, "\"code\":-32602") != null);
    try std.testing.expect(std.mem.indexOf(u8, got.payload, "unknown topic") != null);

    try wss_codec.writeClientFrame(client, .close, &[_]u8{ 0x03, 0xE8 });
}

test "Brain 4.5 helm.unsubscribe stops further events" {
    pinned_clock = 1_700_000_000;
    const allocator = std.testing.allocator;
    const dir = std.testing.tmpDir(.{});
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try dir.dir.realpath(".", &path_buf);
    var tokens = try TokenStore.init(allocator, path, fixedClock);
    defer tokens.deinit();
    const issued = try tokens.issue("test", 0);
    var token_hex: [64]u8 = undefined;
    hexEncodeRaw(&issued.token, &token_hex);

    var broker = helm_event_broker.Broker.init(allocator);
    defer broker.deinit();
    var backend = wss_wallet.Backend{ .tokens = &tokens, .helm_broker = &broker };

    var bound = try bindLoopback();
    defer bound.deinit();

    const ServerCtx = struct { listener: *std.net.Server, backend: *wss_wallet.Backend, alloc: std.mem.Allocator };
    var ctx = ServerCtx{ .listener = &bound.listener, .backend = &backend, .alloc = allocator };
    const t = try std.Thread.spawn(.{}, struct {
        fn run(c: *ServerCtx) void {
            serveOne(c.alloc, c.listener, c.backend) catch {};
        }
    }.run, .{&ctx});
    defer t.join();

    const client = try std.net.tcpConnectToAddress(bound.address);
    defer client.close();
    var auth_buf: [128]u8 = undefined;
    const auth_header = try std.fmt.bufPrint(
        &auth_buf,
        "Authorization: Bearer {s}\r\n",
        .{&token_hex},
    );
    try wss_codec.clientHandshake(client, "127.0.0.1", "/api/v1/wallet", auth_header);

    try wss_codec.writeClientFrame(client, .text,
        \\{"jsonrpc":"2.0","id":1,"method":"helm.subscribe","params":{"topics":["jobs"]}}
    );
    const sub_resp = try wss_codec.readClientFrame(allocator, client, 16 * 1024);
    defer allocator.free(sub_resp.payload);

    try std.testing.expectEqual(@as(usize, 1), broker.subscriberCount());

    try wss_codec.writeClientFrame(client, .text,
        \\{"jsonrpc":"2.0","id":2,"method":"helm.unsubscribe"}
    );
    const unsub_resp = try wss_codec.readClientFrame(allocator, client, 16 * 1024);
    defer allocator.free(unsub_resp.payload);
    try std.testing.expect(std.mem.indexOf(u8, unsub_resp.payload, "\"unsubscribed\":true") != null);

    try std.testing.expectEqual(@as(usize, 0), broker.subscriberCount());

    try wss_codec.writeClientFrame(client, .close, &[_]u8{ 0x03, 0xE8 });
}

// ─── Sovereign-push D.1 — helm.fetch_since RPC conformance ──────────

/// Hand-rolled tick clock for tests that need monotonic timestamps.
const FetchSinceClock = struct {
    var tick: i64 = 1_700_000_000;
    fn now() i64 {
        const v = tick;
        tick += 1;
        return v;
    }
};

test "D.1 helm.fetch_since returns events newer than since_ts" {
    pinned_clock = 1_700_000_000;
    const allocator = std.testing.allocator;
    const dir = std.testing.tmpDir(.{});
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try dir.dir.realpath(".", &path_buf);
    var tokens = try TokenStore.init(allocator, path, fixedClock);
    defer tokens.deinit();
    const issued = try tokens.issue("test", 0);
    var token_hex: [64]u8 = undefined;
    hexEncodeRaw(&issued.token, &token_hex);

    var broker = helm_event_broker.Broker.init(allocator);
    FetchSinceClock.tick = 1_700_000_000;
    broker.setClockFn(FetchSinceClock.now);
    defer broker.deinit();
    var backend = wss_wallet.Backend{ .tokens = &tokens, .helm_broker = &broker };

    // Seed events into the broker BEFORE the client connects.
    broker.publish(.{ .type = "lead.created", .payload_json = "{\"id\":\"L1\"}" });
    broker.publish(.{ .type = "lead.created", .payload_json = "{\"id\":\"L2\"}" });
    broker.publish(.{ .type = "job.transitioned", .payload_json = "{\"id\":\"J1\"}" });

    var bound = try bindLoopback();
    defer bound.deinit();

    const ServerCtx = struct { listener: *std.net.Server, backend: *wss_wallet.Backend, alloc: std.mem.Allocator };
    var ctx = ServerCtx{ .listener = &bound.listener, .backend = &backend, .alloc = allocator };
    const t = try std.Thread.spawn(.{}, struct {
        fn run(c: *ServerCtx) void {
            serveOne(c.alloc, c.listener, c.backend) catch {};
        }
    }.run, .{&ctx});
    defer t.join();

    const client = try std.net.tcpConnectToAddress(bound.address);
    defer client.close();
    var auth_buf: [128]u8 = undefined;
    const auth_header = try std.fmt.bufPrint(
        &auth_buf,
        "Authorization: Bearer {s}\r\n",
        .{&token_hex},
    );
    try wss_codec.clientHandshake(client, "127.0.0.1", "/api/v1/wallet", auth_header);

    // Ask for everything since 0 — should get all 3 events back.
    try wss_codec.writeClientFrame(client, .text,
        \\{"jsonrpc":"2.0","id":1,"method":"helm.fetch_since","params":{"since_ts":0}}
    );
    const got = try wss_codec.readClientFrame(allocator, client, 64 * 1024);
    defer allocator.free(got.payload);

    try std.testing.expect(std.mem.indexOf(u8, got.payload, "\"id\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, got.payload, "\"events\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, got.payload, "\"event_id\":\"0000000000000001\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, got.payload, "\"event_id\":\"0000000000000002\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, got.payload, "\"event_id\":\"0000000000000003\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, got.payload, "\"kind\":\"lead.created\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, got.payload, "\"kind\":\"job.transitioned\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, got.payload, "\"payload\":{\"id\":\"L1\"}") != null);
    // next_cursor_ts is the last event's ts (1_700_000_002).
    try std.testing.expect(std.mem.indexOf(u8, got.payload, "\"next_cursor_ts\":1700000002") != null);

    try wss_codec.writeClientFrame(client, .close, &[_]u8{ 0x03, 0xE8 });
}

test "D.1 helm.fetch_since paginates via next_cursor_ts" {
    pinned_clock = 1_700_000_000;
    const allocator = std.testing.allocator;
    const dir = std.testing.tmpDir(.{});
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try dir.dir.realpath(".", &path_buf);
    var tokens = try TokenStore.init(allocator, path, fixedClock);
    defer tokens.deinit();
    const issued = try tokens.issue("test", 0);
    var token_hex: [64]u8 = undefined;
    hexEncodeRaw(&issued.token, &token_hex);

    var broker = helm_event_broker.Broker.init(allocator);
    FetchSinceClock.tick = 2_000_000_000;
    broker.setClockFn(FetchSinceClock.now);
    defer broker.deinit();
    var backend = wss_wallet.Backend{ .tokens = &tokens, .helm_broker = &broker };

    var i: usize = 0;
    while (i < 4) : (i += 1) {
        broker.publish(.{ .type = "lead.created", .payload_json = "{}" });
    }

    var bound = try bindLoopback();
    defer bound.deinit();
    const ServerCtx = struct { listener: *std.net.Server, backend: *wss_wallet.Backend, alloc: std.mem.Allocator };
    var ctx = ServerCtx{ .listener = &bound.listener, .backend = &backend, .alloc = allocator };
    const t = try std.Thread.spawn(.{}, struct {
        fn run(c: *ServerCtx) void {
            serveOne(c.alloc, c.listener, c.backend) catch {};
        }
    }.run, .{&ctx});
    defer t.join();

    const client = try std.net.tcpConnectToAddress(bound.address);
    defer client.close();
    var auth_buf: [128]u8 = undefined;
    const auth_header = try std.fmt.bufPrint(&auth_buf, "Authorization: Bearer {s}\r\n", .{&token_hex});
    try wss_codec.clientHandshake(client, "127.0.0.1", "/api/v1/wallet", auth_header);

    // Page 1: since_ts=0, limit=2 — first two events.
    try wss_codec.writeClientFrame(client, .text,
        \\{"jsonrpc":"2.0","id":1,"method":"helm.fetch_since","params":{"since_ts":0,"limit":2}}
    );
    const page1 = try wss_codec.readClientFrame(allocator, client, 64 * 1024);
    defer allocator.free(page1.payload);
    try std.testing.expect(std.mem.indexOf(u8, page1.payload, "\"event_id\":\"0000000000000001\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, page1.payload, "\"event_id\":\"0000000000000002\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, page1.payload, "\"event_id\":\"0000000000000003\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, page1.payload, "\"next_cursor_ts\":2000000001") != null);

    // Page 2: since_ts=cursor → last two events.
    try wss_codec.writeClientFrame(client, .text,
        \\{"jsonrpc":"2.0","id":2,"method":"helm.fetch_since","params":{"since_ts":2000000001,"limit":2}}
    );
    const page2 = try wss_codec.readClientFrame(allocator, client, 64 * 1024);
    defer allocator.free(page2.payload);
    try std.testing.expect(std.mem.indexOf(u8, page2.payload, "\"event_id\":\"0000000000000003\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, page2.payload, "\"event_id\":\"0000000000000004\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, page2.payload, "\"next_cursor_ts\":2000000003") != null);

    try wss_codec.writeClientFrame(client, .close, &[_]u8{ 0x03, 0xE8 });
}

test "D.1 helm.fetch_since rejects malformed requests" {
    pinned_clock = 1_700_000_000;
    const allocator = std.testing.allocator;
    const dir = std.testing.tmpDir(.{});
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try dir.dir.realpath(".", &path_buf);
    var tokens = try TokenStore.init(allocator, path, fixedClock);
    defer tokens.deinit();
    const issued = try tokens.issue("test", 0);
    var token_hex: [64]u8 = undefined;
    hexEncodeRaw(&issued.token, &token_hex);

    var broker = helm_event_broker.Broker.init(allocator);
    defer broker.deinit();
    var backend = wss_wallet.Backend{ .tokens = &tokens, .helm_broker = &broker };

    var bound = try bindLoopback();
    defer bound.deinit();
    const ServerCtx = struct { listener: *std.net.Server, backend: *wss_wallet.Backend, alloc: std.mem.Allocator };
    var ctx = ServerCtx{ .listener = &bound.listener, .backend = &backend, .alloc = allocator };
    const t = try std.Thread.spawn(.{}, struct {
        fn run(c: *ServerCtx) void {
            serveOne(c.alloc, c.listener, c.backend) catch {};
        }
    }.run, .{&ctx});
    defer t.join();

    const client = try std.net.tcpConnectToAddress(bound.address);
    defer client.close();
    var auth_buf: [128]u8 = undefined;
    const auth_header = try std.fmt.bufPrint(&auth_buf, "Authorization: Bearer {s}\r\n", .{&token_hex});
    try wss_codec.clientHandshake(client, "127.0.0.1", "/api/v1/wallet", auth_header);

    // Missing since_ts.
    try wss_codec.writeClientFrame(client, .text,
        \\{"jsonrpc":"2.0","id":1,"method":"helm.fetch_since","params":{}}
    );
    const r1 = try wss_codec.readClientFrame(allocator, client, 16 * 1024);
    defer allocator.free(r1.payload);
    try std.testing.expect(std.mem.indexOf(u8, r1.payload, "\"code\":-32602") != null);
    try std.testing.expect(std.mem.indexOf(u8, r1.payload, "missing 'since_ts'") != null);

    // since_ts wrong type.
    try wss_codec.writeClientFrame(client, .text,
        \\{"jsonrpc":"2.0","id":2,"method":"helm.fetch_since","params":{"since_ts":"x"}}
    );
    const r2 = try wss_codec.readClientFrame(allocator, client, 16 * 1024);
    defer allocator.free(r2.payload);
    try std.testing.expect(std.mem.indexOf(u8, r2.payload, "\"code\":-32602") != null);
    try std.testing.expect(std.mem.indexOf(u8, r2.payload, "must be an integer") != null);

    // Negative since_ts.
    try wss_codec.writeClientFrame(client, .text,
        \\{"jsonrpc":"2.0","id":3,"method":"helm.fetch_since","params":{"since_ts":-1}}
    );
    const r3 = try wss_codec.readClientFrame(allocator, client, 16 * 1024);
    defer allocator.free(r3.payload);
    try std.testing.expect(std.mem.indexOf(u8, r3.payload, "\"code\":-32602") != null);
    try std.testing.expect(std.mem.indexOf(u8, r3.payload, "non-negative") != null);

    // params not an object.
    try wss_codec.writeClientFrame(client, .text,
        \\{"jsonrpc":"2.0","id":4,"method":"helm.fetch_since","params":[]}
    );
    const r4 = try wss_codec.readClientFrame(allocator, client, 16 * 1024);
    defer allocator.free(r4.payload);
    try std.testing.expect(std.mem.indexOf(u8, r4.payload, "\"code\":-32602") != null);

    try wss_codec.writeClientFrame(client, .close, &[_]u8{ 0x03, 0xE8 });
}

test "D.1 helm.fetch_since returns empty events when nothing matches" {
    pinned_clock = 1_700_000_000;
    const allocator = std.testing.allocator;
    const dir = std.testing.tmpDir(.{});
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try dir.dir.realpath(".", &path_buf);
    var tokens = try TokenStore.init(allocator, path, fixedClock);
    defer tokens.deinit();
    const issued = try tokens.issue("test", 0);
    var token_hex: [64]u8 = undefined;
    hexEncodeRaw(&issued.token, &token_hex);

    var broker = helm_event_broker.Broker.init(allocator);
    defer broker.deinit();
    var backend = wss_wallet.Backend{ .tokens = &tokens, .helm_broker = &broker };

    var bound = try bindLoopback();
    defer bound.deinit();
    const ServerCtx = struct { listener: *std.net.Server, backend: *wss_wallet.Backend, alloc: std.mem.Allocator };
    var ctx = ServerCtx{ .listener = &bound.listener, .backend = &backend, .alloc = allocator };
    const t = try std.Thread.spawn(.{}, struct {
        fn run(c: *ServerCtx) void {
            serveOne(c.alloc, c.listener, c.backend) catch {};
        }
    }.run, .{&ctx});
    defer t.join();

    const client = try std.net.tcpConnectToAddress(bound.address);
    defer client.close();
    var auth_buf: [128]u8 = undefined;
    const auth_header = try std.fmt.bufPrint(&auth_buf, "Authorization: Bearer {s}\r\n", .{&token_hex});
    try wss_codec.clientHandshake(client, "127.0.0.1", "/api/v1/wallet", auth_header);

    // No events have been published — events array is empty, cursor echoes since_ts.
    try wss_codec.writeClientFrame(client, .text,
        \\{"jsonrpc":"2.0","id":1,"method":"helm.fetch_since","params":{"since_ts":1700000000}}
    );
    const got = try wss_codec.readClientFrame(allocator, client, 16 * 1024);
    defer allocator.free(got.payload);
    try std.testing.expect(std.mem.indexOf(u8, got.payload, "\"events\":[]") != null);
    try std.testing.expect(std.mem.indexOf(u8, got.payload, "\"next_cursor_ts\":1700000000") != null);

    try wss_codec.writeClientFrame(client, .close, &[_]u8{ 0x03, 0xE8 });
}

```
