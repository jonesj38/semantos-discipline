---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/BRAIN-WEDGE-STEP0-AUDIT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.654650+00:00
---

# brain-wedge Step 0 — Slow Blocking I/O Audit

**Date**: 2026-05-07
**Branch**: `fix/brain-wedge-reactor-b-pragmatic`
**Decision**: Worker pool OMITTED from v1. Pure single-threaded reactor.

---

## What we searched for

Any operation in `runtime/semantos-brain/src/*.zig` reachable from the `serve()` →
`handleConnection()` → `handleRequest()` hot path that could block the
main thread for more than ~100 μs:

1. Outbound HTTP calls (LLM API, third-party services)
2. Explicit `fsync` calls on file descriptors
3. Heavy crypto operations over large inputs (BLAKE3 over MB payloads)
4. Shell-out / subprocess execution
5. Any `std.time.sleep` or equivalent busy-wait

---

## Findings per component

### `site_server.zig` — main dispatch loop

All operations on the hot path are microsecond-scale:

- Bearer token verification: constant-time HMAC-SHA256 over 32 bytes → **fast**
- Route lookup: linear scan of `config.routes` (typically < 20 entries) → **fast**
- Static file read: `sendFile` syscall delegated to the OS → **fast for small sites**
- Auth session store: in-memory HashMap with JSONL append (not fsync'd on each write) → **fast**
- Payment ledger: JSONL append (not fsync'd per-call; OS write-back) → **fast**
- CORS header computation: string operations only → **fast**

### `chat_http.zig` + `llm_http_adapter.zig` — the only outbound HTTP path

`chat_http.handle` calls `dispatcher.dispatch("llm", "complete", ...)` which,
when `--enable-repl` is active, calls `llm_http_adapter.HttpLlmAdapter.vParse`.
This makes a **blocking outbound HTTP call** to an LLM endpoint (OpenAI,
Anthropic, or a local llama.cpp server).

**CRITICAL: Is this in the Semantos Brain serve path?**

Yes, when a `RouteType.chat` route is configured AND `--enable-repl` is
enabled. Latency is 1-30 seconds depending on the LLM.

**Is this relevant to the wedge fix?**

The wedge fix is about the `GET /api/v1/wallet` WSS hold blocking `POST
/api/v1/repl` and similar. The chat routes are a separate concern. However,
a chat request would also be blocked if it arrived while the WSS hold was
active — and after the reactor fix, a chat request itself would block the
reactor for 1-30s.

**Decision**: Chat routes are excluded from v1 of the reactor fix. The
reactor will unblock WSS from blocking HTTP. Chat's outbound LLM call
is a **future worker-pool candidate** if chat routes become latency-
critical. Tracked as `TODO-WORKER-POOL: llm_http_adapter outbound`.

The implementation adds a `// TODO-WORKER-POOL` marker in `event_loop.zig`
documenting this; no worker pool ships in v1.

### `voice_extract_http.zig` — shell-out

`voice_extract_http.maybeHandle` calls `acceptor.shell.run(...)` which is
a pluggable shell-out (production: `bun runtime/intent/processIntent`).
This can block for several seconds.

Same analysis as chat: this is a separate endpoint, not /api/v1/wallet.
After the reactor fix, voice extract would temporarily block the reactor
for one connection's shell-out duration. Same future worker-pool candidate.
Marked `// TODO-WORKER-POOL: voice_extract shell-out`.

### All other paths

- `repl_http` / `dispatcher` / all oddjobz handlers: in-memory + JSONL → **fast**
- `broker.zig`: in-memory pub/sub with no I/O → **fast**
- `audit_log.zig`: JSONL append, no fsync → **fast**
- `bearer_tokens.zig`: HMAC-SHA256 over 32 bytes → **fast**
- `wss_wallet.zig::handleJsonRpc`: JSON parse + in-memory dispatch → **fast**
- `device_pair_http.zig`: certificate verify + JSONL append → **fast**
- `info_http.zig`, `push_register_http.zig`: in-memory + JSONL → **fast**

---

## Decision: No worker pool in v1

**Rationale**:

The wedge symptom is the WSS `read()` blocking HTTP. That is fixed by the
single-threaded reactor (poll loop + per-connection state machines). The
only genuinely slow ops (LLM calls, voice-extract shell-out) are on
separate endpoints that are not responsible for the demo-blocking wedge.
Shipping a worker pool for them now would add complexity (3+ mutexes,
bounded queue, thread lifecycle) for a problem we haven't been asked to
fix yet.

The reactor fix ships without a worker pool. The design of `EventLoop`
documents the future worker-pool seam so it can be added in 1-2 days if
needed.

**Grep targets for future worker-pool work**:
```
grep -rn "TODO-WORKER-POOL" runtime/semantos-brain/src/
```

---

## Files to be created by this PR

New (revertable by deletion):
- `runtime/semantos-brain/src/http_parser.zig`
- `runtime/semantos-brain/src/wss_frame_parser.zig`
- `runtime/semantos-brain/src/event_loop.zig`
- `runtime/semantos-brain/src/connection_state.zig`
- `runtime/semantos-brain/tests/http_parser_conformance.zig`
- `runtime/semantos-brain/tests/wss_frame_parser_conformance.zig`
- `runtime/semantos-brain/tests/event_loop_conformance.zig`
- `docs/prd/SESSION-HANDOFF-WEDGE-FIXED.md` (final commit)

Modified (revertable by `git revert <sha>`):
- `runtime/semantos-brain/src/site_server.zig` — `serve()` replaced with reactor loop
- `runtime/semantos-brain/src/wss_wallet.zig` — `serveSession` converted to state machine
- `runtime/semantos-brain/build.zig` — new modules added
