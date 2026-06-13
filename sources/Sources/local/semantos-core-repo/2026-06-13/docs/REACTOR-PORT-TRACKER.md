---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/REACTOR-PORT-TRACKER.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.336833+00:00
---

# Reactor Port Tracker — V1 Pilot Recovery

**Status:** ✅ V1 reactor port cycle closed + T8 acceptor wiring + T3 events WSS + **NATS-canonical event spine** all deployed (T0/T1/T2/T3/T4/T5 + T8a + T8b + A/B 2026-05-13).  Five deploys to `ssh rbs` 2026-05-13: 08:17 AEST (V1 ports), 08:33 (T8a info), 08:51 (T8b voice-extract), 09:15 (T3 events WSS), **09:55 (A: Pravega cut + B: NATS-to-bus bridge)**.  All five V1 endpoints respond end-to-end on production.  **End-to-end NATS→bus→WSS smoke PASSED 09:58 AEST**: published a synthetic fsm_transition to NATS, observed the WS frame on the /api/v1/events client containing the parsed event with `event_id:"0000000000000002"`.  Real V1 pilot gate now is the PWA round-trip — APK built at `apps/oddjobz-mobile/build/app/outputs/flutter-apk/app-debug.apk`, awaiting sideload + paired pairing flow.
**Last edited:** 2026-05-13
**Branch:** main (T0-T5 + T8a + T8b all merged + pushed)
**Backup binaries on rbs:** `/opt/semantos/brain.pre-2026-05-13` (May-11), `brain.pre-t8a-2026-05-13-0833` (V1 ports binary), `brain.pre-t8b-0851` (V1 + T8a binary).  Rollback any layer via `install ... && systemctl restart`.
**Umbrella:** [`docs/design/V1.0-EXECUTION-PLAN.md`](design/V1.0-EXECUTION-PLAN.md) — stages 3–6 cannot complete until the ports in this tracker land.

---

## Why this exists

The B-pragmatic wedge fix on 2026-05-07 rewrote `SiteServer.serve()` in `runtime/semantos-brain/src/site_server.zig` from a blocking accept loop to a poll-based reactor (`event_loop_mod.EventLoop` driving `reactorMakeCtx`). It unblocked one wedge (a single WSS connection stalling every other HTTP request) but the migration of HTTP endpoints into `src/site_server/reactor.zig` stalled mid-port. `reactorDispatchHttp` is now the sole live HTTP entry point, and every branch ends `return .close_after_drain` — there is no fallback into `request.zig`.

As a result `request.zig` (608 LOC) and `connection.zig` (109 LOC) are dead code, and ~9 endpoints used by `apps/oddjobz-mobile/`, `apps/world-apps/jam-room-mobile/`, and `apps/semantos/` are dead in production. This tracker drives porting the four endpoints that block the Odd Job Todd v1 pilot, deletes the dead-code carcass, then ports one more before Oddjobz can be sold to tenants.

This is operational recovery work, not new feature work. It's a prerequisite for the broader V1.0 execution plan, not a replacement.

---

## Definition of done

### V1 — Odd Job Todd PWA pilot deployable

- [ ] Photo capture against jobs works end-to-end (PWA → brain → disk → retrieval).
- [ ] Live job-state updates appear in the PWA without polling.
- [ ] Voice notes against jobs produce intent records that feed the quoting flow.
- [ ] PWA discovers brain config via `/api/v1/info`; no hardcoded URLs anywhere in `apps/oddjobz-mobile`.
- [ ] No orphaned dead-code HTTP endpoints in `runtime/semantos-brain/src/` that aren't reachable from `reactor.zig`.
- [ ] `zig build test -j1 --summary all` is green.

### V2 gate — Oddjobz sellable to other tradies

- [ ] Push notifications reach tradies' mobile devices on new job creation / state transitions.

---

## Decisions settled (don't re-litigate)

| # | Decision | Source |
|---|---|---|
| D1 | `reactor.zig` is the live HTTP path. `request.zig` + `connection.zig` are dead since 2026-05-07. | [`site_server.zig:597`](../runtime/semantos-brain/src/site_server.zig#L597) |
| D2 | No hardcoded fallbacks (e.g. brain URL in the PWA). `/api/v1/info` is ported, not bypassed. | Conversation 2026-05-12; `~/.claude/.../no_hardcoded_workarounds.md` |
| D3 | Subscribe > poll for events. Port `/api/v1/events` WSS, don't polyfill via repeated REPL reads. | Conversation 2026-05-12 |
| D4 | Voice notes are v1, not v2. They feed the OJT quoting workflow. | Conversation 2026-05-12 |
| D5 | Voice-extract supports **both** capture-time-bound and inferred-from-transcript scope paths. Path A: tap "voice note" inside a job view → audio tagged with `scope: job/<id>` in signed Transcript metadata → brain ratifies on that job. Path B: fire up `talk \| self` free-form → no scope hint → gradient pass infers entity bindings from transcript, emits patches against *both* the inferred entity and the self-talk personal stream. Endpoint accepts optional `scope` metadata; populated = strong hint, absent = infer. | Conversation 2026-05-12 (Q1 resolved) |
| D6 | Defer `/api/v1/wallet-op` (no app currently calls it; `BrainWalletService` is unused). | Axis-2 audit 2026-05-12 |
| D7 | Defer `/auth/callback` (no paywalled site exists yet; visitor identity flow off the critical path). | Tracker scope |
| D8 | Defer bundle / frame / `/api/v1/chain/header*` (federation + headers-proxy not in V1 stages). | `docs/design/V1.0-EXECUTION-PLAN.md` §1.3 — WF deferred |
| D9 | Defer brain-side jam WSS (`jam-room-mobile` currently targets `wss://world.semantos.me`; "host jam off brain" is net-new build). | Conversation 2026-05-12 |
| D10 | Port pattern: each endpoint is a request-shape adapter from `std.http.Server.Request` to the reactor's parsed-request shape. The acceptor module (`*_http.zig`) does the multipart parse + signed-blob verification + subprocess shell-out; we don't redesign it. Template is `/api/v1/repl` at [`reactor.zig:202`](../runtime/semantos-brain/src/site_server/reactor.zig#L202). | Conversation 2026-05-12 |
| D11 | `/api/v1/info` is GET-only in V1. It returns **brain-side** info (brain pin, shard-proxy, theme defaults, available hats on this identity, available extensions on this brain). Brain-operator + tenant config changes still happen via REPL. **User-facing per-device + per-cartridge config (theme override, notification prefs, default labor rate, hat preference, etc.) is NOT written through `/api/v1/info`** — it flows as intents through `verb.dispatch` on the existing `/api/v1/wallet` WSS or `/api/v1/repl`, ratifies as cell records, and syncs across the user's paired devices via the substrate. Same path as job creates and quote edits. Hat switching is local-only client state, not stored brain-side; only the *list* of available hats comes from `/api/v1/info`. | Conversation 2026-05-12 (Q2 resolved, then refined: shell/cartridges/hats model means config-as-intents, not a write endpoint) |
| D12 | T3 (events WSS port) preserves the existing simple-bearer auth semantics from `events_stream_handler.zig` — pure code motion, no auth redesign. The richer BRC-52-cert + capability + Plexus-challenge auth model that Todd designed is captured separately as T7. This keeps the port from scope-creeping into a months-long auth refactor. | Conversation 2026-05-12 (Q3 resolved with split) |
| D13 | Reactor parser body strategy: option A (per-route heap-buffered body with declared cap) with forward-compat hook for option B (streaming handoff). Streaming reserved for future routes that genuinely need it; all current and V1 handlers use `.buffer{cap}`. Pure B would force every body-consuming handler to become a state machine — too much complexity for V1's needs. | Conversation 2026-05-12 (after discovering 256 KB parser cap blocks T1) |

---

## Open decisions

(none — Q1, Q2, Q3 resolved 2026-05-12 into D5, D11, D12 above)

---

## Tracking matrix

| # | Task | Status | Est LOC | Depends on | Acceptance | Notes |
|---|---|---|---|---|---|---|
| **T0** | Reactor parser body-handling policy: per-route body buffering with heap allocation + forward-compat hook for streaming | ✅ DONE 2026-05-12 (`2bd68ac`) | ~336 | — | Per-request heap body buffer sized to min(Content-Length, route_cap); `BodyPolicy.buffer{cap}` + reserved `.stream` variant; `ConnectionContext.body_policy_fn` + `body_policy_ctx`; `site_server/reactor.zig:ROUTE_BODY_CAPS` data table; idle per-connection memory dropped from ~272 KB to ~16 KB (1024 conns: 272 MB → 16 MB). Tests: 1513 passing, 44 skipped. | Landed as `2bd68ac` on main. Forward-compat: `.stream` returns `error.StreamNotImplemented` today; opt-in for future routes that need sub-Content-Length progress. |
| **T1** | Port `/api/v1/attachments/upload` + `/<id>/blob` to `reactor.zig` | ✅ DONE 2026-05-12 (pending commit) | ~300 | T0 | Upload + blob routes live in `reactorDispatchHttp` pre-route table at slots 5-6; bearer-gated; acceptor module owns parse/verify/persist; 12 MB body cap wired via ROUTE_BODY_CAPS. Tests: 1513 passing. | Promoted 5 helpers + InsertError to pub in attachments_upload_http.zig so the reactor handler reuses parseMultipart, parseMetadata, canonicaliseCellPayload, verifyCellSignatureRecoveryLoop, createMetadataInline, writeJsonString, renderIsoTimestamp, boundaryFromContentType. Sets the multipart-parsing template T4 will follow. Awaiting `apps/oddjobz-mobile` end-to-end test on real brain to flip pilot-ready gate. |
| **T2** | Port `/api/v1/info` to `reactor.zig` | ✅ DONE 2026-05-12 (pending commit) | ~50 | — | reactorHandleInfo wired at dispatch slot 7. Pure-logic info_http.handle reused (returns InfoResult{body, status}); reactor handler is a thin shape adapter. Tests: 1513 passing. | GET only (D11). No body cap entry needed (request body is empty). End-to-end smoke against `apps/oddjobz-mobile` MeshTransport / jam-mobile ThemeService pending pilot. |
| **T3** | Port `/api/v1/events` WSS to `reactor.zig` + wire OddjobzEventBus producer | ✅ DONE 2026-05-13 (`c063418` + `c71e279` annotation, deployed) | ~600 | T0 (✓) | Real WS upgrade smoke from rbs: `GET /api/v1/events?hat=…` with proper Upgrade headers returns `HTTP/1.1 101 Switching Protocols` + Sec-WebSocket-Accept. `GET` without Upgrade → 400. `POST` → 405. Was 404 pre-T3. | **Scope was wider than the original tracker row suggested** — surfaced during prep that OddjobzEventBus had no producer (jobs_handler had `event_bus` field but cmdServe never populated it). Option B chosen: port reactor side AND wire producer at cmdServe + jobs_handler. Implementation: new `pre_tick_drain` callback in event_loop/connection_state (drains cross-thread queues every 100ms tick); new `EventsReactorSession` + `ReactorCtx.kind` polymorphism; bus callback serialises frames into per-session mutex-protected queue; reactor dispatch_wss routes by kind. Customers/visits/quotes/invoices handlers don't yet bus-publish — future task. |
| **T4** | Port `/api/v1/voice-extract` to `reactor.zig` | ✅ DONE 2026-05-12 (pending commit) | ~200 | T0, T1 | reactorHandleVoiceExtract wired at dispatch slot 8; bearer-gated; multipart parse + signed-Transcript verify + best-effort audio persist + bun pipeline shell-out; IntentResult JSON passes through to client. 6 MB body cap in ROUTE_BODY_CAPS. Tests: 1513 passing. | Pub'd VerifyError in voice_extract_http.zig; reuses parseVoiceMultipart + verifyTranscriptSignature + attachments_upload_http.boundaryFromContentType (T1 helper). Endpoint accepts optional `scope` metadata (Path A vs B per D5) — gradient pass handles scope-or-infer downstream. Awaiting end-to-end smoke against `apps/oddjobz-mobile` for pilot-ready gate. |
| **T5** | Delete `request.zig`, `connection.zig`, orphaned `auth.zig` / `dispatch.zig` / `static.zig` files, dead delegate methods on `SiteServer`, dead imports | ✅ DONE 2026-05-12 (pending commit) | -1700 | T1–T4 done | 5 files removed: request.zig, connection.zig, auth.zig, dispatch.zig, static.zig. 11 delegate methods + handleConnection + openHeaderStore + 21 unused imports removed from site_server.zig (802 → 622 LOC). reactor.zig is the sole HTTP dispatcher. Build green, tests 1513 passing. | T3 deferred; /auth/callback not re-ported (D7); /api/v1/wallet-op, /chain/header*, bundle/frame endpoints intentionally not re-ported (D6, D8). All explicitly captured. |
| **T6** | Port `/api/v1/push-register` to `reactor.zig` (V2 gate) | TODO | ~180 | T1–T5 done | `apps/oddjobz-mobile` registers an APNs/FCM token; brain persists it on the device cert record; a synthetic push to a test device succeeds | Acceptor: `push_register_http.maybeHandle`. |
| **T7** | Auth-model alignment: BRC-52 cert + capability + Plexus-challenge satisfaction across bearer-gated endpoints | DESIGN | ? | Design doc first | Spec'd: `/api/v1/events`, `/api/v1/repl`, `/api/v1/info`, `/api/v1/attachments/*`, `/api/v1/voice-extract`, `/api/v1/push-register` all verify the caller against a cert+capability proof bound to challenges issued at edge creation. Drop-in replacement for the simple-bearer flow inherited from device-pair. | Cross-cutting — not a port. Needs its own design doc that pins how capabilities are issued at edge creation, how challenges are formed/satisfied, and how the proof composes with the existing device-pair → bearer flow. Tracks **Todd's actual auth model**, not the placeholder bearer that currently ships. |
| **T8a** | Wire `info_acceptor` construction in `cli/serve.zig` | ✅ DONE 2026-05-13 (`6b7cb76`, deployed) | ~80 | T2 landed (✓) | `/api/v1/info` returns 401 unauthorised (handler running, bearer-check enforcing) instead of 404.  Was 404 pre-T8a. | Default-on when token_store is up.  Populates brain_pin_cert_id + pubkey_hex from cert_store.rootId() when available; shard_proxy + theme from manifest_holder when --tenant-manifest passed; server_version from cli_lifecycle.VERSION.  Backing buffers live in cmdServe's stack frame.  Bearer-authorized smoke not run (would need a valid token from the bearer-tokens.log). |
| **T8b** | Wire `voice_extract_acceptor` construction in `cli/serve.zig` + implement `VoiceExtractShell` (bun subprocess) | ✅ DONE 2026-05-13 (`699e856`, deployed + systemd drop-in updated) | ~336 | T4 landed (✓) | `/api/v1/voice-extract` returns 401 (no-bearer) or 405 (wrong method) instead of 404.  Was 404 pre-T8b. | New file `src/voice_extract_shell.zig`: spawns `bun <script> --transcript <t> --metadata <m> [--sir-candidate <s>]` via `std.process.Child`; temp files per request (random-hex suffix, defer-deleted); 16 KB chunked stdout read up to 1 MiB cap.  Three new flags: `--voice-extract-script`, `--voice-extract-cwd`, `--voice-extract-bun` (defaults to `bun`).  Systemd drop-in `/etc/systemd/system/semantos-shell.service.d/voice-extract.conf` added on rbs to pass the three flags.  V1 limitations: no timeout (hung bun wedges reactor thread; revisit when handlers become non-blocking); stderr discarded (per CLI contract — rejections mirrored to stdout). |

Update the Status column in-place as work progresses (TODO → IN PROGRESS → DONE → ✅ shipped commit `<sha>`).

---

## Sidequest parking lot

Things we'll notice during the ports but **won't action mid-task**. Capture here so we don't forget and don't chase. When the relevant task finishes, scan this list and decide what's worth opening as its own task.

| Spotted on | Note | Verdict |
|---|---|---|
| 2026-05-12 (axis 2 audit) | 83 unused pubs codebase-wide, plus federation/peer_registry fully orphaned (`onboard`, `recordCorrect`, `recordWrong`, `getPeer`, `listActive`, `purgeEvicted`). | Defer — addresses separately post-V1. |
| 2026-05-12 (axis 2 audit) | `src/repl/` has 54 pubs that exist only so `repl.zig` façade can re-export them. HELM_TEXT-style perma-touch surface. | Defer — generation, not extraction, is the fix; not blocking V1. |
| 2026-05-12 (axis 4 audit) | 114 of 213 src/ files have no inline `test {}` block. `resources/*_handler.zig` (5872 LOC across 6 files) is the highest-leverage place to add property tests. | Defer — add inline tests for resource handlers as a follow-up cycle, post-V1. |
| 2026-05-12 (axis 1 audit) | Known macOS test flake: `unix_socket_transport_conformance.test.D-W1 P1 unix_socket: peer uid mismatch returns capability_denied` — ~10% flake rate. Drain-loop fix attempt caused hangs and was reverted. | Defer — accept retry-on-fail for now. |
| 2026-05-12 (D11 refine) | Canonical "config intents" don't exist yet in the extension grammars. When the PWA starts wiring per-device + per-cartridge settings (theme, notification prefs, default labor rate, etc.) it'll need a small declared set (`set_theme`, `set_notification_pref`, `set_default_labor_rate`, …) that route through `verb.dispatch`. Design work for the experience packages, not the brain. | Defer — capture as a follow-up to the V1 ports; flag when starting on PWA shell/settings UI. |

---

## Acceptance test for V1 pilot done

A single end-to-end test against a freshly-built brain on `ssh rbs` (the production VPS, per [`V1.0-EXECUTION-PLAN.md`](design/V1.0-EXECUTION-PLAN.md) §2):

1. `apps/oddjobz-mobile` pairs via `/api/v1/device-pair` → receives a bearer.
2. App fetches `/api/v1/info` → renders themed UI, discovers shard-proxy URL.
3. App opens `/api/v1/events` WSS → receives a live event when a test job transitions state via REPL.
4. App POSTs a photo to `/api/v1/attachments/upload` → photo is retrievable via `/api/v1/attachments/<id>/blob`.
5. App POSTs a signed voice-note to `/api/v1/voice-extract` → intent record appears in the test job's records, line item appears on the active quote.
6. `grep -rn "request_handler\|fn handleConnection\b\|fn handleAuthCallback\|fn handleAnalytics" runtime/semantos-brain/src/` returns no production-path matches.
7. `zig build test -j1 --summary all` green (one retry permitted for the known macOS uid-mismatch flake).

Pass = V1 pilot ports done. Then T6 + a real first tenant trial gates V2 sell-Oddjobz readiness.

---

## How to use this tracker

- **Update the Status column** as tasks land. Reference the commit SHA on completion.
- **Add to the Sidequest Parking Lot** rather than chasing tangents mid-port. Each row records what was spotted, when, and a one-word verdict.
- **If a task changes scope**, update the row in-place rather than starting fresh. Keep the history in the row notes.
- **When all V1 tasks are done**, write a `✅ V1 closed YYYY-MM-DD (commit <sha>)` line at the top of this file and switch focus to T6.
- **If an Open Decision blocks a task**, do *not* unblock it by guessing. Surface to Todd; the answer changes the port shape.
- **Cross-link to the umbrella plan.** When a task lands, note which V1.0 execution-plan stage it unblocks (stage 3 = auth cutover, stage 4 = substrate, stage 5 = legacy ingest, stage 6 = voice shell).
