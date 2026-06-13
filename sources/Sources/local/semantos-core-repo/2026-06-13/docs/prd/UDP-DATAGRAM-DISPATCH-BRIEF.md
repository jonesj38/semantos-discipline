---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/UDP-DATAGRAM-DISPATCH-BRIEF.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.693821+00:00
---

# Phase U.2 — brain UDP datagram dispatch (implementation brief)

**Status**: paste-ready agent brief.
**Depends on**: U.1 (node-protocol bring-forward landed) + brain-wedge reactor PR landed.
**Subagent type**: bsv-blockchain-ts-sdk-expert (Zig/brain expert).
**Estimated effort**: 2-3 days.

---

## Brief (paste directly to agent)

Working in `/Users/toddprice/projects/semantos-core/runtime/semantos-brain`.

# Task: brain UDP datagram dispatch (Phase U.2)

The brain-wedge reactor (poll-based event loop in `event_loop.zig`) is landed. Phase U.1 is complete (PR #417 + previously-undiscovered #108). Read `docs/prd/UDP-MESH-DIRECTION.md` §3 for the full vision and architectural surprises.

**UDP transport actual paths** (corrected from earlier brief assumptions):
- TS-side `UdpTransport` interface lives at `core/protocol-types/src/adapters/udp-transport.ts` (with `LoopbackUdpTransport` + `NodeUdpTransport`). Used by TS consumers (jam-room, poker-agent).
- For brain's UDP dispatch, implement DIRECTLY in Zig using `std.posix.socket(AF_INET, SOCK_DGRAM, 0)` — there is NO `runtime/udp-transport/` package. The brain-side wire format (defined below) is brain-internal; cross-language interop with TS UdpTransport consumers is out of scope for v1.
- session-protocol's MulticastAdapter is now a 60-line shim into `./multicast/`; if your design touches it, import from session-protocol's exported barrel (don't reach into the split files directly).

Your job: add a UDP socket to the existing reactor's poll set so brain can receive UDP datagrams alongside its existing TCP/HTTPS surface. Each datagram is a complete unit (no fragmentation in v1, no per-connection state machine needed) — `recvfrom()` returns one datagram per call; dispatch by datagram type code; emit response via `sendto()`.

# Architecture

**One** reactor, **two** I/O types:

```
poll_fds = [
    listener_tcp_fd,                      // existing — accepts TCP connections
    udp_socket_fd,                        // NEW — receives UDP datagrams
    ...accepted TCP connections...        // existing — per-conn state machines
]
```

When poll() returns:
- TCP listener ready → accept() new TCP conn (existing path)
- TCP conn ready → advance HTTP/WSS state machine (existing path)
- UDP socket ready → `recvfrom()` ONE datagram → dispatch by type → optionally `sendto()` response

UDP is simpler than TCP: no `ConnectionState`, no per-connection read buffer, no partial-read handling. Each datagram fits in 1472 bytes (well below MTU after UDP header). Self-contained.

# What to ship

## Step 1 — `runtime/semantos-brain/src/udp_dispatcher.zig` (new)

```zig
pub const UdpDispatcher = struct {
    allocator: Allocator,
    socket_fd: std.posix.fd_t,
    server: *SiteServer,

    pub fn init(allocator: Allocator, port: u16, server: *SiteServer) !*UdpDispatcher {
        // socket(AF_INET, SOCK_DGRAM | SOCK_NONBLOCK, 0)
        // bind to 0.0.0.0:port
    }

    /// Called by EventLoop when poll() flags POLL.IN on socket_fd.
    pub fn handleDatagramReady(self: *UdpDispatcher) !EventResult {
        var buf: [1472]u8 = undefined;  // UDP MTU minus IP/UDP headers
        var src_addr: std.posix.sockaddr = undefined;
        var src_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr);

        while (true) {
            const n = std.posix.recvfrom(self.socket_fd, &buf, 0, &src_addr, &src_len) catch |err| switch (err) {
                error.WouldBlock => return .keep_open,  // drained for this poll cycle
                else => return err,
            };
            if (n < HEADER_SIZE) continue;  // malformed, drop silently
            try self.dispatchDatagram(buf[0..n], src_addr);
        }
    }

    fn dispatchDatagram(self: *UdpDispatcher, datagram: []const u8, src_addr: std.posix.sockaddr) !void {
        // Parse header: type byte, nonce, sender peer cellId, HMAC
        // Verify HMAC against sender's shared key (looked up in contacts cell-DAG)
        // Switch on type:
        //   - CELL_SYNC: append cell to graph if novel, emit ACK datagram
        //   - TOPIC_BROADCAST: emit to local pub/sub broker
        //   - HEARTBEAT: update sender's lastSeenAddr in contact cell
        //   - REPLY: route to pending request by nonce
    }

    pub fn deinit(self: *UdpDispatcher) void {
        std.posix.close(self.socket_fd);
    }
};
```

## Step 2 — Datagram header format

Define in a shared module (`runtime/semantos-brain/src/udp_protocol.zig` — new):

```
[1 byte]   datagram type (CELL_SYNC | TOPIC_BROADCAST | HEARTBEAT | REPLY)
[16 bytes] nonce (random, used for replay protection)
[32 bytes] sender peer cellId (sha256-hash, content-addressed)
[N bytes]  payload (cell-encoded, type-dependent)
[32 bytes] HMAC-SHA256 over (everything above, keyed by ECDH-derived shared secret)
```

Total header overhead: 81 bytes. Payload max: 1472 - 81 = 1391 bytes for v1.

This matches the operator's "1024-byte cells" comfortably.

## Step 3 — Anti-replay cache

Per-peer recently-seen-nonce set:

```zig
pub const AntiReplayCache = struct {
    seen: std.StringHashMap(void),   // peerCellId -> set of recent nonces
    max_age_ms: u64 = 5_000,
    // ... timestamp-windowed cache
};
```

If incoming datagram's nonce is in the cache for that peer → drop silently. Otherwise add + handle.

## Step 4 — `runtime/semantos-brain/src/event_loop.zig` integration

Modify `EventLoop` to optionally hold a `*UdpDispatcher` field. If present, register its socket_fd in `poll_fds` (similar to how the TCP listener is registered at index 0). When poll() returns POLL.IN on that fd, call `udp.handleDatagramReady()`.

## Step 5 — `runtime/semantos-brain/src/site_server.zig` integration

Add a `--enable-udp <port>` CLI flag to `brain serve`. When set, construct a `UdpDispatcher` and hand it to the `EventLoop`. Default off — operator's existing TCP-only deployments unchanged.

## Step 6 — Tests

`runtime/semantos-brain/tests/udp_dispatcher_conformance.zig`:

1. Round-trip: synthesize a peer + shared secret + datagram → dispatcher receives → HMAC verifies → handler dispatched
2. Bad HMAC: tampered datagram dropped silently
3. Replay: same nonce twice → second dropped
4. Type dispatch: CELL_SYNC appends to graph, TOPIC_BROADCAST publishes to broker, HEARTBEAT updates lastSeenAddr
5. Concurrent UDP + TCP: poll loop with both → both serviced in same cycle (this is the U.2 cousin of the Semantos Brain-wedge isolation property)
6. Socket close + re-open across poll cycles

## Step 7 — TLA+ extension (defensive)

Update `proofs/tla/ReactorIsolation.tla` to model two socket types: `tcpFds` and `udpFds`. The `RunReactorCycle` action services both atomically. The `IsolationFromStalledConnections` property extends to: "a stalled TCP connection cannot prevent UDP datagram dispatch, and vice versa."

`make check` must continue to pass.

# Constraints

- Don't change brain's CLI surface for users who don't pass `--enable-udp`
- v1 supports payloads ≤ 1391 bytes (one datagram). Fragmentation deferred.
- v1 supports same-network UDP only (no NAT traversal). Cross-network falls back to brain-relayed flow.
- Use Zig stdlib (`std.posix.socket(AF_INET, SOCK_DGRAM | SOCK_NONBLOCK, 0)`, `std.posix.recvfrom`, `std.posix.sendto`) for UDP I/O — there's no `runtime/udp-transport/` package despite the earlier brief assuming so. The TS-side UdpTransport interface (`core/protocol-types/src/adapters/udp-transport.ts`) is for TS consumers only.
- No new external deps; use stdlib + already-vendored packages

# Verification

```
cd /Users/toddprice/projects/semantos-core/runtime/semantos-brain && zig build test
cd ../../proofs/tla && make check
```

# PR

Branch `feat/u2-udp-datagram-dispatch` from origin/main. Title: "Phase U.2 — brain UDP datagram dispatch".

Body: list new files, datagram format spec, replay-protection design, TLA+ extension summary, ties-in to UDP-MESH-DIRECTION.md §3 Phase U.2.

Auto-merge authority on green tests.

Report back: PR URL + 5-line summary including the Zig socket primitives used + how the Semantos Brain wire format compares to the TS-side UdpTransport (we may want to interop later).
