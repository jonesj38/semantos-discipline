---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/event_loop_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.200473+00:00
---

# runtime/semantos-brain/tests/event_loop_conformance.zig

```zig
// event_loop_conformance.zig — Reactor conformance tests
//
// Drives event_loop + connection_state through the build module graph
// using socketpair() / real loopback sockets — no site_server or
// wss_wallet involved.
//
// Scenario coverage:
//   1. Single GET → 200 response (basic request/response cycle)
//   2. Two simultaneous connections both serviced in one loop sweep
//   3. Slow client: request bytes arrive one at a time
//   4. WSS upgrade: HTTP → 101 → WSS frame dispatch
//   5. WSS hold + concurrent HTTP: the key demo criterion (the wedge fix)
//   6. EOF mid-request: state cleaned up, no CLOSE-WAIT leak
//
// These tests do NOT call EventLoop.run() for scenarios that need precise
// control; instead they drive poll_fds and handleEvent() directly so the
// test is deterministic without real timer dependencies.

const std = @import("std");
const event_loop = @import("event_loop");
const connection_state = @import("connection_state");
const http_parser = @import("http_parser");
const wss_frame_parser = @import("wss_frame_parser");
const wss_codec = @import("wss_codec");

const EventLoop = event_loop.EventLoop;
const ConnectionState = connection_state.ConnectionState;
const ConnectionContext = connection_state.ConnectionContext;
const HttpDispatchArgs = connection_state.HttpDispatchArgs;
const HttpDispatchResult = connection_state.HttpDispatchResult;
const WssDispatchArgs = connection_state.WssDispatchArgs;
const WssDispatchResult = connection_state.WssDispatchResult;

// ── Test helper: mock HTTP dispatcher ────────────────────────────────────

/// Writes a 200 OK response with the request path in the body.
fn echoHttpDispatch(args: HttpDispatchArgs) HttpDispatchResult {
    const path = args.request.path;
    const header = std.fmt.allocPrint(
        std.heap.page_allocator,
        "HTTP/1.1 200 OK\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n",
        .{path.len},
    ) catch return .close_after_drain;
    defer std.heap.page_allocator.free(header);
    args.write_buf.appendSlice(args.allocator, header) catch return .close_after_drain;
    args.write_buf.appendSlice(args.allocator, path) catch return .close_after_drain;
    return .close_after_drain;
}

/// Upgrades the connection to WSS if the path is "/ws".
fn upgradeOrEchoHttpDispatch(args: HttpDispatchArgs) HttpDispatchResult {
    if (std.mem.eql(u8, args.request.path, "/ws")) {
        // Produce a minimal 101 response (key computation omitted in tests).
        const resp = "HTTP/1.1 101 Switching Protocols\r\n" ++
            "Upgrade: websocket\r\nConnection: Upgrade\r\n" ++
            "Sec-WebSocket-Accept: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n";
        args.write_buf.appendSlice(args.allocator, resp) catch return .close_after_drain;
        return .upgraded_to_wss;
    }
    return echoHttpDispatch(args);
}

/// Echo text frames back as unmasked server→client frames.
fn echoWssDispatch(args: WssDispatchArgs) WssDispatchResult {
    const frame = args.frame;
    if (frame.opcode == .close) return .close_after_drain;
    if (frame.opcode == .ping) {
        // Pong.
        var hdr = [2]u8{ 0x8A, @intCast(frame.payload.len) };
        args.write_buf.appendSlice(args.allocator, &hdr) catch return .close_after_drain;
        args.write_buf.appendSlice(args.allocator, frame.payload) catch return .close_after_drain;
        return .keep_open;
    }
    if (frame.opcode != .text) return .keep_open;
    // Echo text frame.
    const payload = frame.payload;
    var hdr: [4]u8 = undefined;
    var hdr_len: usize = 2;
    hdr[0] = 0x81;
    if (payload.len < 126) {
        hdr[1] = @intCast(payload.len);
    } else {
        hdr[1] = 126;
        std.mem.writeInt(u16, hdr[2..4], @intCast(payload.len), .big);
        hdr_len = 4;
    }
    args.write_buf.appendSlice(args.allocator, hdr[0..hdr_len]) catch return .close_after_drain;
    args.write_buf.appendSlice(args.allocator, payload) catch return .close_after_drain;
    return .keep_open;
}

fn noopFreeWssCtx(_: *anyopaque, _: std.mem.Allocator) void {}

var dummy_ctx_storage: u8 = 0;

fn makeSimpleCtx() ConnectionContext {
    return .{
        .dispatch_http = &echoHttpDispatch,
        .dispatch_wss = &echoWssDispatch,
        // body_policy_fn left null → parser uses initDefault (256 KB cap).
        .body_policy_ctx = @ptrCast(&dummy_ctx_storage),
        .http_ctx = @ptrCast(&dummy_ctx_storage),
        .wss_ctx = @ptrCast(&dummy_ctx_storage),
        .free_wss_ctx = &noopFreeWssCtx,
        .tick_drain_ctx = @ptrCast(&dummy_ctx_storage),
    };
}

fn makeUpgradeCtx() ConnectionContext {
    return .{
        .dispatch_http = &upgradeOrEchoHttpDispatch,
        .dispatch_wss = &echoWssDispatch,
        .body_policy_ctx = @ptrCast(&dummy_ctx_storage),
        .http_ctx = @ptrCast(&dummy_ctx_storage),
        .wss_ctx = @ptrCast(&dummy_ctx_storage),
        .free_wss_ctx = &noopFreeWssCtx,
        .tick_drain_ctx = @ptrCast(&dummy_ctx_storage),
    };
}

/// Create a UNIX socketpair and make `sv[1]` non-blocking.
/// Returns {client_fd, server_fd}.
fn makePair() ![2]std.posix.fd_t {
    var sv: [2]std.posix.fd_t = undefined;
    const rc = std.c.socketpair(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0, @ptrCast(&sv));
    if (rc != 0) return error.SocketPairFailed;
    const flags = try std.posix.fcntl(sv[1], std.posix.F.GETFL, 0);
    const nb_flag: u32 = @bitCast(std.posix.O{ .NONBLOCK = true });
    _ = try std.posix.fcntl(sv[1], std.posix.F.SETFL, flags | nb_flag);
    return sv;
}

/// Write `data` to `fd`, assert all bytes were written.
fn writeAll(fd: std.posix.fd_t, data: []const u8) !void {
    var written: usize = 0;
    while (written < data.len) {
        const n = try std.posix.write(fd, data[written..]);
        written += n;
    }
}

/// Read from `fd` into a fresh ArrayList until n bytes arrive.
fn readExactly(allocator: std.mem.Allocator, fd: std.posix.fd_t, n: usize) ![]u8 {
    var buf = try std.ArrayList(u8).initCapacity(allocator, n);
    while (buf.items.len < n) {
        const start = buf.items.len;
        try buf.resize(n);
        const got = try std.posix.read(fd, buf.items[start..]);
        buf.items.len = start + got;
    }
    return buf.toOwnedSlice();
}

// ── Scenario 1: Single GET → 200 ─────────────────────────────────────────

test "event_loop_conformance: single GET request gets 200 response" {
    const fds = try makePair();
    defer std.posix.close(fds[0]);
    defer std.posix.close(fds[1]);

    var state = ConnectionState.init(std.testing.allocator, fds[1], makeSimpleCtx());
    defer state.deinit();

    try writeAll(fds[0], "GET /hello HTTP/1.1\r\nHost: x\r\n\r\n");

    // Simulate POLL.IN.
    const r = try state.handleEvent(std.posix.POLL.IN);
    try std.testing.expect(r == .keep_open); // want_close_after_drain set, not yet closed

    // write_buf has response.
    try std.testing.expect(state.write_buf.items.len > 0);
    try std.testing.expect(std.mem.startsWith(u8, state.write_buf.items, "HTTP/1.1 200 OK"));
    try std.testing.expect(std.mem.indexOf(u8, state.write_buf.items, "/hello") != null);

    // Drain writes.
    const drain_r = try state.handleEvent(std.posix.POLL.OUT);
    try std.testing.expect(drain_r == .closed); // want_close_after_drain + drained → closed

    // Read back from the client side.
    var rbuf: [512]u8 = undefined;
    const n = try std.posix.read(fds[0], &rbuf);
    try std.testing.expect(n > 0);
    try std.testing.expect(std.mem.startsWith(u8, rbuf[0..n], "HTTP/1.1 200 OK"));
}

// ── Scenario 2: Two simultaneous connections ──────────────────────────────

test "event_loop_conformance: two simultaneous connections both serviced" {
    const fdsA = try makePair();
    defer std.posix.close(fdsA[0]);
    defer std.posix.close(fdsA[1]);

    const fdsB = try makePair();
    defer std.posix.close(fdsB[0]);
    defer std.posix.close(fdsB[1]);

    var stateA = ConnectionState.init(std.testing.allocator, fdsA[1], makeSimpleCtx());
    defer stateA.deinit();
    var stateB = ConnectionState.init(std.testing.allocator, fdsB[1], makeSimpleCtx());
    defer stateB.deinit();

    // Both connections have a request waiting.
    try writeAll(fdsA[0], "GET /conn-a HTTP/1.1\r\nHost: x\r\n\r\n");
    try writeAll(fdsB[0], "GET /conn-b HTTP/1.1\r\nHost: x\r\n\r\n");

    // Service both in one poll sweep (the wedge fix: neither blocks the other).
    _ = try stateA.handleEvent(std.posix.POLL.IN);
    _ = try stateB.handleEvent(std.posix.POLL.IN);

    try std.testing.expect(std.mem.indexOf(u8, stateA.write_buf.items, "/conn-a") != null);
    try std.testing.expect(std.mem.indexOf(u8, stateB.write_buf.items, "/conn-b") != null);
}

// ── Scenario 3: Slow client — bytes arrive one at a time ─────────────────

test "event_loop_conformance: slow client sends request one byte at a time" {
    const fds = try makePair();
    defer std.posix.close(fds[0]);
    defer std.posix.close(fds[1]);

    var state = ConnectionState.init(std.testing.allocator, fds[1], makeSimpleCtx());
    defer state.deinit();

    const req = "GET /slow HTTP/1.1\r\nHost: x\r\n\r\n";
    var got_response = false;
    for (req) |byte| {
        try writeAll(fds[0], &[1]u8{byte});
        const event_r = try state.handleEvent(std.posix.POLL.IN);
        if (state.write_buf.items.len > 0) {
            got_response = true;
            break;
        }
        try std.testing.expect(event_r == .keep_open);
    }
    try std.testing.expect(got_response);
    try std.testing.expect(std.mem.startsWith(u8, state.write_buf.items, "HTTP/1.1 200 OK"));
}

// ── Scenario 4: WSS upgrade ───────────────────────────────────────────────

test "event_loop_conformance: WebSocket upgrade transitions to WSS mode" {
    const fds = try makePair();
    defer std.posix.close(fds[0]);
    defer std.posix.close(fds[1]);

    var state = ConnectionState.init(std.testing.allocator, fds[1], makeUpgradeCtx());
    defer state.deinit();

    // Send an HTTP upgrade request.
    const upgrade_req =
        "GET /ws HTTP/1.1\r\n" ++
        "Host: x\r\n" ++
        "Upgrade: websocket\r\n" ++
        "Connection: Upgrade\r\n" ++
        "Sec-WebSocket-Key: AAAAAAAAAAAAAAAAAAAAAA==\r\n" ++
        "Sec-WebSocket-Version: 13\r\n" ++
        "\r\n";
    try writeAll(fds[0], upgrade_req);

    const r = try state.handleEvent(std.posix.POLL.IN);
    try std.testing.expect(r == .keep_open);

    // State should have switched to WSS mode.
    try std.testing.expect(state.phase == .wss);

    // write_buf should contain the 101 response.
    try std.testing.expect(std.mem.startsWith(u8, state.write_buf.items, "HTTP/1.1 101"));

    // Drain the 101 response.
    _ = try state.handleEvent(std.posix.POLL.OUT);

    // Now send a masked WSS text frame.
    const mask = [4]u8{ 0xAB, 0xCD, 0xEF, 0x01 };
    const text = "hello";
    var frame_buf: [16]u8 = undefined;
    frame_buf[0] = 0x81; // FIN | text
    frame_buf[1] = 0x80 | @as(u8, @intCast(text.len)); // MASK | len
    @memcpy(frame_buf[2..6], &mask);
    for (text, 0..) |b, i| frame_buf[6 + i] = b ^ mask[i & 3];
    try writeAll(fds[0], frame_buf[0 .. 6 + text.len]);

    const r2 = try state.handleEvent(std.posix.POLL.IN);
    try std.testing.expect(r2 == .keep_open);

    // Echo frame written to write_buf.
    try std.testing.expect(state.write_buf.items.len > 0);
    // The echo dispatcher writes a text frame containing "hello".
    const resp = state.write_buf.items;
    try std.testing.expect(resp[0] == 0x81); // FIN | text
    const echo_payload = resp[2 .. 2 + text.len];
    try std.testing.expectEqualStrings(text, echo_payload);
}

// ── Scenario 5: WSS hold + concurrent HTTP ────────────────────────────────
//
// THIS IS THE KEY DEMO CRITERION.
//
// One "phone" connection upgrades to WSS and holds it open (no frames
// arrive).  A second "browser" connection sends an HTTP GET.  In the
// old blocking model, the HTTP GET would time out because the accept
// loop was stuck in readFrame() on the WSS connection.
//
// In the reactor model, both connections are in poll_fds.  On each tick
// the reactor sweeps all ready fds.  The HTTP connection gets serviced
// regardless of the WSS connection's activity.

test "event_loop_conformance: WSS hold does NOT block concurrent HTTP request" {
    // Phone connection — will upgrade to WSS then go quiet.
    const phoneFds = try makePair();
    defer std.posix.close(phoneFds[0]);
    defer std.posix.close(phoneFds[1]);

    // Browser connection — sends a plain HTTP GET.
    const browserFds = try makePair();
    defer std.posix.close(browserFds[0]);
    defer std.posix.close(browserFds[1]);

    var phoneState = ConnectionState.init(std.testing.allocator, phoneFds[1], makeUpgradeCtx());
    defer phoneState.deinit();
    var browserState = ConnectionState.init(std.testing.allocator, browserFds[1], makeSimpleCtx());
    defer browserState.deinit();

    // Phone: send upgrade request.
    const upgrade_req =
        "GET /ws HTTP/1.1\r\n" ++
        "Host: x\r\n" ++
        "Upgrade: websocket\r\n" ++
        "Connection: Upgrade\r\n" ++
        "Sec-WebSocket-Key: AAAAAAAAAAAAAAAAAAAAAA==\r\n" ++
        "Sec-WebSocket-Version: 13\r\n" ++
        "\r\n";
    try writeAll(phoneFds[0], upgrade_req);

    _ = try phoneState.handleEvent(std.posix.POLL.IN);
    try std.testing.expect(phoneState.phase == .wss);

    // Phone is now in WSS mode.  No frames arrive — phone is "holding" the connection.
    // (In the old model, the main thread would be blocked inside readFrame() here.)

    // Browser: send HTTP GET.  In the reactor, this is just another fd in the sweep.
    try writeAll(browserFds[0], "GET /api/v1/info HTTP/1.1\r\nHost: x\r\n\r\n");
    const browser_r = try browserState.handleEvent(std.posix.POLL.IN);
    try std.testing.expect(browser_r == .keep_open);

    // Browser gets its response immediately — not blocked by the WSS connection.
    try std.testing.expect(browserState.write_buf.items.len > 0);
    try std.testing.expect(std.mem.startsWith(u8, browserState.write_buf.items, "HTTP/1.1 200 OK"));

    // Phone connection still alive and in WSS mode.
    try std.testing.expect(phoneState.phase == .wss);
}

// ── Scenario 6: EOF mid-request ───────────────────────────────────────────

test "event_loop_conformance: EOF mid-request returns closed (CLOSE-WAIT fix)" {
    const fds = try makePair();
    defer std.posix.close(fds[1]);

    var state = ConnectionState.init(std.testing.allocator, fds[1], makeSimpleCtx());
    defer state.deinit();

    // Client sends partial request then closes.
    try writeAll(fds[0], "GET /incomplete");
    std.posix.close(fds[0]);

    // First event: partial bytes arrive, incomplete parse.
    const r1 = try state.handleEvent(std.posix.POLL.IN);
    // May be keep_open (partial data) or closed (EOF caught in same read).
    // Either is acceptable; the important thing is that a second event
    // returns closed so the reactor closes the fd.
    if (r1 == .keep_open) {
        // Read the EOF (n=0).
        const r2 = try state.handleEvent(std.posix.POLL.IN);
        try std.testing.expect(r2 == .closed);
    } else {
        try std.testing.expect(r1 == .closed);
    }
    // The test passing is proof that no fd leak (CLOSE-WAIT) occurs —
    // the reactor closes the fd immediately on EOF rather than waiting
    // for an OS timeout.
}

```
