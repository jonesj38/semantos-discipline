---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/DOGFOOD-READINESS-MATRIX.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.677395+00:00
---

# Dogfood readiness matrix

**Status**: Planning artifact. Operator-driven.
**Goal**: Get the operator (you) to the point where you can direct the system, by voice or by tap, to:

1. Read your Gmail inbox and extract jobs from PDF attachments
2. Organise them into clear job sheets, surfaced by state
3. Do the same with the Meta inbox (secondary)
4. Propose a sequence of calendar events to clear the quote / maintenance backlog
5. Approve / amend / ratify the proposal

…all without leaving the helm, and with the operator's data flowing through nothing they don't own.

**Reference**: `docs/canon/unification-matrix.yml`, `docs/textbook/`, `docs/guides/LEGACY-INGEST-GMAIL-SETUP.md`, `runtime/legacy-ingest/src/`, `extensions/oddjobz/src/`.

---

## §1 — Where you stand today (inventory)

The picture is much rosier than "we need to build this from scratch." Most of the substrate is in place. Catalog:

### §1.1 Legacy-ingest pack — `runtime/legacy-ingest/` (≈2400 LOC core, near-zero TODOs)

Through **LI1 + LI2 + LI3 + (partial) LI4**:

| Surface | File | LOC | State |
|---|---|---|---|
| Gmail provider | `providers/gmail.ts` | 191 | shipped — paginated backfill, blob-store hand-off |
| Meta provider | `providers/meta.ts` | 293 | shipped |
| OAuth orchestrator | `oauth.ts` | 370 | shipped — state nonce + PKCE + token exchange + refresh + revoke |
| Encrypted grant store | `grant-store.ts` | — | shipped |
| Cursor store | `cursor-store.ts` | — | shipped — resumable polling per provider |
| Blob store | `blob-store.ts` | — | shipped — encrypted at rest under wallet KEK |
| Email extractor | `extractor/email.ts` | 316 | shipped |
| Attachment extractor | `extractor/attachment.ts` | 284 | shipped — but PDF byte-parse is the gap (see §2.2) |
| OpenRouter LLM client | `extractor/openrouter.ts` | 285 | shipped |
| Pre-classifier | `extractor/pre-classifier.ts` | — | shipped — fast triage before expensive LLM calls |
| Thread collapser | `extractor/thread.ts` | — | shipped |
| Proposal store | `proposal-store.ts` | — | shipped — encrypted typed Proposals (SIRPrograms + provenance + confidence) |
| Ingest worker | `ingest-worker.ts` | 248 | shipped |
| Ratification orchestrator | `ratification/orchestrator.ts` | 235 | shipped — review/ratify/reject/correct/bulk-ratify/unratify |
| `pask-bridge.ts` | — | 173 | shipped — bridge to brain |
| OAuth callback widget | `widget/serve.ts` | — | shipped — Bun HTTP server, runs on its own port |
| `legacy` REPL verb | `verb.ts` | — | shipped — wired into `apps/legacy-cli/` |

### §1.2 Oddjobz extension — `extensions/oddjobz/src/`

| Surface | State |
|---|---|
| 8 typed cells (job/quote/visit/invoice/customer/site/estimate/message) | shipped |
| State machines (job/quote/visit/invoice FSMs) | shipped |
| Conversation analyzer + hat scoping + substrate bridge | shipped |
| `lead-extract.ts` resource (LlmCompleteFn-parameterised) | shipped — TS pure shape |
| `prompts/pdf-extraction-prompt.ts` (handyman-tuned, ported from `oddjobtodd`) | shipped — prompt only; byte-parse deferred |
| `prompts/system-prompt.ts` | shipped |
| Ratification queue scaffolding | shipped |

### §1.3 Brain (brain) + helms

| Surface | State |
|---|---|
| oddjobz tenant on brain — jobs/leads/quotes/customers/visits/attachments/invoices | shipped (smoke-test verified) |
| `find calendar [--from X] [--to X]` REPL verb | shipped |
| `find attention` REPL verb | shipped |
| Calendar view in helm SPA + mobile (`calendar_screen.dart`, `Calendar.svelte`) | shipped |
| Attention view in helm SPA + mobile | shipped |
| WSS live event stream + `helm.fetch_since` RPC | shipped (D.1) |
| Sovereign push (wake-only, optional UnifiedPush) | shipped (D.1–D.3, PRs #342–#344) |
| Multi-hat helm sessions | shipped (D-O5.followup-8) |
| Per-tenant theming | shipped (D-O5.followup-6) |
| Voice extraction (compression gradient + SIR) | **in flight — D-O5m.followup-3** |

### §1.4 Calendar extension — `extensions/calendar/src/`

api / db / domain / guard / lexicon / policy / ui — shipped scaffold.

### §1.5 Operator runbook for OAuth

`docs/guides/LEGACY-INGEST-GMAIL-SETUP.md` — already written. ~10-minute setup against Google Cloud Console + REPL.

---

## §2 — The dogfood gap (what's missing)

After §1, the gap is narrower than it looks. Concrete missing wires:

### §2.1 Two-CLI dance — `legacy-cli` runs separately from `brain`

The `legacy` verb is registered into a standalone Bun CLI (`apps/legacy-cli`). The operator's mental model is "talk to my brain" (= `brain`). Today they would have to:

1. Run `brain serve …` for the oddjobz tenant
2. **Also** run the legacy widget Bun server for OAuth callbacks
3. **Also** run `bun apps/legacy-cli/src/index.ts legacy connect gmail`

That's three processes. Not catastrophic, but a friction wall.

**Two paths:**
- **A — quick**: ship a wrapper that launches all three under `brain dogfood up`, plus document the dance in a runbook. ~½ day.
- **B — proper**: lift the `legacy` verb into the `brain` REPL itself by exposing the TS layer over a JSON-RPC sidecar (or via Bun-host embedded). ~3–5 days.

For first dogfood: **A**, then promote to **B** as a followup.

### §2.2 PDF byte-parse — explicitly deferred in `pdf-extraction-prompt.ts`

> "The actual PDF byte-extraction step (parsing the bytes into text the LLM consumes) is **deferred** to a follow-up — semantos-core does not yet have a `pdf-parse` or equivalent module wired through the dispatcher. Per the D-O7 brief's 'if something is genuinely ambiguous' §(b), we ship the prompt-only; the operator runs the parse manually for now."

**Three sub-options, in increasing capability:**

1. **Shell out to `pdftotext`** (Poppler) — zero deps, already on most macOS/Linux. Works for text PDFs. **Doesn't work** for scanned/image PDFs.
2. **`pdf-parse` npm package** — pure JS, embedded. Same text-only limitation as #1.
3. **OpenRouter Vision** (`openai/gpt-4o-mini` or similar) — handles scanned PDFs via vision. Costs per page. Rate-limited.

**Recommendation:** layered. Try `pdftotext`. If extracted text is < N chars, fall back to OpenRouter Vision. Cache the parsed text in `blob-store` keyed by attachment hash so repeat ingests are free.

### §2.3 Proposal → oddjobz cell-DAG bridge

The ratification orchestrator produces `Proposal` objects (SIRPrograms). After `legacy ratify`, those need to flow into the oddjobz cell-DAG (`jobs.jsonl`, `customers.jsonl`, `quotes.jsonl`). `pask-bridge.ts` exists; needs end-to-end verification + likely a thin oddjobz-specific adapter that maps SIR programs to oddjobz cell-type writes.

### §2.4 Mobile review queue

The helm SPA is the assumed surface. Mobile mirror of the review queue (so the operator can ratify on the phone while in the field) — likely missing. Mid-priority for first dogfood; the operator can review at the desk.

### §2.5 Execution proposal engine

"Propose a set of events to structure getting on top of my backlog."

Calendar + Attention views are read-only today. Need:

- **Inputs**: backlog (jobs by state) + capacity model (working hours, geographic clustering, current bookings)
- **Heuristic v0**: cluster by suburb, sort by urgency × age × customer LTV, fit into open calendar slots with travel-time padding
- **Output**: a list of proposed `calendar.event.v1` cells (referencing `job.v1` IDs) for operator review
- **Approve flow**: ratify proposed events → write to local calendar cells → push to Google Calendar via the calendar extension

This is genuinely new code. ~3–5 days for v0.

### §2.6 Voice trigger

D-O5m.followup-3 (voice extraction via compression gradient + SIR) is in flight. Once it lands, wire two intents:
- "read my Gmail" → `legacy ingest gmail --since <reasonable-default>`
- "plan tomorrow" → execution proposal engine + helm review

Wait for followup-3 to land before wiring; trivial integration.

### §2.7 Meta-side last mile (secondary)

Provider exists. PDFs are rare in Meta inboxes; mostly text. Same extractor pipeline applies. Only thing genuinely missing is the OAuth runbook (mirror of the Gmail one but for Meta Business Suite Graph API).

---

## §3 — End-state vision (one paragraph)

You open the helm. Tap or say "read my email." Within 30 seconds, the attention pane shows N new proposals — each one a parsed quote request or maintenance order with extracted customer, address, scope, urgency, linked back to the source email + PDF. You scan, tap "ratify all confidence > 0.8," manually correct two, reject one. Then "plan tomorrow." The calendar view fills with proposed visits clustered geographically, padded with travel time, gated by your stated 7-hour working day. You drag two, approve, push. The push lands in Google Calendar; the customer-facing confirmations queue for your sign-off. You close the helm. Sovereignty is preserved end-to-end: Gmail OAuth tokens encrypted under your wallet KEK, OpenRouter LLM calls go direct (no aggregator middleman), proposals + ratifications are signed cells in your own DAG, push wakes flow through your chosen UnifiedPush distributor.

---

## §4 — Execution matrix

Each row is a deliverable sized for one subagent passoff (≤1 day of focused work, single PR). Sequenced for dependency safety.

### Tier 0 — Foundation verification — **DONE 2026-05-03**

Findings (recorded; matrix premise corrected below):

- **V0a**: `apps/legacy-cli` builds + tests green (30/30 + 248/248 in legacy-ingest). **Pipeline gap**: `legacy ingest` only fetches raw blobs into the encrypted blob store; no verb runs `ExtractionRunner` over the blobs to produce proposals. Dead code from CLI's perspective. → New prereq **D-DOG.1.0** below.
- **V0b**: `pask-bridge.ts` is **not** a cell-DAG writer — it's an attention-graph signal emitter (h-state mutations). The actual SIRProgram → cell-DAG seam is `RatificationOrchestrator.opts.writeCell`, which `bootstrap.ts:144` intentionally leaves `null` ("Phase 1 returns SIRProgram + proposal id; Phase 2 wires the bridge"). → New prereq **D-DOG.1.0b** below.
- **V0c**: All TODOs benign. Matrix's "1 in oauth.ts" claim was stale.
- **V0d**: TS `LLMAdapter` interface is small + stable, plug-and-play for new backends. **Two unrelated LLM stacks**: brain-side `llm_adapter.zig` is voice→ParseResponse only (not generic completion); TS legacy-ingest is prompt+schema→typed-payload. Tier 1 TS adapter work unaffected; matrix §6.2's brain-side claim was overstated.

### Tier 1 — Gmail vertical — **restructured into Phase 1.0 (foundation seam) → Phase 1.A (parallel fan-out)**

#### Phase 1.0 — foundation seam — **REVISED 2026-05-03 to Path B' per agent stop-report + operator decision**

The first attempt at Phase 1.0 stopped before any code was committed because the originally-scoped "Path B" relied on architectural pieces that don't exist for oddjobz today:

- `host_persist_cell` is the WASM-module slot-store path (encrypted slots under tier KEKs). It does **not** write `jobs.jsonl` — that file is a denormalized helm-view cache, written by `JobsStore.append` via `jobs_handler.handleCreate`. The `*.jsonl` view stores live in **Layer 2** (dispatcher → handler → JSONL append). The cryptographic cell-DAG lives in **Layer 1** (Pask WASM → host_sign → host_persist_cell → slot store). **Oddjobz today is entirely Layer 2.** Every helm/REPL operator-driven write — including the smoke-test `add job AcmeCorp` that surfaced on the phone — uses Layer 2. No per-cell signing, no `prevStateHash` chain.
- brain holds **no private signing keys** — only pubkey cert records (`identity_certs.zig`). Private keys live on the paired client devices via BKDS.
- Therefore "brain signs cells under a hat" requires a Semantos Brain-side hat key vault that doesn't exist (and has sovereignty implications that need their own design pass — see D-DOG.1.0c below).

**Path B' (honest re-scope) — what Phase 1.0 actually does:**

| ID | Title | Files touched | Notes |
|---|---|---|---|
| D-DOG.1.0 | Wire `ExtractionRunner` into the CLI: chain `runForProvider()` onto the tail of `legacy ingest`, with a `--no-extract` flag for the rare blob-only case | `runtime/legacy-ingest/src/verb.ts`, `apps/legacy-cli/src/bootstrap.ts` | ~30 LOC + tests; without this, no proposals are ever produced |
| D-DOG.1.0b' | **Layer-2 ratify seam**: new brain JSON-RPC verb `oddjobz.ratify_proposal` that takes a SIRProgram + proposal_id, translates each SIR node to the corresponding existing typed dispatcher command (`jobs.create`, `customers.create`, `quotes.create`, etc.), invokes those handlers (which write to the JSONL view stores via the existing `*Store.append` path), and returns the inserted record IDs as `cell_ids` in the receipt. TS-side `RatificationOrchestrator.writeCell` POSTs the SIRProgram via WSS-RPC to this endpoint. | new `runtime/semantos-brain/src/oddjobz_ratify_handler.zig`, new `runtime/legacy-ingest/src/cell-writer/brain-rpc.ts`, `apps/legacy-cli/src/bootstrap.ts` (wire writeCell), end-to-end test | Trust level **= existing operator-driven REPL/helm writes**. We're not lowering the bar — we're meeting the bar that all of oddjobz already meets today. K1–K10 explicitly **deferred** to D-DOG.1.0c. ~½–1 day. |

End-to-end test for Phase 1.0 (revised): stub provider → ingest → extract → ratify → assert a record line appears in `<data_dir>/oddjobz/jobs.jsonl` (or whichever store the stub proposal targets) with the same shape as a REPL-driven `add job` write. **No signature/prevStateHash assertions — those are D-DOG.1.0c's surface, not this PR's.**

#### D-DOG.1.0c — Layer 1 promotion + tiered hat-key vault (deferred — separate deliverable, post-dogfood)

When dogfood is running and the operator has lived with Layer-2-only ratification for a few days, promote oddjobz to Layer 1 (cryptographic cell-DAG with per-cell signing). This is a substantial multi-PR deliverable, not a Tier 1 blocker. Captured here so the matrix is honest about what Phase 1.0 doesn't do.

**Architecture (per operator direction 2026-05-03):**

The hat-signing key vault is **tiered**, mirroring the hot/cold wallet pattern operators already understand from Bitcoin custody:

- **Hot tier — pocket-change hat key.** A single-sig key derived under BRC-42 from the operator's master, accessible to brain for routine ratification (proposal acceptance, day-to-day cell writes, cells whose economic weight is below a configurable threshold). Compromise of this key bounds the blast radius to whatever is signed under it before the operator notices and rotates.
- **Cold tier — value-sweep keys.** Outputs whose economic weight exceeds the hot threshold are routed to keys that require **multi-component unlock** — either k-of-n multisig or threshold signatures (the project already has threshold-signature primitives). Examples: invoices over $X, contract-binding consents, irrevocable economic actions. The operator must supply the additional unlock components (e.g. tap on phone + tap on a hardware token + brain-side hat = 3-of-3) before such cells can be signed.
- **Sweep policy.** A configurable rule on each oddjobz cell-type declares its tier (`tier: "hot" | "cold"` in the cell-type definition). Ratification routes signing requests to the appropriate vault. A second policy specifies value-based promotion (e.g. "any `invoice.v1` with `total_cents > 100_000` is cold regardless of declared tier").
- **Layer 1 schema upgrade.** `jobs_store_fs.zig` and siblings extend the JSONL line shape to carry `signature`, `prevStateHash`, `parentHash`, `typeHash`, `signedBy` (cert_id of the hat that signed). Backwards-compatibility: old lines without these fields treated as Layer-2 legacy records, displayed but flagged in the helm UI. Helm SPA + mobile JobList consumers updated accordingly.
- **Sovereignty implications.** Hot key on the brain is a real attack surface — an attacker who compromises the brain process can sign hot-tier cells. The cold tier preserves operator sovereignty for value-bearing actions. Documented explicitly in the runbook.

Sub-deliverables (sketch — to be expanded when D-DOG.1.0c is properly scoped):

- D-DOG.1.0c.1 — brain-side hat key vault: hot-tier key store (encrypted at rest under wallet KEK), key-derivation path under BRC-42, signing API for handlers
- D-DOG.1.0c.2 — Cold-tier multi-component unlock: threshold-signature integration, mobile-side approval UX, signing-session protocol
- D-DOG.1.0c.3 — JSONL schema upgrade for `*_store_fs.zig` (jobs/customers/quotes/visits/leads/invoices/attachments) + helm + mobile consumers
- D-DOG.1.0c.4 — Sweep policy DSL + per-cell-type tier declaration + value-based promotion rules
- D-DOG.1.0c.5 — Migration: existing Layer-2 records flagged as legacy; operator-initiated re-sign pass to upgrade them under the hot hat
- D-DOG.1.0c.6 — Runbook: explain hot/cold tiers to operators, document compromise blast-radius bounds + key-rotation procedure

Estimated total: 1–2 weeks of focused work spread across 5–6 PRs. Sequenced after Tier 1 dogfood is operationally proven.

#### Phase 1.A — parallel fan-out (after 1.0 lands; up to 4 agents in parallel)

| ID | Title | Files touched | Subagent? | Notes |
|---|---|---|---|---|
| D-DOG.1a | PDF byte-parse — `pdftotext` shell-out + Anthropic Vision fallback + blob cache | `extractor/attachment.ts`, new `extractor/pdf.ts`, tests | yes (1d) | §2.2 |
| D-DOG.1b | TS `OllamaAdapter` (LLMAdapter impl, default for shell ops) | new `extractor/ollama.ts`, tests | yes (½d) | §6.2 |
| D-DOG.1c | TS `AnthropicAdapter` (LLMAdapter + VisionAdapter direct, BYOK from `.env`) | new `extractor/anthropic.ts`, tests | yes (½d) | §6.2 — replaces OpenRouter middleman |
| D-DOG.1d | LLM router: Ollama default → Anthropic on low-confidence or vision | small change in `pipeline.ts` / call sites | yes (½d) | needs 1b + 1c |
| D-DOG.1e | Localhost OAuth callback — add `/auth/callback` route to widget server | `runtime/legacy-ingest/src/widget/server.ts`, `oauth.ts` redirect URI | yes (½d) | §6.1 |
| D-DOG.1f | `dogfood up` — process supervisor for brain + widget + legacy-cli | shell script in `scripts/dogfood-up.sh` | yes (½d) | §2.1 path A |
| D-DOG.1g | Operator runbook: localhost-callback Google Cloud setup + `dogfood up` + first ratify walkthrough | `docs/operator-runbooks/dogfood-gmail.md`, supersede `LEGACY-INGEST-GMAIL-SETUP.md` redirect URI section | yes (½d) | needs 1a–1f |
| D-DOG.1h | First live run — operator OAuth-pairs Google, runs full backfill, walks review queue, ratifies first ~20 proposals | none (operational) | **operator** | needs 1g |

Parallel groupings for Phase 1.A:
- **Group α (LLM swap, all TS)**: 1b + 1c first in parallel; 1d after both land
- **Group β (PDF parse, TS, depends on 1c for Vision fallback)**: 1a — fires once 1c lands
- **Group γ (auth + supervisor, file-disjoint from above)**: 1e + 1f in parallel, can fire same time as Group α
- **Then**: 1g (runbook), then 1h (you)

### Tier 2 — Backlog visualisation polish

| ID | Title | Files touched | Subagent? | Notes |
|---|---|---|---|---|
| D-DOG.2a | Job-state kanban view in helm SPA (read-only, group by FSM state) | `apps/loom-svelte/`, query against existing `jobs.find_*` verbs | yes (1d) | |
| D-DOG.2b | Mobile mirror of kanban | `apps/oddjobz-mobile/lib/src/helm/` | yes (1d) | |
| D-DOG.2c | Backlog summary RPC: `oddjobz.backlog.summary` returning counts by state + age buckets | `runtime/semantos-brain/src/leads_handler.zig` (or new `backlog_handler.zig`) | yes (½d) | feeds voice queries |

### Tier 3 — Execution proposal engine

| ID | Title | Files touched | Subagent? | Notes |
|---|---|---|---|---|
| D-DOG.3a | Capacity model: working-hours config + geographic cluster lib (Haversine, K-means or greedy) | new `runtime/semantos-brain/src/proposal/` | yes (1d) | |
| D-DOG.3b | Proposal engine v0 (heuristic): suggest `calendar.event.v1` cells from backlog × capacity | same dir | yes (1d) | |
| D-DOG.3c | Helm UI: review proposed events, drag/edit, approve in batch | `loom-svelte/` + mobile | yes (1d each, parallel) | |
| D-DOG.3d | Calendar push via existing `extensions/calendar` API hooks | existing extension | yes (½d) | |

### Tier 4 — Voice trigger (waits on D-O5m.followup-3)

| ID | Title | Subagent? | Notes |
|---|---|---|---|
| D-DOG.4a | Wire intent "read my email" → `legacy ingest gmail` verb | yes (½d) | gates on followup-3 landing |
| D-DOG.4b | Wire intent "plan tomorrow" → proposal engine + helm review | yes (½d) | gates on followup-3 + Tier 3 |

### Tier 5 — Meta vertical (secondary)

| ID | Title | Subagent? | Notes |
|---|---|---|---|
| D-DOG.5a | Operator runbook for Meta Business Suite OAuth | yes (½d) | mirror of Gmail guide |
| D-DOG.5b | Meta extractor pass — same pipeline, validate end-to-end | yes (1d) | |
| D-DOG.5c | Cross-source dedupe: same job mentioned in Gmail + Messenger collapses to one proposal | yes (1d) | |

### Tier 6 — Sovereign promotion (followup, not blocking dogfood)

| ID | Title | Subagent? | Notes |
|---|---|---|---|
| D-DOG.6a | Lift `legacy` verb into brain REPL via JSON-RPC sidecar | yes (3–5d) | §2.1 path B |
| D-DOG.6b | Replace OpenRouter with self-hosted LLM (or operator-owned router) | yes (variable) | sovereignty hardening |
| D-DOG.6c | Replace Google Calendar with operator-owned calendar (CalDAV?) | yes (variable) | full sovereignty |

---

## §5 — Quick-win path to first usable dogfood

Revised per §6.1. Sequence to first live ingest in **≤4 days**:

1. **Tier 0 (parallel, 1 day)** — D-DOG.0a + D-DOG.0b + D-DOG.0c in three parallel subagents.
2. **D-DOG.1b + D-DOG.1c in parallel** — Ollama + Anthropic TS adapters (½ day each, parallel).
3. **D-DOG.1a** — PDF byte-parse (1 day, can start once 1c lands for Vision fallback).
4. **D-DOG.1d + D-DOG.1e + D-DOG.1f in parallel** — router + localhost callback + dogfood-up supervisor (½ day each, parallel).
5. **D-DOG.1g** — runbook (½ day).
6. **D-DOG.1h** — you run the live first backfill (≈1 hour active + LLM time in background).

That gets you full Gmail backfill → PDF → extracted job sheets → ratify queue → committed to oddjobz cell-DAG, with **shell-ops on local Llama (sovereign)** and **vision/generative on direct Claude (BYOK, no aggregator)**, surfaced in the existing Calendar + Attention views.

Tier 2 (kanban) and Tier 3 (execution proposal) come after — they're the polish that makes the system feel like it's helping you execute, not just collecting jobs.

---

## §6 — Operator answers (resolved 2026-05-03)

1. **OAuth callback host** — `https://oddjobtodd.info/auth/callback` returns **HTTP 404** (Caddy is serving the host but the route is gone). **Pivot**: localhost callback. The legacy widget Bun server already listens on `localhost:3001` for `/widget/*` — extending it with an `/auth/callback` route is the cleanest fix. Operator updates Google Cloud Console redirect URI to `http://localhost:3001/auth/callback` (Google explicitly permits loopback for installed apps).
2. **LLM provider** — local Llama for shell ops (extraction, classification, dedupe), BYOK Claude for generative contexts (drafting customer-facing replies, complex vision). Claude API keys are already in repo `.env`. **Major existing infrastructure discovered:**
   - `runtime/semantos-brain/src/llm_adapter.zig` + `llm_http_adapter.zig` (with conformance tests) — brain-side abstraction shipped
   - `platforms/flutter/llama_cpp/` — full llama.cpp Flutter binding (`llama_service.dart`, `model_manager.dart`, `bindings.dart`, tests) — **phone-side local inference is already wired**
   - TS `extractor/types.ts` defines `LLMAdapter`; only `OpenRouterAdapter` exists today. Need `OllamaAdapter` (default for shell ops) and `AnthropicAdapter` (BYOK direct, drops the OpenRouter middleman) implementations.
3. **Working day** — **7am–7pm** (12 hours). The proposal engine treats this as the available envelope per workday; subtract travel padding + lunch + admin buffer per scheduled visit.
4. **First-ingest scope** — **full backfill** (no `--since`). The system also receives summaries from Bricks + an external agent listing outstanding items — note these as an additional ingestion source for Tier 5 (cross-source fusion).
5. **Matrix approved** — proceed.

### §6.1 Matrix amendments from operator answers

- **Tier 1 expanded**: PDF byte-parse, Ollama TS adapter, Anthropic TS adapter, **localhost OAuth callback route** (`/auth/callback` added to widget server), `brain dogfood up` supervisor, runbook, first live run.
- **New ingestion source noted for Tier 5**: Bricks + external-agent outstanding-items summaries (likely web-scrape or email-forwarding ingest, TBD).
- **Tier 0 unchanged**: still verification only; LLM adapter abstraction already exists, just needs new backend implementations in Tier 1.

Tier 0 fires next.
