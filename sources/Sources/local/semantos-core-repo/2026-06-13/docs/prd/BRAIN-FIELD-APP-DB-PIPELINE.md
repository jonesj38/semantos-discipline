---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/BRAIN-FIELD-APP-DB-PIPELINE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.697122+00:00
---

# BRAIN Brain + Field App — DB Integration Pipeline

**Status:** plan. Companion to `SEMANTOS-DB-IMPLEMENTATION-PIPELINE.md`.

**Scope:** How the four-tier DB topology (LMDB / SQLite / Pravega / Postgres) surfaces through the BRAIN sovereign node and the Flutter field app. Covers universal layers first; hat-specific surfaces second. Oddjobz is the reference hat — other hats follow the same pattern.

**Read this alongside:** `SEMANTOS-DB-IMPLEMENTATION-PIPELINE.md` (main DB pipeline), `docs/canon/cybernetic-orders.md`, `docs/canon/compression-gradient-as-teachback.md`.

---

## Architectural principle

The BRAIN brain is not an Oddjobz brain. It is a sovereign node that manages cells, identity, capabilities, Pask state, and event streams for any hat the operator wears. The DB topology serves all hats equally; the only hat-specific surface is the domain flag page in the cell header (`0x000101xx` for Oddjobz, different pages for future hats).

The Flutter field app is a reference implementation of the "field app" pattern. The pattern is: offline-first SQLite device DB + cell outbox + Pask device snapshot + Pravega-bridged real-time events. Any future field app (WBA, BREM, supply chain) uses the same pattern with a different active hat.

**The principle:**

> Universal layers own cells, identity, Pask, streams, and reasoning.
> Hat-specific surfaces are filtered views of those layers, scoped by domain flag.

Switching hat on the brain = changing the active domain flag namespace. Switching hat in the Flutter app = reloading hat-scoped SQLite views and re-subscribing to hat-scoped events. No restarts. No separate databases.

---

## Current state: what exists and what is wrong with it

### BRAIN brain (Zig, `runtime/semantos-brain/src/`)

**Prototype note:** Oddjobz has no customer or client data dependencies. There are no backward-compatibility or migration requirements — the JSONL stores can be cut cleanly without data preservation.

Seven JSONL + HashMap stores, one per domain entity:

| Store file | Entity | Problem |
|---|---|---|
| `jobs_store_fs.zig` | Job (v1/v2) | JSONL replay on boot; full ArrayList in memory; no cursor; not a cell |
| `customers_store_fs.zig` | Customer | Same |
| `visits_store_fs.zig` | Visit | Same; FSM state in JSONL, not in cell phase byte |
| `quotes_store_fs.zig` | Quote | Same |
| `invoices_store_fs.zig` | Invoice | Same |
| `attachments_store_fs.zig` | Attachment metadata | Same; blobs separate in `attachment_blobs_fs.zig` |
| `leads_store_fs.zig` | Lead (pending ratification queue) | JSONL + HashMap; fed by the ingest pipeline (gmail, meta); needs LMDB migration and `source` enum expansion |
| `intent_cells_store_fs.zig` | Intent cell | JSONL + HashMap; intent cells are cells — they belong in `LmdbCellStore` |

Supporting files that compound the problem:

- `oddjobz_jsonl_watcher.zig` — polls file mtime at 100ms to detect new JSONL lines and publish broker events. This is JSONL-format-specific and disappears when the stores are replaced.
- `quote_fsm.zig`, `visit_fsm.zig`, `invoice_fsm.zig` — FSM state machines writing into JSONL stores. FSM transitions should emit cells (K4 atomic, K6 hash-chained) not JSONL appends.
- `oddjobz_ratify_handler.zig`, `oddjobz_derivations.zig` — derivation and ratification logic operating on JSONL-backed data. These should operate on cells.
- `oddjobz_query_handler.zig`, `oddjobz_attention_handler.zig` — query and attention handlers backed by JSONL stores.

The core problem: the brain has a parallel, Oddjobz-specific persistence layer sitting alongside the universal DB topology. Every domain entity is stored twice — once as a JSONL record and once (or rather: should be) as a 1024-byte cell in LMDB. The JSONL stores are the read-side cache that should instead be Postgres materialised views via the FDW.

### BRAIN ingest pipeline (`runtime/legacy-ingest/`)

The legacy ingest pipeline is a Node/TS service that polls Gmail and Meta (Facebook/Instagram Messenger) for inbound messages, runs LLM extraction, and writes ratified proposals into BRAIN via the `oddjobz.ratify_proposal` JSON-RPC call over the existing WSS endpoint. It is a **separate process** from the brain — the TS pipeline is not being replaced, only the BRAIN handler it calls.

Current data flow:

```
Gmail provider     ──► IngestWorker ──► LegacyBlobStore (raw items)
Meta provider      ──►                      │
Meta webhook       ──►                      │
                                            ▼
                                  RatificationOrchestrator
                                  (LLM extraction + few-shot)
                                            │
                                            ▼
                                  brain-rpc.ts (cell-writer)
                                            │
                                  oddjobz.ratify_proposal RPC
                                            │
                                            ▼
                              BRAIN oddjobz_ratify_handler.zig
                                  (writes into JSONL stores)
                                  sites / customers / jobs / attachments
                                  + leads_store_fs.zig (pending queue)
```

After the W0 migration, the data flow becomes:

```
Gmail provider     ──► IngestWorker ──► LegacyBlobStore (raw items)
Meta provider      ──►                      │
Meta webhook       ──►                      │
                                            ▼
                                  RatificationOrchestrator
                                  (unchanged — no TS changes needed)
                                            │
                                            ▼
                                  brain-rpc.ts (cell-writer)
                                  (unchanged — same RPC call)
                                            │
                                  oddjobz.ratify_proposal RPC
                                            │
                                            ▼
                              BRAIN oddjobz_ratify_handler.zig
                                  (writes into LmdbCellStore)
                                  + lead cell in LmdbCellStore
                                    source = "gmail" | "meta"
```

**The TS pipeline requires no changes.** The only change is in `oddjobz_ratify_handler.zig`: the JSONL appends are replaced by `LmdbCellStore.put()` calls. The `oddjobz.ratify_proposal` RPC wire shape is preserved.

The `leads_store_fs.zig` source enum must be expanded from `{chat, voice, text, manual}` to include `gmail` and `meta` before the LMDB migration (this is a JSONL-compatible additive change, requires no data migration, and can be done independently).

### Flutter field app

| Persistence | Current shape | Problem |
|---|---|---|
| `outbox_v1` (sqflite) | Ad-hoc JSON payload, no cell_id column, no prev_state_hash | Payload is not a cell; cannot verify with kernel; no K6 chain |
| `jobs_cache_<url>.json` | Flat JSON file snapshot | Not SQLite; no indices; cold-start performance only; not universal |
| flutter_secure_storage | BRC-42 child cert + bearer | Correct. No change needed. |
| No Pask snapshot | — | M2.8 `SqlitePaskSnapshotStore` merged but not wired into Flutter |
| No domain-aware DB | — | All tables are Oddjobz-specific; no hat switching support |

---

## Layer map: where each W-row lives relative to the main DB pipeline

```
Main DB pipeline milestone → BRAIN/Flutter surface
────────────────────────────────────────────────────────────────────────
M1 (LMDB, merged)           → W0.1–W0.4: replace *_store_fs.zig with LmdbCellStore
M2 (SQLite browser, merged) → W1.1–W1.3: Flutter SQLite tables matching M2 vtable shape
M3 (Pravega, merged M3.7-9) → W0.3, W1.4, W3.1–W3.2: replace mtime polling; add oddjobz-events stream
M3.10 (pending)             → W5.1: Pask replay tool (pure main pipeline, unblocked)
M5.5+M5.11 (merged)        → W2.1–W2.3: Postgres hat views; M5.8 content
M5.8 (pending)              → W2.1 IS M5.8; Oddjobz views are the hat-specific subset
M5.10/M5.13 (Bert-owned)    → W4.2: replace intent_action_router with intent reducer
M5.14 (pending)             → teachback backref; universal; unblocked now
M6/M7 (merged)              → W4.1: register Oddjobz cell types in octave_registry
```

---

## Tracking matrix

Status: `pending | in_progress | review | merged | blocked`

Columns: **DB deps** = main pipeline rows this requires to be merged first.

### W0 — Universal BRAIN brain DB wiring

| ID | Deliverable | DB deps | Blocks | Status | Acceptance |
|---|---|---|---|---|---|
| W0.1 | Replace `jobs_store_fs.zig` JSONL+HashMap with LMDB cursor reads. Job cells are in `LmdbCellStore`; the JSONL store is retired. `jobs_handler.zig` reads cells via cursor, not ArrayList walk. | M1.5, M1.7 (merged) | W2.1 | merged | `jobs_store_fs.zig` and `jobs_store_lmdb.zig` (cursor-only) coexist behind feature flag; JSONL store removed after W2.1 lands |
| W0.2 | Replace `customers_store_fs.zig` + `visits_store_fs.zig` + `quotes_store_fs.zig` + `invoices_store_fs.zig` + `attachments_store_fs.zig` with `LmdbCellStore`. Each domain entity is a cell with the appropriate domain flag. FSM transition writes produce a new cell at the next phase (K4 atomic). | M1.5, M1.7 (merged) | W0.5 | merged | All five `*_store_fs.zig` files retired; domain FSMs write cells via cell engine; K4 rollback tested for each FSM transition |
| W0.3 | Replace `intent_cells_store_fs.zig` with `LmdbCellStore`. Intent cells are action-phase cells (phase `0x06`); they belong in the universal cell store, not a custom JSONL store. The `cell_id` is the LMDB key. | M1.5, M1.12 (merged) | W4.1 | merged | `intent_cells_store_fs.zig` retired; intent cells stored as 1024-byte LMDB entries; phase byte carries kernel verdict; `sir_program_hash` field present (M5.14 prereq) |
| W0.4 | Delete `oddjobz_jsonl_watcher.zig`. File-mtime polling replaced by Pravega subscriber (M3.7/M3.8 merged). The attention path is now: BRAIN Pravega subscriber → helm broker topic → WebSocket to Flutter. | M3.7, M3.8 (merged) | W1.4 | merged | `oddjobz_jsonl_watcher.zig` removed; attention events arrive via Pravega bridge; no mtime polling code remains |
| W0.5 | Wire `LmdbPaskSnapshotStore` into `brain/src/main.zig` boot/shutdown sequence. On boot: `pask_restore_state` from LMDB. On shutdown: `pask_snapshot_state` → commit. On every confirmed FSM transition: `pask_interact_run` with the affected cell's `cell_id`. | M1.11, M1.12 (merged) | W4.1, W1.3 | merged | Brain boots with Pask graph loaded from LMDB; `pask_interact_run` called on job state transitions; snapshot committed on clean shutdown; snapshot survives `kill -9` restart |
| W0.6 | Hat-switching in `brain/src/main.zig`: the brain serves cells from any registered extension domain flag simultaneously. No restart when operator adds a hat. Active capabilities per hat loaded from `capability_utxo` change feed. | M1.7, M3.5 (merged) | W1.5 | merged | `brain` serves two domain flag namespaces in a single process; switching active hat in the Flutter app changes capability enforcement without restart; no cross-hat data leakage at K3 domain isolation |

### W1 — Universal Flutter device DB layer

| ID | Deliverable | DB deps | Blocks | Status | Acceptance |
|---|---|---|---|---|---|
| W1.1 | Flutter SQLite migration: create universal `hat_entity_cache` table replacing `jobs_cache_<url>.json` file. Schema parameterised by `domain_flag` — works for any hat. Replaces `jobs_cache.dart` file-based logic with `HatEntityRepository` backed by sqflite. | M2 pattern (merged) | W1.5 | merged | `jobs_cache_<url>.json` files removed; `hat_entity_cache` SQLite table with indices on `(domain_flag, state)` and `(domain_flag, scheduled_at)`; cold-start reads SQLite instead of JSON file |
| W1.2 | Flutter `outbox_v1` schema replacement: drop and recreate the table with `cell_id BLOB(32)`, `prev_state_hash BLOB(32)`, `domain_flag INTEGER NOT NULL`, and 1024-byte cell envelope payload. Rename `last_brain_state` → `prev_state_hash`. No data migration required — this is a prototype with no production data. | M1.12 (merged) | — | merged | Table recreated cleanly; new rows carry properly-formed cell envelope; kernel can verify payload bytes; no legacy row handling needed |
| W1.3 | Wire `SqlitePaskSnapshotStore` into Flutter. On app resume: `pask_restore_state`. On confirmed FSM action (dispatch, quote accept, invoice send): `pask_interact_run` with job cell_id. Snapshot committed on background. | M2.8, M1.12 (merged) | — | merged | Flutter Pask snapshot persists across app restarts; `pask_interact_run` called from job action confirmation UI path; operator's device graph grows with use |
| W1.4 | Flutter Pravega-bridged event subscription. Replace ad-hoc WebSocket polling with hat-scoped event subscription via BRAIN `/api/v1/events?hat=<domain_flag>` endpoint. `AttentionService` rewired to this endpoint. | M3.7 (merged), W0.4 | W3.2 | merged | Real-time job state updates arrive without polling; app receives event within 1s of FSM transition on brain; reconnect resumes from last-acked event |
| W1.5 | Flutter universal hat context. `HatContext` class: active `domain_flag` + extension id stored in app state. All SQLite queries, Pravega subscriptions, and capability checks scoped by `HatContext`. Hat switch triggers SQLite view reload and event resubscription. | W1.1, W0.6 | — | merged | Switching hat in Flutter changes visible entities, active capabilities, and event feed without app restart; previous hat's data not visible in new hat's UI |

### W2 — Universal brain Postgres hat views (this is M5.8's content)

M5.8 is pending in the main pipeline. These rows define what M5.8 must contain from the brain/hat perspective.

| ID | Deliverable | DB deps | Blocks | Status | Acceptance |
|---|---|---|---|---|---|
| W2.1 | Postgres migration `013_hat_views.sql`: universal hat view scaffold. `hat_cell_list(p_domain_flag BYTEA)` function joining `cells_lmdb` FDW + `pask_node_view` filtered by domain flag prefix. This is the template every hat's views are built on. | M5.5, M5.11 (merged) | W2.2, M5.8 gate | merged | Function exists; returns cells scoped to any 2-byte domain flag prefix; refresh < 500ms on 1M-cell dataset; Oddjobz test case: `hat_cell_list('\x000101')` returns only Oddjobz cells |
| W2.2 | Oddjobz-specific views on top of W2.1: `oddjobz_job_list`, `oddjobz_job_by_id`, `oddjobz_customer_index`, `oddjobz_site_index`, `oddjobz_active_jobs` (jobs with h_state > threshold in `pask_node_view`). These replace the JSONL HashMap as the authoritative read model for `jobs_handler.zig`. | W2.1, M5.11 (merged) | W2.3, W4.2 | merged | All five views created; `oddjobz_active_jobs` surfaces jobs the operator has recently interacted with (Pask-ranked); refresh < 1s on representative dataset |
| W2.3 | Helm read contexts for Oddjobz hat. The 15 Helm context slots (M5.8 gate) include: `oddjobz.jobs.active`, `oddjobz.jobs.scheduled_today`, `oddjobz.jobs.awaiting_invoice`, `oddjobz.customers.recent`, `oddjobz.visits.upcoming`, `oddjobz.learned_concepts` (from `pask_stable_thread`). | W2.2, M5.12 (merged) | — | merged | Each context refreshes in < 1s; `oddjobz.learned_concepts` surfaces stable threads whose `type_path` starts with `oddjobz.`; Helm UI can render each context without additional queries |

### W3 — Oddjobz domain event stream

| ID | Deliverable | DB deps | Blocks | Status | Acceptance |
|---|---|---|---|---|---|
| W3.1 | `oddjobz-events` Pravega stream producer. Every job FSM transition emits `{job_id, cell_id, from_state, to_state, ts_ms, hat_id}` with routing key = job_id. Replaces the broker-topic approach in `jobs_handler.zig`. Hat-scoped: other hats get their own streams following the same pattern. | M3.2 (merged) | W3.2 | merged | 6 conformance tests green: each of the 8 FSM transitions emits one event; routing key preserved; exactly-once per job_id per transition |
| W3.2 | Flutter subscriber for `oddjobz-events` via BRAIN WebSocket bridge. Drives real-time job state updates in Flutter job list and detail screens. No polling. | W3.1, W1.4 | — | merged | Job card state updates within 1s of brain-side FSM transition; reconnect resumes from last-acked event; no stale state visible > 2s after reconnect |

### W4 — Oddjobz intent routing upgrade

| ID | Deliverable | DB deps | Blocks | Status | Acceptance |
|---|---|---|---|---|---|
| W4.1 | Wire Pask h_state into `intent_action_router.zig`. Replace pure substring customer_name matching with: (a) query `oddjobz_active_jobs` for jobs with elevated `h_state` and matching name fragment; (b) substring match as tiebreaker only. Immediate improvement before M5.10 lands. | W0.5, W2.2 | W4.2 | merged | Intent routing picks the correct job in >95% of cases on a test corpus of 100 operator intents; ambiguous cases return confidence score < 0.5 and request clarification rather than guessing |
| W4.2 | Replace `intent_action_router.zig` with Bert's intent reducer. Reducer queries `pask_entailment` + `oddjobz_job_list` to compose SIR programs from natural-language intent. `intent_action_router.zig` is retired. | M5.10, M5.13 (Bert-owned, pending) | — | blocked | `intent_action_router.zig` deleted; one end-to-end pipeline: voice → SIR → intent reducer → job FSM transition; `sir_program_hash` in action cell links back to reducer output |

### W6 — Ingest pipeline seam migration

The TS ingest pipeline (`runtime/legacy-ingest/`) is preserved as-is. Only the BRAIN handler it calls needs updating. These rows ensure ingest keeps working through and after the W0 LMDB migration.

| ID | Deliverable | DB deps | Blocks | Status | Acceptance |
|---|---|---|---|---|---|
| W6.1 | Expand `leads_store_fs.zig` source enum to include `"gmail"` and `"meta"`. Additive change — existing JSONL logs with `chat|voice|text|manual` replay without error; new sources are accepted and stored. Allows ingest pipeline to tag leads by channel before the LMDB migration lands. | none | W6.2 | merged | `LEAD_SOURCES` array includes `"gmail"` and `"meta"`; conformance test covers round-trip of a `source = "meta"` lead through append → replay; `leads_store_fs.zig` tests still green |
| W6.2 | Update `oddjobz_ratify_handler.zig` to write site, customer, job, attachment, and lead entities into `LmdbCellStore` instead of the JSONL stores. The RPC wire shape (`oddjobz.ratify_proposal` request/response) is unchanged — the TS cell-writer (`brain-rpc.ts`) requires no modification. | M1.5, M1.7 (merged), W0.2, W6.1 | W6.3 | merged | End-to-end test: `brain-rpc.ts` submits a ratify_proposal; BRAIN stores entities as LMDB cells; `oddjobz_job_list` Postgres view returns the job; `leads_store_fs.zig` is no longer written to by this handler |
| W6.3 | Delete `leads_store_fs.zig`. Lead cells now live in `LmdbCellStore` (phase `0x01` pending, `0x02` ratified/rejected). `oddjobz_leads_pending` Postgres view replaces the JSONL queue as the ratification UI's data source. | W6.2, W2.2 | — | merged | `leads_store_fs.zig` deleted; `oddjobz_leads_pending` view returns pending leads sourced from LMDB; ratification UI reads from view; Meta and Gmail ingest still produces leads correctly end-to-end |

### W5 — Unblocked main pipeline remainders

These are main pipeline rows that became unblocked but have no separate W-row — they just need to be claimed in a Claude Code session.

| ID | Main pipeline row | Status | Unblocked by |
|---|---|---|---|
| W5.1 | M3.10 — Pravega-replay → Pask snapshot derivation tool | merged | M3.9 (merged), M1.11 (merged) |
| W5.2 | M5.8 — Helm read-view materialised views | merged | M5.5, M5.6, M5.7 (all merged); W2.1–W2.3 define the content |
| W5.3 | M5.14 — Action-cell teachback backref (`sir_program_hash` in phase-`0x06` payload) | merged | M5.3 (merged) |

---

## Dependency graph

```
Main pipeline             BRAIN brain                Flutter               Postgres
─────────────             ─────────                ───────               ────────
M1 (merged)       ──────► W0.1 (jobs LMDB)
                  ──────► W0.2 (entity LMDB)
                  ──────► W0.3 (intent LMDB)
                  ──────► W0.5 (Pask boot)   ───────────────────────► W4.1 (intent routing)

M2 (merged)       ──────────────────────────► W1.1 (hat SQLite)
M2.8 (merged)     ──────────────────────────► W1.3 (Pask device)

M3.7-9 (merged)   ──────► W0.4 (rm watcher) ─► W1.4 (Pravega bridge)
                  ──────────────────────────────────────────────────── W3.1 (oddjobz stream)
                                                                        └─► W3.2 (Flutter sub)

M5.5+M5.11(merged)────────────────────────────────────────────────── W2.1 (hat view scaffold)
                                                                        └─► W2.2 (oddjobz views)
                                                                              └─► W2.3 (Helm ctx)

M5.10 (Bert)  ────────────────────────────────────────────────────── W4.2 (intent reducer)

M3.10 (merged)  = W5.1 ─ done
M5.8  (merged)  = W5.2 ─ done
M5.14 (merged)  = W5.3 ─ done

Ingest pipeline (no main pipeline deps beyond M1):
legacy-ingest (TS, unchanged) ─► W6.1 (leads source enum) ─► W6.2 (ratify handler → LMDB)
                                                                   └─► W6.3 (leads_store_fs.zig deleted; needs W2.2)
```

---

## Blocking analysis

**Nothing in W0–W3 is blocked on pending main pipeline rows.** All main pipeline dependencies for W0.1–W0.6, W1.1–W1.5, W2.1–W2.3, W3.1–W3.2, and W4.1 are merged.

**W6.1 is unblocked and should be done first** — it is a two-line additive change to `leads_store_fs.zig` that expands the source enum. Landing this before W0.2 ensures ingest keeps writing correct data right up until the JSONL cut.

**W6.2 depends on W0.2** (entities in LMDB) and W6.1 (expanded source enum). The TS pipeline does not change at all — `brain-rpc.ts` stays exactly as-is. The only change is in the Zig handler.

**W6.3 depends on W2.2** (the `oddjobz_leads_pending` view must exist before the JSONL store is deleted). No backward compat work needed — the JSONL data is dropped, not migrated.

The only blocked row is W4.2 (Bert's intent reducer replaces intent_action_router) — blocked on M5.10 and M5.13, which are Bert-owned.

**W2.1–W2.3 are the content that unblocks M5.8.** M5.8 cannot close without the hat view scaffold (W2.1) and at least one hat's views (W2.2). These are the same deliverable from different perspectives: W2.1+W2.2 is what makes M5.8 meaningful, not just a generic migration.

**Critical path for full Oddjobz field app DB penetration:**

```
W6.1                                  (ingest source enum — do first, unblocked, 10 min)
W0.1 → W0.2 → W0.3 → W0.5 → W4.1   (brain LMDB + Pask + routing)
       W0.2 → W6.2 → W6.3            (ingest seam migration; W6.3 also needs W2.2)
W0.4 → W1.4 → W3.2                   (event stream, real-time Flutter UI)
W2.1 → W2.2 → W2.3 → M5.8 close     (Postgres hat views; W2.2 also unlocks W6.3)
W1.1 → W1.2 → W1.3                   (Flutter SQLite upgrade; no migration needed)
M3.10, M5.14                          (Pask replay, teachback — unblocked, main pipeline)
```

All of these can start immediately in Claude Code sessions. W4.2 (intent reducer) waits for Bert.

---

## What "done" looks like for this pipeline

The Oddjobz field app DB integration is complete when:

1. All eight `*_store_fs.zig` files in `runtime/semantos-brain/src/` are retired (the seven entity stores plus `leads_store_fs.zig`). Domain entities live in `LmdbCellStore`; read views are Postgres materialised views; no JSONL HashMap in production.
2. `oddjobz_jsonl_watcher.zig` is deleted. Attention events arrive via Pravega-bridged WebSocket.
3. The Flutter `outbox_v1` table has been replaced with the clean cell-envelope schema (`cell_id`, `prev_state_hash`, `domain_flag`). No data migration — prototype, no production data.
4. The `jobs_cache_<url>.json` file pattern is deleted. Flutter reads from `hat_entity_cache` SQLite table.
5. `SqlitePaskSnapshotStore` is wired into Flutter. `pask_interact_run` is called on every confirmed job action.
6. The Oddjobz Postgres views (`oddjobz_job_list`, `oddjobz_customer_index`, `oddjobz_site_index`, `oddjobz_active_jobs`, `oddjobz_leads_pending`) are live and refresh < 1s.
7. `oddjobz-events` Pravega stream is producing; Flutter subscribes and receives events within 1s.
8. The ingest pipeline (Gmail + Meta) still produces leads end-to-end after the migration: `legacy-ingest` → `oddjobz.ratify_proposal` RPC → `LmdbCellStore` → `oddjobz_leads_pending` view. No changes to the TS ingest code.
9. M5.8, M3.10, and M5.14 are merged in the main pipeline.
10. A second hat can be added (new domain flag page, new extension manifest, new hat-scoped views) without touching any of the universal layers. The universal layers serve both hats from the same LMDB, Pravega, and Postgres instance.

---

## For other hats (the pattern)

When a new hat is added (WBA, BREM, supply chain, CDM derivatives), the implementation follows this template:

1. **Define domain flag page** in the extension manifest (new 2-byte namespace under the `0x0001xxxx` page).
2. **Define cell types** for the hat's domain entities (extension `src/cell-types/*.ts`).
3. **Add hat view migration** (`01N_<hat>_views.sql`): call `hat_cell_list(domain_flag)` + hat-specific joins. No new universal infrastructure.
4. **Add Pravega stream producer** for the hat's FSM transitions. One stream per hat, same producer pattern as `oddjobz-events`.
5. **Flutter hat context**: register the new hat in `HatContext`; all universal SQLite tables and event subscriptions already support it via `domain_flag` column.
6. **No new JSONL stores.** The `*_store_fs.zig` pattern is retired; every new hat's entities are cells in `LmdbCellStore` from day one.

---

## Document maintenance

This pipeline is the source of truth for BRAIN brain + Flutter DB integration work. Update status in-place. New rows get IDs `W<section>.<next>` continuing the sequence.

Companion docs: `SEMANTOS-DB-IMPLEMENTATION-PIPELINE.md`, `docs/canon/SEMANTOS-DB-PASKIAN-ADDENDUM.md`, `docs/canon/cybernetic-orders.md`.
