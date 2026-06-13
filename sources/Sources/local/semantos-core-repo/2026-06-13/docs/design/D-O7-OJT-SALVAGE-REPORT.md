---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/D-O7-OJT-SALVAGE-REPORT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.723330+00:00
---

# D-O7 — OJT salvage + substrate canon-alignment — investigation report

**Status**: Working notes for the D-O7 reframed deliverable.
**Date**: 2026-05-01
**Branch**: `feat/oddjobz-d-o7-salvage`
**Reframing**: The original D-O7 spec called for a "shadow-mode for a week
of measurement before authority flip". The operator has confirmed OJT was
**never live with real customers** — the entire production deployment was
testing. D-O7 therefore becomes: salvage the load-bearing logic out of OJT
into the canon substrate, drop the rest, single PR. No shadow mode, no
data migration, no production cutover. The OJT repo at
`/Users/toddprice/projects/oddjobtodd/` is to-be-archived after this PR
merges; nothing in this PR touches it.

OJT files listed in §1 below were read **in read-only mode**.

---

## 1. Conversation issues OJT exposed

The operator flagged that the kernel work (D-W1 dispatcher + the K3 hat-
isolation theorem) was specifically meant to address "the issues in the
conversation" the multi-hat conversation flow had been hitting. After
reading `conversationStateManager.ts`, `chatService.ts`, and
`ojtHandleMessage.ts`, the load-bearing failure modes are:

### Finding 1 — Hat-boundary is application-filtered, not structurally enforced

`chatService.ts` lines 180–223 auto-create a channel per
`(jobId, customerId)` pair and then filter `schema.messages` by
`channelId` to scope what the LLM sees. This is enforcement at the SQL
filter layer — a missing `channelId` (the auto-create comment at line
180–201 explicitly tracks pre-channel writes that pass the filter) or a
bug in `getChannelForParticipant` lets one hat's context leak into
another's prompt construction.

The `HatContext` built by `buildOjtHat` in `ojtHandleMessage.ts` lines
222–234 does NOT carry capabilities or a real domain flag — `capabilities:
[]` and `domainFlag: 0` are hard-coded TODOs ("Once the cell-engine side
lands these will carry real values"). The hat-scoping is therefore **a
filter, not a gate**. A misconfigured filter is a silent leak.

**Fix sketch**: Hat-scoped patches must be derived under the hat's
context-tag at cap-mint time so that even if the filter is wrong, the
presenter pubkey (BKDS-derived from the wrong hat) does not satisfy the
spend gate. This is exactly what `oddjobz_cap_isolation_cryptographic`
(PR #279, `proofs/lean/Semantos/Capabilities/Oddjobz.lean` line 283)
proves: BKDS injectivity-in-context_tag means the wrong hat's child
pubkey can't spend the cap. Port `hat-scoping.ts` so the application
threads the hat's contextTag through to cell construction; the kernel
gate enforces the rest.

### Finding 2 — Patch ordering is "best-effort", not totally ordered

`chatService.persistTurnPatches` writes to `sem_object_patches` after
the LLM returns. With concurrent in-flight customer messages on the same
job (e.g. the customer types two messages before the AI replies to the
first), there is no kernel-enforced total order — the writes interleave
at PostgreSQL transaction commit. Federation consumers downstream
(another tenant pulling patches via the §O11 dispatch envelope) see
patches in commit-order, not message-arrival-order.

**Fix sketch**: D-W1's dispatcher gives total ordering at the audit-pair
seam — every patch flows through `dispatch.send` and inherits the
audit-pair invariant (every emit produces a matched receipt). Conversation
patches that ride through the dispatcher inherit it for free. Don't
rebuild a per-job ordering ledger at the application layer; route
conversation patches through `dispatch.send` and let the kernel-mediated
seam own the ordering.

### Finding 3 — State machine has no kernel-level "stuck state" guarantee

`conversationStateManager.evaluateConversationState` is a 230-line cascade
of `if` clauses that decides the next conversation action. Each branch is
locally sound, but there is no theorem that the function is **total** —
that for every reachable `AccumulatedJobState` it returns a non-`continue`
action (or an explicit `continue`). In practice the operator hit cases
where the bot would loop on `{ type: 'continue' }` without ever asking
the next question (e.g. when `estimateReadiness` was 49 — one below the
threshold — and `scopeClarity` was 34, one below the second-chance
threshold).

**Fix sketch**: D-O4's Job FSM has `job_fsm_transitions_total` proven in
`proofs/lean/Semantos/Extensions/Oddjobz/StateMachines/JobFSM.lean`. That
gives "no stuck state at the substrate level". The conversation
state-manager runs ABOVE the FSM — it picks which transition to drive
next. The right shape is: when the conversation manager returns
`{ type: 'continue' }` AND the underlying Job is in a state with an
ungated transition (`scheduled → in_progress`, `invoiced → paid`), the
ungated transition fires automatically. The application-layer cascade
becomes a hint, not a gate. Port the cascade verbatim (its tuned
thresholds are load-bearing) but document that it is hint-only — the FSM
is the source of truth for "what's the next valid move".

### Finding 4 — Extraction confidence drift across model tunes

`extractionSchema.ts` defines `lenientEnum` and falls back to `null` on
unknown values. In practice, when the operator swapped `claude-haiku-4-5`
for a different model mid-development, fields silently went `null` — the
extraction prompt was tuned against the old model's verbatim quirks, and
the new model returned values just outside the enum (e.g. `"price-
focused"` with a hyphen rather than `"price_focused"` with an underscore).
The **confidence** field in D-O6b's `lead_extract` resource is the right
place to surface this drift, but OJT had no mechanism to threshold-gate.

**Fix sketch**: The `confidence` field in `lead-extract.ts` already
exists (line 73, `readonly confidence: number`); the
`confidenceFloor` parameter (line 57, default 0.5) thresholds. Port the
OJT extraction schema's tuned prompt and tagged-facts shape into a
companion module that emits a `confidence` value and gates the same
way. When confidence drops below the floor, surface a `lead-extract:
low_confidence` warning into the audit log and skip auto-ratification.

### Finding 5 — Prompt collisions across multi-hat operator personas

The operator runs under a single OJT identity but the long-term plan has
multiple hats per identity (carpenter, musician, RE-property-manager) per
the BRAIN-DISPATCHER §2.5 motivating example. OJT's `systemPrompt.ts`
hard-codes Todd's handyman business persona; if a second hat (say,
musician booking enquiries) ran through the same chat infrastructure, it
would inherit Todd's tradie tone and rules. The prompt was authored as
single-tenant from day one.

**Fix sketch**: Port the system prompt as `system-prompt.ts` keyed by
`hatId` (carpenter | musician | …) so the prompt-builder selects the
right persona text at chat time. The hat selection is downstream of the
K3 isolation check — the cap-presenter pubkey identifies which hat is
authoring, the prompt-builder reads the hat tag and picks the persona.

### Finding 6 — `semanticRuntimeAdapter` was a mid-migration shim, now mostly obsolete

`semanticRuntimeAdapter.ts` is explicitly labelled "SHIM" at the top and
delegates to `src/lib/semantos-kernel/verticals/trades/`. The shim
exposed `ensureSemanticObject`, `recordStateSnapshot`, `recordScores`,
`recordEvidence`, `recordInstrument`, `recordStatusTransition`. Every
one of these is now subsumed by the canon merged work:

| OJT shim function          | Canon replacement                                                  |
| -------------------------- | ------------------------------------------------------------------ |
| `ensureSemanticObject`     | D-O2 `OddjobzJob` cell + D-O4 `genesisJobLead`                     |
| `recordStateSnapshot`      | D-O4 `jobTransition` (each transition mints a successor cell)      |
| `recordScores`             | Out of scope — scoring is application logic; cell carries inputs   |
| `recordEvidence`           | D-O6b `oddjobz.message.v1` cell via `chat-persistence.ts`          |
| `recordInstrument`         | D-O6b `lead-extract.ts` `draftEstimate` (Estimate cell pre-ratify) |
| `recordStatusTransition`   | D-O4 `jobTransition` returns `{ consumedCellId, successorCellId }` |

So the shim layer is fully obsolete. The cron endpoint
(`/api/cron/analyze-conversations/route.ts`) calls a Vercel-internal
endpoint that doesn't exist in the OJT repo — dead code.

---

## 2. What's worth porting

For each OJT file in scope, a one-paragraph verdict:

### `oddjobtodd/src/lib/ai/prompts/systemPrompt.ts` — **SALVAGE**

Salvage because the prompt encodes ~6 months of operator-tuned behaviour
(ROM vs quote framing, pre-qualification mechanic, photos guidance,
critical scope questions per trade, pushback handling, jural lexicon
verb-aware elicitation). The operator wants this kept verbatim. Land at
`extensions/oddjobz/src/prompts/system-prompt.ts`. The PDF-import branch
and channel-context branch port across; the hat parameter becomes a
required input (no implicit Todd default).

### `oddjobtodd/src/lib/ai/prompts/extractionPrompt.ts` — **SALVAGE (most)**

Salvage the extraction body, the JSON shape, the EXTRACTION RULES (job
types, urgency, tones, cheapest-mindset, conversation phase, suburb
hints, jobPivot HARD RULES). The TAGGED FACTS section depends on
`@/lib/lexicons` which doesn't exist in semantos-core; that section
ports as a parameterised hook (caller passes the lexicon registry as a
function arg, default empty). Land at
`extensions/oddjobz/src/prompts/extraction-prompt.ts`.

### `oddjobtodd/src/lib/ai/prompts/pdfExtractionPrompt.ts` — **SALVAGE (prompt only)**

Salvage the prompt as a frozen string; the PDF parser itself (`pdf-parse`
or similar) is a downstream library decision that the Semantos Brain-side isn't
ready for. Land at `extensions/oddjobz/src/prompts/pdf-extraction-prompt.ts`
with a doc comment noting that the actual PDF byte-extraction step is
deferred.

### `oddjobtodd/src/lib/ai/extractors/extractionSchema.ts` — **SALVAGE (fold into D-O6b)**

The OJT extraction schema is RICHER than D-O6b's MVP `LeadExtractResult`:
sub-scores (`scopeClarity`, `locationClarity`, `contactReadinessScore`,
`estimateReadiness`, `decisionReadiness`), estimate-acknowledgement
state, customer-fit + worthiness scores, RomInstrument shape. The
`lead_extract` resource only exposes `{has_lead, draft_estimate, confidence}`
to keep the dispatcher seam minimal. Fold the OJT richness into a
companion `accumulated-job-state.ts` module under
`extensions/oddjobz/src/conversation/` that the application layer reads
between turns; D-O6b's `LeadExtractResult` stays the dispatcher boundary.

### `oddjobtodd/src/lib/domain/workflow/conversationStateManager.ts` — **SALVAGE (refactored)**

The 356-line file is THE most load-bearing OJT artefact for D-O7. Port
verbatim into `extensions/oddjobz/src/conversation/state-manager.ts`,
refactored to use D-O4's Job FSM as the substrate (per Finding 3 above).
The `ConversationAction` discriminated union ports unchanged; the
`evaluateConversationState` cascade ports unchanged; the tuned thresholds
(70 for decision-readiness, 50 for estimate-readiness, 35 for scope-
clarity etc.) port verbatim. The `generateSystemInjection` exhaustive
switch ports unchanged — its strings are operator-tuned.

### `oddjobtodd/src/lib/services/chatService.ts` — **SALVAGE (selectively)**

The 1829-line file is a kitchen-sink orchestrator. The bits worth porting
are: (a) the `processCustomerMessage` cycle outline (12 numbered steps in
the docblock, lines 6–19 — port as a doc-comment to the new module);
(b) the channel auto-creation pattern (lines 180–201) — port as
`hat-scoping.ts`; (c) the `pivot.decision` logging (lines 290–305 in
chatService — was load-bearing for debugging); (d) the
`buildChatMessages` transcript-building helper (line 806). The DB-access
boilerplate, the `getDb()` and `schema.messages` etc. drop because
semantos-core has no PostgreSQL. The `handleTenantMessage` shape ports
as the public entry-point of the conversation module.

### `oddjobtodd/src/lib/services/ojtHandleMessage.ts` — **SALVAGE (the HatContext-build pattern)**

Most of `ojtHandleMessage.ts` is wiring around `@semantos/intent`'s
`handleMessage` orchestrator with no-op pipeline deps. That noop wiring
DROPS — D-W1 dispatcher is now real. The load-bearing bits are:
(a) `buildOjtHat()` shape — port to `hat-scoping.ts` as
`buildOddjobzHat()`, fixing the `capabilities: []` / `domainFlag: 0`
hard-codes (real values from `OPERATOR_ROOT_CAPS` / `NODE_SERVICE_CAPS`
in `extensions/oddjobz/src/capabilities.ts`); (b) `mapTriageHint` — the
`PROPOSES | RATIFIES | NO_INTENT | REJECT_CONFLICT` quad is a useful
classifier output shape, port as `triage-hint.ts`. Both small.

### `oddjobtodd/src/lib/domain/bridge/semanticRuntimeAdapter.ts` — **DROP**

Drop wholesale. Each shim function is subsumed by the canon merged work
(see Finding 6's table). Nothing to port.

### `oddjobtodd/src/app/api/cron/analyze-conversations/route.ts` — **DROP**

Drop. The endpoint is a 47-line reverse-proxy to
`/api/analyze-conversations` which **does not exist** in the OJT repo
(verified via `find /Users/toddprice/projects/oddjobtodd/src
-iname "*analyze*"` — only the cron stub matches). Dead code. The
periodic-conversation-analysis idea is worth preserving as a placeholder;
land a stub at `extensions/oddjobz/src/conversation/analyzer.ts` with a
TODO that says "operator triggers manually via REPL/CLI; brain has no
built-in cron". External cron + curl is documented as the production
trigger path.

---

## 3. What's structurally subsumed by D-O2/3/4/6b

Calling out OJT logic that is already (better) covered by the canon:

- **Cell-type declarations** (`messages`, `jobs`, `customers`, `sites`,
  etc. in OJT's Drizzle schema) → D-O2's eight cell types
  (`oddjobz.{job,quote,visit,invoice,customer,site,estimate,message}.v1`).
  OJT's PostgreSQL `messages` table maps onto `oddjobz.message.v1`
  one-to-one for the chat-relevant subset. The OJT `jobs` table's
  `status` enum maps onto `JOB_FSM_STATES`.
- **Capability gating** (OJT had no kernel-level cap enforcement; checks
  were SQL-row-level via `operators.role`) → D-O3's six caps
  (`cap.oddjobz.{quote,dispatch,invoice,close,write_customer,
  public_chat_serve}`) and the `OP_CHECKDOMAINFLAG` opcode that enforces
  domain-flag match on a presented cap UTXO.
- **Job state transitions** (OJT's `job_state_events` audit log) → D-O4's
  `JOB_TRANSITIONS` table + `jobTransition()` function with K1/K2/K3a/K4
  enforcement. OJT's audit log was a passive record; D-O4 prevents
  invalid transitions structurally.
- **Chat persistence** (OJT's `messages` + `sem_object_patches`) →
  D-O6b's `chat-persistence.ts` (`buildVisitorMessageCell` +
  `buildAiMessageCell`) producing canonical `oddjobz.message.v1` cells
  with deterministic channel-IDs from the chat-session-id.
- **Lead detection** (OJT's `extractionPrompt.ts` + the chatService
  scoring cascade) → D-O6b's `lead-extract.ts` resource with
  `LeadExtractResult.has_lead + draft_estimate + confidence`. The OJT
  prompt's richer extraction stays — it lives in
  `extensions/oddjobz/src/prompts/extraction-prompt.ts` as the input to
  `lead-extract.ts`.
- **Ratification** (OJT had implicit ratification — operator clicks
  "approve" in the helm UI) → D-O6b's `ratification-queue.ts` with
  explicit `cap.oddjobz.write_customer` + `cap.oddjobz.quote` spend at
  ratify time.

The OJT versions of all of the above are being dropped.

---

## 4. Operator-facing TODO (post-merge)

After this PR merges and the CI is green, the operator should:

1. **Archive `/Users/toddprice/projects/oddjobtodd/`**. Tag the repo head
   with `archived-2026-05-01` and mark the repo read-only on GitHub.
   The Postgres database `ojt_prod` on the `rbs` VPS can be backed up
   one final time and powered down — there are no real customers to
   migrate.
2. **Point any production DNS away** from `oddjobtodd.info` to the
   semantos-core tenant once D-O10 ships and the tenant is provisioned.
   Until D-O10 lands, the public chat surface is the D-O6b widget at
   `/chat` on whichever VPS is running `runtime/semantos-brain`.
3. **Snapshot any test data worth keeping** as fixtures in
   `extensions/oddjobz/tests/vectors/` — specifically the multi-turn
   conversations the operator used for regression-testing the prompts.
   These become test cases for the ported `state-manager.ts` cascade.
4. **Verify the Lean K3 + cryptographic-isolation theorems** still
   build (`cd proofs/lean && lake build`); D-O7 doesn't change them but
   the salvage code cites them, so a future Lean break would surface a
   dangling reference.

That's the full to-do for the operator. Everything else (extension
loading, cap minting, FSM enforcement) is automatic via the existing
boot sequence.

---

## 5. Findings table (PR body inline)

| # | Finding                                  | Fix substrate primitive                              |
| - | ---------------------------------------- | ---------------------------------------------------- |
| 1 | Hat-boundary leakage (filter, not gate)  | K3 + `oddjobz_cap_isolation_cryptographic` (PR #279) |
| 2 | Patch ordering is best-effort            | D-W1 dispatcher audit-pair invariant                 |
| 3 | State machine has no totality theorem    | D-O4 `job_fsm_transitions_total`                     |
| 4 | Extraction confidence drift              | D-O6b `lead_extract.confidence` + `confidenceFloor`  |
| 5 | Prompt collisions across multi-hat ops   | Hat-keyed prompt selection (port + parameterise)     |
| 6 | `semanticRuntimeAdapter` is obsolete     | D-O2 cells + D-O4 FSM (drop the shim)                |

---

## References

- `docs/design/ODDJOBZ-EXTENSION-PLAN.md` §O7 (the original framing).
- `docs/design/post-mortems/OJT-SCHEMA-DRIFT-2026-04.md` (prior audit).
- `proofs/lean/Semantos/Theorems/DomainIsolationK3.lean` (K3 hat isolation).
- `proofs/lean/Semantos/Capabilities/Oddjobz.lean` line 283
  (`oddjobz_cap_isolation_cryptographic`, PR #279).
- `extensions/oddjobz/src/state-machines/job-fsm.ts` (D-O4 Job FSM).
- `extensions/oddjobz/src/lead-extract.ts` (D-O6b lead-extract resource).
- `extensions/oddjobz/src/chat-persistence.ts` (D-O6b chat persistence).
- `extensions/oddjobz/src/ratification-queue.ts` (D-O6b ratification).
- `docs/design/BRAIN-DISPATCHER-UNIFICATION.md` §2.5 (carpenter+musician
  motivating example for hat isolation).
