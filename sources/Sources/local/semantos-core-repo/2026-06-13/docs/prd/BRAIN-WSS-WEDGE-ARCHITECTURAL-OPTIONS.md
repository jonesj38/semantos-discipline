---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/BRAIN-WSS-WEDGE-ARCHITECTURAL-OPTIONS.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.655184+00:00
---

# brain serve WSS-wedge — architectural options

**Status**: design call needed. Operator to choose between three options.
**Reporter**: Bridget Doran (2026-05-07 02:38 demo session)
**Severity**: blocks live cross-machine demo + the FSM-write-direction validation. Likely also explains yesterday's "Quote button taps don't produce `jobs.transition` audit entries" — phone POSTs race the wedged read loop.

---

## §1 — Symptom

With a phone holding a WSS connection to `/api/v1/wallet`, every other request to the brain (POST `/api/v1/repl` from a Mac, REST calls from the same phone, even raw `GET /` via `nc`) times out: TCP connection accepts, but no response is ever sent.

Phone surfaces "failed to load visits / network error / receive timeout."

Reproducible locally on Bridget's VM (no Caddy involvement):

```bash
pkill -9 -f 'brain serve'
cd ~/semantos-core/runtime/semantos-brain && ./zig-out/bin/brain serve <site> --enable-repl --port 8080 &

# Connect anything that does GET /api/v1/wallet → 101 Switching Protocols
# (the iOS app does this on launch)

# Then from the same VM:
curl --max-time 5 -X POST http://localhost:8080/api/v1/repl \
  -H 'Content-Type: application/json' -d '{"command":"ping"}'
# → HTTP 000 | 5.001s
```

## §2 — Diagnosis

`/proc/<pid>/stack` shows the main thread blocked in a kernel `read()` syscall on the WSS socket:

```
[<0>] wait_woken+0x7f/0x90
[<0>] sk_wait_data+0x17d/0x1a0
[<0>] tcp_recvmsg_locked+0x240/0xb20
[<0>] tcp_recvmsg+0x83/0x200
[<0>] sock_read_iter+0x8b/0x100
[<0>] vfs_read+0x353/0x390
[<0>] ksys_read+0xce/0xf0
```

`ss -tnp | grep :8080` shows growing `CLOSE-WAIT` count — server isn't calling `close()` when peer sends FIN on a half-finished read. Connection slots accumulate forever until restart.

Source confirms by design: `runtime/semantos-brain/src/site_server.zig:17-22`:
> *"Single-threaded request loop. Each connection is handled to completion before accept()ing the next. Fine for personal / low-traffic sovereign nodes (the vast majority of v0.1 deployments). Multi-connection threading is operator infra (run multiple brain processes behind a load balancer) and lands in WSITE2.5+ if warranted."*

The "warranted" trigger has fired: cross-machine pairing demo + TestFlight roadmap need a brain that can serve more than one connection at a time.

## §3 — Two layered bugs

1. **CLOSE-WAIT leak** — read-EOF not triggering `close()`. Connection slots accumulate. Fix is a few lines (handle EOF in the read loop, `socket.close()` on EOF or read error). Lands deceptively — the brain still wedges as soon as the phone's WSS attaches, because of #2.
2. **Single-thread WSS hold** (the demo blocker) — main thread is parked inside the WSS read loop, no other connections can be `accept()`'d or serviced.

The CLOSE-WAIT fix is small and worth shipping for hygiene, but it doesn't unblock the demo. The threading model is the actual fix.

## §4 — Three architectural options

### Option A — Thread-per-connection

Simplest model. On each `accept()`, `std.Thread.spawn` a worker that handles the connection to completion, then exits. Main loop continues to `accept()` immediately.

**Pros**:
- ~30-50 lines of change in `site_server.zig`
- Conceptually trivial; matches what most HTTP servers do
- Scales to dozens of concurrent connections without issue (each WSS is mostly idle)

**Cons**:
- Each thread costs ~1-2 MB of stack by default; running thousands of WSS connections would balloon RAM. Not relevant at personal-node scale.
- Shared mutable state (broker, view stores, audit log) needs synchronisation. Most reads are already lock-free; writes need audit. Audit is moderate work but localised.

**Effort**: 1-2 days for safe ship + audit of all state mutations + tests.

### Option B — Async I/O with poll/select

Rewrite the I/O loop to be non-blocking. One thread, many sockets, multiplexed via `std.posix.poll` or `std.os.linux.epoll` (Linux-only) / `kqueue` (Darwin).

**Pros**:
- Single thread, no shared-state synchronisation problems
- Scales to thousands of WSS connections trivially
- Natural fit for Zig's async story (when stable)

**Cons**:
- Requires rewriting every handler to be non-blocking — currently `handleRequest()` does blocking reads/writes throughout. Major refactor.
- `std.http.Server` doesn't fully support non-blocking mode in 0.15.2. Would need either the upcoming async-aware HTTP machinery or a hand-rolled subset.
- Multi-day effort with significant risk surface.

**Effort**: 5-10 days. Substantial.

### Option C — Split WSS pump to its own thread (SMALLEST SCOPE)

Keep the main accept loop synchronous as today. When the request reaches the WSS upgrade handler in `wss_wallet.zig`, `std.Thread.spawn` a dedicated WSS pump thread for that connection's lifetime. Main accept loop continues immediately.

**Pros**:
- Targeted fix exactly where the wedge is
- Doesn't touch HTTP request handling for non-WSS paths (which are fast and complete in microseconds)
- Maybe ~50-100 lines including the EOF + close handling
- Each long-lived WSS connection costs one thread; HTTP requests cost zero extra threads. Personal-node scale is fine.

**Cons**:
- Same shared-state concerns as Option A but constrained to the small surface that WSS handlers touch (broker subscribe, audit log writes).
- Two code paths (HTTP-sync, WSS-thread) — slight cognitive overhead.

**Effort**: 1-2 days.

## §5 — Recommendation

**Option C** as the v0.1.5 ship target. It addresses the demo blocker with the smallest design surface; doesn't preclude Option B as a future evolution; matches the system's existing "WSS is where the long-lived multiplex happens" architecture cleanly.

The CLOSE-WAIT leak fix folds in naturally as part of the WSS pump's `defer socket.close()` + EOF handling.

---

## §6 — Cross-references for the agent that ships this

- `runtime/semantos-brain/src/site_server.zig` — main accept loop + `handleRequest`. The hand-off point is wherever the WSS upgrade is detected (search for `Upgrade: websocket`).
- `runtime/semantos-brain/src/wss_wallet.zig` — the WSS read loop currently running on the main thread. This is where the spawn would end.
- `runtime/semantos-brain/src/dispatcher.zig` — JSON-RPC dispatch (called from WSS pump). Already uses arena allocators per-request; no obvious shared-state hazards beyond the broker / audit log.
- `runtime/semantos-brain/src/broker.zig` — pub/sub broker. Audit if topic-publish + topic-subscribe are thread-safe.
- `runtime/semantos-brain/src/audit_log.zig` — audit append. Audit if the file-handle mutation is thread-safe.

## §7 — Bridget's offer

> *"Happy to take a swing at it if you want, but my read is the threading model is enough of a design call that you'd want to pick the shape. The diagnosis above should be the hard part."*

Right call from Bridget. The diagnosis IS the hard part. Operator picks Option A/B/C, and either Bridget or another agent ships the implementation against that target.

---

## §9 — Decision history (2026-05-07)

### First pass: Option D selected
Operator initially picked Option D (reactor + worker thread pool with 3 mutexes).

### Reconsidered: switched to B-pragmatic
Operator pushed back on two of my arguments:
1. **Zig async risk was overstated.** I conflated Zig's language-level async features (`async`/`await`, in flux) with the syscall wrappers (`std.posix.poll`, `epoll_wait`, `kevent`) which are perfectly stable. The reactor pattern doesn't need language async — nginx and redis are hand-rolled state machines using these same syscalls.
2. **No-mutex state model is a real correctness win.** With single-threaded I/O loop, the view stores + broker + audit log don't need locks because there's only ever one writer. That's not just less code — it's no deadlock surface, no missed-mutex races, no lock ordering discipline.

A middle path I should have proposed initially: **B-pragmatic** — single-threaded reactor for ALL state-touching work; small worker pool offloads only genuinely slow blocking I/O (LLM API calls, etc.) and returns results via channel. This is what redis does. Most of brain's work (cell mints, view reads, JSONL appends, bearer-token verify) is microsecond-scale and stays on the main thread.

### Final decision: B-pragmatic
**Estimated effort**: 3-5 days vs D's 1-2 days. The extra time buys "right thing once" — no later refactor when scale grows.

**Reasoning recap**:
- UTXO-atomic-state model + single-threaded reactor → state correctness for free
- Scales to ~10k+ WSS without extra work (vs D's ~1k thread-cost ceiling)
- Architecturally aligned with operator's "bind workflows to UTXOs" intuition
- Zig poll/epoll syscall wrappers are stable — no language async risk
- Most likely there's NO slow blocking I/O in the Semantos Brain serve path (LLM calls are in legacy-ingest); worker pool may not even be needed for v1

Implementation brief: `docs/prd/BRAIN-WEDGE-FIX-IMPLEMENTATION-BRIEF.md` (rewritten for B-pragmatic).

## §10 — Adjacent: Bridget shipped a stable HTTPS endpoint (related, no action needed)

While diagnosing the wedge, Bridget set up `brain.utxoengineer.com` via Caddy reverse-proxy → `localhost:8080`, with Let's Encrypt auto-cert. Persistent across VM reboot. Solves the ngrok-rotating-URL problem; survives the TestFlight roadmap; gives a stable cross-brain endpoint.

She's offering the operator a bearer token for cross-brain testing at `https://brain.utxoengineer.com/api/v1/repl`. Adjacent infrastructure — captured here so the operator sees it in context.
