---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/BRAIN-WEDGE-FIX-IMPLEMENTATION-BRIEF.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.683173+00:00
---

# brain-wedge fix — Option B-pragmatic implementation brief

**Status**: paste-ready agent brief. Operator selected **B-pragmatic** (single-threaded reactor + optional worker pool for slow I/O) per `BRAIN-WSS-WEDGE-ARCHITECTURAL-OPTIONS.md` §9.
**Subagent type**: bsv-blockchain-ts-sdk-expert (despite name, this agent is the Zig/brain expert too)
**Estimated effort**: 3-5 days careful work, requires real WSS connection rig for verification (Bridget has one).

---

## Why B-pragmatic vs D

Single-threaded reactor IS the synchronization. No mutexes needed on view stores, broker, or audit log because only one thread mutates state. This matches the operator's "bind workflows to UTXOs for atomic state" intuition: the cell-DAG layer is lock-free by design, and the reactor extends that property to the derived layer for free.

The worker pool exists in the design for genuinely-slow blocking I/O (LLM calls, heavy disk fsync, etc.). **Audit step #1 below: confirm whether any slow blocking ops live in the Semantos Brain serve path.** If they don't (LLM calls are in legacy-ingest, not brain), v1 ships without a worker pool — pure single-threaded reactor.

---

## Brief (paste directly to agent)

Working in `/Users/toddprice/projects/semantos-core/runtime/semantos-brain`.

# Task: brain serve — single-threaded reactor (B-pragmatic, Option B)

Bridget Doran reproduced a demo-blocking wedge: with one phone holding a WSS connection to `/api/v1/wallet`, every other request to the brain times out. Single-threaded accept loop + blocking read on the WSS socket = no other connection serviceable. Read `docs/prd/BRAIN-WSS-WEDGE-ARCHITECTURAL-OPTIONS.md` for diagnosis + the operator's B-pragmatic choice.

# Architecture

ONE thread (the main thread) owns:
- The poll() / epoll_wait() / kevent() syscall loop (use `std.posix.poll` for cross-platform v1; abstract behind a thin interface so we can swap to `epoll_wait`/`kevent` later if 10k+ connections become real)
- All connection state machines (HTTP request parsing, WSS frame parsing)
- All cell mints + view-store writes + broker dispatches + audit log writes (nothing blocks for more than microseconds)

If audit step #1 (below) finds slow blocking ops in the Semantos Brain path: spawn a 4-thread worker pool for those, communicate via channel (mutex+condvar bounded queue), main thread receives results and continues processing. Result: zero mutex on state, only mutex is on the worker-pool input/output queue.

# What to ship

## Step 0 — Audit slow blocking ops in the Semantos Brain serve path

Search for any operation in `runtime/semantos-brain/src/*.zig` that:
- Makes outbound HTTP calls (LLM API, third-party fetch)
- Blocks on disk fsync (most appends are buffered + fast; explicit fsync is rare)
- Does heavy crypto (BLAKE3 over MB-sized inputs, etc.)

Best-guess answer: there's nothing slow. LLM calls live in `runtime/legacy-ingest`, not `brain`. Most brain work is microsecond-scale: hash, JSONL append, in-memory map lookup, audit append.

**Decision**: if no slow ops, omit the worker pool. v1 is pure single-threaded reactor. If you find any (audit `chat_http.zig`, `voice_extract_http.zig`, etc. by reading), spec the worker pool in the PR description and ship it alongside.

## Step 1 — `runtime/semantos-brain/src/event_loop.zig` (new)

Core abstraction. Owns the poll set + connection states.

```zig
pub const EventLoop = struct {
    allocator: Allocator,
    poll_fds: ArrayList(std.posix.pollfd),
    states: ArrayList(*ConnectionState),
    listener_fd: std.posix.fd_t,
    server: *SiteServer,
    shutdown: std.atomic.Value(bool),

    pub fn init(allocator: Allocator, listener: std.net.Server, server: *SiteServer) !*EventLoop {
        // Allocate self, set listener fd as poll_fds[0], initial states[0] = listener marker
    }

    pub fn run(self: *EventLoop) !void {
        while (!self.shutdown.load(.acquire)) {
            // poll() with a 100ms tick so shutdown signal is responsive
            const ready = std.posix.poll(self.poll_fds.items, 100) catch |err| switch (err) {
                error.SignalInterrupt => continue,
                else => return err,
            };
            if (ready == 0) continue;

            // Index 0 is always the listener
            if (self.poll_fds.items[0].revents != 0) {
                try self.acceptNewConnection();
            }

            // Sweep connection fds
            var i: usize = 1;
            while (i < self.poll_fds.items.len) {
                const events = self.poll_fds.items[i].revents;
                self.poll_fds.items[i].revents = 0;
                if (events == 0) { i += 1; continue; }

                const state = self.states.items[i];
                const result = state.handleEvent(events) catch |err| blk: {
                    std.log.warn("connection {d} error: {any}", .{ self.poll_fds.items[i].fd, err });
                    break :blk .closed;
                };

                switch (result) {
                    .keep_open => i += 1,
                    .closed => {
                        // Close fd, free state, swap-remove from arrays
                        std.posix.close(self.poll_fds.items[i].fd);
                        state.deinit();
                        self.allocator.destroy(state);
                        _ = self.poll_fds.swapRemove(i);
                        _ = self.states.swapRemove(i);
                        // don't increment i — swapped element needs handling
                    },
                }
            }
        }
    }

    fn acceptNewConnection(self: *EventLoop) !void {
        const fd = try std.posix.accept(self.listener_fd, null, null, std.posix.SOCK.NONBLOCK);
        const state = try self.allocator.create(ConnectionState);
        state.* = try ConnectionState.init(self.allocator, fd, self.server);
        try self.poll_fds.append(self.allocator, .{ .fd = fd, .events = std.posix.POLL.IN, .revents = 0 });
        try self.states.append(self.allocator, state);
    }
};

pub const EventResult = enum { keep_open, closed };
```

Key invariants:
- Every fd in `poll_fds` is non-blocking (set via `accept(SOCK_NONBLOCK)` or `fcntl(O_NONBLOCK)` for the listener fd if needed)
- Every read returns `error.WouldBlock` instead of blocking → state machine stores partial bytes, waits for next poll cycle
- Every write that can't send all bytes registers `POLL.OUT` and drains in subsequent cycles

## Step 2 — `runtime/semantos-brain/src/connection_state.zig` (new)

Per-connection state machine. Separate from `event_loop.zig` so the parser logic is testable in isolation.

```zig
pub const ConnectionState = struct {
    allocator: Allocator,
    fd: std.posix.fd_t,
    server: *SiteServer,

    // Read-side: accumulated bytes for the current request
    read_buffer: ArrayList(u8),
    parser_state: enum { reading_headers, reading_body, complete, upgraded_to_wss },
    parsed_request: ?HttpRequest,

    // Write-side: pending bytes to send + tracking offset
    write_buffer: ArrayList(u8),
    write_offset: usize,
    want_close_after_drain: bool,

    // WSS state, populated after upgrade
    wss: ?WssState,

    pub fn handleEvent(self: *ConnectionState, events: i16) !EventResult {
        if (events & (std.posix.POLL.HUP | std.posix.POLL.ERR) != 0) return .closed;

        if (events & std.posix.POLL.IN != 0) {
            const r = try self.handleRead();
            if (r == .closed) return .closed;
        }

        if (events & std.posix.POLL.OUT != 0) {
            const r = try self.drainWrites();
            if (r == .closed) return .closed;
        }

        return .keep_open;
    }

    fn handleRead(self: *ConnectionState) !EventResult {
        var buf: [8192]u8 = undefined;
        const n = std.posix.read(self.fd, &buf) catch |err| switch (err) {
            error.WouldBlock => return .keep_open,
            error.ConnectionResetByPeer => return .closed,
            else => return err,
        };
        if (n == 0) return .closed; // EOF — peer sent FIN. CLOSE-WAIT fix lives here.

        if (self.parser_state == .upgraded_to_wss) {
            return self.feedWssBytes(buf[0..n]);
        }

        try self.read_buffer.appendSlice(self.allocator, buf[0..n]);
        return self.tryParseHttp();
    }

    fn tryParseHttp(self: *ConnectionState) !EventResult {
        // Look for \r\n\r\n.  If absent, keep accumulating.
        const idx = std.mem.indexOf(u8, self.read_buffer.items, "\r\n\r\n") orelse return .keep_open;
        // Parse headers up to idx; remaining bytes are body or pipeline.
        // ... (see HttpParser detail below)
        // On complete: dispatch via self.server, write response into self.write_buffer.
        // If response includes "Upgrade: websocket": switch to .upgraded_to_wss state.
    }

    // ... drainWrites, feedWssBytes, etc.
};
```

## Step 3 — Minimal HTTP/1.1 parser (resumable)

`std.http.Server.receiveHead()` does blocking reads through its reader interface. Maybe extractable, but cleanest to roll a minimal HTTP/1.1 parser that's purely byte-driven and fits the state-machine model:

- Parse request line: `METHOD /path HTTP/1.1`
- Parse headers until `\r\n\r\n`
- If `Content-Length: N` present, accumulate N more bytes as body
- (Skip chunked encoding for v1 — brain doesn't receive chunked anyway; document as TODO if needed)

Output: `HttpRequest { method, path, headers, body }` ready to dispatch through the existing `SiteServer.handleRequest()` (or whatever the dispatch entry point becomes).

~200 lines + tests. Tests should feed bytes one chunk at a time and verify parser handles partial inputs correctly.

## Step 4 — Minimal WSS frame parser (resumable)

After HTTP upgrade, switch to WSS framing per RFC 6455:
- Parse frame header (1-2 bytes)
- Parse extended length (0/2/8 bytes)
- Parse mask key if MASK bit set (4 bytes — always set for client→server)
- Accumulate payload
- Unmask payload, deliver to handler
- Repeat

~150 lines + tests. Test partial-frame inputs (e.g., 1 byte at a time).

## Step 5 — Migrate `site_server.zig::serve()` and `wss_wallet.zig::serveSession()`

Replace `serve()`'s while-true accept loop:
```zig
// Before
pub fn serve(self: *SiteServer, cancel: ?*const std.atomic.Value(bool)) !void {
    var listener = try addr.listen(.{ .reuse_address = true });
    while (true) { const conn = listener.accept(); ...; self.handleConnection(conn); }
}

// After
pub fn serve(self: *SiteServer, cancel: ?*const std.atomic.Value(bool)) !void {
    var listener = try addr.listen(.{ .reuse_address = true });
    var loop = try EventLoop.init(self.allocator, listener, self);
    defer loop.deinit();
    if (cancel) |c| loop.bindCancel(c);
    try loop.run();
}
```

`wss_wallet.zig::serveSession()` currently runs as a blocking loop that owns the connection. Refactor it as a state machine:
- The "loop" body becomes "process one frame" — driven by the event loop calling `feedWssBytes()`
- Internal state (subscribed topics, queue of outbound messages, etc.) stays in the WssState struct
- Outbound writes go into `write_buffer` and the event loop drains them in `POLL.OUT` cycles

This is the heaviest part of the refactor. The existing serveSession is a long blocking function; it needs to become an "advance one step" method called per-frame.

## Step 6 — CLOSE-WAIT leak fix (folded in for free)

In `connection_state.zig::handleRead`, when `read()` returns `0` we return `.closed`, which causes `event_loop.zig::run` to call `std.posix.close(fd)`. That's the close on EOF. Bridget's leak fixed.

For WSS-side, ensure that when the WSS frame parser sees a CLOSE frame OR the read returns EOF, the same `.closed` propagates up.

## Step 7 — Tests

Add `runtime/semantos-brain/tests/event_loop_conformance.zig`:

1. Single connection: GET /api/v1/info → 200 response. Verify response bytes match expected. Use a mock socket pair (pipe).
2. Two simultaneous connections: both make requests "concurrently" (drive poll manually with both fds ready). Verify both responses correct.
3. Slow client: feed bytes of a single request 1 byte at a time. Verify parser eventually completes + responds.
4. WSS upgrade: send valid Upgrade request → verify 101 response → switch to WSS mode → send a frame → verify framed response.
5. WSS hold + concurrent HTTP: phone connection (mock) holds WSS, separate connection sends HTTP request. Verify HTTP gets serviced promptly (within one poll tick).
6. EOF mid-request: client sends partial bytes then closes. Verify state cleanup, no leak.

`runtime/semantos-brain/tests/http_parser_conformance.zig` and `wss_frame_parser_conformance.zig`:
- Standalone parser tests with various partial-input shapes
- Edge cases: huge headers, empty body, body with Content-Length: 0, etc.

## Step 8 — Manual verification with Bridget's rig

Before declaring done:
- Restart `brain serve`
- Connect phone → WSS established
- `curl --max-time 5 -X POST http://localhost:8080/api/v1/repl ...` from same VM — must respond within 1s
- `ss -tnp | grep :8080` — CLOSE-WAIT count must NOT grow on phone reconnects
- Phone taps FSM Quote button — `audit.log` must show `jobs.transition` entry, job state must transition `lead → quoted`

This is the demo-pass criterion.

# Constraints

- Don't change brain's CLI surface; existing `brain serve <site> --enable-repl --port 8080` keeps working
- Don't break existing tests
- v1 uses `std.posix.poll` (works everywhere, fine to ~10k connections); abstract behind a 1-method interface so swapping to `epoll`/`kqueue` later is a couple-day swap
- Zero mutexes for view stores / broker / audit log (single-threaded reactor IS the sync)
- Worker pool ONLY if Step 0 audit finds slow blocking ops in the Semantos Brain path (likely none)
- Pure threaded I/O via `std.posix.read`/`std.posix.write` — no Zig language async/await features

# Verification

```
cd runtime/semantos-brain && zig build test
git diff --stat HEAD
# Expected ~6-8 files: event_loop.zig new, connection_state.zig new, http_parser.zig new,
# wss_frame_parser.zig new, site_server.zig modified, wss_wallet.zig refactored,
# 3-4 test files new
```

Plus manual verification per Step 8.

# PR

Branch `fix/brain-wedge-reactor-option-B` from `origin/main`. Title: "fix(brain): single-threaded reactor unwedges WSS-held server (B-pragmatic)".

Body must include:
- Bridget's diagnosis link
- Step 0 audit result (worker pool included or omitted, with justification)
- Architecture summary (poll loop + per-connection state machines, no mutexes for state)
- WSS migration approach (state machine vs old blocking serveSession)
- CLOSE-WAIT fix called out
- Verification rig used

Report back: PR URL + summary of (a) audit result for slow blocking ops, (b) whether wss_wallet refactor was clean or messy, (c) manual phone test pass/fail.
