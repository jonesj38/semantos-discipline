---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/SESSION-JOURNAL-2026-05-13.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.336539+00:00
---

# Session journal — 2026-05-13

**Operator was away for the final stretch (NATS-canonical refactor) on bypass permissions.**  This file captures what shipped while Todd was off, with commit SHAs, smoke evidence, and rollback paths.

---

## What landed today (chronological, all on `origin/main`)

| Time (AEST) | Commit | Title | What it does |
|---|---|---|---|
| 08:14 | `2bd68ac` | T0 — per-route body-handling policy | Reactor parser drops idle per-conn memory 272 KB → 16 KB; per-route heap body buffers with declared caps; `.stream` reserved as forward-compat |
| 08:23 | `d2d67c6` | T1 — port `/api/v1/attachments/upload` + `/<id>/blob` | First dead-since-wedge-fix endpoint pair back live; 12 MiB body cap; bearer-gated |
| 08:32 | `f14d1a6` | T2 — port `/api/v1/info` | Brain pin + shard-proxy + theme discovery for PWAs |
| 08:48 | `ad52988` | T4 — port `/api/v1/voice-extract` + defer T3 | Voice-notes-to-intent pipeline; 6 MiB body cap; supports Path A + Path B per `voice_notes_workflow.md` |
| 08:53 | `468ea6d` | T5 — delete dead pre-wedge-fix dispatch path | 1495 LOC across 5 files removed; site_server.zig 802 → 622 LOC |
| 09:09 | `fdd1545` | docs(tracker): V1 reactor port cycle ✅ closed | Tracker status banner update |
| 09:34 | `6b7cb76` | T8a — wire `info_acceptor` in cmdServe | `/api/v1/info` flipped 404 → 401 (handler running, bearer-check active) |
| 09:43 | `fa5675c` | docs(tracker): T8 split into T8a (✓) + T8b (deferred) | |
| 09:50 | `699e856` | T8b — wire `voice_extract_acceptor` + bun-subprocess shell | Real `VoiceExtractShell` (Zig subprocess spawn → bun extensions/oddjobz/tools/voice-extract.ts) + 3 cmdServe flags + systemd drop-in on rbs |
| 09:53 | `b832305` | docs(tracker): T8b landed; all 4 V1 endpoints live | |
| 09:30* | `c063418` | T3 — port `/api/v1/events` WSS to reactor (joint commit) | EventsReactorSession + ReactorCtx polymorphism + pre_tick_drain mechanism + bus-callback path; landed under a docs commit's message due to a concurrent committer (see `c71e279` annotation) |
| 09:30 | `c71e279` | note: T3 code landed inside c063418 | Empty commit annotating the merge accident |
| 09:31 | `1ec7169` | docs(tracker): T3 ✅ DONE + deployed | |
| ~09:45 | `c656eb8` | docs(unification): v0.5 — §11.6 BRC alignment additions | (Concurrent docs work by another session) |
| 09:54 | `c931c8c` | **A — cut Pravega producer (W3.1)** | Pravega was overkill + always-null in production.  Removed `oddjobz_event_producer.zig` + `pravega_client_mod` + W3.1 publish block + the 10-test conformance suite.  Other orphan Pravega producer source files left on disk (not in build). |
| 09:55 | `7247694` | **B — NATS-as-canonical-event-stream** | New `nats_subscriber.zig` (push-subscription client with reader thread, 8 inline TDD tests).  New `nats_event_bridge.zig` (NATS→OddjobzEventBus relay, 8 inline TDD tests).  jobs_handler cuts its direct bus publish.  cmdServe constructs + starts the bridge after NATS is up. |

`*` T3 timestamp approximate — landed under an unrelated commit message due to concurrent committer.

---

## Production deploys today

Five deploys to `ssh rbs`, all single-script (no SSH-drop risk after the first one):

| Time | Binary swap | Backup at | What's new on prod |
|---|---|---|---|
| 08:17 | V1 reactor port cycle binary | `/opt/semantos/brain.pre-2026-05-13` (May-11) | T0/T1/T2/T4/T5 |
| 08:33 | T8a info acceptor wiring | `brain.pre-t8a-2026-05-13-0833` | `/api/v1/info` → 401 (was 404) |
| 08:51 | T8b voice-extract + bun shell | `brain.pre-t8b-0851` | `/api/v1/voice-extract` → 401 (was 404) |
| 09:15 | T3 events WSS port | `brain.pre-t3-0915` | `/api/v1/events` → 101 Switching Protocols on real WS upgrade (was 404) |
| **09:55** | **A + B (NATS canonical)** | `brain.pre-natsbridge-0955` | jobs_handler.transition only goes to NATS; bridge subscribes + republishes to bus; WSS sub flow unchanged |

Each deploy: backup binary, stop service, install new, start service.  Outages ~3-5s on `oddjobtodd.info` during each restart.  All deploys preserved on-disk state (`/var/lib/semantos/` LMDB, NATS persistence, audit logs).

---

## End-to-end smoke evidence (the critical proof for B)

Ran from rbs at ~09:58 AEST after the A+B deploy:

```python
# 1. Hold a WS connection open on /api/v1/events?hat=oddjobtodd.info
# 2. From a separate thread, publish to NATS at
#    op.0000000000000000.oddjobtodd.info.fsm_transition
#    with a synthetic fsm_transition JSON payload
# 3. Read from the WS socket
```

WS upgrade response (server → client):
```
HTTP/1.1 101 Switching Protocols
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Accept: ICX+Yqv66kxgM0FcWaLWlFLwTAI=
```

WS frame received within 1s of the NATS pub:
```
{"event_id":"0000000000000002","job_id":"smoke-job-2","cell_id":"deadcafe","from_state":"lead","to_state":"quoted","ts_ms":1715561800000,"hat_id":"oddjobtodd.info"}
```

**This proves the full chain works end-to-end:**
NATS pub → `nats_subscriber` MSG reader thread → `nats_event_bridge.onMessage` (JSON parse) → `OddjobzEventBus.publish` (event_id assigned) → reactor `pre_tick_drain` (100ms tick) → `write_buf` → socket → PWA receives.

---

## Architectural state of the brain's event surface

```
                              ┌──────────────────────────────┐
                              │  brain process (semantos-shell.service)
                              │
jobs_handler.transition ──────┼──► helm_event_broker  ───────────► wallet WSS helm subscribers
                              │
                              ├──► NatsEventProducer ──► op.<op_pkh16>.<hat>.fsm_transition
                              │                              │
                              │                              ▼ (NATS JetStream durable)
                              │                              │
                              │   nats_event_bridge  ◄───MSG─┤
                              │     (reader thread)          ▼
                              │           │
                              │           ▼ parse + bus.publish
                              │   OddjobzEventBus
                              │           │
                              │           ▼ reactor pre_tick_drain
                              │   /api/v1/events WSS subscribers (PWAs)
                              └──────────────────────────────┘
```

NATS is the canonical local event stream.  Pravega is removed.  jobs_handler is single-purpose: emit to broker + NATS.  Bus is a fan-out adapter, not a parallel producer.

---

## Rollback procedure

If anything bad surfaces in production:

```bash
# Roll back ONE step (back to T3 + T8 binary; reverts A + B):
ssh rbs 'systemctl stop semantos-shell.service && \
         install -m 0755 -o root -g semantos /opt/semantos/brain.pre-natsbridge-0955 /opt/semantos/brain && \
         systemctl start semantos-shell.service'

# Roll back to a different prior state — substitute the backup path:
#   brain.pre-2026-05-13           (May-11, pre-everything)
#   brain.pre-t8a-2026-05-13-0833  (V1 ports without T8 wiring)
#   brain.pre-t8b-0851             (V1 + T8a, without T8b)
#   brain.pre-t3-0915              (V1 + T8a + T8b, without T3)
#   brain.pre-natsbridge-0955      (V1 + T8 + T3, without A+B)
```

None of the deploys today changed on-disk schema or data.  Rolling back is binary-only; LMDB stores, NATS state, audit logs, certs, bearer tokens — all preserved.

---

## Tests + TDD framework (per Todd's "robust TDD framework" request)

**New inline tests added today** (all pure or socketpair-based — no real NATS / brain server needed):

`src/nats_subscriber.zig` (8 tests):
1. parseMsgHeader — 3 fields (no reply)
2. parseMsgHeader — 4 fields (with reply)
3. parseMsgHeader — rejects non-MSG
4. parseMsgHeader — rejects malformed too-few tokens
5. parseMsgHeader — rejects too-many tokens
6. parseMsgHeader — rejects non-numeric len
7. readMsg round-trip on socketpair (no reply)
8. readMsg with reply subject roundtrips

`src/nats_event_bridge.zig` (8 tests):
1. parsePayload — extracts all six fields
2. parsePayload — rejects non-object
3. parsePayload — rejects missing required field
4. parsePayload — rejects wrong-typed field
5. parsePayload — accepts ts_ms as integer or float
6. parsePayload — clamps negative ts_ms to 0
7. onMessage skips non-fsm_transition subjects
8. onMessage publishes valid fsm_transition payload to bus

**Coverage strategy:**
- Pure-function tests for protocol bytes (parseMsgHeader, parsePayload) — fast, deterministic, no I/O.
- Socketpair-based integration tests for readMsg — exercises the actual stream-reading path without needing a NATS server.
- End-to-end production smoke via Python NATS-pub + WS-recv on rbs — last-mile verification that the assembly works against real NATS JetStream.

Pre-A test count: 1513 passing.
Post-B test count: 1519 passing (+16 new tests for the two new modules).
Other 44 tests still skipped as before.
Known macOS `unix_socket_transport_conformance` flake hit once on this run; retried green per the tracker sidequest log.

---

## What's still open

| Item | Status | Why deferred |
|---|---|---|
| **PWA round-trip smoke** | Awaiting Todd's hand on a phone | Operator action — APK ready at `apps/oddjobz-mobile/build/app/outputs/flutter-apk/app-debug.apk` |
| **T6 — `/api/v1/push-register` port** | Tracker row | Gates Oddjobz tenancy sales, not OJT personal pilot |
| **T7 — BRC-52+capability+Plexus auth** | Tracker row | Cross-cutting design work; current bearer flow is a placeholder per `brain_auth_model_intent.md` |
| **Bridge: other event types** | Inline TODO in `nats_event_bridge.zig` | Only `fsm_transition` flows today; `intent_outcome` / `stable_transition` go to NATS but bridge doesn't carry them (bus doesn't expose publish methods for them yet) |
| **Multi-tenant subject filter** | Inline TODO | Bridge subscribes to `op.>` (single-tenant).  Production multi-tenant should narrow to `op.<own_op_pkh16>.>` to avoid cross-tenant bleed |
| **Other Pravega producers** | Orphan source on disk | `mfp_tick_producer`, `identity_event_producer`, `region_tick_producer`, `registry_change_producer`, `pravega_subscriber` all already dead (not in build).  Separate cleanup decision when their feature replacements are scoped |
| **Bridge reconnect logic** | Inline doc | If NATS goes down mid-run, bridge silently exits.  Brain restart needed to re-subscribe.  Add reconnect when this becomes operationally painful |

---

## Things I deliberately did NOT do

- **Did not implement full JetStream pull-consumer multiplexing** — was the original B sketch but real risk of 3+ hours of protocol work with limited integration testing.  Pivoted to a simpler "internal NATS subscriber feeds the existing bus" architecture that delivers the same property.
- **Did not touch other Pravega producers** (mfp_tick, identity_event, registry_change, region_tick).  Todd's "Pravega is overkill" comment was scoped to the jobs/events stream.  Those are separate concerns to scope individually.
- **Did not modify the helm_event_broker path** (wss_wallet helm WSS).  That's a separate event spine for wallet clients; out of scope for "NATS is the *Oddjobz* event stream."
- **Did not run a refactor of `nats_client.zig`** — kept it as request/reply-only; added the subscribe-side as a parallel module with its own connection.  Avoids a stream-multiplexer that the brain doesn't need today.

---

## Reading order for catch-up

1. This file (you're here).
2. `docs/REACTOR-PORT-TRACKER.md` — full task matrix + decision register + sidequest log.
3. `~/.claude/.../brain_reactor_v1_recovery_complete.md` — V1 reactor recovery memory.
4. New code:
   - `runtime/semantos-brain/src/nats_subscriber.zig` — push-subscription client
   - `runtime/semantos-brain/src/nats_event_bridge.zig` — NATS→bus relay
   - `runtime/semantos-brain/src/cli/serve.zig` — cmdServe wiring (search for `nats_event_bridge`)
   - `runtime/semantos-brain/src/resources/jobs_handler.zig` — see the `W3.2 direct bus publish cut` block

Total commits today: 14 on `origin/main`.  Production status: green, all five V1 endpoints live, NATS event spine validated end-to-end.
