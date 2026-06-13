---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/ODDJOBZ-WSS-RPC-TRACKER.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.737437+00:00
---

# Oddjobz WSS-RPC Rebuild — Tracker & Handoff Matrix

**Last updated:** 2026-06-09 (M1.7 brain half landed) · **Branch:** `feat/oddjobz-wss-rpc` · **Worktree:** `worktrees/oddjobz-wss-rpc`

Parity rebuild of the oddjobz operator surface in **`apps/semantos`** (Flutter, the
renamed monolith successor) against `archive/apps-semantos-monolith` (reference spec),
talking to the brain over **one unified `/api/v1/rpc` WSS channel**. Full design:
`~/.claude/plans/distributed-doodling-flame.md` (Todd's machine).

## First moves for a new session
```bash
cd /Users/toddprice/projects/semantos-core/worktrees/oddjobz-wss-rpc
git log --oneline f7e6080..HEAD          # what's landed (see commit log below)
# brain unit tests:
cd runtime/semantos-brain && zig build && zig build test-rpc
# flutter unit tests:
cd ../../apps/semantos && flutter pub get && flutter test test/rpc test/repositories
```

## Locked decisions (do not relitigate)
1. **Transport** = ONE multiplexed bidirectional WSS RPC channel (`/api/v1/rpc`), cartridge-agnostic (many cartridges share one brain).
2. **NL pipeline** = hybrid, **BYOK OpenRouter** cloud LLM for SIR extraction (NOT llama.cpp), brain `/voice-extract`+`/intent/classify` fallback.
3. **Strategy** = rebuild on the cartridge/manifest helm shell; monolith is reference only. Drive UI from manifest/schema (anti-circling seam).

## Why this channel matters (the unblock)
The new `/api/v1/rpc` channel is the **immune path** for the long-standing `cell.query`
blocker: the legacy `wss_wallet.zig::handleJsonRpc` static `if`-chain silently drops
the `cell.query`/`cell.get` branches under a deterministic **Zig 0.15.2 codegen bug**
(reproduces locally; `strings <brain> | grep 'cell.query: '` = 0). Runtime-registry
dispatch can't be branch-eliminated. Confirmed live both python + Dart. See memory
`brain_build_cellquery_anomaly`. Root cause NOT chased — channel sidesteps it.

---

## Status matrix

| ID | Milestone / Task | Status | Verified by | Commit |
|----|------------------|--------|-------------|--------|
| M0.1 | Brain `wss_rpc_registry.zig` (registry + frame codec) | ✅ DONE | `zig build test-rpc` (5/5) | `bff5e34` |
| M0.2 | Reactor `/api/v1/rpc` upgrade + frame dispatch + session | ✅ DONE | `zig build` | `18280ca` |
| M0.3 | Register `cell.query` + `repl.eval` substrate methods | ✅ DONE | `zig build test-rpc` | `d0cea6e` |
| M0.4 | Live E2E harness (`scripts/rpc_e2e.py`) | ✅ DONE | python E2E PASS | `3357d0f` |
| M0.5 | `?bearer=` query auth (web/PWA clients) | ✅ DONE | live E2E over query | `8e9849c` |
| M0.6 | Dart `BrainRpcClient` + contract constants + tests | ✅ DONE | `flutter test` (7) + live Dart E2E | `4f95fa9` |
| M1.5 | `JobsRepository` (typed, FSM buckets) on RPC | ✅ DONE | `flutter test` (7) | `6224d03` |
| M1.x | Generic `CellQueryRepository` (type-agnostic read seam) | ✅ DONE | `flutter test` (5) | `b5e3b1d` |
| **M1.6** | **Wire `BrainRpcClient` into app boot + identity** | ⛔ BLOCKED | needs full-app run | — |
| **M1.7a** | **`cells.mint` over RPC (brain half: shared core + method)** | ✅ DONE | `zig build test-rpc` + live dual-path parity | _this branch_ |
| **M1.7b** | **App half: point `IntentDispatcher` at `cells.mint` + retire HTTP clients** | ⛔ BLOCKED | needs M1.6 (live client) + full-app run | — |
| **M1.8** | **Home + FIND generic renderer from manifest** | ⛔ BLOCKED | needs full-app run | — |
| M2 | Conversation first-class + `subscribe` push | ⬜ TODO | — | — |
| M3 | Voice notes on the brain | ⬜ TODO | — | — |
| M4 | BYOK OpenRouter NL pipeline | ⬜ TODO | — | — |
| M5 | Outbox durability + reconnect/resume + retire HTTP | ⬜ TODO | — | — |

Legend: ✅ done · ⛔ blocked (reason below) · ⬜ not started

---

## Blockers (detail)

### B1 — M1.7 brain half ✅ RESOLVED (this branch); app half (M1.7b) still gated on M1.6
- **What (done — brain half):** extracted a shared mint body and registered `cells.mint` on the WSS RPC registry. Both transports now call the same code, so HTTP behaviour can't drift.
- **How the cycle trap was sidestepped:** rather than grow `cells_mint_http.zig`'s import surface (the cycle risk — `attachments_upload_http` is a sibling HTTP handler), a **NEW LEAF `src/cells_mint_core.zig`** holds `mintCellCore(acceptor, mint_req, entry, alloc) -> MintOutcome`. It imports the heavy deps (`substrate_entity` / `anchor_emitter` / `attachments_upload_http` / `cells_mint_validator`) + `cells_mint_http` (Acceptor + parser); none of those import `cells_mint_core`, so no cycle. Verified by build.
  - `reactorHandleCellsMint` now does transport-specific steps 1–5 (acceptor/method/auth/parse/lookup) then delegates 5b–9 to `mintCellCore`, mapping the structured `MintOutcome` back to byte-identical HTTP bodies + status.
  - `wss_rpc_methods.cellsMint` reuses `cells_mint_http.parseRequestBody` (params envelope == HTTP body) → `resolveCellType` → `mintCellCore`, mapping `MintOutcome` to the RPC `res`/`err` frame (`Failure.rpcCode()` maps HTTP status → WSS code vocabulary).
  - Registered in `serve.zig` with `required_cap = "cap.brain.admin"` (matches the admin-gated HTTP route; M0 makes any valid upgrade admin-equivalent).
- **Do NOT** create a second, simpler mint path for intent cells — it would skip the dispatch hook and diverge. (Honoured: there is exactly one mint body.)
- **Verification (done):** `zig build` clean, `zig build test-rpc` green, full `zig build test -j1` green. **Live dual-path parity:** stood up a one-cellType cartridge in an isolated `BRAIN_DATA_DIR`, minted the same body over `curl POST /api/v1/cells` and a `cells.mint` RPC frame — `cartridgeId`+`cellType` identical, both `cellId`s well-formed. NOTE: cellId equality is **not** a valid invariant — the cell embeds a mint timestamp (`substrate_entity` bytes 78..85 = `nanoTimestamp()`), so two separate mints of identical input hash differently by construction. `scripts/rpc_e2e.py` now has a `cells.mint` routing arm (bare brain) + an optional parity arm gated on `RPC_MINT_TYPEHASH`/`RPC_MINT_PAYLOAD`.
- **Still blocked (M1.7b — app half):** point `IntentDispatcher` at `rpc.call("cells.mint", …)` and retire `apps/semantos/lib/src/brain/brain_http_client.dart` + `packages/oddjobz_experience/lib/src/operator/brain_client.dart`. Prereq: **M1.6** (boot wiring) must land first so the app has a live RPC client to mint through.

### B2 — M1.6 / M1.8 need the full Flutter PWA running against a brain
- **What:** M1.6 = construct `BrainRpcClient` from `IdentityStore` creds at boot and hand it to repositories + dispatcher; M1.8 = generic `cell_card`/`cell_list_view` renderer driving Home (grouped jobs) + FIND tabs from manifest render hints, replacing the in-memory recent-mints stub.
- **Why blocked here:** these are boot glue + UI that can only be `flutter analyze`-checked in a headless agent env. They need the **app running against a live brain** (emulator/device/web) to verify a job list renders and a transition fires — which the current session environment can't do. Not a code blocker; an environment one.
- **Entry points:**
  - Boot: `apps/semantos/lib/main.dart:113-193` (`_prepare`). Creds: `identity_adapter.buildIdentityStore()`; pairing saves baseUrl+bearer via `WalletResolver.saveBrainConnection` (`main.dart:332`). Hand the client through `_ShellData` → `SemantosPlatform`.
  - Lifecycle: connect on auth, `close()` on unpair. `BrainRpcClient.connect()` awaits the handshake (surfaces 401 there).
  - Renderer: consume `CellQueryRepository.list(typeHash)` (already built); FIND tab typeHashes/filters come from `packages/oddjobz_experience/assets/manifest.json` query blocks (add them — M1.8 also touches the manifest/schema seam).

### B3 — `cell.get` ✅ RESOLVED (registered as an RPC method)
- `wss_rpc_methods.cellGet` wraps `cell_query_handler.Handler.get` (mirror of `cellQuery`); registered in `serve.zig` alongside `cell.query` with the same read posture (no extra cap). `Handler.get` extracts the 64-hex ref from the params object itself, so the method only pulls `typeHash` and hands it the raw params. Result envelope `{"<singular_key>": {…}|null}`. Live-routing arm added to `scripts/rpc_e2e.py`. App side (`CellQueryRepository` is list-only by design) can adopt it when a by-ref get is needed.

---

## Gotchas (cost real time last session)
- **Bearer token extraction:** `brain bearer issue` prints a `fingerprint:` 64-hex **before** the token. `grep -oE '[0-9a-f]{64}' | head -1` grabs the **fingerprint**. Use:
  `awk '/Token \(copy/{f=1;next} f&&/[0-9a-f]{64}/{print $1;exit}'`.
- **Zig 0.15.2** + macOS has no `timeout`; the Bash tool's own timeout handles long builds. `zig build test-rpc` warnings (ceiling/duplicate) are expected from the registry tests.
- **`?bearer=` vs header:** browsers can't set WS handshake headers → web uses `?bearer=` query (brain accepts it as a fallback when no `Authorization` header; header wins when both present; `require_cert_auth` retires both).
- **Auth at upgrade (M0 simplification):** any valid bearer/cert upgrade → `is_admin=true` on the session (matches brain's bearer-implies-everything posture). `repl.eval` gates on `cap.brain.admin` (passes). When cert→cap-set derivation lands, snapshot real caps in `RpcReactorSession.caps` and stop collapsing `allow_admin`/`allow_user` in `reactorAuthorize`.

---

## Live E2E recipe (local, isolated data dir)
```bash
cd runtime/semantos-brain && zig build
export BRAIN_DATA_DIR=$(mktemp -d /tmp/rpc.XXXXXX)
B=zig-out/bin/brain
TOKEN=$($B bearer issue --label live --ttl-seconds 3600 \
        | awk '/Token \(copy/{f=1;next} f&&/[0-9a-f]{64}/{print $1;exit}')
$B serve localhost --enable-repl --port 8810 &        # entity store + repl + RPC methods
# python path:
RPC_PORT=8810 RPC_TOKEN=$TOKEN python3 scripts/rpc_e2e.py    # needs `websockets`
# Dart path:
cd ../../apps/semantos && RPC_PORT=8810 RPC_TOKEN=$TOKEN flutter test --tags live test/rpc/brain_rpc_live_test.dart
```
A bare brain has no oddjobz decoder, so `cell.query oddjobz.job.v2` answers
`err{not_found, unknown_type_hash}` — that still proves the method ROUTED.

---

## Contract reference (frozen — keep both sides in lockstep)
Frame envelope (RFC 6455 text, `t` discriminates):
```
req  {"t":"req","id":"c-1","method":"cell.query","params":{…}}
res  {"t":"res","id":"c-1","result":{…}}              # handler body verbatim
err  {"t":"err","id":"c-1","code":"forbidden","message":"…"}
push {"t":"push","sub":"s-1","channel":"hat.events","payload":{…}}
ack  {"t":"ack","sub":"s-1","event_id":"…"}
```
Codes: `unauthorized|forbidden|bad_request|unknown_method|not_found|internal`.

**Key files**
- Brain: `runtime/semantos-brain/src/wss_rpc_registry.zig` (registry+codec), `src/wss_rpc_methods.zig` (substrate methods incl. `cellsMint`), `src/cells_mint_core.zig` (**M1.7** shared transport-agnostic mint body — the single source of truth both transports call), `src/cells_mint_http.zig` (parser + Acceptor, reused by both), `src/site_server/reactor.zig` (`reactorRpcUpgrade`/`reactorRpcDispatchText`/`reactorRpcHandleFrame`, `RpcReactorSession`, `reactorHandleCellsMint` now delegates to the core), `src/site_server.zig` (`attachRpcRegistry`), `src/cli/serve.zig` (method registration), `scripts/rpc_e2e.py`.
- Flutter: `apps/semantos/lib/src/rpc/` (`brain_rpc_client.dart` + `RpcCaller` iface, `rpc_methods.dart`, `rpc_error.dart`), `apps/semantos/lib/src/repositories/` (`jobs_repository.dart`, `job.dart`, `cell_query_repository.dart`), `apps/semantos/test/rpc/`, `apps/semantos/test/repositories/`.

## Recommended next-session order
1. ~~**M1.7 brain half**~~ ✅ DONE this branch (`cells_mint_core.zig` leaf + `cells.mint` method + live dual-path parity).
2. **M1.6** — boot-wire `BrainRpcClient` (run the app; watch connect + a job list load).
3. **M1.7b app half** — point `IntentDispatcher` at `cells.mint`; retire the two HTTP clients. (Brain side is ready and parity-proven.)
4. **M1.8** — generic renderer for Home + FIND (manifest render hints + query blocks).
5. Then M2 conversation (`subscribe` reuses `oddjobz_event_bus`), M3 voice, M4 OpenRouter NL, M5 durability.

Optional brain follow-up: **B3 `cell.get`** is now a one-method add following the exact `cells.mint`/`cell.query` pattern — fully verifiable on the brain whenever a by-ref read is needed.
