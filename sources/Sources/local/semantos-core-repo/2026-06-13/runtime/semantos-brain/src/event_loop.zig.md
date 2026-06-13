---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/event_loop.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.241845+00:00
---

# runtime/semantos-brain/src/event_loop.zig

```zig
// event_loop.zig — Single-threaded poll-based I/O reactor
//
// WHY THIS FILE EXISTS
// --------------------
// The original site_server.zig::serve() blocks in handleConnection() for
// the entire lifetime of each connection.  When a phone holds a WebSocket
// to /api/v1/wallet, no other request can be serviced — the "Bridget wedge".
//
// This file replaces that blocking accept loop with a single-threaded
// poll() reactor (the "B-pragmatic" option from the architectural options
// doc).  The single thread owns ALL state: connection reads/writes, HTTP
// dispatch, WSS frame dispatch, broker event delivery.  No mutexes are
// needed on view stores or the in-memory broker because there is only one
// thread.
//
// DESIGN
// ------
//   poll_fds[0]  — the listening socket (POLL.IN → accept)
//   poll_fds[1…] — one entry per active connection
//   states[i]    — ConnectionState corresponding to poll_fds[i]
//
// The loop runs with a 100 ms timeout so the shutdown signal is processed
// promptly even when no I/O is ready.
//
// FUTURE: the Poll abstraction below wraps std.posix.poll behind a
// one-method interface so a future engineer can swap in epoll_wait or
// kevent with minimal diff.  See the "TODO-EPOLL-SWAP" marker below.
//
// WORKER POOL (not in v1)
// -----------------------
// See docs/prd/BRAIN-WEDGE-STEP0-AUDIT.md §Decision.  No slow blocking ops
// were found in the Semantos Brain serve path.  The two slow ops identified
// (llm_http_adapter outbound HTTP, voice_extract shell-out) are on
// endpoints orthogonal to the WSS wedge.  A worker pool seam is documented
// here but NOT implemented.
//
//   TODO-WORKER-POOL: llm_http_adapter.zig outbound HTTP call to LLM
//   TODO-WORKER-POOL: voice_extract_http.zig shell-out to bun runtime
//
// HOW TO REVERT
// -------------
// This file is new — delete it.  connection_state.zig is also new.
// Revert the `serve()` method in site_server.zig via the RIP-OUT-MARKER
// there to restore the old blocking accept-loop behaviour.
//
// RIP-OUT-MARKER (brain-wedge B-pragmatic, 2026-05-07):
//   Delete event_loop.zig + connection_state.zig and revert
//   site_server.zig to restore the pre-reactor blocking accept loop.

const std = @import("std");
const connection_state = @import("connection_state");
const ConnectionState = connection_state.ConnectionState;
const ConnectionContext = connection_state.ConnectionContext;
const EventResult = connection_state.EventResult;
// W0.4: oddjobz_jsonl_watcher removed — mtime polling replaced by Pravega.
const intent_action_router_mod = @import("intent_action_router");
const visit_rollup_router_mod = @import("visit_rollup_router");
const quote_seed_router_mod = @import("quote_seed_router");
// Phase U.2 — optional UDP datagram dispatcher serviced from the same poll set.
const udp_dispatcher_mod = @import("udp_dispatcher");

/// poll() timeout in milliseconds.  100 ms ensures the shutdown signal
/// is noticed within one tick; low enough to be invisible on any workload.
const POLL_TIMEOUT_MS: i32 = 100;

/// Maximum connections the event loop will hold simultaneously.
/// 1024 is well above the expected peak for brain (a brain serves one
/// team, not the internet).  The OS ulimit on open fds is the real cap.
pub const MAX_CONNECTIONS: usize = 1024;

/// Thin abstraction over std.posix.poll.
/// Exists so a future engineer can swap in epoll/kqueue by replacing the
/// single `wait()` implementation below.
///
/// TODO-EPOLL-SWAP: implement an EpollPoller and a KqueuePoller that
/// satisfy this same interface; swap EventLoop.poller to select at
/// runtime based on @import("builtin").os.tag.
const Poller = struct {
    /// Block until at least one fd is ready or `timeout_ms` elapses.
    /// Returns the number of ready fds (0 = timeout, negative = error).
    /// `fds` is updated in-place with revents.
    fn wait(fds: []std.posix.pollfd, timeout_ms: i32) !usize {
        return std.posix.poll(fds, timeout_ms) catch |err| blk: {
            // EINTR: signal interrupted poll — treat as zero-ready (loop again).
            if (err == error.SignalInterrupt) break :blk @as(usize, 0);
            return err;
        };
    }
};

/// The core reactor.  Created by site_server.serve() after the listener
/// socket is set up.  Runs until `shutdown` is set to true.
pub const EventLoop = struct {
    allocator: std.mem.Allocator,
    /// poll_fds[0] is always the listener socket.
    /// poll_fds[1..] are active connection sockets.
    poll_fds: std.ArrayList(std.posix.pollfd),
    /// states[i] corresponds to poll_fds[i].
    /// states[0] is null (listener has no ConnectionState).
    states: std.ArrayList(?*ConnectionState),
    /// The raw listener fd (same as poll_fds.items[0].fd).
    listener_fd: std.posix.fd_t,
    /// Application-supplied factory that builds a ConnectionContext for
    /// each accepted connection.  Returns error on allocation failure.
    make_ctx: *const fn (fd: std.posix.fd_t, ud: *anyopaque) anyerror!ConnectionContext,
    /// Opaque pointer passed through to make_ctx (e.g. *SiteServer).
    make_ctx_ud: *anyopaque,
    /// Set to true from any thread to stop the loop cleanly.
    shutdown: std.atomic.Value(bool),
    /// Tier 3 — optional intent-action router.  When non-null,
    /// `run()` calls `router.tick()` once per poll tick to drain
    /// the router's pending-action queue (filled by the broker
    /// callback when `intent_cell.created` events fire).  Cheap:
    /// when the queue is empty (the common case) it's a single
    /// mutex acquire + length check.  Borrowed pointer; cmdServe
    /// owns the actual Router instance.
    intent_router: ?*intent_action_router_mod.Router = null,
    /// Tier 3 follow-up — optional visit-rollup router, drained on
    /// the same poll tick as `intent_router`. Borrowed pointer;
    /// cmdServe owns the Router. Cheap when its queue is empty.
    visit_rollup_router: ?*visit_rollup_router_mod.Router = null,
    /// Slice 4 — optional quote-seed router, drained on the same poll
    /// tick. Borrowed pointer; cmdServe owns the Router. Cheap when
    /// its queue is empty.
    quote_seed_router: ?*quote_seed_router_mod.Router = null,
    /// Phase U.2 — optional UDP dispatcher. When non-null, its socket
    /// occupies slot `udp_slot_idx` in `poll_fds`; on POLL.IN the
    /// reactor drains it via `handleDatagramReady()`. Borrowed pointer;
    /// the caller (cmdServe) owns the dispatcher lifecycle.
    udp_dispatcher: ?*udp_dispatcher_mod.UdpDispatcher = null,
    /// Slot index of the UDP socket in `poll_fds` if `udp_dispatcher`
    /// was attached, else 0 (meaningless when dispatcher is null).
    udp_slot_idx: usize = 0,
    /// First slot in `poll_fds` that holds a TCP connection. Defaults
    /// to 1 (right after the listener at slot 0). Bumped to 2 after
    /// `attachUdpDispatcher()` so the connection sweep skips the UDP fd.
    conn_start_idx: usize = 1,

    pub fn init(
        allocator: std.mem.Allocator,
        listener_fd: std.posix.fd_t,
        make_ctx: *const fn (fd: std.posix.fd_t, ud: *anyopaque) anyerror!ConnectionContext,
        make_ctx_ud: *anyopaque,
    ) !EventLoop {
        // Use per-method-allocator form (Zig 0.15 ArrayList API).
        var poll_fds: std.ArrayList(std.posix.pollfd) = .{};
        var states: std.ArrayList(?*ConnectionState) = .{};

        // Slot 0 — listener.
        try poll_fds.append(allocator, .{
            .fd = listener_fd,
            .events = std.posix.POLL.IN,
            .revents = 0,
        });
        try states.append(allocator, null); // listener has no ConnectionState

        return .{
            .allocator = allocator,
            .poll_fds = poll_fds,
            .states = states,
            .listener_fd = listener_fd,
            .make_ctx = make_ctx,
            .make_ctx_ud = make_ctx_ud,
            .shutdown = std.atomic.Value(bool).init(false),
        };
    }

    pub fn deinit(self: *EventLoop) void {
        // Close and free all active connections.
        var i: usize = 1;
        while (i < self.states.items.len) : (i += 1) {
            if (self.states.items[i]) |s| {
                std.posix.close(self.poll_fds.items[i].fd);
                s.deinit();
                self.allocator.destroy(s);
            }
        }
        self.poll_fds.deinit(self.allocator);
        self.states.deinit(self.allocator);
    }

    /// Signal the loop to stop after the current poll tick.
    pub fn stop(self: *EventLoop) void {
        self.shutdown.store(true, .release);
    }

    /// Phase U.2 — register a UDP dispatcher with the reactor so its socket
    /// is polled alongside the TCP listener and connections. Must be called
    /// before `run()` and before any TCP connections are accepted; the
    /// connection sweep assumes the UDP fd is the only non-listener,
    /// non-connection entry in `poll_fds`.
    pub fn attachUdpDispatcher(
        self: *EventLoop,
        dispatcher: *udp_dispatcher_mod.UdpDispatcher,
    ) !void {
        std.debug.assert(self.udp_dispatcher == null);
        std.debug.assert(self.poll_fds.items.len == 1); // listener only
        try self.poll_fds.append(self.allocator, .{
            .fd = dispatcher.socket_fd,
            .events = std.posix.POLL.IN,
            .revents = 0,
        });
        try self.states.append(self.allocator, null);
        self.udp_dispatcher = dispatcher;
        self.udp_slot_idx = 1;
        self.conn_start_idx = 2;
    }

    /// Run the reactor until stop() is called or a fatal error occurs.
    /// Blocks the calling thread.
    pub fn run(self: *EventLoop) !void {
        while (!self.shutdown.load(.acquire)) {
            // Tier 3 — intent-action router tick.  Drains any
            // `intent_cell.created` events the broker enqueued since
            // the last tick.  Runs OUTSIDE the broker mutex so a
            // resulting `jobs.transition` can re-publish
            // `job.transitioned` without deadlocking.
            if (self.intent_router) |r| r.tick();
            // Tier 3 follow-up — drain the visit-rollup queue
            // (visit.transitioned→completed → job `visited`). Same
            // off-broker-mutex safety as the intent router.
            if (self.visit_rollup_router) |r| r.tick();
            // Slice 4 — drain the quote-seed queue (job.transitioned
            // qualified→quoted → seed draft Quote). Same
            // off-broker-mutex safety as the other routers.
            if (self.quote_seed_router) |r| r.tick();

            // T3 — per-connection pre-tick drain.  Lets cross-thread
            // producers (e.g. OddjobzEventBus subscribers for the
            // /api/v1/events WSS endpoint) flush queued WSS frames
            // into the per-connection write_buf.  The POLL.OUT
            // re-registration below picks them up if the connection
            // didn't have an I/O event this tick.
            {
                var k: usize = self.conn_start_idx;
                while (k < self.states.items.len) : (k += 1) {
                    if (self.states.items[k]) |s| {
                        s.tickDrain();
                        // Refresh POLL.OUT registration in case the
                        // drain added bytes to write_buf without the
                        // fd otherwise being touched this tick.
                        self.poll_fds.items[k].events = if (s.needsWrite())
                            std.posix.POLL.IN | std.posix.POLL.OUT
                        else
                            std.posix.POLL.IN;
                    }
                }
            }

            const ready = try Poller.wait(self.poll_fds.items, POLL_TIMEOUT_MS);
            if (ready == 0) continue;

            // Accept new connections when the listener is readable.
            if (self.poll_fds.items[0].revents & std.posix.POLL.IN != 0) {
                self.poll_fds.items[0].revents = 0;
                self.acceptNewConnection() catch |err| {
                    std.log.warn("accept failed: {s}", .{@errorName(err)});
                };
            }

            // Phase U.2 — drain UDP datagrams when the dispatcher slot is
            // readable. Each call drains until WouldBlock, so we service
            // every queued datagram in this tick (matches the brief's
            // reactor-isolation property: a UDP flood cannot starve TCP
            // because we yield to the next poll cycle once the socket
            // returns WouldBlock).
            if (self.udp_dispatcher) |udp| {
                const idx = self.udp_slot_idx;
                if (self.poll_fds.items[idx].revents & std.posix.POLL.IN != 0) {
                    self.poll_fds.items[idx].revents = 0;
                    udp.handleDatagramReady() catch |err| {
                        std.log.warn("udp datagram dispatch failed: {s}", .{@errorName(err)});
                    };
                }
            }

            // Sweep connection fds.  Use an index loop so we can
            // swap-remove while iterating.
            var i: usize = self.conn_start_idx;
            while (i < self.poll_fds.items.len) {
                const revents = self.poll_fds.items[i].revents;
                self.poll_fds.items[i].revents = 0;
                if (revents == 0) {
                    i += 1;
                    continue;
                }

                const state = self.states.items[i].?;
                const result = state.handleEvent(revents) catch |err| blk: {
                    std.log.warn("connection fd={d} error: {s}", .{
                        self.poll_fds.items[i].fd,
                        @errorName(err),
                    });
                    break :blk .closed;
                };

                // Update POLL.OUT registration based on whether there
                // are pending writes.
                if (result == .keep_open) {
                    self.poll_fds.items[i].events = if (state.needsWrite())
                        std.posix.POLL.IN | std.posix.POLL.OUT
                    else
                        std.posix.POLL.IN;
                    i += 1;
                } else {
                    // Close fd, free state, swap-remove so the next
                    // element (swapped into position i) is checked on the
                    // next loop iteration without incrementing i.
                    std.posix.close(self.poll_fds.items[i].fd);
                    state.deinit();
                    self.allocator.destroy(state);
                    _ = self.poll_fds.swapRemove(i);
                    _ = self.states.swapRemove(i);
                    // i stays the same — the swapped-in element is next.
                }
            }
        }
    }

    /// Make the acceptNewConnection step publicly callable for the
    /// cancel-aware serve() wrapper in site_server.zig.
    pub fn acceptNewConnection(self: *EventLoop) !void {
        if (self.poll_fds.items.len - 1 >= MAX_CONNECTIONS) {
            // At capacity — accept and immediately close to avoid
            // leaving the connection in SYN_RCVD limbo.
            const fd = try std.posix.accept(self.listener_fd, null, null, std.posix.SOCK.NONBLOCK);
            std.posix.close(fd);
            std.log.warn("event_loop: MAX_CONNECTIONS ({d}) reached, dropping connection", .{MAX_CONNECTIONS});
            return;
        }

        const fd = try std.posix.accept(self.listener_fd, null, null, std.posix.SOCK.NONBLOCK);
        errdefer std.posix.close(fd);

        const ctx = try self.make_ctx(fd, self.make_ctx_ud);
        const state = try self.allocator.create(ConnectionState);
        errdefer self.allocator.destroy(state);
        state.* = ConnectionState.init(self.allocator, fd, ctx);

        try self.poll_fds.append(self.allocator, .{
            .fd = fd,
            .events = std.posix.POLL.IN,
            .revents = 0,
        });
        try self.states.append(self.allocator, state);
    }
};

// ── Embedded unit tests ───────────────────────────────────────────────────
// These drive EventLoop through a full poll cycle using socketpair().

const testing = std.testing;

fn echoHttpDispatch(args: connection_state.HttpDispatchArgs) connection_state.HttpDispatchResult {
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
    return .close_after_drain;
}

fn echoWssDispatch(args: connection_state.WssDispatchArgs) connection_state.WssDispatchResult {
    _ = args;
    return .keep_open;
}

fn noopFreeWssCtx(_: *anyopaque, _: std.mem.Allocator) void {}

var dummy_wss_ctx: u8 = 0;
var dummy_http_ctx: u8 = 0;

fn makeTestMakeCtx(fd: std.posix.fd_t, ud: *anyopaque) anyerror!ConnectionContext {
    _ = fd;
    _ = ud;
    return .{
        .dispatch_http = &echoHttpDispatch,
        .dispatch_wss = &echoWssDispatch,
        // body_policy_fn left null → parser uses initDefault (256 KB cap).
        .body_policy_ctx = @ptrCast(&dummy_http_ctx),
        .http_ctx = @ptrCast(&dummy_http_ctx),
        .wss_ctx = @ptrCast(&dummy_wss_ctx),
        .free_wss_ctx = &noopFreeWssCtx,
        // pre_tick_drain left null in tests.
        .tick_drain_ctx = @ptrCast(&dummy_http_ctx),
    };
}

test "event_loop: accepts a connection and handles a GET request" {
    // Create a real listener socket.
    const addr = try std.net.Address.parseIp4("127.0.0.1", 0);
    var listener = try addr.listen(.{ .reuse_address = true });
    defer listener.deinit();

    // Make the listener fd non-blocking so poll() is responsive.
    const listener_fd = listener.stream.handle;
    const flags = try std.posix.fcntl(listener_fd, std.posix.F.GETFL, 0);
    _ = try std.posix.fcntl(listener_fd, std.posix.F.SETFL, flags | @as(u32, @bitCast(std.posix.O{ .NONBLOCK = true })));

    var loop = try EventLoop.init(
        testing.allocator,
        listener_fd,
        &makeTestMakeCtx,
        @ptrCast(&dummy_wss_ctx),
    );
    defer loop.deinit();

    // Connect a client.
    const actual_addr = listener.listen_address;
    const client_fd = try std.posix.socket(std.posix.AF.INET, std.posix.SOCK.STREAM, 0);
    defer std.posix.close(client_fd);
    try std.posix.connect(client_fd, &actual_addr.any, actual_addr.getOsSockLen());

    // Poll once — should accept the new connection.
    const ready1 = try Poller.wait(loop.poll_fds.items, 200);
    try testing.expect(ready1 > 0);
    try loop.acceptNewConnection();
    try testing.expectEqual(@as(usize, 2), loop.poll_fds.items.len);

    // Send a GET request from the client.
    const req = "GET /ping HTTP/1.1\r\nHost: x\r\n\r\n";
    _ = try std.posix.write(client_fd, req);

    // Wait for the data to arrive on the server side.
    const ready2 = try Poller.wait(loop.poll_fds.items[1..], 500);
    try testing.expect(ready2 > 0);

    // Process the request.
    const state = loop.states.items[1].?;
    const result = try state.handleEvent(loop.poll_fds.items[1].revents);
    // echo dispatcher returns close_after_drain, write_buf should be populated.
    try testing.expect(state.write_buf.items.len > 0);
    try testing.expect(result == .keep_open); // want_close_after_drain set, not yet closed
}

test "event_loop: stop() causes run() to return" {
    const addr = try std.net.Address.parseIp4("127.0.0.1", 0);
    var listener = try addr.listen(.{ .reuse_address = true });
    defer listener.deinit();

    const listener_fd = listener.stream.handle;
    const flags = try std.posix.fcntl(listener_fd, std.posix.F.GETFL, 0);
    _ = try std.posix.fcntl(listener_fd, std.posix.F.SETFL, flags | @as(u32, @bitCast(std.posix.O{ .NONBLOCK = true })));

    var loop = try EventLoop.init(
        testing.allocator,
        listener_fd,
        &makeTestMakeCtx,
        @ptrCast(&dummy_wss_ctx),
    );
    defer loop.deinit();

    // Signal stop immediately — run() should return after one 100ms tick.
    loop.stop();
    try loop.run();
}

```
