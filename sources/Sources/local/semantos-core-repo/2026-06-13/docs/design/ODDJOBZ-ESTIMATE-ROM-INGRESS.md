---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/ODDJOBZ-ESTIMATE-ROM-INGRESS.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.740775+00:00
---

# Oddjobz — Estimate entity + ROM ingress + Estimate→Quote promotion

Status: design (approved direction — true-to-design Estimate entity; ROM
flows via the conversation patch as an intent; `authorized` 13th Job FSM
state already shipped `1b0d7e3`).

Author: automated lift session, 2026-05-17.

## 1. Why

The Job FSM `lead → qualified` edge means "customer accepted the ROM
(rough order of magnitude) in the chat widget". Today that figure never
reaches the brain: the operator-typed `accept_rom` intent carries no
number, and the shell's `rom_accept` only mutates local conversation
state (`runtime/shell/src/chat/action-executor.ts`, `rom-engine.ts`).

Goal: when a ROM is accepted, persist it as a typed **Estimate** cell on
the brain, drive `lead → qualified`, and have the operator's eventual
`qualified → quoted` skip-path produce a **draft Quote pre-filled from
the accepted Estimate** — so the operator never re-keys the figure, and
Pask + pricing analytics get a clean ROM→Quote→outcome lineage.

True-to-design (operator's call): the AFFINE Estimate and the LINEAR
Quote stay distinct cells. An Estimate can be discarded without becoming
a Quote (per `cell-types/estimate.ts` §O2). This decomposes the intake
so any tradesman's process can be modelled, and specific steps
fast-forwarded per user (e.g. the `authorized` no-quote REA branch).

## 2. What already exists (do not rebuild)

| Piece | Location | Note |
|---|---|---|
| Estimate cell type | `extensions/oddjobz/src/cell-types/estimate.ts` | AFFINE, TS-canon only. `estimateId, jobId, estimateType(auto_rom\|operator_rom\|revised), costMin/Max cents, ackStatus(pending\|accepted\|tentative\|pushback\|rejected\|wants_exact_price\|rate_shopping), acknowledgedAt, …`. **No FSM** — `ackStatus` is a plain field; AFFINE = no linear-consumption transition table. |
| Quote entity | `quotes_store_lmdb.zig` (module-aliased `quotes_store_fs`), `resources/quotes_handler.zig`, `quote_fsm.zig`, `quote_fsm.json` | Fully built. `quotes.create {job_id, cost_min, cost_max, notes, status}`. Quote FSM `draft→presented→accepted/rejected/expired/superseded`. |
| Job FSM | `state-machines/job-fsm.ts` + mirrors | 13 states incl. `authorized`. `lead→qualified` (null cap/operator), `qualified→quoted` skip (cap.oddjobz.quote/operator). |
| Intent router | `extensions/oddjobz/zig/src/intent_action_router.zig` | `accept_rom/rom_accepted/qualify→qualified`. Subscribes `intent_cell.created`, dispatches `jobs.transition`. **Ignores** the spec'd `targetJson.amount` money channel (`docs/spec/oddjobz-intent-cell-v1.md:76`). |
| Broker subscriber pattern | `extensions/oddjobz/zig/src/visit_rollup_router.zig` | Proven subscribe→enqueue→tick→dispatch with the broker-reentrancy guard. The template for the promotion router. |
| Shell ROM | `runtime/shell/src/chat/{action-executor,rom-engine}.ts`, `intent-adapters/shell-to-intent.ts` | `rom_accept` produces a local patch `{autoRomStatus:'accepted', status:'estimate_accepted'}`; `rom-engine` computes `autoRomMin/Max`. Intent-adapter layer exists to turn shell actions into brain intents. |

## 3. Design

### 3.1 Estimate store + handler (Slice 2)

Mirror the **quotes** pattern exactly (it is the closest sibling — same
LMDB-entity-cell backing, same handler/dispatcher shape), minus the FSM
transition machinery (Estimate is AFFINE, no linear consume):

- `extensions/oddjobz/zig/src/estimates_store_lmdb.zig` — clone
  `quotes_store_lmdb.zig`. Record shape from `estimate.ts` (id, job_id,
  estimate_type, cost_min, cost_max, ack_status, acknowledged_at,
  notes, created_at, updated_at). `isValidAckStatus` gate over
  `ESTIMATE_ACK_STATUSES`. Entity-cell `put` writes a `created` cell;
  an `acknowledge` writes an `updated` cell (same kind-tagged replay as
  jobs_store_lmdb_entity). Add the live-index `rescanCreatedCells`
  hook from day one (we already learned that lesson — commit `956eb81`).
- `extensions/oddjobz/zig/src/resources/estimates_handler.zig` — clone
  `quotes_handler.zig`. Resource `"estimates"`. Verbs:
  - `create {job_id, estimate_type?, cost_min, cost_max, notes?}` →
    mints an Estimate (ackStatus `pending`), FK-checks `job_id`.
  - `find {job_id?}`, `find_by_id {id}`.
  - `acknowledge {id, ack_status, acknowledged_at?}` → sets ackStatus
    (the ROM-accept path uses `ack_status:"accepted"`). AFFINE: no
    consumed-cell gate; idempotent on identical re-ack.
  Caps: `cap.oddjobz.read_estimates` / `cap.oddjobz.write_estimate`
  (mirror the quotes cap pair; add constants alongside the existing
  oddjobz caps).
- `quote_fsm.json`-style parity oracle is **not** needed (no FSM).
  Conformance test mirrors `quotes_handler` minus FSM-transition cases.
- Wire `estimates_store_fs`-aliased module + handler in `build.zig`
  (mirror the quotes `createModule`/import/test sites) and register in
  `serve.zig` next to the quotes block (~`serve.zig:1252-1267`).

### 3.2 ROM ingress — conversation patch → intent (Slice 3)

Decision (operator): ROM rides the **conversation patch as an intent**,
not a config write. Two integration points:

1. **Shell side** (`runtime/shell/src/intent-adapters/shell-to-intent.ts`
   + `chat/action-executor.ts`): when `rom_accept` fires, in addition
   to the local patch, emit a brain intent carrying the ROM range. Use
   the already-spec'd intent-cell money channel:
   `originalIntent.targetJson = { jobId, costMin, costMax }`
   (`docs/spec/oddjobz-intent-cell-v1.md:76`; cents). Action verb stays
   `accept_rom` / `rom_accepted`.
2. **Brain side** (`intent_action_router.zig`): on an `accept_rom`
   action whose payload carries `targetJson` cost bounds, BEFORE the
   `jobs.transition lead→qualified` dispatch, dispatch
   `estimates.create {job_id, estimate_type:"auto_rom", cost_min,
   cost_max}` then `estimates.acknowledge {id, ack_status:"accepted"}`
   (or a single `create` with `ack_status:"accepted"` for the
   auto-ROM-accepted case). Then the existing `lead→qualified`
   transition fires as today. Figure-less `accept_rom` (no targetJson)
   keeps working exactly as now (transition only) — non-breaking.

Router stays transition-orchestration; the Estimate mint is one extra
dispatch through the dispatcher (uniform audit/caps), enqueued+ticked
off the broker mutex like every other router action.

### 3.3 Estimate→Quote promotion (Slice 4)

New broker subscriber `extensions/oddjobz/zig/src/quote_seed_router.zig`,
**cloned from `visit_rollup_router.zig`** (same enqueue+tick+guard):

- Subscribe `job.transitioned`. Filter `to=="quoted"` AND
  `from=="qualified"` (the skip path — quote straight off the
  prequalified ROM). `visited→quoted` is left to the operator's manual
  quote (a post-visit quote is not a ROM carry-through; degrade: no
  seed, no error).
- On match: look up the job's most-recent **accepted** Estimate
  (`estimates.find {job_id}` → pick `ackStatus=="accepted"`). If none,
  audit-skip (operator quotes from scratch — graceful no-op).
- Dispatch `quotes.create {job_id, cost_min, cost_max (from the
  Estimate), status:"draft", notes:"seeded from auto_rom estimate
  <id>"}` as `in_process_root`. Idempotent: if a draft quote already
  exists for the job, skip (quotes.create is idempotent on identical
  args; we additionally check find first).
- Shares the intent-router gate (same `--enable-intent-action-router`
  systemd flag; zero ops change), mirrors visit_rollup wiring in
  build.zig/serve.zig/site_server/event_loop.

## 4. Slice plan (each = test-gate-green + path-scoped commit + deploy)

1. **Slice 1 — n/a.** (No estimate FSM; folded into Slice 2.)
2. **Slice 2 — Estimate store + handler + dispatcher wiring +
   conformance.** Self-contained; ships an inert `estimates` resource.
3. **Slice 3 — ROM ingress.** Shell intent-adapter emits the figure;
   `intent_action_router` mints/acks the Estimate on `accept_rom`.
   After this, accepted ROMs are persisted Estimate cells.
4. **Slice 4 — `quote_seed_router`.** `qualified→quoted` seeds a draft
   Quote from the accepted Estimate. Closes the loop.

Each slice independently valuable and reversible. Stop/raise to operator
if any slice surfaces a new substantive FSM/scope decision.

## 5. Decisions captured (so future readers don't re-litigate)

- **Estimate has no FSM.** It is AFFINE with a plain `ackStatus` field.
  We do NOT add an estimate_fsm; acknowledgement is a field write, not
  a linear-consumption transition. (If a formal estimate FSM is ever
  wanted, it is a separate decision.)
- **ROM ingress = intent, not config.** Carried on the intent cell's
  existing `targetJson` money channel. No new HTTP write path.
- **Promotion = broker subscriber**, not in-handler — same
  broker-reentrancy reasoning as `intent_action_router` /
  `visit_rollup_router`.
- **Skip-path only for auto-seed.** `qualified→quoted` seeds from the
  ROM Estimate; `visited→quoted` stays a from-scratch operator quote.
- **No new capability for `authorized`** (already shipped); estimates
  add `cap.oddjobz.{read_estimates,write_estimate}` mirroring quotes.

## 6. Open questions (non-blocking; sensible defaults taken)

- Estimate `estimateType` for the chat-widget ROM: defaulting to
  `auto_rom`. `operator_rom` when an operator hand-enters a figure
  (future verb).
- Multiple ROMs per job (revised): `estimates.find {job_id}` returns
  all; promotion picks the most-recent accepted. `revised` supported by
  the type; no special-casing this pass.
- Currency: cents, AUD implied (matches quotes — no currency field).
