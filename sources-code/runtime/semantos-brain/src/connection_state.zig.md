---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/connection_state.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.242451+00:00
---

# runtime/semantos-brain/src/connection_state.zig

```zig
// connection_state.zig — Per-connection state machine for the Semantos Brain reactor
//
// WHY THIS FILE EXISTS
// --------------------
// The reactor (event_loop.zig) multiplexes N connections over a single
// thread via std.posix.poll. Each connection is an independent state
// machine: it accumulates bytes from non-blocking reads, parses them with
// http_parser or wss_frame_parser, and dispatches completed requests to
// the application layer.
//
// DESIGN
// ------
// ConnectionState owns:
//   - A read buffer (stack-allocated via http_parser / wss_frame_parser)
//   - A write buffer (heap ArrayList, drained to the socket in POLL.OUT)
//   - The current phase: HTTP request accumulation → (optional) WSS session
//
// The application layer is plugged in via two function pointers on
// ConnectionContext, keeping connection_state.zig free of any direct
// dependency on site_server.zig or wss_wallet.zig:
//
//   dispatch_http   — called when a complete HTTP request has been parsed.
//                     The function appends response bytes to write_buf and
//                     returns either .keep_open or .closed.
//   dispatch_wss    — called per decoded WSS frame. Same contract.
//
// This decoupling lets the conformance tests (event_loop_conformance.zig)
// drive the state machine with simple mock dispatchers without spinning up
// the full SiteServer.
//
// CLOSE-WAIT FIX (folded in for free)
// ------------------------------------
// When std.posix.read() returns 0, the remote peer sent a FIN (TCP
// half-close). The old blocking-loop server left the fd open in CLOSE-WAIT
// until the OS reclaimed it (when the process exited or the FD table
// overflowed). In the reactor model, handleRead returns .closed on n==0,
// which causes event_loop.run to call std.posix.close(fd) immediately.
// CLOSE-WAIT count stays at zero on repeated phone reconnects.
//
// HOW TO REVERT
// -------------
// This file is new — delete it.  event_loop.zig is also new; the pair
// lands as a unit.  site_server.zig is modified to call EventLoop.run()
// instead of its own accept loop; revert that change via the
// RIP-OUT-MARKER in site_server.zig.
//
// RIP-OUT-MARKER (brain-wedge B-pragmatic, 2026-05-07):
//   Delete connection_state.zig + event_loop.zig and revert
//   site_server.zig + wss_wallet.zig to unwedge the reactor and restore
//   the previous blocking accept-loop behaviour.

const std = @import("std");
const http_parser = @import("http_parser");
const wss_frame_parser = @import("wss_frame_parser");
const wss_codec = @import("wss_codec");

/// Outcome of one call to ConnectionState.handleEvent.
pub const EventResult = enum { keep_open, closed };

/// Arguments passed to the HTTP dispatch callback.
/// `write_buf` is the mutable ArrayList the dispatcher appends response bytes
/// to; event_loop drains it via POLL.OUT in subsequent cycles.
pub const HttpDispatchArgs = struct {
    fd: std.posix.fd_t,
    request: *const http_parser.HttpRequest,
    write_buf: *std.ArrayList(u8),
    /// Allocator to use for all write_buf mutations.  Always pass this
    /// allocator (not a different one) to keep the backing store consistent.
    allocator: std.mem.Allocator,
    /// Application-supplied per-connection context (e.g. *SiteServer for
    /// the production reactor, or a dummy pointer in tests).  Passed
    /// through from ConnectionContext.http_ctx.
    http_ctx: *anyopaque,
};

/// Return value from the HTTP dispatch callback.
pub const HttpDispatchResult = enum {
    /// Normal HTTP response — keep the connection open (or close after
    /// drain if want_close is set by the dispatcher).
    keep_open,
    /// Upgraded to WebSocket — caller set .mode = .wss already.
    upgraded_to_wss,
    /// Something went wrong — close after draining the write buffer.
    close_after_drain,
};

/// Arguments passed to the WSS dispatch callback.
pub const WssDispatchArgs = struct {
    fd: std.posix.fd_t,
    frame: wss_codec.Frame,
    write_buf: *std.ArrayList(u8),
    /// Allocator to use for all write_buf mutations.
    allocator: std.mem.Allocator,
    ctx: *anyopaque, // application-supplied per-connection context
};

pub const WssDispatchResult = enum {
    keep_open,
    close_after_drain,
    close_immediately,
};

/// Application hooks passed at construction time.  The reactor never
/// calls into site_server.zig or wss_wallet.zig directly; instead it
/// calls these function pointers.  This allows conformance tests to
/// supply simple mock dispatchers.
pub const ConnectionContext = struct {
    /// Called when an HTTP request is fully parsed.
    dispatch_http: *const fn (args: HttpDispatchArgs) HttpDispatchResult,

    /// Called for each decoded WSS frame after upgrade.
    dispatch_wss: *const fn (args: WssDispatchArgs) WssDispatchResult,

    /// T0 — body-handling policy callback.  Invoked once per request
    /// after headers parse, before body bytes are buffered.  Returns
    /// the per-route body cap (or `.stream`, reserved).  When null, the
    /// parser falls back to its default policy (DEFAULT_BODY_CAP, 256 KiB).
    body_policy_fn: ?http_parser.PolicyFn = null,

    /// Context pointer passed to `body_policy_fn`.  When body_policy_fn
    /// is set, this must be a valid pointer; when null, ignored.
    body_policy_ctx: *anyopaque,

    /// Opaque per-connection HTTP context (e.g. *SiteServer for
    /// production; a dummy pointer for tests).  Passed through to
    /// dispatch_http as `http_ctx`.
    http_ctx: *anyopaque,

    /// Opaque per-connection WSS context pointer (e.g. a *WssSession for
    /// wss_wallet, or null for plain HTTP).  Passed through to
    /// dispatch_wss as `ctx`.
    wss_ctx: *anyopaque,

    /// Free the wss_ctx allocation (called by deinit).
    free_wss_ctx: ?*const fn (ctx: *anyopaque, allocator: std.mem.Allocator) void,

    /// T3 — called once per poll tick BEFORE poll() blocks.  Lets the
    /// application drain cross-thread queues (e.g. bus event frames
    /// produced on a publisher thread) into the per-connection
    /// write_buf so the next poll cycle picks up the pending writes
    /// via POLL.OUT.  Optional; absent → no-op tick.
    pre_tick_drain: ?*const fn (
        ctx: *anyopaque,
        write_buf: *std.ArrayList(u8),
        allocator: std.mem.Allocator,
    ) void = null,

    /// Context pointer passed to pre_tick_drain.  Typically the same as
    /// wss_ctx (the same per-connection session struct), but kept
    /// separate so a future producer that lives outside the WSS
    /// context can wire its own drain.
    tick_drain_ctx: *anyopaque,
};

/// Connection phase.
const Phase = enum {
    /// Accumulating an HTTP request (either the initial request or a
    /// pipelined one on a keep-alive connection).
    http,
    /// HTTP response has been sent; draining write buffer before closing.
    draining_close,
    /// Connection upgraded to WebSocket — WSS frame parser active.
    wss,
};

/// Per-connection state owned by event_loop.
pub const ConnectionState = struct {
    allocator: std.mem.Allocator,
    fd: std.posix.fd_t,
    ctx: ConnectionContext,
    phase: Phase,

    /// HTTP parser accumulates bytes until a complete request arrives.
    http_parser_state: http_parser.Parser,
    /// Scratch storage for the parsed HttpRequest.  Borrows from
    /// http_parser_state.buf — valid until http_parser_state.reset().
    parsed_request: http_parser.HttpRequest,

    /// WSS frame parser accumulates bytes until a complete frame arrives.
    wss_parser: wss_frame_parser.FrameParser,

    /// Bytes queued for writing.  Appended by dispatch callbacks and by
    /// WSS frame builders; drained to the socket in POLL.OUT cycles.
    write_buf: std.ArrayList(u8),
    write_offset: usize,

    /// If true, close the connection once write_buf is fully drained.
    want_close_after_drain: bool,

    pub fn init(
        allocator: std.mem.Allocator,
        fd: std.posix.fd_t,
        ctx: ConnectionContext,
    ) ConnectionState {
        // T0 — construct the parser with the per-connection allocator and
        // the policy callback from the ConnectionContext.  When the
        // context didn't set a policy fn, fall back to the parser's
        // default (DEFAULT_BODY_CAP / 256 KiB).
        const parser_state = if (ctx.body_policy_fn) |fn_ptr|
            http_parser.Parser.init(allocator, fn_ptr, ctx.body_policy_ctx)
        else
            http_parser.Parser.initDefault(allocator);
        return .{
            .allocator = allocator,
            .fd = fd,
            .ctx = ctx,
            .phase = .http,
            .http_parser_state = parser_state,
            .parsed_request = undefined,
            .wss_parser = wss_frame_parser.FrameParser.init(),
            // Use zero-init form (Zig 0.15 ArrayList per-method-allocator API).
            .write_buf = .{},
            .write_offset = 0,
            .want_close_after_drain = false,
        };
    }

    pub fn deinit(self: *ConnectionState) void {
        // T0 — free any in-flight body buffer the parser may still own.
        self.http_parser_state.deinit();
        self.write_buf.deinit(self.allocator);
        if (self.ctx.free_wss_ctx) |free_fn| {
            free_fn(self.ctx.wss_ctx, self.allocator);
        }
    }

    /// Called by event_loop when poll() reports events on this fd.
    /// Returns .closed if the caller should remove this connection.
    pub fn handleEvent(self: *ConnectionState, events: i16) !EventResult {
        const hup = std.posix.POLL.HUP;
        const err_flag = std.posix.POLL.ERR;
        if (events & (hup | err_flag) != 0) return .closed;

        if (events & std.posix.POLL.IN != 0) {
            const r = try self.handleRead();
            if (r == .closed) return .closed;
        }

        if (events & std.posix.POLL.OUT != 0) {
            const r = try self.drainWrite();
            if (r == .closed) return .closed;
        }

        return .keep_open;
    }

    /// Attempt a non-blocking read and advance the state machine.
    fn handleRead(self: *ConnectionState) !EventResult {
        var buf: [8192]u8 = undefined;
        const n = std.posix.read(self.fd, &buf) catch |err| switch (err) {
            error.WouldBlock => return .keep_open,
            error.ConnectionResetByPeer => return .closed,
            else => return err,
        };

        // n == 0 → peer sent FIN.  CLOSE-WAIT fix: close immediately.
        if (n == 0) return .closed;

        return switch (self.phase) {
            .http => self.feedHttpBytes(buf[0..n]),
            .wss => self.feedWssBytes(buf[0..n]),
            .draining_close => .keep_open, // ignore reads while draining
        };
    }

    /// Feed bytes into the HTTP parser and dispatch on completion.
    fn feedHttpBytes(self: *ConnectionState, bytes: []const u8) !EventResult {
        var remaining = bytes;

        while (remaining.len > 0) {
            const result = self.http_parser_state.feed(remaining, &self.parsed_request);
            switch (result) {
                .incomplete => return .keep_open,
                .err => return .closed,
                .complete => |c| {
                    remaining = remaining[c.bytes_consumed..];
                    const dispatch_result = self.ctx.dispatch_http(.{
                        .fd = self.fd,
                        .request = &self.parsed_request,
                        .write_buf = &self.write_buf,
                        .allocator = self.allocator,
                        .http_ctx = self.ctx.http_ctx,
                    });
                    self.http_parser_state.reset();

                    switch (dispatch_result) {
                        .keep_open => {
                            // Pipelining: if there are leftover bytes after
                            // this request, loop to process the next one.
                            continue;
                        },
                        .upgraded_to_wss => {
                            // The dispatcher performed the WSS handshake and
                            // appended the 101 response.  Switch parser phase.
                            self.phase = .wss;
                            self.wss_parser.reset();
                            // Any remaining bytes are the start of WSS frames.
                            if (remaining.len > 0) {
                                return self.feedWssBytes(remaining);
                            }
                            return .keep_open;
                        },
                        .close_after_drain => {
                            self.want_close_after_drain = true;
                            return .keep_open;
                        },
                    }
                },
            }
        }
        return .keep_open;
    }

    /// Feed bytes into the WSS frame parser and dispatch on each complete frame.
    fn feedWssBytes(self: *ConnectionState, bytes: []const u8) !EventResult {
        var remaining = bytes;

        while (remaining.len > 0) {
            const result = self.wss_parser.feed(remaining);
            switch (result) {
                .incomplete => return .keep_open,
                .err => {
                    // Protocol violation — send a close frame then drain.
                    wss_codec.writeClose(std.net.Stream{ .handle = self.fd }, 1002, "protocol error") catch {};
                    self.want_close_after_drain = true;
                    return .keep_open;
                },
                .complete => |c| {
                    remaining = remaining[c.bytes_consumed..];
                    const frame = self.wss_parser.getFrame();
                    const dispatch_result = self.ctx.dispatch_wss(.{
                        .fd = self.fd,
                        .frame = frame,
                        .write_buf = &self.write_buf,
                        .allocator = self.allocator,
                        .ctx = self.ctx.wss_ctx,
                    });
                    self.wss_parser.reset();

                    switch (dispatch_result) {
                        .keep_open => continue,
                        .close_after_drain => {
                            self.want_close_after_drain = true;
                            return .keep_open;
                        },
                        .close_immediately => return .closed,
                    }
                },
            }
        }
        return .keep_open;
    }

    /// Drain as many bytes from write_buf as the socket will accept
    /// (non-blocking write).  Returns .closed if the caller should close.
    fn drainWrite(self: *ConnectionState) !EventResult {
        while (self.write_offset < self.write_buf.items.len) {
            const pending = self.write_buf.items[self.write_offset..];
            const n = std.posix.write(self.fd, pending) catch |err| switch (err) {
                error.WouldBlock => return .keep_open,
                error.BrokenPipe, error.ConnectionResetByPeer => return .closed,
                else => return err,
            };
            self.write_offset += n;
        }

        // Everything drained.
        self.write_buf.clearRetainingCapacity();
        self.write_offset = 0;

        if (self.want_close_after_drain) return .closed;
        return .keep_open;
    }

    /// True if there are pending writes that need POLL.OUT to be registered.
    pub fn needsWrite(self: *const ConnectionState) bool {
        return self.write_offset < self.write_buf.items.len;
    }

    /// T3 — invoke the per-connection tick-drain hook (if any).  The
    /// EventLoop calls this once per state per poll cycle BEFORE
    /// poll() blocks so cross-thread producers can flush queued
    /// frames into write_buf.  Re-registration of POLL.OUT happens in
    /// the EventLoop's main sweep based on needsWrite().
    pub fn tickDrain(self: *ConnectionState) void {
        if (self.ctx.pre_tick_drain) |f| {
            f(self.ctx.tick_drain_ctx, &self.write_buf, self.allocator);
        }
    }
};

// ── Embedded unit tests ───────────────────────────────────────────────────
// These tests drive ConnectionState directly via socketpair() — no
// site_server or wss_wallet involved.

const testing = std.testing;

/// A trivial HTTP dispatcher that sends a minimal 200 OK with the
/// request path echoed back in a plain-text body.
fn echoHttpDispatch(args: HttpDispatchArgs) HttpDispatchResult {
    const path = args.request.path;
    const body_len = path.len;
    const header = std.fmt.allocPrint(
        std.heap.page_allocator,
        "HTTP/1.1 200 OK\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n",
        .{body_len},
    ) catch return .close_after_drain;
    defer std.heap.page_allocator.free(header);

    args.write_buf.appendSlice(args.allocator, header) catch return .close_after_drain;
    args.write_buf.appendSlice(args.allocator, path) catch return .close_after_drain;
    return .close_after_drain; // single-shot for tests
}

/// WSS dispatcher used by tests — echoes text frames back.
fn echoWssDispatch(args: WssDispatchArgs) WssDispatchResult {
    if (args.frame.opcode == .close) return .close_after_drain;
    if (args.frame.opcode != .text) return .keep_open;

    // Build an unmasked server→client text frame.
    const payload = args.frame.payload;
    var hdr: [10]u8 = undefined;
    var hdr_len: usize = 2;
    hdr[0] = 0x81; // FIN | text
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

var dummy_wss_ctx: u8 = 0;
var dummy_http_ctx: u8 = 0;

fn makeTestCtx() ConnectionContext {
    return .{
        .dispatch_http = &echoHttpDispatch,
        .dispatch_wss = &echoWssDispatch,
        // body_policy_fn left null → parser uses initDefault (256 KB cap).
        .body_policy_ctx = @ptrCast(&dummy_http_ctx),
        .http_ctx = @ptrCast(&dummy_http_ctx),
        .wss_ctx = @ptrCast(&dummy_wss_ctx),
        .free_wss_ctx = &noopFreeWssCtx,
        // pre_tick_drain left null in tests; no cross-thread producers
        // run inside the unit test harness.
        .tick_drain_ctx = @ptrCast(&dummy_http_ctx),
    };
}

/// Create a UNIX socketpair and make `sv[1]` non-blocking.
/// Returns {client_fd, server_fd}.
fn makeTestSocketPair() ![2]std.posix.fd_t {
    var sv: [2]std.posix.fd_t = undefined;
    const rc = std.c.socketpair(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0, @ptrCast(&sv));
    if (rc != 0) return error.SocketPairFailed;
    const flags = try std.posix.fcntl(sv[1], std.posix.F.GETFL, 0);
    const nb_flag: u32 = @bitCast(std.posix.O{ .NONBLOCK = true });
    _ = try std.posix.fcntl(sv[1], std.posix.F.SETFL, flags | nb_flag);
    return sv;
}

test "connection_state: HTTP GET handled and write_buf populated" {
    // Create a socketpair: fds[0] is the "client" side, fds[1] the server.
    const fds = try makeTestSocketPair();
    defer std.posix.close(fds[0]);
    defer std.posix.close(fds[1]);

    var state = ConnectionState.init(testing.allocator, fds[1], makeTestCtx());
    defer state.deinit();

    // Write a request from the client side.
    const req = "GET /hello HTTP/1.1\r\nHost: x\r\n\r\n";
    _ = try std.posix.write(fds[0], req);

    // Drive the state machine: read side.
    const r = try state.handleEvent(std.posix.POLL.IN);
    try testing.expect(r == .keep_open);

    // write_buf should now contain the 200 response.
    try testing.expect(state.write_buf.items.len > 0);
    const resp = state.write_buf.items;
    try testing.expect(std.mem.startsWith(u8, resp, "HTTP/1.1 200 OK"));
    try testing.expect(std.mem.indexOf(u8, resp, "/hello") != null);
}

test "connection_state: EOF on read returns closed" {
    const fds = try makeTestSocketPair();
    defer std.posix.close(fds[1]);

    var state = ConnectionState.init(testing.allocator, fds[1], makeTestCtx());
    defer state.deinit();

    // Close the client side — server sees EOF on next read.
    std.posix.close(fds[0]);

    const r = try state.handleEvent(std.posix.POLL.IN);
    try testing.expect(r == .closed);
}

test "connection_state: partial request across two reads" {
    const fds = try makeTestSocketPair();
    defer std.posix.close(fds[0]);
    defer std.posix.close(fds[1]);

    var state = ConnectionState.init(testing.allocator, fds[1], makeTestCtx());
    defer state.deinit();

    // Send the request in two chunks.
    const part1 = "GET /partial HTTP/1.1\r\n";
    const part2 = "Host: x\r\n\r\n";

    _ = try std.posix.write(fds[0], part1);
    const r1 = try state.handleEvent(std.posix.POLL.IN);
    try testing.expect(r1 == .keep_open);
    // No response yet — request not complete.
    try testing.expect(state.write_buf.items.len == 0);

    _ = try std.posix.write(fds[0], part2);
    const r2 = try state.handleEvent(std.posix.POLL.IN);
    try testing.expect(r2 == .keep_open);
    // Now response is queued.
    try testing.expect(state.write_buf.items.len > 0);
    try testing.expect(std.mem.indexOf(u8, state.write_buf.items, "/partial") != null);
}

test "connection_state: drainWrite flushes write_buf" {
    const fds = try makeTestSocketPair();
    defer std.posix.close(fds[0]);
    defer std.posix.close(fds[1]);

    var state = ConnectionState.init(testing.allocator, fds[1], makeTestCtx());
    defer state.deinit();

    // Manually populate the write buffer.
    const msg = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nhi";
    try state.write_buf.appendSlice(testing.allocator, msg);

    // Drain: POLL.OUT event.
    const r = try state.handleEvent(std.posix.POLL.OUT);
    // drainWrite returns keep_open (want_close_after_drain not set here).
    try testing.expect(r == .keep_open);
    try testing.expect(state.write_buf.items.len == 0);

    // Read back the data from the client side.
    var read_buf: [256]u8 = undefined;
    const n = try std.posix.read(fds[0], &read_buf);
    try testing.expect(n == msg.len);
    try testing.expectEqualStrings(msg, read_buf[0..n]);
}

```
