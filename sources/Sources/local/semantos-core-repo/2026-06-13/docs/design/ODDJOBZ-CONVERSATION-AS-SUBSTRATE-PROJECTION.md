---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/ODDJOBZ-CONVERSATION-AS-SUBSTRATE-PROJECTION.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.739452+00:00
---

# Oddjobz — ROM/Job conversation flows on the universal intent pipeline

Status: **Design (reconciled 2026-05-17).** This document was
originally written from a shell+brain investigation that did not reach
`runtime/intent/`. That draft reinvented an architecture that **already
exists and is partially shipped** as `@semantos/intent`. This rewrite
**defers to that substrate** and specifies only the thin oddjobz-specific
binding on top of it.

> **Read `docs/INTENT-PIPELINE.md` first.** It is the canonical
> architecture. This doc does not restate it; it maps oddjobz's ROM /
> qualified-lead / return-link-job-edit flows onto its primitives and
> names the genuinely-missing oddjobz pieces.

## 0. The vision is already the house substrate

Todd's framing — "conversation is a first-class citizen; the unit is
the patch, not the context window; every turn (customer / AI agent /
operator) is deconstructed into an append-only, introspectable log;
proposal vs ratify; replay is the projection" — is, almost line for
line, `docs/INTENT-PIPELINE.md §"Triage and conversation patches"`.
It is implemented as shipped, composable primitives in
`runtime/intent/`:

| Vision element | Already exists (file) | State |
|---|---|---|
| Every turn → a cheap patch (no LLM/SIR/kernel) | `conversation-patch.ts` `writeConversationPatch` / `ConversationPatchShape` | **shipped** |
| Turn deconstructed; decide if the expensive path runs | `triage.ts` `triage()` + pluggable `Classifier` → `TriageOutcome` | **shipped** (classifier pluggable) |
| Proposal-vs-applied | `TriageOutcome` `proposes` → `processIntent`; derived patch `companionOf`→conv patch, `ratificationState:'pending'` | **shipped** |
| Ratification is itself a (signed) patch | `ratification.ts` `issueRatification` / `RatificationPatch` (signed pointer at the pending proposal id) | **shipped** |
| One engine, many interfaces | `pipeline.ts` `processIntent` — every input mode is an `Intent` producer; NL/voice/shell/UI/host/network/governance all funnel here | **shipped** |
| Customer proposes, only operator ratifies | per-patch trust tier; `lowerSIR` **structurally rejects** cross-role authoritative claims (a tenant cannot lower a landlord-tier approval) | **shipped (SIR layer)** |
| Patch log = introspection, not a context window | `companionOf` typed graph + one `correlationId` per turn + JSONL `StageEvent` stream (`logger.ts`) — "every state change traces to a conversation patch, not a text search" | **shipped** |
| Turn orchestrator | `handle-message.ts` `handleMessage`: conv patch → lookup pending → triage → {halt / `processIntent` / `issueRatification`}, one correlationId | **shipped** |
| The oddjobz vertical that consumes it | `INTENT-PIPELINE.md §Module layout` names a `conversation-loop.ts` Slice-2 vertical; the built app dir is `apps/oddjobtodd/` (the doc's `apps/odd-job-todd/` path is stale drift) — *loop not yet built* | **planned** |

The LLM lives only in the producer adapter + the triage classifier (the
edge). The substrate stays AI-free. Patches flow as intents, never as
config writes. These were "non-negotiables" in the prior draft; they
are simply how `@semantos/intent` already works.

**Consequence:** there is no `ConversationPatch` type to invent (the
prior draft's §2 is withdrawn — defer to `ConversationPatchShape` +
`RatificationPatch` + `TriageOutcome`), no replay machinery to build
(it is the correlationId/companionOf graph), no "conversation engine"
to write (it is `handleMessage`). The work is **a binding**, not an
architecture.

## 1. The oddjobz mapping (ROM, qualify, return-link edits)

Everything below is "configure/extend the existing primitives", not
"new substrate".

### 1.1 The ROM-ratify-and-flip loop

| Turn | Primitive | Oddjobz binding |
|---|---|---|
| Customer types into the widget | `handleMessage` writes a conversation patch authored by the **customer hat** (phone-identity hat — `ODDJOBZ-CUSTOMER-CONVERSATIONS §2`; customers are not cert holders) | new producer + hat-context (greenfield, §2) |
| "ballpark/price?" detected | oddjobz `Classifier` returns `proposes` with an oddjobz `Intent` (`action:'rom'`, `target:{job}`, money on `targetJson` `{costMin,costMax}`) | new classifier (greenfield, §2) |
| Pipeline runs | `processIntent` → derived **ROM proposal patch**, `companionOf`→conv patch, `ratificationState:'pending'` | reuse `rom-engine.ts` + `state-manager.ts` cascade as the classifier's ROM policy |
| Customer accepts ("yep that works") | `handleMessage` sees an open pending ROM proposal → `Classifier` returns `ratifies{pendingPatchId}` → `issueRatification` writes a signed `RatificationPatch` | the customer-phone-identity is the ratifier for a *customer-scoped acknowledgement*; cap-tier flip is operator's (next row) |
| Ratification → substrate | the `ratifies` branch emits the **already-shipped** brain path: `intent_cells.submit` `accept_rom` with `originalIntent.targetJson={jobId,costMin,costMax}` → brain mints an accepted `auto_rom` Estimate (`ae9eabb`) → Job FSM `lead→qualified` → later `qualified→quoted` auto-seeds the draft Quote (`quote_seed_router`, `2714dfd`) | **brain side already deployed**; the seam is "ratify → envelope" (§2.3) |

Everything from "Ratification → substrate" rightward is **live on rbs
today**. This design only has to produce the conversation patches and
wire the `ratifies` branch to the envelope.

### 1.2 Return-link job edits

`oddjobtodd.info/chat?conv=<id>` (link/session shape already specified
`ODDJOBZ-CUSTOMER-CONVERSATIONS §2.2`). Resume = re-run `handleMessage`
turns against the same conversation object; "state" is the accumulated
patch graph, nothing server-held. A returning customer changing scope
→ conversation patch → classifier `proposes` a **job-detail patch**
(`action:'patch'`, `target:{job}`, `delta`) → pending. The operator's
"yes, updated" message → `ratifies` → applied. The customer **cannot
self-apply**: `lowerSIR` refuses to lower an operator-tier mutation
signed by a customer hat (structural, not a runtime check). The full
edit history is the conversation+derived+ratification patch chain on
the job object — attributable, replayable, append-only (corrections are
new patches; nothing is destroyed).

### 1.3 Re-quote on material change

If a job-detail patch crosses a re-quote threshold, the oddjobz
classifier (reusing the operator-tuned `state-manager.ts:123` cascade)
emits a fresh ROM `proposes` instead of a silent patch. The job sitting
in `qualified` with changed scope is exactly the `qualified` bucket
`find_pipeline_gaps` (shipped `357ec26`) already surfaces — no new
query.

## 2. What is genuinely missing for oddjobz (the real, narrowed scope)

The prior draft's 6 phases collapse to **5 oddjobz deliverables**, two
of which lean on already-shipped brain work:

1. **Oddjobz triage `Classifier`** (`triage.ts` `Classifier` is
   pluggable; the shipped stub can't do `proposes` — needs domain
   knowledge/cheap LLM). Recognises ROM / job-detail / accept ("yes")
   turns; emits `proposes` (ROM or job-patch) and `ratifies` (pointer
   at the open pending proposal). Reuses `extensions/oddjobz/src/
   conversation/state-manager.ts` (operator-tuned thresholds) +
   `rom-engine.ts` as its policy. **Net-new, but pure + unit-testable.**
2. **Oddjobz Intent producer adapter** — widget/NL turn → oddjobz
   `Intent`. The canonical classifier/adapter scaffold already exists
   as `extensions/extraction/src/intent-adapters/{classifier-tool,
   llm-classifier}.ts` (the doc's reserved `llm-to-intent.ts` name was
   never built — stale planning name) feeding an
   `apps/oddjobtodd/conversation-loop.ts` vertical; the existing
   `extensions/oddjobz/src/conversation/pipeline.ts` does most of the
   extraction. Wire it to feed `handleMessage`, not its own loop.
3. **Ratify→brain seam** — in the `ratifies` branch (ROM accepted),
   emit the shipped `intent_cells.submit` envelope (`accept_rom` +
   `targetJson`). This is "Option B" correctly placed: the envelope is
   produced where the pipeline already has opcode bytes + kernelResult
   + correlationId, i.e. `processIntent`/`handleMessage`, **not** a
   shell shim. Brain consumer already deployed.
4. **Persistence wiring** — `handleMessage`'s `write` deps persist
   conversation/derived/ratification patches as the
   `oddjobz.conversation.v1` cell (cells sketched
   `ODDJOBZ-CUSTOMER-CONVERSATIONS §3`); the deferred brain-side
   `persist_message` (`CUSTOMER-CONV-LOOP-PLAN`) is this.
5. **Customer ingress + Twilio identity + the oddjobtodd.info widget**
   — genuinely greenfield, but now scoped as *one more `Intent`
   producer + a phone-identity `HatContext`* feeding the **same**
   `handleMessage` over the anon-capable `chat_http.zig` dispatch
   pattern (`BRAIN-DISPATCHER-UNIFICATION`). Twilio adapter +
   `/conversation/<id>/send` already shipped (`CUSTOMER-CONV-LOOP-PLAN`).

## 3. Phasing (verified-increment loop)

- **Phase 0 — done.** `targetJson` spec drift reconciled (`af2791d`):
  `{jobId,costMin,costMax,currency}` canonical, `amount` = point-collapse
  alias, matching the deployed router. The prior draft's "promote
  PatchRecord → ConversationPatch" is **withdrawn**: defer to
  `@semantos/intent`'s shipped types. (The shell's local
  `PatchRecord`/`.semantos-chat-state.json` is a separate legacy
  concern; migrating the operator shell onto `handleMessage` is a shell
  refactor, not part of this binding — track separately.)
- **Phase 1 — oddjobz classifier + Intent adapter** (deliverables 1–2).
  Pure TS in `extensions/oddjobz` + the reserved intent-adapter path;
  unit-tested against `triage()`/`handleMessage` with in-memory deps.
  No brain transport. Proves ROM `proposes`→`ratifies` end-to-end in
  test.
- **Phase 2 — ratify→brain seam** (deliverable 3). The `ratifies`
  branch emits the shipped `intent_cells.submit` envelope. End-to-end
  ROM → accepted Estimate → `lead→qualified` against the live brain.
- **Phase 3 — persistence** (deliverable 4). `oddjobz.conversation.v1`
  patch persistence + the deferred brain `persist_message`.
- **Phase 4–5 — customer ingress + widget** (deliverable 5).
  Anon+phone-identity producer over `chat_http`-style dispatch; then
  the `oddjobtodd.info/chat` widget as an oddjobz product surface.
  Genuinely greenfield; sequence explicitly with the operator.

Phases 1–2 deliver the operator-side ROM loop end-to-end on the proven
gate-green→path-scoped-commit→deploy loop. 3–5 are the customer product.

## 3a. DECISION-A3 — brain↔TS transport — **RESOLVED: Option C** (2026-05-17)

> **Operator ruling: Option C — the free-text→intent pipeline runs at
> the EDGE (PWA/shell with TS+LLM); the brain stays a pure
> submit-target.** The "A.3 gap" is therefore **intentional
> architecture, not a defect**: the brain never orchestrates an LLM
> call; the edge runs `handleMessage/triage/processIntent/
> writeConversationPatch` and submits the finished envelope via the
> already-shipped `submit-intent-cell` / `intent_cells.submit` verb
> that the deployed `intent_action_router → Estimate → FSM` loop
> already consumes. **Zero new brain code.** Consequences: (1) the
> Phase 1/2 "binding" collapses to *the edge producer calling the
> existing submit verb*; the customer widget (Phases 4–5) IS that
> producer (operator-sequenced greenfield). (2) The relic
> deprecations are now UNBLOCKED — `intake_http`'s per-request-bun
> mechanism + the shell `chat/` subtree are confirmed superseded;
> proceed to cauterise them and repoint shell `rom.ts` →
> `extensions/oddjobz/src/rom.ts`. (3) `jobs_store_lmdb.zig`
> cursor-only remains a SEPARATE parked operator decision (not A3).

The REPL-canonicalisation pass established the canonical REPL (brain
HTTP `/api/v1/repl`, `runtime/semantos-brain/src/repl.zig`) is intact
and 13-state-FSM-aware but has **no** intent-extraction/conversation-
patch wiring. Grounded transport investigation (2026-05-17):

- The per-request `bun` subprocess is the **only** extant brain↔TS
  mechanism; `voice_extract_shell.zig` is its hardened form,
  `intake_http.zig` a cruder sibling. **Neither is routed in any
  deployed site config** (`oddjobtodd-site-s15.json` /-`example.json`
  expose only operator_home/static/chat/analytics); the systemd unit
  ships `--enable-repl` with **no** `--voice-extract-script`. The
  deployed brain is *already* a pure imperative substrate with the
  LLM pipeline entirely outside it.
- No persistent-sidecar precedent exists.
- The reactor is single-threaded (`event_loop.zig`); a blocking
  subprocess stalls every connection — `event_loop.zig` carries an
  unresolved `TODO-WORKER-POOL` for exactly the voice_extract
  shell-out. An LLM-latency `converse` verb would inherit + worsen it.

Options:

| | A: per-request bun behind a REPL verb | B: persistent bun sidecar | **C: edge owns pipeline; brain = pure submit-target** |
|---|---|---|---|
| New brain code | a `converse` verb + shell config + deploy flags | full sidecar lifecycle/IPC (no precedent) | **none — `submit-intent-cell` already exists & is deployed-routable** |
| Reactor stall | yes (LLM-secs on the single thread) | yes sans worker-pool | none (LLM borne at edge) |
| Zero-AI-substrate | brain orchestrates the LLM call (subprocess=edge, precedented) | same | **cleanest — brain never orchestrates an LLM call; the "A.3 gap" is intentional architecture** |

**Recommendation: Option C.** Zero new brain code (the shipped
`intent_action_router → Estimate → FSM` loop already consumes the
finished envelope via `submit-intent-cell`/`intent_cells.submit`),
strictest reading of zero-AI-in-substrate, avoids the flagged reactor
stall, no new infra. Under C the "A.3 gap" is a deliberate boundary,
the Phase 1–2 "binding" collapses to *the edge producer calling the
existing submit verb*, and the customer widget (Phases 4–5) is that
producer. Option A is the fallback **only** if thin clients must hand
raw free-text to the brain itself (then gated behind the worker-pool
fix). Option B is unjustified (no precedent, premature).

**The one operator question:** does the free-text→intent pipeline run
at the **edge** (PWA/shell with TS+LLM) — → Option C, decisively — or
must the **brain itself** be a free-text endpoint for thin clients
that cannot run the pipeline — → Option A behind the worker-pool fix?

**Resolved → C (above). Post-decision deprecation campaign COMPLETE
(2026-05-17):**
- Graft-before-cut groundwork: ROM math `bb3c0c4`, extraction
  richness `0246257` (canonical, correct under C).
- (1) ~~`intake_http` relic mechanism deprecated — `5fb7ec2`~~
  **REVERTED `46b67c4` — `intake_http` is LIVE PRODUCTION INFRA, not
  a relic.** Verified on rbs: `oddjobtodd.info/api/chat` →
  Caddy(`consulting_proxy`) → brain `:8080` → live site.json
  `type:"intake"` → `intake-handler` (the bun pipeline the brain
  spawns) = the working customer bot. The `5fb7ec2` premise ("routed
  in no deployed config") was worktree-blind (it read the repo's
  `deploy/*.json`, not the live `/var/lib/semantos/sites/.../
  site.json`). `5fb7ec2` was a latent landmine (next brain redeploy
  → `/api/chat` 501); reverted before any redeploy. Prod was never
  harmed (rbs pinned at `2714dfd1`).
- (2)+(3) shell `rom.ts`/`rom-engine.ts` + the whole shell `chat/`
  subtree + the `@deprecated chat.ts` shim excised as one verified
  island — `84cc8bb` (21 files, ~2047 LOC; no external importer / no
  bin / no barrel; the recon's "legacy-ingest consumes rom.ts" claim
  was false). No repoint needed (every consumer was inside the deleted
  island).
- Earlier in the pass: 7 orphan `*_store_fs.zig` (~9.7k LOC,
  `e84e3fc`+`319fa76`), dead `repl_http.maybeHandle` (`a2c684d`),
  stale 8-state/`lead|open` signal scrub (`c7386ad`).

Net: the canonical REPL is intact + 13-state-FSM-aware; ~14k LOC of
vestigial wiring excised, every step gate-proven; both
unique-functionality grafts are canonical. The brain is a clean pure
imperative substrate; the edge owns the LLM pipeline.

**Remaining = operator-gated only (loop correctly stops here):**
- Phases 4–5 — the customer anon+Twilio ingress + `oddjobtodd.info`
  chat widget. Under C this IS the edge producer that runs
  `@semantos/intent` and calls the shipped `submit-intent-cell`.
  Greenfield, sequence explicitly with the operator.
- PARKED operator decisions (do not auto-excise): `jobs_store_lmdb.zig`
  cursor-only (test-anchored relic); full retirement of the `.intake`
  `RouteKind` from the config schema (schema-breaking).

## 4. Cross-references (own nothing these already own)

- `docs/INTENT-PIPELINE.md` — **the** architecture. Triage, conversation
  patches, ratification, companionOf, observability/replay, module
  layout (incl. the named `apps/oddjobtodd` vertical). Do not restate.
- `runtime/intent/` — shipped primitives: `conversation-patch.ts`,
  `triage.ts`, `ratification.ts`, `handle-message.ts`, `pipeline.ts`,
  `types.ts` (`TriageOutcome`, `RatificationPatch`, `Intent`).
- `docs/design/ODDJOBZ-CUSTOMER-CONVERSATIONS.md` — customer identity
  (§2, phone/Twilio), conversation/message/job_sheet cells (§3), Job
  FSM `lead→qualified` gating (§4/§10), widget (§8.1).
- `docs/design/CUSTOMER-CONV-LOOP-PLAN.md` — shipped-vs-deferred ledger
  (Twilio adapter, `/conversation/<id>/send`, `search/contacts` shipped;
  widget, intake posture, customer Verify, `persist_message` deferred).
- `docs/design/BRAIN-DISPATCHER-UNIFICATION.md` — the anonymous-dispatch
  model the customer ingress extends.
- `docs/design/ODDJOBZ-ESTIMATE-ROM-INGRESS.md` + commits `b722aa4`
  (Estimate entity), `ae9eabb` (ROM ingress brain-side), `2714dfd`
  (`quote_seed_router`), `1b0d7e3` (`authorized` state) — the deployed
  brain consumer this binding feeds. Unaffected by this reconciliation.

## 5. Net effect of the reconciliation

The prior draft's invented `ConversationPatch` type and 6-phase
"build a conversation engine" plan are **withdrawn**. The conversation
engine, patch log, proposal/ratify model, replay/introspection, and
the cross-role enforcement Todd wants **already exist and are
shipped** in `@semantos/intent`. Oddjobz's remaining work is a
classifier, a producer adapter, a ratify→(already-deployed-brain)
seam, persistence, and the (still-greenfield) customer ingress/widget
— a binding onto the substrate, materially smaller and lower-risk than
the original framing, and it builds directly on the brain loop already
live on rbs.

## 6. Phase 4–5 scoping — DECISION-A4 **DISSOLVED** (the bridge already exists in prod)

> **UPDATE 2026-05-17 (post-VPS verification):** DECISION-PENDING-A4
> below is **DISSOLVED**. The "no customer→brain submit path / need a
> credentialed bridge" crux was an artifact of worktree-only recon.
> Production reality (verified on rbs): `oddjobtodd.info/api/chat` →
> Caddy(`consulting_proxy`) → brain `:8080` → live site.json
> `type:"intake"` → the brain spawns the `intake-handler` bun
> pipeline per request = the **working customer bot, in production
> now**. The customer→brain path EXISTS and is exactly the Option-C
> shape (brain spawns a server-side TS pipeline per request — the
> same family as the deployed `--voice-extract-script`). There is no
> bridge to design.
>
> **Re-scoped real Phase 4–5 (operator-confirmed, NOT greenfield, NOT
> decision-blocked):** the prod bot (`extensions/oddjobz/src/
> intake-handler.ts` → `conversation/turn-handler`) holds an LLM
> conversation but **does not pipe jobs as proper cells and is not
> wired to the new ROM math (`bb3c0c4` canonical `rom.ts`) + 13-state
> FSM + the shipped `accept_rom → Estimate → lead→qualified` loop**.
> The work is to UPGRADE that existing handler to do so (it runs in
> the same brain process that already exposes `submit-intent-cell` /
> `intent_cells.submit`). Twilio = operator inputs credentials (the
> `twilio_adapter` config field exists), not a build. The
> shipped-vs-greenfield table + auth-bridge analysis below are kept
> for provenance but the "auth-bridge crux" is void.

Grounded recon 2026-05-17 (HEAD `4982415`). The brain-side ROM→FSM
loop + `@semantos/intent` are real and deployed; the customer surface
is a v0.5 LLM-echo shell.

**Shipped vs greenfield (Phase 4–5 surface):**

| Component | State | File |
|---|---|---|
| Outbound SMS (`sendSms`) | ✅ shipped (operator-scoped) | `twilio_adapter.zig:355` |
| Twilio Verify (OTP send/check) | ❌ config field only | `twilio_adapter.zig:167` |
| Anon brain ingress | ⚠️ reaches `llm.complete` only | `chat_http.zig` (mounted `s15.json:33`) |
| `submit-intent-cell` + envelope→Estimate→FSM | ✅ shipped, deployed | `intent_cells_handler.zig:201`, `repl.zig:628` |
| **Anon/customer submit path** | ❌ **does not exist** | — |
| `@semantos/intent` pipeline | ✅ lib, injectable; no edge harness | `runtime/intent/src/*` |
| Proposing (ROM) classifier | ❌ stub can't `propose` | `triage.ts:96` |
| Chat widget SPA | ⚠️ v0.5 LLM-echo, wrong path | `extensions/oddjobz/public/chat-widget/` |
| Phone-identity / session / conv cells | ❌ designed only | ODDJOBZ-CUSTOMER-CONVERSATIONS §2/§3 |
| Return-link resume; patch persistence | ❌ designed only / `persist_message` no-op | — |

Correction to prior assumptions: `apps/oddjobtodd` is a **helm
animation/palette demo**, NOT a chat surface; the shipped
`chat-widget.{js,css}` posts to `/api/v1/chat` (`llm.complete`), NOT
the intent pipeline. No `conversation-loop.ts` / edge harness exists.

### DECISION-PENDING-A4 — the customer→brain auth bridge (the crux)

**There is NO anonymous/customer submit path into the brain.**
`submit-intent-cell` is reachable only via `reactorHandleRepl`, which
requires a valid **bearer** (`reactor.zig:928-960`); `handleSubmit`
additionally requires a cert-store-resolvable **`certId`** chain-bound
to **`hatId`** (`intent_cells_handler.zig:279-302`) and the
`cap.oddjobz.write_customer` cap (`:61,:134`). Customers are **not**
cert holders (ODDJOBZ-CUSTOMER-CONVERSATIONS §2). The only anon brain
ingress (`/api/v1/chat`) reaches `llm.complete` and nothing else.

So Phase 4–5 **stands or falls on a server-side
operator-credentialed submit bridge that exists in no form today.**

**Recommendation:** the widget-server-side process holds an
operator/service **bearer + operator cert/hat** and submits the
finished envelope **on the customer's behalf**; the customer's phone
identity rides as conversation-patch / `originalIntent` metadata,
never as the submit credential. This preserves DECISION-A3's "zero
new brain code" (reuses the shipped operator-gated
`submit-intent-cell`) and the cert-binding security intent. The
alternative — a new anonymous intake verb with cap relaxation —
contradicts A3 and weakens the brain's auth model; not recommended.

**Operator questions this raises (block build):**
1. Confirm the credentialed-bridge model (recommended) vs the
   anon-verb alternative.
2. **Where the bridge runs.** Option C says the edge runs the
   pipeline; the bridge is a privileged credential-holding
   server-side process. Is it a new bun/node sidecar (no precedent;
   reactor is single-threaded), an external host the brain-served
   static SPA calls, or folded into an existing operator surface?
3. Operator-credential provisioning/rotation/trust model for that
   bridge (it can mint `accept_rom` on any customer's behalf).
4. Identity: build Twilio **Verify** (unbuilt) to gate submit, or
   ship anon-submit + name/address predicate with Verify deferred?
5. Conversation-patch persistence target (`write`/`writeCell` unbound;
   `persist_message` is a no-op).

### Proposed phase breakdown (smallest verified slices, post-A4)

- **P4.0** edge harness running `handleMessage` with in-memory deps +
  a JS/WASM kernel; unit-prove ROM `proposes`→`ratifies` (no brain).
- **P4.1** operator-credentialed submit bridge; verify `lead→qualified`
  vs a live `--enable-repl` brain. (Resolves the crux concretely.)
- **P4.2** oddjobz LLM proposing classifier (reuse `state-manager.ts`).
- **P4.3** widget rework: existing SPA → harness, anon + ratify UI.
- **P5.0** Twilio Verify + `customer_session.v1`; gate submit.
- **P5.1** return-link `?conv=<id>` resume + patch persistence.

~~**Build is BLOCKED on the A4 ruling**~~ **SUPERSEDED by the §6
DISSOLVED banner.** No bridge to build, no A4 ruling needed. The
re-scoped, unblocked Phase 4–5 is a single concrete track:

- **P4.A** — read `extensions/oddjobz/src/intake-handler.ts` +
  `conversation/turn-handler` and pinpoint exactly where the turn
  pipeline stops short of (a) computing a ROM via the canonical
  `extensions/oddjobz/src/rom.ts` (`bb3c0c4`) and (b) emitting the
  `accept_rom` + `targetJson{costMin,costMax}` envelope to the
  in-process `submit-intent-cell` / `intent_cells.submit` →
  `intent_action_router → Estimate → lead→qualified` (all shipped &
  deployed at `2714dfd1`).
- **P4.B** — wire ROM compute into the handler's turn flow (reuse
  `rom.ts` + the `0246257` sizing-prompt richness).
- **P4.C** — on customer ROM-accept, submit the envelope (the brain
  process already exposes the submit verb; the handler runs
  in-process-adjacent via the intake spawn — credentials are the
  brain's, exactly like `voice-extract`). Verify `lead→qualified`
  end-to-end on a live `--enable-repl` brain.
- **P5** — operator inputs Twilio creds; (later) Verify-gate +
  return-link `?conv=<id>` + conversation-patch persistence.

### Phase-3 — RESOLVED direction (operator chose Option 1, 2026-05-18) + GROUNDED scope

The "edge runs the pipeline" capability is **not invented — it
already exists** and Phase-3 is far more tractable than the blocker
framing implied. Linchpin: `runtime/shell/src/intent-adapters/
shell-pipeline-deps.ts` `createShellPipelineDeps({engine, storage,
signer, mode, ...})` already builds a **real `PipelineDeps`** for a
non-brain TS runtime and runs `processIntent` end-to-end:
- `engine: CellEngineLike` ← **`@semantos/cell-engine`'s
  `bindings/bun/cell-engine.ts`** — the kernel **already has a bun
  binding**. "Kernel in bun" is solved.
- `emitBytes` ← `@semantos/semantos-ir` `emit()`; `lowerSIR` ←
  `@semantos/semantos-sir` (pipeline defaults).
- `storage: StorageAdapter` (`.write(key,bytes)`); `signer:
  AsyncSigner` (`.sign(bytes)`).
- `mode:'authoring'` runs a trivially-balanced `OP_1` frame at the
  kernel (no inbound cell on an authored intent's stack); the real
  emitted bytes still reach storage + the signed receipt; the brain
  re-runs/reconciles on submit.

**∴ Phase-3 for the oddjobz edge = reuse `createShellPipelineDeps`,
not greenfield.** The voice-extract placeholder was simply never
wired to it.

**Grounded decomposition (each a verified slice; coupling rule:
authored in the local worktree → committed → built/verified only
where `@semantos/*` resolves [the bun-installed rbs worktree] → never
hand-edited on rbs):**
- **P3.1 — feasibility spike (decision-independent).** In a
  bun-installed context, drive `processIntent` from a tiny harness
  using `createShellPipelineDeps` with the real
  `@semantos/cell-engine` bun engine + `@semantos/semantos-ir`/`-sir`
  defaults + an in-memory StorageAdapter + a **StubSigner** + an
  `accept_rom` Intent built around `acceptRomTargetJson()` (1297eaa).
  Proves a valid `oddjobz.intent_cell.v1` envelope (opcodeBytes +
  kernelResult) is producible edge-side. Make-or-break; no operator
  decision needed.
- **P3.2 — brain-submit StorageAdapter.** A `StorageAdapter` whose
  `.write` base64s the produced envelope and POSTs the brain REPL
  `submit-intent-cell` (cap `cap.oddjobz.write_customer`, brain
  bearer). Reuses fully-grounded existing infra.
- **P3.3 — signer identity (THE remaining sub-decision).** What
  `AsyncSigner` the decoupled cartridge edge uses to sign as the
  operator: (a) brain sign-callback endpoint (edge → preimage →
  brain signs with operator cert → sig; key never leaves the brain —
  best for the sellable multi-tenant model); (b) edge-provisioned
  operator child-cert signer (key in the spawned bun — security
  posture call); (c) confirm whether the brain's submit-side kernel
  re-exec + its own signing makes the edge receipt-sig
  non-authoritative (reconciliation nuance — may reduce the bar).
  Needs the operator's call; gates only P3.4+, not P3.1/P3.2.
- **P3.4 — wire both edges.** `submitAcceptRom` (chat widget) +
  collapse `voice-extract.ts` Phase-3 onto the same deps. Best-effort
  (JSONL shadow retained → cannot regress the live reply).
- **P3.5 — gated rbs build (`build-oddjobz-bundle.sh`) + live verify**
  `oddjobz.lead.v1` (+ `auto_rom` Estimate) in `IntentCellLmdbStore`,
  `lead→qualified`, readback. Then U2 (Gmail/Meta) + U3 (PWA WSS)
  reuse the identical seam; U4 multi-tenant rides P3.3's choice.

P3.1 is the de-risking crux and is decision-independent — the right
next focused unit (env-gated build, so authored local + verified in
the bun-installed context, ending in NO live change — pure
feasibility). P3.3 is the only genuine operator sub-decision and it
does not block P3.1/P3.2.

### P3.5 STATUS — P3.5a/c shipped (dormant-live), P3.5b DONE; activation = checkpoint

- **P3.5a** corrected (one-time-bootstrap, not per-request pairing —
  caught + fixed before live), `1eda4c3`, 24/24 worktree.
- **P3.5c (dormant deploy)** DONE: corrected bundle built (provenance
  gate passed) + backed up (`intake-handler.js.bak-20260518-1505`) +
  installed + smoke `HTTP 200` + re-probe `HTTP 200`. The seam is
  LIVE in the bundle but DORMANT (no `ODDJOBZ_AGENT_*` env ⇒ skipped;
  zero behaviour change; de-blackbox intact). Rollback ready.
- **P3.5b** DONE: `brain device pair` minted a 5-min token (caps
  `cap.oddjobz.write_customer`, label `oddjobz-agent`, operator root
  `af90d1d6…873`) → `provision-agent-cert.ts` paired ONCE against the
  LIVE `/api/v1/device-pair` → brain validated the operator-root sig
  + **minted the persistent agent child cert in the live cert store**.
  Durable agent identity (non-secret cert *ids*, recorded so a re-pair
  isn't needed):
  - `ODDJOBZ_AGENT_HAT_ID  = af90d1d61ae742839897e24cc59ce873`
  - `ODDJOBZ_AGENT_CERT_ID = bfe14fba2dea86f66bdc8d4b250ac900`
  Proves P3.4's option-2 device-pair orchestration end-to-end on prod.

- **ACTIVATION (checkpoint — the genuine irreversible prod step):**
  pin into `semantos-shell.service` `Environment=`:
  `ODDJOBZ_AGENT_HAT_ID` + `ODDJOBZ_AGENT_CERT_ID` (above) +
  `ODDJOBZ_BRAIN_REPL_URL=https://oddjobtodd.info/api/v1/repl` +
  `ODDJOBZ_BRAIN_BEARER=<token from the brain bearer-tokens.log;
  SECRET — env only, never git>`; then `systemctl daemon-reload &&
  systemctl restart semantos-shell.service`. This restarts the
  PRODUCTION brain (brief downtime; the gmail/meta business pipeline
  runs through it) — the one genuine irreversible mutation. Reversible:
  unset the env + restart to deactivate; bundle backup for the code.
- **P3.5d verify (post-activation):** a real /api/chat conversation
  reaching `estimatePresented` ⇒ confirm an `oddjobz.lead.v1`
  (+`auto_rom` Estimate) in `IntentCellLmdbStore`, `lead→qualified`
  (`find intent-cells --hat af90d1d6…873`).

### P3.5 RUNBOOK — Path A (operator chose A, 2026-05-18): use the brain's existing root

Operator: "Path A. nothing needs securing yet, it's just testing and
wiring, then I can start using it for my business." ⇒ no passphrase
bridge, no root rotation; mint the agent token with the deployed
brain's existing provisioned operator root. Path A is SHIPPED:
`cli/device.zig cmdDevicePair` (`brain device pair`) builds+signs a
5-min one-shot pairing token via the brain's `operator_root_priv`
(`device_pair.signAndEncode`). BRIDGE-OPERATOR-IDENTITY (passphrase)
is NOT taken — kept on file for the post-Plexus/portable case.

**Exact, zero-ambiguity P3.5 sequence (live prod; operator-approved
for the prototype):**

- **P3.5a — wire the seam into intake-handler (CODE, this is the
  remaining build).** On `result.done`, ADDITIVELY + best-effort
  (mirror the `recordIntakeTurn` try/catch — a failure must NOT
  regress the reply; keep `persistLead` jsonl as the transitional
  shadow): run the createShellPipelineDeps pipeline (P3.1 pattern)
  with `writeCell` = the P3.2 brain-submit StorageAdapter, the P3.4
  `assembleAcceptRomEnvelopeContext` (agent-cert from the P3.4
  provider, configured from env: `ODDJOBZ_AGENT_PAIRING_TOKEN`,
  `ODDJOBZ_BRAIN_REPL_URL`, `ODDJOBZ_BRAIN_BEARER`), `costMin/Max`
  from the conversation's ROM. Env-gated build → authored local →
  commit → bundle-built on rbs. ZERO live until the deploy.
- **P3.5b — mint + pair (TTL-coupled, run together, ≤5 min).** On
  rbs: `brain device pair --device-name oddjobz-agent --caps
  cap.oddjobz.write_customer --brain-domain oddjobtodd.info
  --brain-pair-endpoint https://oddjobtodd.info/api/v1/device-pair
  --brain-wss-endpoint wss://oddjobtodd.info/api/v1/events` → emits
  the signed token. Immediately set it as `ODDJOBZ_AGENT_PAIRING_
  TOKEN` and run the P3.4 provider once → POST /api/v1/device-pair →
  **mints the persistent agent child cert in the LIVE brain cert
  store** (first irreversible-ish live step; low stakes — prototype,
  no customers, test data). Returns the durable `(hatId, certId)`.
- **P3.5c — deploy.** `build-oddjobz-bundle.sh` (gated; backup +
  rollback + provenance gate) — the live bot now mints typed cells.
- **P3.5d — verify live.** A real /api/chat conversation to
  completion → confirm an `oddjobz.lead.v1` (+ accepted `auto_rom`
  Estimate) in `IntentCellLmdbStore`, `lead→qualified`, readable via
  `find intent-cells --hat <hatId>`. Reply path unaffected (best-
  effort + jsonl shadow).
Rollback: the bundle backup (`build-oddjobz-bundle.sh` retains it);
the agent child cert is additive (a stray test cert in the prototype
store is harmless / can be ignored).

P3.5a is the remaining code; P3.5b–d is one tight operator-approved
live sequence (real cert mint + customer-bot data-path redeploy) —
executed deliberately/staged with verify+rollback, not bulldozed at
session-tail. /loop halts here: this is the live-prod execution
boundary (no ScheduleWakeup — it's an operator-run/confirmed
sequence, not time/event-gated).

### BRIDGE-OPERATOR-IDENTITY — passphrase-derived root until Plexus (2026-05-18)

Operator wants a deterministic, recoverable operator identity NOW
(before Plexus ships recoverable identity certs). This is an
architecture-preserving bridge: the model (operator root → signs the
D-O5p pairing token → brain trusts ITS provisioned root → mints the
chain-bound agent child cert → submit chain-validates) is unchanged;
only the *key source* swaps from `plexus_identity_tx`-derived
(`provision_tenant.zig` first-boot, §3) to passphrase-derived.

**The pairing token is a signed payload, NOT a hash.** Conversion:
```
passphrase → KDF → operator_root_priv (32B secp256k1 scalar)
           → operator_root_pub (compressed SEC1 66 hex)
           → operator_root_cert_id (id from the pub, per the scheme)
build v2 payload {domain:brain-device-pair-v2, operator_root_*,
  label:"oddjobz-agent", capabilities:["cap.oddjobz.write_customer"],
  nonce, brain_pair_endpoint, brain_pin_*, ...}
sign canonical(payload) with operator_root_priv  (canonical =
  keys alphabetical, no whitespace, signature field omitted —
  device_pair.zig:canonicalJsonForSigning; sig = DER-ECDSA-SHA256)
token = base64url(payload incl. signature)
```
Reference minter (no hand-rolled crypto): the shipped
`runtime/semantos-brain/tools/gen_pair_vector.zig` (build+sign v2);
verify side `device-pair-client.ts decodePairingToken`.

**KDF (prototype-only):** `SHA-256("semantos-oddjobz-operator-root-v0:"
|| passphrase)` → secp256k1 scalar. Domain-separated, still
trivially recoverable from passphrase + the fixed tag. Bare unsalted
hash is acceptable ONLY because: prototype, no customers, rbs is test
data. NOT for any real custody.

**LOAD-BEARING — it is NOT token-only.** The agent child cert must
chain to the root the brain's cert store trusts, so the
passphrase-derived keypair must ALSO be the **brain's provisioned
operator root**. ∴ the bridge = *(re)provision the deployed brain's
operator root from the passphrase-derived key* (replaces the current
6-cert root chain) **+** sign tokens with it. That is an
operator-gated brain re-provision + redeploy (same P3.5 gate, larger
blast radius — it rotates the deployed root identity), NOT a
one-liner.

**Honest caveats (operator must internalise):**
- The example passphrase typed in chat is **burned** (cleartext in a
  log). Use a FRESH secret never entered into a chat for anything
  past throwaway local testing. The passphrase becomes the operator
  ROOT authority.
- **Plexus migration path (document now):** when Plexus ships the
  recoverable identity cert, it replaces this passphrase-derived
  root; agents re-pair under the new root (the D-O5p flow is
  identical — only the root key changes). Clean swap, not a fork,
  *because* the bridge keeps the model intact.

This unblocks P3.5's token requirement conceptually but inherits +
enlarges the P3.5 operator gate (brain root re-provision). Surfaced,
not bulldozed — re-provisioning the live brain's root identity is a
deliberate operator decision.

### P3.3 RESOLVED (opt 2) + P3.4 SHIPPED + P3.5 = operator-gated STOP (2026-05-18)

**P3.3 → option 2, and it's a reuse, not net-new.** The "brain
pairing/identity endpoint" already exists + is deployed: `POST
/api/v1/device-pair` (`device_pair_http.zig`, wired in
`site_server.zig`, live on oddjobtodd.info) — validates an
operator-root-signed pairing token, mints + persists a child cert in
the cert store chain-bound to the operator root, returns
`{status:"registered", cert_id, brain_cert_id}`. A shipped TS client
(`device-pair-client.ts`, proven by its roundtrip + Zig conformance)
already exists. So no net-new brain Zig, no endpoint redeploy.

**P3.4 SHIPPED** (`c1640da`): `agent-cert-provider.ts` —
`makeAgentCertProvider` orchestrates the shipped device-pair-client
primitives (decode→BRC-42 child derive→accept-body→POST→parse) →
maps `{brain_cert_id,cert_id}`→`{hatId,certId}` (all derivation
inputs from the decoded operator-signed token; no guessed crypto;
BRC-42 correctness stays the shipped client's). `device-pair-client`
(→`@bsv/sdk`) is lazy-imported so mock-injected unit tests stay pure/
worktree/zero-live (6/6; 20/20 across the P3.x siblings). +
`assembleAcceptRomEnvelopeContext` → the P3.2 `EnvelopeContext` for an
oddjobz `accept_rom` cell (action=accept_rom, taxonomy
what=oddjobz.lead.v1, money channel via `acceptRomTargetJson`) — the
oddjobz-correct shape replacing the P3.1 spike's golden placeholder;
`intent_action_router` mints the accepted `auto_rom` Estimate +
lead→qualified (SD2 ratify path).

**∴ the entire pure/decision-independent Phase-3 build is DONE +
verified, ZERO live change**: P3.1 feasibility proven · P3.2
brain-submit adapter · P3.3 resolved (reuses shipped device-pair) ·
P3.4 agent-cert provider + accept_rom EnvelopeContext. The seam is
complete end-to-end in code; only the live actuation remains.

**P3.5 — the operator-gated STOP (NOT bulldozable; the /loop halts
here).** Going live requires actions only the operator can take:
1. **Operator-signed agent pairing token** — the operator generates,
   with the operator ROOT key (out-of-band; not on the edge, not me),
   a v2 device-pair token whose `capabilities` = the agent's narrow
   allowlist (`cap.oddjobz.write_customer` for the lead submit) and
   `label`=the agent identity. (Format: `device_pair.zig` /
   `device-pair-client.ts decodePairingToken`.)
2. **Operator-approved live deploy** — running the pairing mints a
   **real cert in the live brain cert store**, and the chat-widget
   bundle must be rebuilt (`build-oddjobz-bundle.sh`) to use the
   agent-cert + brain-submit seam = a live production substrate
   behaviour change. Operator approval required (the standing
   redeploy gate).
Once (1)+(2) are provided, the gated live verify: pair → submit a
real `oddjobz.lead.v1` (+`auto_rom` Estimate) → confirm in
`IntentCellLmdbStore` with `lead→qualified`. Then U2 (gmail/meta
convergence on the same seam) / U3 (PWA WSS) / U4 (multi-tenant)
follow. Patch-log-signing stays the Tier-B-crypto-gated later layer
(substrate-owner). DEBT-XLANG-MULTICELL-PACKING remains parked.

### IDENTITY MODEL — refined by operator (2026-05-18); resolves P3.3

Three principals, all under the operator's cert chain (the D-O5p
model), grounded against the substrate:

1. **Customer / chat visitor — NOT a cert.** Browser token/cookie +
   phone number as the durable return-link correlation key. Lead /
   conversation cells are authored under the operator/agent hat, not
   the customer ("customers aren't certs", the existing rule).
   Unchanged — already pure.

2. **Operator field app (PWA) — a DERIVED child cert, NOT a shared
   key.** "Same cert on phone and brain" is formally excluded:
   `proofs/tla/KeyCustody.tla` + Lean K11/K12 model per-tier custody
   as leaf-key *derivation* (root seed never leaves; leaf keys
   re-derived locally). Pure = the substrate's D-O5p model: the
   operator root delegates to a **phone child cert with a tiered
   capability allowlist** (`capabilities.ts` §10 — high-risk caps not
   delegated by default). Sole operator signs offline with its own
   derived leaf key, pushes the envelope; the brain validates the
   chain (`cert_unknown`/`cert_binding_mismatch`, hatId=operator root,
   certId=phone child — the P3.3-grounded `intent_cells.submit`
   validation).

3. **Chat-widget AI agent — its OWN agent child cert (net-new
   principal; resolves P3.3).** A child cert under the operator root
   with a *least-privilege* cap allowlist (write conversation
   patches, propose leads pre-ratification) — explicitly NOT the
   operator's ratify/transition caps (the D-O5p "not delegated by
   default" tier). The operator's high-trust cert never reaches the
   edge. This supersedes the three earlier P3.3 options: the edge
   presents the **agent cert's** `(hatId=operator-root,
   certId=agent-child)`, provisioned at deploy/pairing — not the
   operator's identifiers. It also anchors de-black-box: the
   conversation patch log (UNSIGNED today — `hatId` is a placeholder
   string, `conversation-turn-patch.ts:57`) becomes
   agent-cert-signed ⇒ cryptographically attributable to the agent
   principal + prompt/decision-tree version.

**Two separable signing concerns — only one is gated:**
- *Intent-cell submit (P3.2/P3.4)* needs **no edge signing**:
  `intent_cells.submit` parses no envelope signature; it validates
  `(hatId, certId)` against the cert store + chain binding, brain is
  trust root. So the agent-cert-**as-identifier** path proceeds now —
  the agent cert only needs to **exist in the brain cert store,
  chain-bound** (a provisioning/pairing concern). **P3.4 unblocked.**
- *Agent-cert SIGNING the patch log* + *PWA OFFLINE-signing cells*
  need real BRC-42 leaf derivation/sign (`host_derive_leaf`,
  `host_sign`, `host_state_next_index`) — exactly the **Tier-B
  documented-failure stubs** (DEBT-KERNEL-ABI-V2-HOST-DESYNC,
  substrate-owner crypto). A deliberate LATER layer, NOT a P3.4
  blocker.

**Residual operator sub-decision (narrowed, no crypto):** the
agent-cert *provisioning* mechanism under D-O5p — (1) generate +
register the agent child cert in the brain cert store at deploy/
pairing (D-O5p-style, brain-ambient, recommended for oddjobtodd
now); (2) a brain pairing/identity endpoint the cartridge calls to
mint+register its agent cert (cleaner for U4 multi-tenant, net-new
surface); (3) defer per-tenant agent-cert minting to U4. P3.4 wiring
takes `(hatId, certId)` as `EnvelopeContext` regardless of which —
only the *source* differs. Patch-log-signing tracked separately
(gated on Tier-B crypto).

### P3.2 SHIPPED + P3.3 grounded & narrowed — operator decision (`13ed13c`, 2026-05-18)

**P3.2 shipped** (`13ed13c`): `brain-submit-storage.ts` —
`buildIntentCellEnvelope` (intent_cell.v1 spec) +
`makeBrainSubmitStorageAdapter` (POST `/api/v1/repl`,
`Authorization: Bearer`, `{"cmd":"submit-intent-cell --envelope
<b64>"}`). Dependency-light + transport-injected; 6/6 mock-transport
tests; ZERO live change (real POST is P3.5). `hatId`/`certId`
parameterised via `EnvelopeContext` so P3.2 stayed
decision-independent.

**P3.3 — grounded, and the decision is much narrower than feared.**
`intent_cells_handler.zig` parseEnvelope parses **no envelope
`signature`/receipt-sig field** (test fixtures = kind/version/cellId/
opcodeBytes/hatId/certId/correlationId/kernelResult/originalIntent —
no sig). It (Step 3) resolves `certId` in the brain's cert store
(`cert_unknown`) and (Step 4) validates `hatId` matches the chain
binding for `certId` (`cert_binding_mismatch`); the brain is then the
**authoritative trust root** (the `kernelResult` is likewise "the
producer's claim — the brain re-runs + overrides"). **∴ the cartridge
edge does NOT sign anything** — it presents the operator's cert
*identifiers* `(hatId, certId)`; the brain (holding the operator cert
+ cert store) is the authority. Options (a) brain-sign-callback and
(b) edge-child-cert-KEY both **collapse**: there is no edge signing.
This is the architecturally-pure decoupled outcome (operator key
never leaves the brain; the cartridge edge is keyless) and it matches
the P2.d "kernel/brain owns the trust boundary" ruling.

**The residual operator decision (genuinely narrowed, no crypto):**
*how does the cartridge edge obtain the valid `(hatId, certId)` to
present?* The deployed brain carries a 6-cert chain (boot:
"Identity certs: 6 cert(s)"); the spawned edge runs with the brain's
ambient context (the `voice-extract` precedent). Options:
  1. **Brain-ambient identifiers (recommended, single-operator)** —
     the edge is handed the operator root `hatId` + a chain-bound
     child `certId` via env/config at spawn (no key), exactly as
     `voice-extract` inherits brain creds. Minimal; unblocks
     oddjobtodd now.
  2. **Brain identity endpoint** — a small read-only brain route the
     edge calls to fetch its `(hatId, certId)` for the active hat.
     Cleaner for multi-tenant (U4) but is net-new brain surface.
  3. Defer to U4 — wire (1) for oddjobtodd now; the per-tenant
     `(hatId, certId)` provisioning is the U4 multi-tenant story
     (which already rides this decision).
Needs the operator's call on (1) vs (2)/sequencing — surfaced, NOT
guessed. P3.4 (oddjobz-correct accept_rom Intent + wiring) and the
P3.2 adapter are unaffected by which is chosen; only the
`EnvelopeContext.{hatId,certId}` *source* depends on it. The /loop
HALTS here per its stop-conditions (operator decision; not
time/event-gated — no ScheduleWakeup).

### P3.1 — GREEN: Phase-3 Option-1 feasibility PROVEN end-to-end (`8e127c1`, 2026-05-18)

After the kernel-ABI resync (`d450746`) + the harness Intent fix
(`8e127c1`: proven-green mkHat — certId+capabilities[5]→interpretive
trust — + the golden-test G1 `> amount 500` comparison constraint, so
the REAL lowerSIR→emit produces non-degenerate bytes), the P3.1 probe
ran the **entire real pipeline edge-side**, verified isolated on rbs
(ZERO live change):

  intent_extracted ✓ (producerMeta.targetJson = the U1 money channel:
                       {costMin:40000,costMax:60000,currency:AUD})
  sir_built        ✓ trustClass interpretive, constraintCount 1
  sir_lowered      ✓
  ir_emitted       ✓ byteLength 6 (REAL @semantos/semantos-ir emit)
  script_executed  ✓ kernelOk:true (REAL cell-engine WASM kernel)
  cell_written     ✓ cellId cell-000006-03010101-5459eb9f
  intent_completed ✓ ok:true
  → verdict "P3.1 OK — envelope producible edge-side", exit 0

**Phase-3 Option-1 is PROVEN feasible**: the oddjobz edge runs the
real `processIntent` pipeline against the real (now-instantiable)
kernel and produces a valid cell envelope, using the shipped
`createShellPipelineDeps` pattern + the U1 `acceptRomTargetJson`
money channel. The de-risking spike has delivered its verdict —
infrastructure works end-to-end; what remains is forward construction
(P3.2+), not feasibility unknowns. The probe
(`extensions/oddjobz/tools/p3-spike-processintent.ts`) is retained as
the standing edge-pipeline conformance test.

Remaining for the oddjobz-correct path (P3.4, not feasibility):
the spike uses the golden jural/comparison Intent to prove the
pipeline; the real oddjobz `accept_rom` taxonomy/action + the lead
cell shape is the P3.4 wiring (the money channel + cap path are
already proven).

### DEBT-KERNEL-ABI-V2-HOST-DESYNC — RESOLVED + verified (`d450746`, 2026-05-18)

The resync shipped (`d450746`) and was verified isolated on rbs
(coupling honoured: local→git→rbs; ZERO live change — deployed bot
at `0cda1ac9` untouched, service active throughout):

- **Kernel-ABI desync FIXED.** The WASM now instantiates — the P3.1
  probe progressed from "LinkError: hostDbOpenCursor" to running
  `processIntent` clean through `intent_extracted → sir_built →
  sir_lowered` (deep into host-call territory; the host imports are
  now callable).
- **Regression-free + strongly net-positive (trust-but-verified).**
  cell-engine package tests: pre-resync parent `d2526b8` = **119
  fail / 12 err**; post-resync `d450746` = **40 fail / 4 err (103
  pass)** — the resync *recovered ~79 tests* (the missing host
  imports were failing nearly every engine-loading test). The
  remaining 40 are a strict subset of the original 119: **pre-existing
  cross-language multi-cell packing drift** (RM-050 V2 header/
  multi-cell layout vs the TS packer) — a SEPARATE workstream, NOT
  introduced by this change. Filed: DEBT-XLANG-MULTICELL-PACKING.
- **Proof-safe — confirmed by construction.** Purely additive JS host
  impls; zero `.lean`/`.tla`/kernel-Zig/WASM bytes touched (`d49d44e`
  touched no proof files; proofs have no host-I/O refs). `lake build`
  is a CI gate (`gate.yml:98`) — lake is not on the rbs PATH, but the
  change *structurally cannot* affect the Lean/TLA+ (they verify
  kernel semantics; this is the JS host boundary). Operator's "don't
  break Lean/TLA+" constraint satisfied by construction.
- **Tier-B crypto stubs never reached** — the probe's later failure is
  upstream of any host_sign/derive_leaf/unlock_tier call, so the
  documented-failure-stub safety argument was not even exercised yet
  (and remains valid).

**Remaining (NOT this debt; smaller, isolated):** the P3.1 probe now
throws downstream — `RangeError at emitBinding (core/semantos-ir/src/
emit.ts:123)` with `allowedEmitOps:[]` at `sir_lowered`, i.e. the
spike's *synthetic minimal Intent* gives the IR emitter a zero-length
array. This is a **P3.1-harness Intent-shaping refinement** (the
jural/declaration placeholder Intent emits nothing; needs a real
oddjobz emit-op surface or a richer Intent), NOT substrate and NOT the
ABI desync. Next P3.1 iteration.

The kernel-ABI host desync — the thing that blocked Phase-3 AND
independently broke every bun kernel consumer (runtime/shell incl.) —
is **sorted, verified, regression-free, proof-safe**, exactly as the
operator required.

### DEBT-KERNEL-ABI-V2-HOST-DESYNC — complete diagnosis + criticality-tiered resync spec (2026-05-18)

`core/cell-engine/src/host.zig` declares **21** `pub extern "host" fn`;
`core/cell-engine/bindings/host-functions.ts` `createHostFunctions`
provides **10**. **11 missing** (the WASM imports them; instantiation
LinkErrors on the first referenced-but-absent one — P3.1 hit
`hostDbOpenCursor`). This is a pre-existing substrate breakage on
`main` affecting **every bun kernel consumer** (`runtime/shell`
included — it calls `loadCellEngine({profile:'full'})` identically).

**Proof-safety (the operator's hard constraint):** the fix is purely
additive JS host-fn implementations on the object `createHostFunctions`
returns. It does NOT touch the kernel Zig, the WASM, or any
`.lean`/`.tla` (verified: `d49d44e` touched no proof files; grep of
`proofs/lean`+`proofs/tla` for `hostDb|Cursor|host I/O` is empty — the
proofs model kernel *semantics* (Cell/BoundedStack/Linearity + 21 TLA+
specs), orthogonal to host-I/O impls). Lean check = `lake build`
(`.github/workflows/gate.yml:98`). **Every missing fn documents `0` as
its defined failure return** ("Returns 1 on success, 0 on …") — so a
callable returning `0` is the kernel's *defined clean-failure path*
(exactly the failure case the proofs already model), provably
non-corrupting and categorically different from a wrong impl.

**Tier A — implement correctly (zero ambiguity; mirror existing
patterns; no key/state/crypto risk):**
- `hostDbOpenCursor(filter_ptr,filter_len)→cursor_id|0`,
  `hostDbCursorPull(cursor_id,out_ptr)→1|0`,
  `hostDbCursorClose(cursor_id)→void` — per-instance cursor registry
  closed over in `createHostFunctions` (like `store`); back it with
  `store: Map<string,Uint8Array>` iteration; 1024-byte memory write
  mirrors `host_fetch_cell` (`new Uint8Array(memory.buffer,outPtr,
  1024).set(...)`). filter reserved ⇒ unfiltered. This is the family
  P3.1's edge pipeline actually exercises.
- `host_sha1`, `host_ripemd160` — fixed standard hashes; correct impl
  is unambiguous, mirrors `host_sha256` exactly (read len bytes at
  dataPtr, write digest at outPtr).

**Tier B — documented-failure stubs ONLY (trusted-crypto boundary;
correct impl is substrate-owner work; the host keystore/KEK/slot
infra these need does not exist in the lightweight bun bindings):**
- `host_sign`→`0` (out buffer untouched, per host.zig:33-35),
  `host_derive_leaf`→`0`, `host_state_next_index`→`0`,
  `host_unlock_tier`→`0`, `host_persist_cell`→`0`,
  `host_load_cell`→`0`. Each with a loud
  `// DEBT-KERNEL-ABI-V2-HOST-DESYNC: documented-failure stub — real
  W3.5/W4 crypto/keystore impl is substrate-owner work; returning the
  kernel's defined failure sentinel is non-corrupting, NOT a guess`.
  Safe because `0` = the kernel's handled failure path; a W3.5/W4
  wallet/tier path that calls them fails cleanly rather than corrupts.
  P3.1's `accept_rom` authoring path (OP_1 frame) is not expected to
  invoke these — the re-run of the P3.1 probe is the empirical test:
  if instantiation succeeds and `processIntent` completes, Tier-A is
  sufficient to unblock Phase-3; if it hits a Tier-B fn, that fn's
  correct crypto impl becomes a hard Phase-3 prerequisite (substrate
  owner), surfaced rather than guessed.

**Verification gate (all must hold):** (1) `cd proofs/lean && lake
build` green (Lean unaffected — structurally, by the proof-safety
argument; verified empirically); (2) `core/cell-engine` package tests
green; (3) the P3.1 probe (`extensions/oddjobz/tools/
p3-spike-processintent.ts`) re-run in the bun-installed rbs worktree
→ WASM instantiates + verdict. Coupling: author local → commit →
verify in the bun-installed/proof-capable context → never hand-edit
on rbs. ZERO live change (core/cell-engine bindings; the deployed bot
bundle is unaffected until a deliberate P3.4 redeploy).

This spec is complete + zero-re-grounding. It is a focused substrate
unit (the trusted-crypto host boundary + Lean verification in the
loop) — deliberately not bulldozed blind at session-tail, where a
wrong `host_sign`/`host_derive_leaf`/`host_unlock_tier` is precisely
the catastrophic silent corruption the "don't break Lean/TLA+"
constraint exists to prevent.

### P3.1 — RAN; verdict: edge-pipeline blocked by a pre-existing kernel-ABI desync on main (2026-05-18)

The spike was authored (`5e3640a`), iterated in the isolated
bun-installed rbs worktree (coupling honoured: local→git→rbs, never
hand-edited; ZERO live change — deployed tree/bundle/brain untouched
throughout), and produced a **definitive feasibility verdict**:

- Cycle 1 (`5e3640a`): `bun install` ✓ (749 pkgs); error —
  `loadCellEngine` not on `@semantos/cell-engine` main entry.
- Cycle 2 (`0dde7e2`): fixed import → `@semantos/cell-engine/
  bindings/bun/loader` (the proven `runtime/shell/src/index.ts:74`
  precedent). Import ✓, binding loaded ✓. New error at WASM
  instantiation: **`LinkError: import function host:hostDbOpenCursor
  must be callable`**.

**Root cause (fully characterised, not guessed):** the committed
`core/cell-engine/zig-out/bin/cell-engine.wasm` was last changed by
`d49d44e feat(phase-h): RM-050 — kernel ABI bump V1 → V2`, which added
the `host:hostDbOpenCursor` import. The TS host bindings
(`core/cell-engine/bindings/host-functions.ts` /
`builtin-host-functions.ts`) were last touched by the *pre-ABI-bump*
`0b3b6b5` refactor and **never resynced to the V2 ABI** —
`hostDbOpenCursor` is absent from the JS. The V2 WASM therefore cannot
instantiate against the V1 host bindings.

**This is a pre-existing substrate breakage on `main`, not an
oddjobz/harness bug.** `runtime/shell/src/index.ts` calls
`loadCellEngine({profile:'full'})` *identically with no hostRegistry*
— so the cell-engine bun kernel binding is broken for **every** bun
consumer, not just P3.1. The P3.1 harness + pattern are correct
(install ✓, the `@semantos/cell-engine/bindings/bun/loader` +
inlined-`createShellPipelineDeps` approach is exactly the proven
shell precedent); the blocker is below oddjobz.

**∴ Phase-3 Option-1 is gated on a substrate fix: resync the
cell-engine TS host bindings to the RM-050 V2 kernel ABI (add
`hostDbOpenCursor` + any other V2-added host imports), or rebuild a
host-matching WASM.** This is kernel-ABI work with repo-wide blast
radius (the WASM↔host contract) — a substrate-owner escalation, NOT
something to shim by guessing host semantics (a wrong host ABI
silently corrupts kernel execution). The spike delivered its highest
value: it converted "wire U1 and hope" into an empirically-proven,
precisely-located substrate blocker that would otherwise have
surfaced as mysterious live failures. NEW WORKSTREAM filed:
**DEBT-KERNEL-ABI-V2-HOST-DESYNC** (blocks Phase-3; independently
breaks runtime/shell + every bun kernel consumer).

The P3.1 harness (`extensions/oddjobz/tools/p3-spike-processintent.ts`)
is retained as the ready conformance probe — re-run it once the ABI
desync is fixed to confirm Option-1 feasibility and proceed P3.2+.

### P3.1 — authoring spec (fully grounded 2026-05-18; zero re-grounding, near-one-shot)

A standalone feasibility harness `extensions/oddjobz/tools/
p3-spike-processintent.ts` (a `tools/` script like voice-extract.ts —
NOT wired to anything live; proves the edge can run `processIntent`
and produce a valid envelope). Mirror `runtime/shell/src/
intent-adapters/run-shell-intent.ts` exactly. Grounded APIs:

- **Kernel:** `import { loadCellEngine } from '@semantos/cell-engine'`
  (bun binding; `loadCellEngine(opts?) => Promise<CellEngine>`,
  default `profile:'full'`, resolves the bundled wasm; `CellEngine.
  executeScript(lock:Uint8Array, unlock?:Uint8Array) =>
  {success,typeClassification,opcodeCount,error}`).
- **PipelineDeps:** inline an equivalent of `createShellPipelineDeps`
  (don't depend on runtime/shell internals being importable from the
  oddjobz pkg — it's ~40 lines; copy the mapping incl.
  `mode:'authoring'` → `AUTHORING_FRAME = Uint8Array([0x51])`,
  `mapKernelResult`, `deriveCellId`). `emitBytes` ←
  `import { emit } from '@semantos/semantos-ir'`. `lowerSIR` ← omit
  (pipeline defaults to `@semantos/semantos-sir`).
- **Storage:** in-memory `StorageAdapter` (`@semantos/protocol-types`
  shape: `write(key,bytes)/read/...`) — a `Map`. Proves wiring; P3.2
  swaps the brain-submit adapter.
- **Signer:** inline trivial `AsyncSigner` — `sign:async()=>new
  Uint8Array(64)`. Real signing is P3.3. (No StubSigner class exists;
  `runtime/session-protocol/src/signer.ts` has the `Signer`
  interface + `BsvSdkSigner` only — inline a stub.)
- **Intent:** mirror `shell-to-intent.ts`: `{ id: uuid(),
  correlationId: uuid(), summary, category: {lexicon:'jural',
  category:<valid juralCat>} as TaggedCategory, taxonomy:<minimal
  TaxonomyCoordinates>, action:'accept_rom', constraints:[],
  confidence:1, source:<shell-like IntentSource> }`. The
  oddjobz-correct lexicon/taxonomy is a P3.4 refinement — the spike
  uses a lowerSIR-accepted `jural` category to prove the pipeline
  runs. `originalIntent.targetJson` ← `acceptRomTargetJson({costMin,
  costMax})` (1297eaa).
- **Hat:** `buildHatContext({ identity:<dev IdentityServiceLike
  stub>, extension:{extensionId:'oddjobz',domainFlag:
  capWritePolicy/ writeCustomer flag}, resolveMaxTrustClass:
  defaultTrustCeiling })`; `isDevIdentityStub()` ⇒ `requireCert`
  false, so no real cert needed for the spike.
- **Call:** `const r = await processIntent(intent, {hat, logger:
  createJsonlStderrLogger(), correlationId}, deps)`. **Success
  criterion:** `r.ok === true`, `r.cell.id` present, a
  `kernelResult` produced — i.e. a valid `oddjobz.intent_cell.v1`
  envelope is assemblable edge-side. Print it; exit 0.

**Execution loop (coupling rule):** author in the local worktree →
commit → in the bun-installed rbs isolated worktree at origin/main
(the one the bundle build proved resolves `@semantos/*`):
`bun install` then `bun run extensions/oddjobz/tools/
p3-spike-processintent.ts` → captures type/API errors → fix in local
→ recommit → re-verify. **NO live change** (standalone harness; never
touches the bundle/site/brain). Expect 1–3 iteration cycles — that is
the spike working as designed, at zero live risk. Green ⇒ Option-1
feasibility proven; proceed P3.2 (brain-submit StorageAdapter), then
P3.3 (signer-identity, the operator sub-decision), P3.4 (wire chat +
collapse voice-extract), P3.5 (gated build + live verify).

This spec is complete enough to author the spike with zero
re-grounding. It is the next focused unit (env-gated multi-cycle
authoring + the bun-resolving verify loop) — deliberately not
authored blind at session-tail, where each compounding cycle is the
degraded-precision risk this project's discipline exists to prevent.

### U1 — earlier "BLOCKED" finding (SUPERSEDED by the Phase-3 grounding above; retained for the contracts)

Comprehensive cross-codebase scoping (local) of the edge→substrate
cell-mint produced a load-bearing finding that **invalidates U1's
"edge runs processIntent → envelope → submit" premise**:

- `intent_cells.submit` / REPL `submit-intent-cell`
  (`intent_cells_handler.zig:handleSubmit`) **requires a complete,
  pre-built `oddjobz.intent_cell.v1` envelope**: it `parseEnvelope`s
  and **re-runs the kernel over the supplied `opcodeBytes`** to
  reconcile/override the producer's claimed `kernelResult`. It does
  **not** lower an intent. The producer must supply `opcodeBytes`
  (OIR-emitted opcode stream) **and** a locally-run `kernelResult`.
- There is **no brain-side pipeline**: `processIntent` / `produceIntent`
  / `lowerSIR` exist only in `runtime/intent/src` (TS); the brain
  (Zig) embeds/calls none of them. The brain is a pure submit-target
  that *validates + re-executes the kernel over* a finished envelope —
  it cannot accept a lightweight `{summary,action,targetJson}`
  candidate and mint.
- The phone produces the full envelope **on-device** (sir_extractor
  + on-device kernel — the Phase-2 `sir_candidate` path).
  `extensions/oddjobz/tools/voice-extract.ts` — the only existing
  oddjobz edge-pipeline tool — does **NOT** call `processIntent`; it
  is an explicit **Phase-1/2 placeholder** ("Phase 3 swaps both for
  the real `processIntent(intent, ctx, deps)` call once the brain has
  the kernel + storage + sign deps available to bun"). The spawned
  bun edge process has **no kernel/storage/sign deps** to run the
  pipeline — the *identical* unsolved blocker U1's chat-widget mint
  hits.

**∴ The chat-widget→typed-cell store path is blocked by the same
unsolved "Phase 3" substrate gap as voice-extract, not by missing
glue.** The pure money-channel core (`accept-rom-target.ts`,
`1297eaa`) is done and correct; it is necessary but **not sufficient**
— nothing can assemble it into a submittable envelope edge-side today.

**The real decision (operator) — how the edge mints without an
on-device kernel:**
1. **Phase-3 proper — give the spawned bun the pipeline deps.** Bundle
   the cell-engine kernel WASM into the edge bundle + a brain
   sign-callback (the brain holds the operator cert) + use
   `submit-intent-cell` for storage. Then `processIntent` runs
   edge-side and the (ii)-pure A3-C model is real. Largest; also
   unblocks voice-extract Phase 3; most architecturally pure (edge
   genuinely owns the pipeline).
2. **New generic brain lowering endpoint.** Add a brain capability
   that accepts a typed candidate `{summary,action,taxonomyJson,
   targetJson}` + cap and runs lower→OIR→kernel→mint server-side.
   NB: the brain is Zig and embeds none of the TS pipeline, so this
   collapses into "the brain spawns a bun that *can* run
   `processIntent`" — i.e. it still requires solving (1)'s
   kernel/storage/sign-to-bun problem. Not an independent shortcut.
3. **Defer structured chat cells; keep the JSONL shadow** as the
   chat-widget store until Phase-3 lands for voice+chat together
   (they share the blocker). Gmail/Meta ingest (U2) has the same
   constraint — none of the three sources can mint typed cells until
   the edge-pipeline gap is closed.

This is a genuine substrate-architecture decision + substantial Phase-3
work, surfaced — deliberately NOT bulldozed into a guessed
opcode/kernelResult forgery shipped to the live customer bot (which
the brain's kernel re-execution would reject anyway). The decoupled-
cartridge model (DECISION-P4C) still holds; "Phase 3" is its
prerequisite.

### U1 — executable build spec (SUPERSEDED by the Phase-3 finding above; retained for the contracts it grounds)

The structured-cell seam. **Grounded contracts (all located, no
unknowns):**
- **Submit transport:** brain REPL verb `submit-intent-cell --envelope
  <base64-json>` over `/api/v1/repl` (the brain already serves this;
  `--enable-repl`, 20 bearer tokens issued at boot) → `intent_cells`
  resource `submit` cmd (`intent_cells_handler.zig:handleSubmit`, "the
  architectural heart") → cap-gate **`cap.oddjobz.write_customer`**
  (`CAP_SUBMIT_INTENT`, reused until a dedicated cap lands — confirms
  SD1) → `intent_action_router` → on `accept_rom` mints an accepted
  `auto_rom` Estimate from the ROM range + maps `lead → qualified`
  (`intent_action_router.zig:123`) → `IntentCellLmdbStore` (THE
  standardised store). Brain stays generic — nothing oddjobz-specific.
- **Envelope schema:** `docs/spec/oddjobz-intent-cell-v1.md`.
  `kind:"oddjobz.intent_cell.v1"`, `version:1`, required `cellId`,
  `opcodeBytes` (base64 OIR), `hatId` (operator root-cert 32-hex),
  `certId`, `correlationId`, `kernelResult{ok,opcount,stackDepth,
  gasUsed,errorKind}`, `originalIntent{summary,action,taxonomyJson,
  targetJson}`. `action="accept_rom"`; `targetJson` (≤1 KiB) canonical
  `{jobId,customerId,costMin,costMax,currency}` cents (the
  `ae9eabb` ROM-range channel).
- **Producer:** the envelope is NOT hand-built — it is produced by the
  shipped `@semantos/intent` pipeline (`produceIntent` /
  `processIntent`, DECISION-A3 Option C: edge owns the pipeline; it
  lowers intent→OIR→opcodeBytes, runs the local kernel for
  `kernelResult`, threads `correlationId`).
- **Build site:** `extensions/oddjobz/src/conversation/
  substrate-bridge.ts` — currently an explicit stub ("what's left to
  port: the typed Plumbing surface"). U1 ports the submit plumbing
  there.
- **Identity:** `hatId`/`certId` = the brain's deployed operator cert
  (boot: "Identity certs: 6 cert(s) in chain"), exactly as
  `voice-extract` uses brain-ambient creds — so U1 is **unblocked for
  the oddjobtodd single-operator case**. Per-tenant operator-cert
  binding is the U4 generalisation (SD3), NOT a U1 blocker.

**Execution steps (each verified; the build is not worktree-runnable
— `@semantos/intent` is env-gated here, so it builds/verifies in a
bun-installed context on rbs, like the bundle, ending in a gated live
redeploy via `build-oddjobz-bundle.sh`):**
1. `substrate-bridge.ts`: implement `submitAcceptRom(state, deps)` —
   map `AccumulatedJobState` → an `accept_rom` Intent with
   `targetJson{jobId,customerId,costMin,costMax,currency}` (costMin/
   costMax from the ROM; SD2: mint `oddjobz.lead.v1` via the existing
   ratify path that `intent_action_router` already drives) → run
   `processIntent` (edge pipeline) → POST the produced envelope to
   `/api/v1/repl` `submit-intent-cell --envelope <b64>` with the
   brain bearer token (deps-injected REPL client + cert ids — the
   A5.P2.c deps-injection shape, so the pure mapping is unit-testable
   even though the pipeline/REPL are integration-only).
2. intake-handler completion: call `submitAcceptRom` (replacing the
   flat `persistLead`/`leads.jsonl` write; keep jsonl as a
   transitional shadow until the store is verified).
3. `build-oddjobz-bundle.sh` → gated live redeploy.
4. Verify end-to-end on the live `--enable-repl` brain: an
   `oddjobz.lead.v1` (+ accepted `auto_rom` Estimate) cell lands in
   `IntentCellLmdbStore`, `lead → qualified`, and is readable back
   (`find intent-cells --hat <op>`). THEN U2 (ingest convergence) and
   U3 (PWA WSS discovery) reuse the identical `submitAcceptRom` seam.

This spec is complete enough to execute with zero re-grounding. It is
deliberately a self-contained next unit (env-gated build + live
customer-bot data-path redeploy) rather than a session-tail bulldoze.

### DECISION-P4C — RESOLVED (operator, 2026-05-18): option (ii)-pure, the decoupled sellable cartridge

The (i) brain-parses-stdout vs (ii) handler-self-submits choice is
resolved to **(ii), in its architecturally pure form**, because the
product goal is a **sellable, multi-tenant oddjobz cartridge**: a
customer buys a deployment, ingests jobs from *their* lead sources
(chat widget on their site, Gmail, Meta), everything lands in a
**standardised store**, and is discoverable via *their* PWA running
the same cartridge over WSS.

Two decouplings are load-bearing and define the architecture:

1. **Cartridge ⟂ brain.** The brain MUST NOT contain any
   oddjobz-specific stdout-parsing/submission logic — that would make
   every cartridge require brain changes (un-sellable, re-couples the
   substrate to one vertical). Option (i) is rejected on exactly this
   ground. Instead the cartridge (intake handler + Gmail/Meta ingest
   adapters) mints typed cells and submits them through the **standard,
   cartridge-agnostic, cap-gated substrate API** — the shipped
   `submit-intent-cell` / `intent_cells.submit` →
   `intent_action_router` path (this is DECISION-A3 Option C — "edge
   owns the pipeline; brain is a pure submit-target" — taken to its
   conclusion). The brain still owns the trust boundary (cap-spend +
   linearity enforcement, the P2.d purity principle); it just never
   learns anything oddjobz-specific. Any cartridge uses the identical
   path.

2. **Operator ⟂ cartridge.** The cartridge code is byte-identical
   across all deployments. A deployment is parameterised by an
   **operator cert / cartridge license** (the CC1 license / SpvContext
   path) — `oddjobtodd` is just *one* operator of the oddjobz
   cartridge. Per-tenant: the operator identity, their configured lead
   sources, and their slice of the standardised store. The
   `set_pricing_policy` cap model (A5.P2) is the precedent: hat/cert-
   gated, per-operator config as cells.

**The standardised store.** One typed-cell substrate store (not the
three disjoint JSONL/lmdb islands of today). Chat-widget intake,
Gmail ingest, and Meta ingest all converge on the **same mint+submit
seam**: raw lead → `oddjobz.lead.v1` (and `job`) typed cell →
cap-gated `intent_cells.submit` → substrate. Partitioned by the
operator-cartridge tenancy (the cap context-tag / hat, exactly as
`pricing_policy` is per-hat). The flat `persistLead`/`leads.jsonl`
idiom is superseded.

**PWA discovery.** The same cartridge, loaded in the PWA shell (CC2c
registry, bound by `cartridge.json`), discovers the standardised store
over WSS — the cross-shell id contract CC3 already proves end-to-end
for the first cartridge. The PWA is a *reader* of the same cap-gated
store the ingest seam writes.

**Net:** deploy cartridge → ingest from any lead source → one
standardised cap-gated typed-cell store → PWA discovery over WSS, with
the brain a generic substrate and the operator a swappable license
holder. This reshapes P4.C/P5 from "make oddjobz submit" into "make
the cartridge a self-contained, sellable, brain-agnostic unit."
Builds on: DECISION-A3 (Option C, the precedent), the Canonical-
Cartridge wave CC0–CC3 (cartridge model + license + dual-shell loader,
now on main), and A5.P2 (the cap-gated typed-cell write-seam
template). Decomposition + the flagged sub-decisions (store tenancy
partitioning, operator-cert↔cartridge binding, the WSS discovery
contract) are scoped as the next epic, not bulldozed.

Each a verified increment (TS: `cd extensions/oddjobz && bun test`;
zig gate for any brain change; FF-safe; path-scoped commit; push;
**redeploy the brain from main is now SAFE post-`46b67c4`** and is
required for P4.C to take effect — the running rbs binary is pinned
at `2714dfd1`). Graft/cauterise arc + brain loop unaffected and
shipped.

## 7. DECISION-PENDING-A5 — PricingPolicy as a Ricardian operator-config cell

Operator direction (2026-05-17): the `PricingPolicy` `calculateROM`
needs must be a **configurable operator policy**, each aspect a
**field like a Ricardian contract**, edited in a console that ships
in the **operator dashboard / field app / brain cartridge under the
right hat**, so the **Paskian** system can pick it up and tune it.
Grounded recon — what's shipped vs greenfield:

| Component | State | File |
|---|---|---|
| `defineCellType` framework (validate/canonical/type-hash/linearity) | ✅ reuse | `cell-types/cell-type.ts:64-103` |
| Structural cell-shape template | ✅ copy | `cell-types/site.v2.ts:178-189` |
| Operator-signing precedent (hat-sign at mint + provenance field) | ◑ partial | `cell-types/lead.ts:39,46,114` (`ratifiedBy`) |
| `verb.dispatch` infra + mutating-walker template | ✅ reuse | `verb_dispatcher.zig:19-83`; `oddjobz_ratify_walker.zig:122` |
| cap/domain-flag + hat gating scheme | ✅ extend | `capabilities.ts:133-228` |
| **policy/Ricardian/config cell type** | ❌ net-new | — |
| **config-intent verb + write walker** | ❌ net-new (explicitly a deferred sidequest) | `docs/SHELL-CARTRIDGES-HATS.md:229-231,310` |
| **`cap.oddjobz.write_policy`** | ❌ net-new | — |
| **operator policy-edit UI** | ❌ net-new (no pricing screen; the one settings screen persists to platform store — wrong model) | `apps/oddjobz-mobile/lib/src/helm/` |
| **`calculateROM` wired into the estimate path** | ❌ **DEAD CODE — zero production callers, no default policy** | `rom.ts:76` |
| Pask reads/tunes a policy cell | ❌ aspirational; **excluded by Pask's own contract** | `core/pask/PRIMER.md:44-49` |

**Honest correction (load-bearing): "Pask picks it up and tunes it"
contradicts what Pask is.** Pask is a constraint-graph *stability*
kernel — "Not a recommendation engine… does not tell you what's
next… no objective being minimised, no model weights" (`PRIMER.md:
44-49`); zero AI in the substrate by design. A Pask pass that emits
tuned price values would be a net-new optimiser/ML in the kernel —
the exact thing the substrate excludes. Realistic reframe: Pask can
*observe* policy-cell interaction stability and surface which fields
are settled vs volatile (`types.zig` `StableThread`); the operator
(or an edge model) does the actual tuning. **"Pask auto-tunes /
writes the policy back" must be explicitly ruled out or deferred —
it is not what Pask does.**

The other smoking gun: **`calculateROM` is dead code today** (no
callers, no default policy). So this is not "make an existing policy
configurable" — it is "build the policy substrate AND wire ROM into
the estimate path for the first time," with a safe default:
**no `pricing_policy` cell under this hat → do NOT surface auto-ROM;
route to formal quote** (reuse the existing `rom.ts` `requiresQuote`
/ `note:'requires_formal_quote'` branch).

**Operator decisions that BLOCK build (DECISION-PENDING-A5):**
1. **Cell linearity** — singleton-per-hat PERSISTENT (mutable
   successor, prevStateHash-chained, like site.v2) vs append-only
   versioned history (each edit a signed new cell, latest-wins).
   Ricardian/contract framing argues append-only+signed; PERSISTENT
   is least-resistance. The load-bearing choice.
2. **"Contract"/signing depth** — is mint-time hat-signing + a
   `signedBy` provenance field (the `lead.ratifiedBy` precedent)
   sufficient, or do you want true Ricardian (explicit detached
   signature + a human-readable prose clause per field)? The latter
   is substantial net-new.
3. **Pask scope** — confirm the reframe: Pask *observes* field
   stability (in scope, small) and auto-tuning/write-back is
   **deferred** (out of scope, by Pask's contract). Or rule
   otherwise.
4. **Surface** — new field-addressable policy screen in
   `apps/oddjobz-mobile` helm, gated by a new `cap.oddjobz.write_
   policy`, persisting via a NEW `set_pricing_policy` config-intent
   (per `SHELL-CARTRIDGES-HATS.md:295` — NOT a config endpoint). The
   config-intent grammar is itself an unstarted naming sprint.

**A5 rulings — RESOLVED (2026-05-17):** (1) linearity =
`PERSISTENT` → wire `RELEVANT` (operator: "only knew it as relevant
not persistent" — accumulate-never-consumed config, the
customer/site/message precedent; the Ricardian amendment chain is the
app-layer `version`/`prevPolicyHash`/`signedByOperatorId` envelope,
NOT kernel linearity). (2) default — mint-time hat-sign +
`signedByOperatorId` provenance (`lead.ratifiedBy` precedent), not
per-clause detached sigs. (3) Pask *observes* field stability; an
**agent** (edge intelligence) interprets Pask's findings and tunes
via the config-intent — kernel stays AI-free, NOT Pask auto-tuning.
(4) default — helm screen + `cap.oddjobz.write_policy` +
`set_pricing_policy` config-intent.

**Phased build (smallest verified slices, config-as-intents /
cell-as-unit-of-thought):**
- **A5.P0 — SHIPPED** (`379c53d`, linearity-corrected `ee7d004`):
  `oddjobz.pricing_policy.v1` (defineCellType; fields = rom.ts
  `PricingPolicy` verbatim + `hatId` + `version`/`prevPolicyHash`/
  `signedByOperatorId` provenance) + round-trip/type-hash/amendment-
  chain conformance, 7 tests green.
- **A5.P1a — SHIPPED** (`6e8142d`): `resolvePricingPolicy(cell|
  null|undefined)` projector — the single auditable "no policy cell
  ⇒ route to formal quote, never call `calculateROM`" seam +
  `shouldAutoRom()` type-guard; `pricingPolicyCellType` registered in
  cell-types/index.ts via a SEPARATE `ODDJOBZ_CONFIG_CELL_TYPES` list
  (config, not a §O2 entity; hash/name-lookup wiring deferred to
  A5.P2). 3 projector + 102 registry/conformance tests green.
- **A5.P1b — DESIGN GROUNDED, build deferred** (substantive new
  design; see below). Wire `calculateROM` into the estimate path,
  replacing the toy `DEFAULT_ESTIMATOR_FN`/`ROM_BANDS` table behind
  the UNCHANGED state-manager `present_estimate` gate.
- **A5.P2** `cap.oddjobz.write_policy` + a `set_pricing_policy`
  mutating walker (ratify-walker template), hat-gated,
  mints/successor-chains under the operator hat; hash/name-lookup
  wiring into the global cell-type tables. **TS core SHIPPED:**
  - **P2.a** (`1828f76`) — `cap.oddjobz.write_policy` registered
    (domain flag `0x0001_0111`, operator-root); conformance bumped
    (registry 16→17, OPERATOR_ROOT 15→16). `tests/capabilities.test.ts`
    is env-gated here (`@semantos/semantos-sir` via `lexicon.ts`, pre-
    existing — fails identically on clean HEAD) so code-read-verified;
    runnable consumer `ratification-queue.test.ts` green confirms
    clean compile.
  - **P2.b** (`007474e`) — `ODDJOBZ_CONFIG_CELL_TYPES` wired into
    `ODDJOBZ_CELL_TYPES_ALL` (+ `AnyOddjobzCellTypeDef` union), so
    `cellTypeByName`/`cellTypeByHashHex` resolve `pricing_policy`
    (the A5.P1a-deferred wiring); registry-v2 14→15 ×2; v1-length-10
    untouched. 121/121.
  - **P2.c** (`4b09ebe`) — `setPricingPolicy` TS handler: kernel-gates
    on the cap (`checkDomainFlag`), reads latest revision from an
    injected store, builds the append-only signed chain (genesis ⇒ no
    `prevPolicyHash`; amendment ⇒ sha256-of-predecessor link,
    version+1, stable policyId/createdAt), stamps `signedByOperatorId`,
    `pack`-revalidates. `makeMemoryPricingPolicyStore`. 7/7 + 50/50
    regression. Pure/intra-package.
  - **AU default** (`c058fb9`) — `AU_DEFAULT_PRICING_POLICY` (named,
    research-cited, operator-editable VALUE, NOT inlined calculator
    constants) + `auDefaultGenesisInput`. 7/7 incl genesis-mint →
    Slice-3a estimator end-to-end.
  - **P2.d (REDEPLOY-GATED + design call)** — the Zig `verb.dispatch`
    walker adapter (`oddjobz_set_pricing_policy_walker.zig` +
    serve.zig/build.zig wiring). Code-read-only in this worktree
    (needs the full `runtime/semantos-brain` build) and touches the
    deployed brain binary surface (rbs pinned `@2714dfd1`, no
    redeploy). NOTE: the ratify precedent is a 1362-LOC *Zig* handler;
    the P2.c TS handler is **not** in-process-callable from a Zig
    walker — P2.d is either a Zig reimplementation of the chain logic
    or a new TS-handler bridge. Substantive design decision +
    operator-approved redeploy required → surfaced, not bulldozed
    (the analog of Slice 3b / Slice 4).

    **P2.d design — RESOLVED (operator, 2026-05-18): Zig handler, not
    a bridge.** Rationale (architectural purity = *where the trust
    boundary lives*, not LOC): in Semantos the kernel owns linearity;
    a policy write is a `cap.oddjobz.write_policy` UTXO **spend**. The
    TS `kernel-gate.ts` `checkDomainFlag` is an explicit *stub that
    models* `OP_CHECKDOMAINFLAG` — the real enforcement is the Zig FSM
    genesis structurally **consuming** the cap-UTXO inside the handler
    (the recon's load-bearing finding; `verb.dispatch` does not thread
    a cap check). A Zig→TS bridge would put a security-relevant cap
    gate *outside the kernel* (a TS stub a direct caller bypasses with
    no real UTXO consumed) AND re-introduce the per-write subprocess
    black-box + broken snapshot/replay determinism the de-black-boxing
    arc (Inc 1–3) specifically removed. The cross-language duplication
    a bridge avoids is the cheaper cost. So: **Zig walker + thin Zig
    handler owns the cap-spend + successor-chain (kernel = trust
    boundary, consistent with the ratify precedent); the P2.c TS
    `setPricingPolicy` + its exhaustive tests are REPOSITIONED as the
    canonical executable spec / conformance oracle, not the production
    path.**

    **Substrate-debt item — DEBT-XLANG-CELL-CONTRACT.** The genuine
    purity win is *one* canonical definition of each cell's
    encoding + validation + chain invariants that both TS and Zig
    consume, so a hand-mirrored Zig handler cannot silently drift from
    its TS cell-type. The 1362-LOC `oddjobz_ratify_handler.zig`
    already carries this exact debt — it is **substrate-wide, not
    pricing-policy-specific**, and must NOT be papered over with a
    per-walker bridge (that entrenches the impurity). North-star
    *approach* (chosen over speculative schema→codegen as the
    pragmatic, codebase-consistent first realisation): make the TS
    cell-type the **single source of truth via committed canonical
    conformance vectors** — the exact `(value → bytes)` +
    `(malformed → rejection)` golden set the existing **§O2
    vector-parity** convention already uses for the ten entity cells —
    and have the Zig P2.d handler's conformance test consume those
    same vectors. Neither side is "generated", but drift becomes
    *impossible to merge silently*: the Zig test fails the moment its
    output diverges from the TS-authored oracle, and it is the
    foundation any later true-codegen step needs anyway. First
    decision-independent slice (worktree-verifiable, no redeploy):
    emit `oddjobz.pricing_policy.v1` conformance vectors from the TS
    cell-type, wired into the §O2 vector-parity test, as the Zig
    P2.d oracle; the rest is filed as DEBT-XLANG-CELL-CONTRACT (the
    ratify handler is its second instance).
- **A5.P3** field-addressable policy editor screen in the helm
  field app, dispatching the config-intent.
- **A5.P4 (deferred)** Pask *observation* of policy-field stability,
  read-only; agent-tuner separate. Auto-tune/write-back NOT in scope.

**A5.P1b — grounded mapping design (corrects the pre-grounding fear
that the conversation lacks the inputs).** Investigation of
`accumulated-job-state.ts` / `reply-generator.ts` / `state-manager.ts`
/ `chat-service.ts`:

- ✅ **Location IS collected.** `MessageExtraction.suburb/postcode/
  address/locationClue` are LLM-extracted and merged into
  `AccumulatedJobState`. No new conversation capture needed.
- ✅ **Urgency IS collected AND already sequenced.**
  `MessageExtraction.urgency` is a rich enum (`emergency|urgent|
  next_week|next_2_weeks|flexible|when_convenient|unspecified`),
  merged into state, scored in `computeClarity`, labelled in
  `state-manager.ts:331-340`. The "urgency question" already exists
  in the decision tree.
- The real seam: `EstimatorFn` (reply-generator.ts:56-63) =
  `{jobType, scopeDescription, suburb, quantity, accessDifficulty,
  allowWidenedBand} → string`; the toy `DEFAULT_ESTIMATOR_FN` keys a
  `ROM_BANDS` table off `jobType` only. `ROMInput` needs
  `{effortBand, suburbGroup, categoryPath, urgency,
  complexityHints[]}`.

So P1b decomposes into FOUR parts, ordered by decision-independence:

1. **(decision-independent, small) Widen `EstimatorFn` request** to
   carry `urgency` + `postcode` from `AccumulatedJobState` (both
   already in state; the signature just doesn't forward them). Pure
   type + call-site change, unit-testable here. *Buildable now.*
2. **(new pure classifier) `suburbGroup` geo-classify** —
   `state.postcode`/`suburb` + operator home postcode + radius bands
   → a `policy.travelModifiers` key (`'core'`/`'outside'`/…). NO geo
   util exists in-repo (grep-confirmed). Needs a postcode→band
   classifier driven by NEW PricingPolicy fields
   (`operatorHomePostcode`, `radiusBands`).
3. **(new pure classifier) `effortBand` rubric** — operator's rubric:
   technical difficulty + displacement-over-time + mass/density +
   access + risk + **one-man-team HR physical limits** → a
   `policy.baseRates` key. NO effort classifier exists (toy table is
   jobType-only). Needs a NEW `effortRubric` PricingPolicy field
   (incl. operator HR capacity) + `categoryPath` ← jobType/
   subcategory→`policy.categoryModifiers` key (needs a category
   taxonomy) + `complexityHints[]` ← derived from `accessDifficulty`.
4. **(versioned decision-tree change) urgency presupposition** —
   job-type urgency priors that *escalate* (ask urgency early /
   force) or *relegate* (push down the ROM question sequence) the
   already-existing urgency question. This is a `THRESHOLDS`/
   decision-tree change → bumps `DECISION_TREE_VERSION` and trips the
   template-version.ts hash tripwire BY DESIGN (auditable).

**PricingPolicy schema extension P1b implies** (a `.v1`→`.v2` or
additive-optional decision — itself an A5 sub-ruling): add optional
`operatorHomePostcode`, `radiusBands` (→ suburbGroup),
`jobTypeUrgencyPriors` (→ decision-tree escalate/relegate),
`effortRubric` (incl. operator HR capacity), `categoryTaxonomy`
(jobType→categoryPath). The cell's `validatePolicyPayload` already
treats unknown branches leniently; additive-optional keeps P0/P1a
conformance green, but the projector/classifiers need the shapes
pinned before build.

**A5.P1b — concrete schema proposal, grounded in the handyman-
estimating research the operator supplied (vendored at
`docs/design/research/handyman-estimating-research.md`, 2026-05-17).** This converts the abstract "needs a ruling on the
shapes" into a ratifiable proposal. The report's core thesis maps 1:1
onto the existing ROM structure: *an estimate prices three things —
the visible task, the jobsite conditions, the business risk* ≡
`effortBand` (task) / `suburbGroup`+travel (site) / `complexityHints`
+contingency (risk). The report **validates the existing safe-default**
(no policy / unbounded uncertainty ⇒ formal quote, never fabricate a
fixed price) and **validates P1b part-1** (plumbing `urgency` through —
the report makes after-hours/emergency a first-class price axis).

Proposed additive-optional `oddjobz.pricing_policy.v1` fields (keeps
P0/P1a conformance green; lenient `validatePolicyPayload`):

- `serviceArea: { homePostcode: string; radiusBands: Array<{ maxKm:
  number; suburbGroup: string }>; outsideDeclines: boolean }` — the
  operator-home-postcode + radius → `suburbGroup` classifier input
  (report: travel recovered by zone/mileage/flat-trip; "outside
  service area ⇒ decline" already exists in `rom.ts` travelModifiers
  `decline:true`).
- `effortRubric` — structured map from the operator's rubric axes
  {technicalDifficulty, displacementOverTime, mass/density, access,
  risk, **hrCapacity**} → a `baseRates` band key. The report's
  lead+helper labor build + "what it costs to hire ≠ what it costs to
  sell a billable hour" backs a *loaded* band; **one-man-team**
  (hrCapacity) means any job needing a second person or >1 day routes
  to `requiresQuote` (the existing `multi_day`/
  `note:'requires_formal_quote'` branch — no new mechanism).
- `minimumCallout: { amount: number; label: string }` — report:
  minimum service call (~A$ equivalent) is standard on short jobs;
  currently unmodelled (baseRates only carry min/max).
- `urgencyModifiers: Record<string,{ premiumPct: number; label:
  string }>` — the price effect of `ROMInput.urgency` (now plumbed):
  report starting points **after-hours ≈ +25%**, **true emergency ≈
  +50% and/or higher trip minimum**; `emergency` also implies
  stabilization-first / staged scope (decision-tree, below).
- `contingencyBands: { repeatVisible; firstTimeVisible;
  moderateHidden; highUncertainty }` — report's certainty→contingency
  ladder: **0–5%** repeat+visible, **5–10%** first-time+visible,
  **10–20%** moderate hidden-condition, **20–30% OR switch to T&M /
  staged** at high uncertainty (the last band = route to formal quote,
  reusing the safe default — *not* a fabricated number).
- `materialsMarkup: { standardPct; specialOrderPct }` +
  `subcontractorCoordinationPct` — report: **10–20%** stock /
  **20–35%** special-order materials, **10–20%** sub-coordination.
  NOTE: `calculateROM` is band-based today (materials inside the
  band); these are *recorded for the agent/Pask + future itemised
  path*, not necessarily wired into v1 `calculateROM` arithmetic —
  flag, don't silently expand the calculator.
- `jobTypeUrgencyPriors` + `licensedTradeCategories` — the decision-
  tree inputs (below), not `calculateROM` inputs.

`orgMarkup.percent` (existing, 0–50) semantic note: the report frames
the operator target as a **gross margin** (`sell = loaded /
(1 − margin)`), recommending **40–55%** short / **30–45%** bundled —
*margin*, not *markup*. v1 keeps `orgMarkup` as a markup (no behaviour
change); the margin/markup distinction is recorded for the A5.P3
console copy + the agent-tuner so it isn't silently conflated.

**Decision-tree (`oddjobz.intake.decision-tree`, currently `2026-04`)
gaps the report exposes** — each is a *versioned* change that bumps
`DECISION_TREE_VERSION` and trips the template-version.ts hash
tripwire **by design** (auditable):
- legal-scope / licensed-trade screen *before* pricing (plumbing /
  electrical / gas → refer or quote-as-coordination). Partially
  present via `categoryModifiers` `note:'specialist'`; the report
  makes it a hard pre-pricing branch.
- scope-visibility screen → if not visible/measurable/repeatable,
  T&M / paid-diagnostic / not-to-exceed instead of a fixed ROM
  (maps to the existing `requiresQuote` route + a new "staged" wording).
- emergency / after-hours branch → `urgencyModifiers` premium +
  stabilization-first scope split.
- new-vs-repeat client → selects the `contingencyBands` entry.
- the existing hazard-keyword → `site_visit` branch (asbestos etc.)
  is *confirmed correct* by the report's lead/asbestos stop-and-screen
  ("cannot price past that uncertainty by eye").

**Localization caveat (load-bearing):** the report is US-centric
(BLS/SBA/IRS/OSHA/EPA/FTC, US$). The operator is **AU, Queensland,
one-man, prototype, no customers** (oddjobtodd.info; hipages A$55–A$85/
hr is the relevant benchmark; QBCC written-contract >A$3,300; licensed
plumbing/electrical regardless of price). The report itself says
*localize five things before a live price book*: licence scope, permit
exemptions, payment/deposit rules, tax treatment, waste-disposal
pricing. So the **structure** is adopted; the **numbers are AU-
calibrated starting defaults to be back-tested**, not US figures
copied in. Per "no hardcoded workarounds": these defaults ship as
operator-editable policy fields (A5.P3 console), never inlined
constants.

Build BLOCKED/parked: P1b parts 2–4 are substantive NEW design +
schema extension — the proposal above needs the operator's ruling on
(a) additive-optional `.v1` vs `.v2`, (b) the AU starting numbers, and
(c) the decision-tree version bump scope — before the projector/
classifiers + the decision-tree change are built. P1b part 1 (widen
EstimatorFn / forward suburb·postcode·urgency) is **SHIPPED**
(`17829dd`). The de-black-box arc
(Inc 1-3, shipped) + the brain loop are unaffected. P4.C submit
mechanism RESOLVED → option (ii)-pure (see DECISION-P4C above: the
decoupled sellable cartridge — cartridge ⟂ brain, operator ⟂
cartridge, one standardised cap-gated typed-cell store, PWA discovery
over WSS). Parked: jobs_store_lmdb + `.intake` RouteKind retirement.

## P3.5 — ACTIVATION COMPLETE (2026-05-18, operator-approved)

The env-gated-dormant seam is now **LIVE in production** (oddjobtodd.info).
Operator approval: explicit "activate" on the P3.5 redeploy checkpoint.

- **P3.5b** (done, `0871a19`): persistent agent child-cert minted in the
  LIVE brain cert store via `brain device pair` → `provision-agent-cert`
  on `/api/v1/device-pair`. Identifiers (not secrets):
  `ODDJOBZ_AGENT_HAT_ID=af90d1d61ae742839897e24cc59ce873`,
  `ODDJOBZ_AGENT_CERT_ID=bfe14fba2dea86f66bdc8d4b250ac900`.
- **REPL bearer**: issued into the **live running daemon's** TokenStore.
  Root-cause of the earlier `daemon_capability_denied RC=12`: the brain
  daemon runs as user `semantos` and its Unix control socket enforces a
  **peer-uid match** (`transport/unix_socket.zig` — SO_PEERCRED ==
  daemon uid ⇒ `in_process_root` scope; mismatch ⇒ capability_denied).
  The CLI must be invoked **as `semantos`** (`runuser -u semantos -- env
  BRAIN_DATA_DIR=/var/lib/semantos brain bearer issue …`). The raw token
  is shown once at issuance and is **never** written to git or any
  design doc — it lives only in the 0600 root systemd drop-in. Bearer
  sufficiency verified end-to-end: HTTP REPL bearer gate is the only
  auth check; `intent_cells.submit` then dispatches as
  `in_process_root` (cap-bypass), so `cap.oddjobz.write_customer` is
  satisfied structurally (no per-bearer scope needed).
- **Activation**: `/etc/systemd/system/semantos-shell.service.d/`
  `oddjobz-agent.conf` (0600 root, additive drop-in, rm-reversible)
  pins the 4 env vars (HAT_ID, CERT_ID, `ODDJOBZ_BRAIN_REPL_URL=
  https://oddjobtodd.info/api/v1/repl`, `ODDJOBZ_BRAIN_BEARER=<secret>`).
  `daemon-reload` → unit parses (env present, bearer masked) →
  `systemctl restart semantos-shell.service` (the explicit irreversible
  prod-brain restart; ~66s boot, came up HTTP 200, new MainPID, all 4
  vars confirmed live in `/proc/<pid>/environ`).
- **Rollback**: `rm oddjobz-agent.conf && systemctl daemon-reload &&
  systemctl restart semantos-shell.service` (returns to env-gated-
  dormant; the P3.5c bundle backup `intake-handler.js.bak-20260518-1505`
  is the deeper rollback). The seam is additive/best-effort by
  construction — a submit failure is logged + swallowed, the customer
  reply and the `persistLead` jsonl shadow are unaffected.
- **P3.5d (verification, in progress)**: a clean non-hazardous well-
  scoped intake driven to `estimatePresented` actuates `submitLeadCell`
  → `oddjobz.lead.v1` accept_rom cell + auto_rom Estimate in
  IntentCellLmdbStore under hat `af90d1d6…873`, lead→qualified. First
  attempts hit transient Anthropic `529 overloaded` on the intake LLM
  (haiku) — a fenced/material-condition job correctly took the
  `needs_site_visit` branch (seam gates out → jsonl shadow only, as
  designed). Re-driving a painting-class intake when the upstream LLM
  recovers; activation itself is complete and durable independent of
  this verification.

### P3.5d — VERIFIED + a bundled-loader bug fixed (`a20b0ae`)

**Bug found in prod (silent):** the first activated end-to-end run
completed the intake (jsonl shadow written, normal reply) but minted
**no cell**. The seam *was* firing — it threw
`ENOENT … /opt/semantos/dist/cell-engine.wasm` and the throw was
swallowed to the brain's **`.Ignore`'d** intake-handler stderr
(`intake_http.zig`: `child.stderr_behavior = .Ignore`). Root cause:
the bun loader resolves the kernel WASM from `PACKAGE_ROOT =
join(import.meta.dir,'..','..')`. Bundled into the deployed handler,
`import.meta.dir` is the *bundle* dir (`…/extensions/oddjobz`), so
`PACKAGE_ROOT` collapses to `/opt/semantos` and the
`dist/cell-engine.wasm` fallback ENOENTs. Fix (`a20b0ae`): the
`ODDJOBZ_CELL_ENGINE_WASM` env seam — explicit absolute WASM path when
set, loader self-resolution when unset (additive; unbundled/dev/tests
unchanged; **no hardcoded path in the cartridge**). Pinned in the
0600 drop-in to `/opt/semantos-core/core/cell-engine/zig-out/bin/
cell-engine.wasm`; bundle rebuilt via `build-oddjobz-bundle.sh`
(backup `…bak-20260518-1633`); brain restarted (PID 887465).

**Verified live (2026-05-18T06:36:03Z):** a painting-class intake
driven to `present_estimate` → `summarise_and_close` actuated the
seam — full `@semantos/intent` pipeline green
(`intent_extracted → sir_built → sir_lowered → ir_emitted →
script_executed kernelOk:true → cell_written → intent_completed
ok:true`), `submitLeadCell: {"submitted":true,"cellId":
"cell-000006-03010101-b14cdec3"}`. The cell is in the **live
IntentCellLmdbStore**: `hat_id=af90d1d6…873`,
`cert_id=bfe14fba…c900` (the P3.5b agent cert),
`correlation_id=p35d-v1779085390` (the chat session),
`intent_action=accept_rom`,
`taxonomy={"what":"oddjobz.lead.v1","how":"oddjobz.accept_rom",
"why":"chat-intake"}`, `kernel_ok=true`. **The chat-intake →
standardised-store seam (DECISION-P4C / Phase-3) is DONE and proven
on production.**

**Boundary surfaced (modeling fact, not a regression):**
`intent_action_router` maps `accept_rom → qualified` by *transitioning
an EXISTING job* in the `oddjobz.jobs` FSM (`intent_action_router.zig`
L123; L510 "Cold-boot defence: zero jobs → nothing to match"). The
jobs store is empty (`find jobs` ⇒ `[]`), so the router correctly
no-ops — `lead→qualified` presupposes a job-creation / lead-propose
path that is **explicitly deferred** (post Slice-3b / SD2; see the
P3.5a gating note above — `AccumulatedJobState` carries no structured
job identity). So P3.5d's *in-scope* deliverable (oddjobz.lead.v1
accept_rom cell in IntentCellLmdbStore via the live seam, agent-cert
signed) is fully met; the end-to-end `lead→qualified` FSM closure is
gated on that deferred modeling, NOT on this seam. Bulldozing a
synthetic job-creation here would violate the deferred-modeling
decision + "no hardcoded workarounds" — surfaced, not guessed.

**Follow-up — RESOLVED (this change):** `intake_http.zig` `callScript`
previously set `child.stderr_behavior = .Ignore`, silently discarding
ALL intake-handler stderr — it hid the ENOENT above for an entire
session. Now `.Inherit`: stdout stays the wire protocol (JSON
`{reply,action,done}`), and the handler's best-effort diagnostics —
`submitLeadCell` success/diagnostic line, `recordIntakeTurn`/
`persistLead`/seam failures — flow to the brain's stderr and thus the
systemd journal (`journalctl -u semantos-shell.service`). `.Inherit`
(vs `.Pipe`) needs no draining, so it cannot deadlock against the
bounded 128 KB stdout read loop. Brain-code + binary-redeploy; verified
by driving a completed /api/chat intake and confirming the
`submitLeadCell: {...}` line appears in the journal.

## U2 — gmail/meta ingest convergence: GROUNDED, gated on an operator decision (2026-05-18)

P3.5 proved the chat→standardised-store seam live. U2 is "gmail/meta
ingest converges on the **same** seam." Grounding the existing code
surfaced that this is a substantive decision + a live-pipeline change,
**not** a P3.5a-style additive increment — so it is surfaced, per the
loop stop-conditions, not bulldozed.

**The two seams are architecturally distinct, both live:**
- **Chat (P3.5, just shipped):** `submitLeadCell` → `@semantos/intent`
  pipeline → envelope → `submit-intent-cell` over **`/api/v1/repl`**
  → `intent_cells` resource → `intent_action_router` →
  **`IntentCellLmdbStore`** (accept_rom / `oddjobz.lead.v1`).
- **Gmail/Meta (legacy-ingest, already live on rbs — the operator's
  business pipeline):** `runtime/legacy-ingest/` (Gmail provider,
  OAuth, extractor, role-classifier, ratification) → `cell-writer/
  brain-rpc.ts` `writeCell` → JSON-RPC method **`oddjobz.ratify_
  proposal`** over **`/api/v1/wallet`** WSS → `substrate_entity.zig`
  `entity.encode` (DECISION-10 / D-RTC.4) → a *different* island.
  Deployed at `/opt/semantos*/runtime/legacy-ingest` (semantos-owned;
  journal shows live legacy-ingest/reingest/entity.encode activity).

**Why U2 is not a clean additive next step (three real gates):**
1. **Substantive NEW architecture decision.** Convergence means
   choosing: retire the legacy-ingest `oddjobz.ratify_proposal` /
   `substrate_entity` minting for leads in favour of
   `intent_cells.submit`; OR dual-write/bridge during a migration;
   AND which store is canonical; AND what happens to the existing
   live gmail data island. That is the "next epic" decomposition the
   doc already refuses to bulldoze (store-tenancy partitioning,
   operator-cert binding, WSS contract).
2. **V1 / live behaviour change.** legacy-ingest IS the deployed
   gmail/meta business pipeline; redirecting its sink is a live
   data-path change → the standing operator-approved-redeploy gate
   (the doc already flags "the gmail/meta business pipeline" downtime
   as operator-gated).
3. **Gated on the deferred SD2 plain-lead-propose modeling.** The
   proven seam mints only on `accept_rom` (an estimate/ROM was
   presented — the money channel). Gmail/Meta inbound leads carry **no
   presented ROM**, so they hit the *exact* plain-`oddjobz.lead.v1`
   lead-propose modeling that is explicitly deferred (post Slice-3b /
   SD2) — the same boundary as chat-no-estimate (see P3.5d boundary
   note). An additive "ROM-carrying ingest lead → submitLeadCell"
   adapter would cover ≈0 real inbound leads (over-engineering for
   no coverage); the real convergence *needs* SD2.

**Status: U2 BLOCKED pending an operator decision** on (a) the
plain-lead-propose cell modeling (SD2 — unblocks chat-no-estimate AND
all gmail/meta inbound, the shared root), and (b) the legacy-ingest
seam **retire-vs-bridge** architecture + canonical-store choice for
the live gmail pipeline. P3.1–P3.5 remain complete + verified-live;
U3 (PWA WSS read) and U4 (multi-tenant) also reuse the same seam and
inherit (a). Surfaced, not guessed — consistent with the P3.3 / P3.5
stop discipline.

## SD2 — RESOLVED (operator, 2026-05-18): lead-on-contact, ROM-optional + a lead→authorized edge

Operator decision: **(a)** mint a lead on EVERY completed contact, ROM
optional ("anyone touching our system is a lead"); **(b)** ingested
work-orders skip straight to approved via a NEW `lead→authorized`
job-FSM edge ("everything starts as a lead" stays uniform).

**Grounded mechanism (no guesses — all located):**
- The Job FSM (`extensions/oddjobz/zig/src/job_fsm.zig`) genesis
  `∅→lead` is `jobs.create`; the router NEVER creates, only
  *transitions*. `jobs.create` REPL verb: `add job "<name>" <state>`
  → `oddjobz_cmds.zig:cmdJobsCreate` → `jobs.create
  {customer_name,state}` (no id ⇒ store-generated; **NOT** dedup'd by
  name). `splitArgs` (`repl.zig:697`) DOES group `"…"` (spaces
  preserved, quotes stripped) so a multi-word name is one arg.
- `dispatchJobs` runs `.auth=.in_process_root` (cap bypass, exactly
  like `dispatchIntentCells`) ⇒ the already-pinned REPL bearer
  satisfies `jobs.create`'s `cap.oddjobz.write_customer` structurally.
- `intent_action_router.findSingleMatchingJob`: tokenises the cell
  `intent_summary` (lowercased, tokens ≥ `DEFAULT_MIN_TOKEN_LEN=4`),
  matches a token as a **substring of a job's `customer_name`**;
  multi-match ⇒ most-recently-created wins (W4.1, not a skip). The
  shipped `submit-lead-cell.ts` summary is `"<jobType> — <scope>"`
  with **no name** ⇒ today it could never match a job. THE
  correlation fix.

**Architecture — edge-only, DECISION-P4C-pure (no brain/Zig change for
incr.1; bundle-redeploy only, no brain restart):**
- **incr.1 (TS, this unit):** on completed contact, exactly-once per
  session (a persisted `leadJobCreated` flag on `AccumulatedJobState`,
  because a conversation can emit `done:true` on multiple turns and
  `add job` is not idempotent), POST `add job "<sanitised
  customerName>" lead` to `/api/v1/repl` with the pinned bearer →
  the job is born in `lead`. Best-effort/additive (mirrors the
  `submitLeadCell` try/catch — never regresses the reply or the
  jsonl shadow). Amend the `submitLeadCell` summary to prepend
  `customerName` so the router correlates the `accept_rom` cell to
  the just-created job and flips `lead→qualified`. Net: every
  completed contact ⇒ a `lead` job; ROM ⇒ additionally
  `qualified`. The brain stays generic (only the shipped
  `jobs.create` + `intent_cells.submit` + the existing router);
  deps-injected so it's worktree-unit-tested, ZERO live.
- **incr.2 (Zig, gated — separate increment):** add the
  `.from="lead" .to="authorized"` `Transition` to `job_fsm.zig`
  (+ its TS mirror + any TLA+/Lean FSM proof) for the work-order
  path. Proofs-sensitive + brain-binary redeploy ⇒ done after
  incr.1 is proven, and it pairs with the ingest quote-request-vs-
  work-order classifier (U2 territory). Not bundled into incr.1.

leads.jsonl stays the transitional shadow until the store is verified.
Same staged, coupling-honored, surfaced-not-bulldozed discipline as
P3.5.

## ⚠ CRITICAL — SELF-CALL DEADLOCK (live outage 2026-05-18, recovered); the seam is BLOCKED on an architecture fix

**What happened.** SD2 incr.1's gated live redeploy (bundle only,
operator-approved) was followed by a full outage of oddjobtodd.info —
ALL brain HTTP endpoints (`/`, `/api/chat`, `/api/v1/repl`) hung
(curl 000), the brain process `active/running` (no crash, NRestarts=0)
but wedged: parent `wchan=pipe_read`, 3 threads, sleeping, with stuck
spawned `intake-handler` children.

**Root cause (definitive, NOT an SD2 logic bug).** `intake_http.zig`
`callScript` spawns the bun intake child and **synchronously blocks
reading the child's stdout to completion** before responding
(`wchan=pipe_read`). On `done` the child calls `ensureLeadJob` +
`submitLeadCell`, which POST to `ODDJOBZ_BRAIN_REPL_URL=
https://oddjobtodd.info/api/v1/repl` — i.e. **back into the very brain
that is blocked reading the child**. Circular wait → deadlock → the
request thread wedges → every endpoint hangs. SD2's unit logic is
correct (11/11 + 229/229 green); the failure is purely this transport
topology.

**Pre-dates SD2.** First `submitLeadCell error: The operation timed
out` was 17:17:48 on the OLD P3.5 bundle under a parallel session's
load — *before* the 17:21 SD2 install. P3.5's `submitLeadCell` already
self-calls; "P3.5d verified" (06:36) only worked because of zero
concurrency — it was always a race. SD2's `ensureLeadJob` adds a
SECOND synchronous self-call per contact, raising the deadlock
probability: SD2 **exposed**, did not cause, a pre-existing P3.x
architectural defect. **A loopback URL alone does NOT fix it** — the
deadlock is brain-blocked-on-child while child-waits-on-brain, same
process regardless of URL/TLS.

**Recovery (operator-approved, applied, verified).** The 0600 drop-in's
`ODDJOBZ_BRAIN_REPL_URL` + `ODDJOBZ_BRAIN_BEARER` were commented out
(dated `# DISABLED` marker, bearer preserved for re-enable), `daemon-
reload`, brain restarted (MainPID 905696). The intake-handler env-gate
(`if (replUrl && bearer)`) now short-circuits ⇒ BOTH `ensureLeadJob`
and `submitLeadCell` skip ⇒ no self-call ⇒ no deadlock. Verified: public
+ loopback 200, real chat reply, `/api/v1/repl` 401 in 55 ms (responds,
not hung), brain `wchan=do_poll` (normal). Bot is back to the known-
good jsonl-shadow behaviour; no data loss (the shadow still captures
leads). SD2 incr.1 code stays committed (`27faec8`) but **dormant**.

**STATUS: the whole chat→store seam (P3.5 submitLeadCell AND SD2
ensureLeadJob) is BLOCKED, live, on a substantive NEW architecture
decision** — surfaced, not bulldozed. The brain-spawned intake child
must not synchronously call back into the brain that is blocking on
its stdout. Fix directions (operator decision required):
1. **Brain reads child stdout async / on a worker thread** so it can
   concurrently service the child's REPL callback (`intake_http.zig`
   — Zig + brain-binary redeploy; proofs-neutral but coupling-heavy).
2. **Decouple the submit from the request.** The child writes the
   lead/job intent locally (file/queue); a separate async drainer
   (or the brain post-response, out of the pipe_read path) performs
   the cap-gated submit. No synchronous self-call (edge + brain).
3. **Async fire-and-forget with a hard sub-second timeout** in the
   child so it ALWAYS closes stdout promptly — bounds, does not
   remove, the coupling (the work still races the timeout); a
   mitigation, not a fix.
Loopback `ODDJOBZ_BRAIN_REPL_URL=http://127.0.0.1:8080/...` is a
necessary hygiene change (no public-TLS round-trip for an internal
call) but is INSUFFICIENT alone. The decision is which of (1)/(2)/(3),
and it is a brain-architecture change → gated, not guessed.

### Operator chose (1) async — grounded shape + a material risk the menu under-stated

Operator picked option (1) ("async stdout read in the brain"). Grounding
the brain reveals (1)'s true shape and a risk the menu under-described:

- The brain HTTP server is a **deliberately single-threaded poll
  reactor** (`event_loop.zig`, `site_server.zig:serve`), introduced by
  the **"Bridget wedge" rip-out (2026-05-07)** precisely *because*
  concurrency there caused a wedge. `event_loop.zig` documents
  `WORKER POOL (not in v1)` + `TODO-WORKER-POOL` as an explicit
  **unimplemented seam**.
- `site_server/reactor.zig:901` calls `intake_http.callScript`
  **synchronously on the single reactor thread**. While it runs
  (spawn bun → block in `pipe_read` on child stdout) the *entire
  reactor* cannot poll/accept — so the child's re-entrant
  `/api/v1/repl` is never even accepted ⇒ the deadlock. "Async stdout
  read" therefore is NOT a localized `intake_http.zig` tweak: it
  requires **implementing the unbuilt TODO-WORKER-POOL seam** —
  offload `callScript` to a worker thread + hand the connection/
  response back to the reactor (self-pipe/eventfd registered in the
  poll set). That is a core-reactor concurrency feature with
  connection-ownership + poll-set-race correctness hazards, landing
  on the exact single-threaded design chosen to fix a prior wedge.
  Material V1/live-stability risk; brain-binary redeploy; the kind of
  change that must be designed + operator-confirmed, not bulldozed.
- **Lower-risk alternative — reactor untouched (edge-only):** the
  deadlock is purely the *synchronous self-call from the spawned
  child while the brain blocks on it*. NB the brain blocks in BOTH
  `callScript`'s stdout read loop AND the following `child.wait()`,
  so merely closing stdout early just moves the block from
  `pipe_read` to `wait()` — insufficient. The sound reactor-untouched
  fix: the intake child writes its stdout JSON and **exits
  immediately**, having handed the cap-gated submit to a **detached
  grandchild** (double-fork → reparented to init) that performs
  `ensureLeadJob`/`submitLeadCell` against the **loopback** REPL
  out-of-band. The brain's `read`+`wait()` both complete promptly
  (child already exited) ⇒ the reactor is free before the detached
  submit lands ⇒ no cycle. EDGE-only (intake-handler spawns a
  detached submitter, logs its diagnostics to a file since its stderr
  no longer rides the brain journal) + loopback URL hygiene; NO
  brain-reactor change; far lower V1-stability risk; same
  no-self-call-deadlock outcome. This is option (2) in minimal form
  (decouple via a detached process, no durable queue/drainer).

STATUS: surfaced for operator confirmation — implement the true (1)
(core-reactor worker-offload, higher risk, the documented seam) vs the
reactor-untouched respond-then-submit + loopback (lower risk, edge-only,
same no-self-call-deadlock outcome). Bot remains safe + dormant
meanwhile. Not bulldozed.

### RESOLVED + LIVE — reactor-untouched detached submitter (operator chose; `46551bf`, re-enabled 2026-05-18)

Operator chose the reactor-untouched path. Implemented (`46551bf`,
edge-only, NO brain-reactor change): `intake-handler.ts` writes its
reply and spawns a DETACHED grandchild — the SAME bundle invoked
`--detached-submit <payload>` — with `detached:true` +
`stdio:'ignore'` + `unref()`, then exits. The grandchild reparents to
init and holds no stdout pipe, so the brain's read EOFs and
`child.wait()` returns at once ⇒ the single-threaded reactor is freed
BEFORE the submit lands ⇒ no cycle. The grandchild runs the unchanged
`ensureLeadJob` + `submitLeadCell` out-of-band on the **loopback**
REPL (`ODDJOBZ_BRAIN_REPL_URL=http://127.0.0.1:8080/api/v1/repl`,
re-enabled in the 0600 drop-in), logging to `<oddjobz>/submit.log`
(its stderr is `/dev/null`'d by the parent's `stdio:'ignore'`).

**Verified LIVE on production (2026-05-18, gated op-approved
re-enable):** a completed gutter-clean contact (ROM shown) →
`submit.log`: `ensureLeadJob {created:true … status:"created"}`,
2nd done-turn `ensureLeadJob {skipped:"already_created"}`
(exactly-once guard via read-modify-write flag works),
`submitLeadCell {submitted:true, cellId:…}`. `find jobs` →
**`Derek Stone -> qualified`**: the job born in `lead` by
`ensureLeadJob`, flipped to `qualified` by `intent_action_router` via
the name-correlated `accept_rom` cell (the SD2 summary fix). **The
full `contact → lead → qualified` lifecycle now works end-to-end on
the live system.** Deadlock FIXED: endpoints stayed HTTP 200 through
completed contacts, brain `wchan=do_poll` (never `pipe_read`), no
stuck children. P3.5 `submitLeadCell` self-call is fixed by the same
mechanism. `leads.jsonl` remains the transitional shadow.

Net: every completed chat contact on oddjobtodd.info is now a
durable `oddjobz.lead.v1` lead in the standardised store (ROM-ratified
⇒ `qualified`), via the agent's own cert, with the brain generic and
the single-threaded reactor untouched. SD2 incr.1 COMPLETE + LIVE.
Remaining: SD2 incr.2 (the decided `lead→authorized` `job_fsm` edge +
TS mirror + FSM proof for the work-order path — the heavier
proofs-sensitive Zig/brain-binary increment, pairs with the U2 ingest
quote-vs-WO classifier).

### SD2 incr.2 — GROUNDED, BLOCKED on two surfaced facts (2026-05-18, read-only)

Grounding the proof + impl surface before any change surfaced two
load-bearing facts; incr.2 is held, not bulldozed.

**1. The Lean JobFSM proof is ALREADY STALE vs the shipped FSM
(pre-existing, NOT caused by this work).**
- `proofs/lean/.../StateMachines/JobFSM.lean` hardcodes the table
  "verbatim" as a **7-row / 8-state linear** FSM:
  `lead→quoted→scheduled→inProgress→completed→invoiced→paid→closed`,
  with `theorem jobTransitions_length = 7` and closed-world totality
  theorems (`findRow_none_lead_to_scheduled`, …). It has **no
  `qualified`, no `authorized`, no `visit_*`**.
- Shipped `extensions/oddjobz/zig/src/job_fsm.zig` (`JOB_TRANSITIONS`,
  20 rows / 13 states) and its TS mirror
  `extensions/oddjobz/src/state-machines/job-fsm.ts` are the
  **13-state remodel** (`lead→qualified ┬→ visit_* / quoted /
  └→ authorized`) and are **mutually in sync**.
- **No conformance/vector binding** ties JobFSM.lean to the impl
  (`proofs/vectors`, `compliance-matrix.json` — no jobTransitions/
  JobFSM ref). So the Lean proof is divorced from the shipped FSM by
  an entire remodel: it proves properties of a table the code no
  longer has. The operator's "don't break Lean/TLA+" intent is
  intersected by the fact it is **already not a faithful model** —
  this is a proofs-integrity decision (realign JobFSM.lean to the
  13-state table = substantive proof-engineering; vs formally
  accept+document the divergence; vs a vector-bound regen) for the
  proofs-owner/operator, NOT to be guessed or silently rewritten.
  Adding `lead→authorized` is proof-NEUTRAL to the *current* (stale)
  Lean proof (it models neither state) but widens the gap.

**2. incr.2's edge is DEAD CODE until U2's ingest classifier
exists.** `lead→authorized` only fires when something emits a
`work_order`/`authorize` action for a `lead` job. The chat seam never
does (chat = quote-request → `accept_rom`); only an **ingested
work-order document** would. That classifier is U2 territory, and U2
is gated on the still-open operator legacy-ingest **retire-vs-bridge**
decision (dismissed earlier). Building the edge now ships unreachable
code before its only driver — premature; sequence-coupled to U2.

The edge change itself is mechanically tiny (one `Transition` row in
`job_fsm.zig` mirroring `qualified→authorized`
{`cap_required=null, principal_kinds={.operator}`} + the TS-mirror
row) and a brain-binary redeploy — but it should land WITH its U2
driver and ALONGSIDE the proofs-integrity ruling, not as orphaned
proof-diverging dead code. Surfaced for operator decision; SD2 incr.1
remains COMPLETE + LIVE meanwhile.

### U2 legacy-seam — GROUNDED for the retire-vs-bridge decision (operator: make this call, 2026-05-18)

Operator chose to make the U2 legacy-ingest seam decision. Grounding
(read-only) changed the risk calculus that earlier made *bridge* look
safer:

- **legacy-ingest is fully DORMANT on rbs.** No running worker
  (`pgrep` — none), **no systemd unit** (`/etc/systemd/system` — none),
  view-stores `/var/lib/semantos/oddjobz/{customers,jobs}.jsonl` last
  modified **May 7** (11 days stale). It is manual CLI tooling with
  historical TEST data, **not a live production service**. The
  "disrupt the live gmail/meta business pipeline" risk that argued for
  bridge was an assumption; grounding disproves it (consistent with
  the standing "V1 on rbs is test data; gmail reingest pending; don't
  over-engineer V1-preserve" guidance).
- **Distinct seams/representations.** legacy-ingest:
  Gmail/Meta → extractor → role-classifier → **Proposal → human
  ratification queue** → `RatificationOrchestrator.writeCell` →
  JSON-RPC `oddjobz.ratify_proposal` over WSS `/api/v1/wallet` →
  brain → **JSONL view-stores** (sites/customers/jobs.jsonl), the
  D-RTC.4/substrate_entity island. P3.5/SD2: `intent_cells.submit`
  (REPL) → `intent_action_router` → `IntentCellLmdbStore` + the jobs
  FSM (SD2 incr.1 adds `jobs.create`-in-`lead`).
- **Convergence is a focused rewire of ONE seam.** Only
  legacy-ingest's terminal `RatificationOrchestrator.opts.writeCell`
  changes — from `oddjobz.ratify_proposal` to the proven
  `ensureLeadJob`+`submitLeadCell` (detached-submitter) path. The
  extractor / role-classifier / Proposal / ratification-queue stay.
  **No data migration** (test-data island; per standing guidance).

**Conclusion surfaced (not auto-decided): RETIRE is now the lower-risk
AND cleaner choice** — bridge's safety rationale (protect a live
pipeline) is void because the pipeline isn't live; dual-write would be
complexity to preserve dormant test tooling (explicitly the
over-engineering the memory warns against). One genuine *forward*
sub-decision rides along, for the operator: gmail/meta leads currently
pass a **human ratification gate** before `writeCell`; chat (SD2) does
NOT (every contact auto-becomes a lead). Converge with the human gate
PRESERVED (ingested lead → on human-accept → proven seam) or DROPPED
(ingest auto-creates leads like chat, ratification post-hoc)? That is
product semantics, surfaced — not guessed.

### U2 — DECIDED (operator 2026-05-18): RETIRE + DROP gate. Locked build plan.

Operator: **retire** (rewire legacy-ingest's terminal `writeCell` to
the proven seam) + **drop the human ratification gate** (gmail/meta
auto-create leads, uniform with chat SD2 incr.1).

**Grounded integration point (zero re-grounding needed):**
- `RatificationOrchestrator.opts.writeCell: CellWriterFn` is already
  deps-injected (`ratification/orchestrator.ts:191`,
  `completeRatification`). Retire = supply a NEW `CellWriterFn`,
  swapping `cell-writer/brain-rpc.ts` (`oddjobz.ratify_proposal`/WSS/
  JSONL island) — no orchestrator logic change.
- Gate drop: `orchestrator.bulkRatify({minConfidence})` ALREADY runs
  the gateless `auto-ratified` path (`orchestrator.ts:123,138` →
  `completeRatification(..., 'auto-ratified')`). No orchestrator code
  change; it's an invocation/config choice (ingest uses bulkRatify).
- `Proposal` (`extractor/types.ts:42`) fields for the lead map:
  `proposalId` (stable → correlationId/dedup, the chat `session_id`
  analogue), `confidence` (≥0.85 auto-ratify), `pointOfContact?`
  (display identity → `customer_name`; fallback `primaryContact?.name`
  then the legacy customer_name heuristic), `provenance`
  (providerId/providerItemId). The `program: SIRProgram` is NOT
  needed for the lead (ensureLeadJob only needs the name; the job is
  born in `lead`, no kernel-lowering — same as chat-no-estimate).
  `workOrderNumber`/`referenceNumber` are the future incr.2
  work-order→authorized signal (NOT this increment).

**Build plan (verified-increment, coupling-honored, edge-only TS, NO
brain change; legacy-ingest is standalone tooling — NOT a brain-
spawned child, so the self-call deadlock does NOT apply: it calls the
loopback REPL synchronously, no detached-submitter needed):**
1. Additive refactor of the proven `extensions/oddjobz/src/
   conversation/ensure-lead-job.ts`: extract an exported
   `ensureLeadJobForName(name, alreadyCreated, deps)` core;
   `ensureLeadJob(state, deps)` becomes a thin wrapper (ZERO chat
   behaviour change; the 11/11 tests must stay green).
2. New `runtime/legacy-ingest/src/cell-writer/converged-seam.ts`: a
   `CellWriterFn` that derives `customerName` from the Proposal
   (`pointOfContact ?? primaryContact?.name ?? heuristic`), calls
   `ensureLeadJobForName` on the LOOPBACK REPL (env-injected
   replUrl/bearer, deps-injected fetch ⇒ unit-tested, ZERO live),
   returns the job/cell id for the `RatificationReceipt`. No
   `submitLeadCell` (ingest has no ROM ⇒ accept_rom gated out, exactly
   like chat-no-estimate — the job in `lead` IS the converged
   outcome).
3. Wire it at the legacy-ingest construction site (`index.ts`,
   the brain-rpc `CellWriter` build) — env-gated: configured env ⇒
   converged writer; absent ⇒ dormant/no-op (no regression).
4. Unit tests (deps-injected, worktree-runnable) + verify in the
   isolated bun rbs context; commit/push origin/main. legacy-ingest
   is dormant tooling ⇒ NO gated live redeploy needed for this
   increment (it actuates only when the operator next runs ingest).

**STATUS: U2 converged-seam DONE (`77688dd`, verified zero-live).**
builds 1–4 shipped: `ensureLeadJobForName` extraction (chat unchanged,
11/11 green), `cell-writer/converged-seam.ts`
(`makeConvergedSeamCellWriter`, 7/7), barrel export. Verified in the
isolated bun rbs context; rbs source synced. NOT yet actuating: the
**consumer-side writer SELECTION** (which `CellWriterFn` the
`RatificationOrchestrator` is constructed with) is NOT in
services/brain — legacy-ingest is dormant manual tooling, so the
orchestrator is wired by whatever invokes `legacy ratify`/`bulkRatify`.
Per the no-bulldoze rule that selection (one-line: pass
`makeConvergedSeamCellWriter({replUrl,bearer})` instead of
`BrainRpcCellWriter` at the operator's ingest entrypoint, env-gated)
is the operator's ingest-invocation wiring — surfaced, not guessed; it
actuates the next time ingest is run with the converged writer
selected. Remaining: SD2 incr.2 (`lead→authorized`) + the
`JobFSM.lean` proof-drift ruling — both gated, already surfaced.

### SD2 incr.2 — proof-impact RESOLVED (read-only, 2026-05-18); hard checkpoint surfaced

Grounding the proof ENFORCEMENT (not just the table) settles the
"break Lean/TLA+?" question precisely:
- **`JobFSM.lean` is unenforced.** No `lakefile`/`*.toml`/`Makefile`/
  CI workflow references `proofs/lean` or `lake build`;
  `compliance-matrix.json` has no JobFSM/`JOB_TRANSITIONS` binding;
  no `proofs/vectors` tie. It is an inert doc artifact, already
  drifted (7-row/8-state vs the shipped 13-state Zig+TS).
- **Theorem 1 (`job_fsm_transitions_total`) + the negative
  `findRow_none_*` theorems operate ONLY on the Lean-internal
  7-row `jobTransitions` list.** They never reference the Zig
  `JOB_TRANSITIONS` or the TS mirror. **No mechanism can make a Zig
  edge addition "break" the Lean proof** — it still compiles/holds
  about its own list.
- ∴ **SD2 incr.2 (`lead→authorized`) is PROOF-NEUTRAL** to Lean/TLA+
  as enforced (TLA+ has no JobFSM at all; only `MeteringFSM.tla`).
  The operator "don't break Lean/TLA+" constraint is satisfied. The
  honest caveat: the proof gives ZERO assurance about the shipped
  13-state FSM regardless — the realign-vs-accept `JobFSM.lean` drift
  is a SEPARATE pre-existing proofs-integrity decision (surfaced
  `023b22d`), neither caused nor worsened by incr.2.

**incr.2 mechanical shape (tiny, located):** one `Transition` row in
`extensions/oddjobz/zig/src/job_fsm.zig` `JOB_TRANSITIONS` —
`{ .from="lead", .to="authorized", .cap_required=null,
.principal_kinds=&[_]PrincipalKind{.operator} }` (a verbatim mirror of
the existing `qualified→authorized` row L139-142) + the analogous row
in the TS mirror `extensions/oddjobz/src/state-machines/job-fsm.ts`
`JOB_TRANSITIONS`. `intent_action_router.zig` already maps
`work_order`/`authorize`/`pre_authorized`/`no_quote` → `authorized`
and delegates eligibility to `job_fsm.findTransition`, so the FSM row
is sufficient for the router to permit `lead→authorized` once a
`work_order` action arrives.

**The two real gates (NOT proof, NOT mechanics):**
1. **No driver.** Nothing emits `work_order` for a `lead`. The
   shipped U2 converged-seam (`77688dd`) is the operator-decided
   UNIFORM lead-on-contact path (every ingested proposal → `lead`,
   NO quote-vs-WO classifier). So incr.2's edge is unreachable until
   a work-order classifier is added to the ingest path — a separate,
   larger increment than the FSM row.
2. **Gated brain-binary redeploy.** A Zig change ⇒ rebuild + the
   standing operator-approved brain-binary redeploy (heaviest
   coupling) — for currently-unreachable behaviour unless (1) lands
   too.

Surfaced for the operator's hard-checkpoint call (build edge-only now
as forward track w/ a redeploy for dead code, vs edge+classifier
together, vs defer until the classifier is scoped, vs pair with the
JobFSM.lean realign). NOT bulldozed; SD2 incr.1 + U2 converged-seam
remain DONE.

### SD2 incr.2 — DECIDED (operator: edge + WO-classifier together). Locked, fully-grounded build plan.

Operator chose **edge + classifier together** (proof-neutral, real
driver, one redeploy). Binding fully grounded — zero re-grounding:

- **The classifier signal is the SIRProgram node `action`** (the
  `Proposal` carries NO `job_type` field).
  `email.ts:mapJobTypeToAction`: `quote_request→create_quote_request`,
  `work_order→create_work_order`,
  `maintenance_order→create_maintenance_order`. `brain-rpc.ts`
  L528-535 is the proven access pattern: iterate
  `program.nodes[]`, read `node.action: string`.
- **Routing:** `{create_work_order, create_maintenance_order}` →
  drive `lead→authorized` (operator has been *assigned* the job,
  no customer quote owed — the REA/PM WO case); `create_quote_request`
  → stay `lead` (customer asking for a price — qualify/quote as
  today). Matches the operator "work-order vs quote-request" intent.
- **FSM transition verb:** `transition job <id> <to_state>`
  (`repl.zig:767`, `cmdJobsTransitionGeneric`, dispatched
  `.in_process_root` ⇒ pinned bearer satisfies it). `add job`
  returns `{id,status}` so the converged writer parses `id` for the
  follow-on transition.

**Build (verified-increment; the Zig row ⇒ a GATED brain-binary
redeploy, the heaviest coupling — operator-approved redeploy is a
SEPARATE step after zero-live verification):**
1. **Zig** `extensions/oddjobz/zig/src/job_fsm.zig` `JOB_TRANSITIONS`:
   add `{ .from="lead", .to="authorized", .cap_required=null,
   .principal_kinds=&[_]PrincipalKind{.operator} }` — verbatim mirror
   of the `qualified→authorized` row (L139-142). `zig build test`
   green (proof-NEUTRAL per the resolved finding above).
2. **TS mirror** `extensions/oddjobz/src/state-machines/job-fsm.ts`
   `JOB_TRANSITIONS`: the analogous `lead→authorized` row (match the
   `qualified→authorized` cap/principal). Keep Zig↔TS in sync (the
   shipped contract; JobFSM.lean is the inert stale one, untouched —
   its realign is the separate pre-existing ruling).
3. **Classifier** in `cell-writer/converged-seam.ts`: add
   `proposalJobAction(proposal)` (first `program.nodes[].action`
   string); after the genesis `add job "<name>" lead` parse `id`
   from the `{id,status}` JSON; if action ∈
   {create_work_order, create_maintenance_order} → POST
   `transition job <id> authorized` on the same loopback REPL
   (best-effort/surfaced like the create; throw ⇒ orchestrator
   `cell_write_error`). quote_request ⇒ no transition (today's
   behaviour).
4. Unit tests (deps-injected): classifier routes WO→transition,
   quote→none, id-parse, transition failure surfaced; + the FSM
   edge (zig build test + the TS-mirror conformance test). Verify
   in the isolated bun rbs ctx + `zig build test`. Commit/push
   origin/main. THEN surface the gated brain-binary redeploy
   checkpoint (incr.1-class: build-oddjobz-bundle is NOT enough —
   job_fsm.zig is in the brain binary ⇒ deploy-rbs.sh path).

### SD2 incr.2 — CODE COMPLETE + FULLY VERIFIED ZERO-LIVE (a34b082); gated redeploy surfaced

Built + verified (commits 88a783d, a34b082):
- **Zig** `job_fsm.zig` `lead→authorized` row (verbatim mirror of
  `qualified→authorized`), count 14→15, row-1 assertions, AND the
  necessary update of the pre-existing negative assertion
  `findTransition("lead","authorized")==null` (the *expected direct
  corollary* of the operator-approved edge — NOT stale drift; positive
  coverage retained). **`zig test job_fsm.zig` → 11/11 pass** on the
  git-synced rbs source.
- **TS mirror** `job-fsm.ts` row in declaration-order lockstep +
  focused `lead-authorized-edge.test.ts`; **converged-seam**
  WO-classifier (`proposalJobAction` reads the SIRProgram node action;
  `create_work_order`/`create_maintenance_order` ⇒ post
  `transition job <id> authorized`; `create_quote_request`/none ⇒
  stay `lead`). **18/18 in the isolated bun rbs ctx.**
- **Production build verified:** `zig build -Dcpu=baseline` (the
  exact `deploy-rbs.sh` step-2 invocation; `-Dcpu=baseline` is the
  documented workaround for the rbs-VM `athlon-xp` CPU-misdetection —
  a KNOWN quirk, NOT new breakage; bare `zig build`/`zig build test`
  fails without it, which is why the full test-suite gate is
  pre-existing-broken on rbs — orthogonal to this pure-Zig change)
  **succeeds clean** with the change. ZERO live (no install/swap).
- **Proof-NEUTRAL** (JobFSM.lean unenforced+stale; TLA+ has no
  JobFSM). The §O4 TS table-shape 4-fail + JobFSM.lean drift remain
  the SEPARATE pre-existing surfaced realign-vs-accept ruling — incr.2
  kept orthogonal (a focused new test, no rewrite of the stale block).

**GATED — brain-binary redeploy checkpoint (operator-approved, NOT
auto-run).** `job_fsm.zig` is compiled into the brain binary ⇒ the
heavy `deploy-rbs.sh` path (rebuild + binary swap + brain restart),
NOT `build-oddjobz-bundle.sh`. Risk profile for the operator: the new
`lead→authorized` edge is **inert for the live chat path** (chat never
emits a `work_order`/`authorize` action — it's `accept_rom`→qualified;
the edge only actuates when the converged-seam ingest writer processes
a WO/maintenance proposal, and legacy-ingest is dormant). So the
redeploy makes the edge *available* with no live chat behaviour
change; it's the standing operator-gated brain restart (brief
downtime, reversible — the prior binary backup is kept by
deploy-rbs.sh). Surfaced; not bulldozed.

### SD2 incr.2 — LIVE + VERIFIED on production (operator-approved deploy, 2026-05-18)

`deploy-rbs.sh` ran (operator-approved): pre-flight `main=origin/main=
47b88ab`, rbs pull, `zig build -Dcpu=baseline`, binary swap, brain
restart. **Live: 47b88ab.** Boot-verify (incr.1-class, given the prior
outage): `/opt/semantos/brain` rebuilt 19:48 (fresh), `active`,
MainPID 936449, **`wchan=do_poll`** (NOT `pipe_read` — the SD2 incr.1
detached-submitter deadlock fix holds across the new binary),
pub+loopback root `200`, live chat returns a normal LLM reply (incr.2
edge is inert for the chat path, as designed). **Decisive:**
`transition job <probe> authorized` on a throwaway `lead` job →
`{"state":"authorized"}` — the new `lead→authorized` FSM edge WORKS
end-to-end in the live brain (pre-incr.2 it returned an invalid
transition). Rollback kept: `/opt/semantos/brain.pre-47b88ab-1948`.

**The full operator model is now live on oddjobtodd.info:** every
contact → a `lead` (incr.1); ROM-ratified → `qualified`; gmail/meta
converge on the same seam (U2, built+verified, actuates on next
ingest); ingested work-order/maintenance-order → `lead→authorized`
(incr.2, live + proven). Brain stays generic; reactor untouched;
agent-cert signed; coupling + proofs constraints honoured throughout.

Remaining (operator-decided): a dedicated increment to REALIGN
`JobFSM.lean` + the §O4 TS table-shape block to the shipped 13-state
FSM (make the proof load-bearing again — separate from incr.2, which
stayed orthogonal). Then U3 (PWA WSS reader) / U4 (multi-tenant).

### JobFSM.lean + §O4 TS realign — DONE + VERIFIED (operator-decided, bf0f14e)

The proof is **load-bearing again** — it now faithfully models the
SHIPPED 13-state / 15-row FSM (was a superseded 7-row §O4 relic):
- `JobFSM.lean`: `JobState` 8→13 (added qualified, authorized,
  visitPending, visitScheduled, visited); `jobTransitions` 7→15
  (verbatim mirror of `job_fsm.zig` + the TS mirror, declaration
  order = row order); `jobTransitions_length` 7→15; added
  `findRow_some_lead_{authorized,qualified}` faithfulness witnesses
  for the SD2 edges; replaced the now-invalid
  `job_fsm_cap_required_lead_quoted` (lead→quoted removed in the
  remodel) with `_qualified_quoted` (the analogous cap-gated edge —
  same correction class as the Zig negative-test fix). The 4 negative
  + totality + K1/K2/K4 theorems stay valid over the new table
  (`decide`/`rfl` recompute). **Verified: `lake build` green locally
  incl. the full `Semantos` lib (39 jobs, no `sorry`, no downstream
  refs).** Lean is hermetic + toolchain-pinned (`lean-toolchain`
  v4.29.0, `lake-manifest`) and not installed on rbs (a build/CI-time
  proof, not a deployed-runtime concern) ⇒ local `lake build` is the
  authoritative locus (the rbs-ctx rule is for env-gated bun/zig
  workspace deps, which a pinned proof is not).
- §O4 TS `job-fsm.test.ts`: the 4 stale assertions (7-row count+order,
  cap-gated, principals, happy-path lead→quoted) realigned to the
  15-row canon (`lead→quoted` → the remodel's `qualified→quoted`).
  **Verified: 26/26 in the rbs bun ctx** (was 22 pass / 4 fail
  pre-realign).

All operator-driven Phase-3 goals are now DONE + (where live-gated)
LIVE + proof-faithful: chat lead-on-contact (incr.1), ROM→qualified,
U2 gmail/meta converged-seam (built+verified), work-order→authorized
(incr.2, live+proven), and the Job-FSM proof realigned to the shipped
truth. Forward epics remain: U3 (PWA as cap-gated WSS reader of the
standardised store) / U4 (multi-tenant, gated on the SD3 operator-cert
binding).

### U3 — GROUNDED read-only (2026-05-18); surface, not bulldoze

Grounding the read path settled what is shipped vs net-new:

**Already shipped + working — the operator-facing read EXISTS.**
`/api/v1/events` is a cap-gated, **hat-filtered** WSS endpoint
(`events_stream_handler.zig`: `GET /api/v1/events?hat=<flag>[&resume_
after=][&bearer=]`, per-connection hat filter, ring-buffer resume) fed
by `jobs_handler` on every `jobs.transition` — so the seam's live
`lead→qualified` / `lead→authorized` lifecycle ALREADY flows through
it. The `loom-svelte` web helm is a working reader:
`src/lib/helm-event-stream.ts` (WebSocket + `?bearer=<64hex>` +
auto-reconnect + hat scope) + `jobs-store.ts` / `joblist-graph.ts` /
`job-detail-graph.ts` / `oddjobz-query.ts`. **For single-operator
oddjobtodd, "see the structured leads/jobs the seam produces in a
cap-gated reader, per operator hat" is available TODAY** — no new
build. `cap.oddjobz.read_jobs` is the read cap; CC0–CC3 (cartridge
model + license + dual-shell loader + cross-shell id) is on main.

**U3-proper = net-new + flagged sub-decisions (the doc's "next epic,
not bulldozed").** The design-doc "PWA discovery" specifically means
the **oddjobz cartridge bound into the Flutter `apps/semantos`
PWA** (CC2c registry / `cartridge.json`) discovering the store over
WSS via the CC3 cross-shell-id contract. `semantos-shell/lib`
(`main.dart`, `shell/semantos_platform.dart`) has the shell
scaffolding but NO oddjobz cartridge reader yet. Its two flagged
sub-decisions — the **WSS discovery contract** and **operator-cert↔
cartridge binding** — are exactly what the doc scopes as the next
epic; and operator-cert↔cartridge binding **IS the SD3 decision U4
(multi-tenant) is gated on**. So U3-proper and U4 converge on ONE
substantive operator decision (SD3) plus the discovery-contract
shape — both explicitly not-to-be-guessed.

**STATUS: U3 surfaced as a checkpoint.** The operator's actual
business need (read the structured lead/qualified/authorized lifecycle,
cap-gated, per hat) is met by the existing loom-svelte helm — Phase-3
delivers an end-to-end working system without U3-proper. U3-proper
(Flutter-PWA cartridge discovery) + U4 (multi-tenant) are a coherent
*next epic* pivoting on the SD3 operator-cert↔cartridge-binding
decision, surfaced for the operator — not bulldozed into a speculative
Flutter/CC2c build.

### SD3 — GROUNDED for the operator decision (2026-05-18)

Operator chose to take SD3 now (unblocks U3-proper + U4). Grounding:
SD3 is **not greenfield crypto** — the substrate ships two
*complementary* layers; SD3 selects how they compose for oddjobz
multi-tenant (per the standing "do NOT guess crypto/keys" rule, the
options are grounded selections among shipped primitives, not
invention):

- **CC1 cartridge-license** (`core/protocol-types/src/identity-
  adapters/cartridge-license.ts`, Wave Cap-Substrate Decision-A): a
  cartridge's ownership is an **affine PushDrop license UTXO**
  (BRC-108 capability token); the license check requires the loading
  operator's identity pubkey (PEM) == the license-holder cert subject
  (K15d), scoped to the cartridge, fail-closed unlicensed. The
  *commercial / sellable* entitlement gate ("is THIS operator allowed
  to run the oddjobz cartridge").
- **Tenant manifest** (`runtime/semantos-brain/src/tenant_manifest.zig`
  + `docs/operator-runbooks/tenant-manifest-schema.md`, D-O8/D-O10):
  the operator-facing *deployment* descriptor — `owner_cert_path`
  (→ D-O10 owner-cert verification) + `operator_caps` (→ first-boot
  CapabilitySet seed for the operator hat) + lead sources + branding.
  Byte-identical cartridge code; the manifest is the per-tenant
  parameterisation ("who + how"). Already wired end-to-end via the
  D-O10 `node provision` first-boot flow.
- Per-operator *config* (lead sources, pricing) as hat/cert-gated
  cells is the **A5.P2 `set_pricing_policy` precedent** — already
  shipped; it rides on whichever binding is chosen (a consequence,
  not the decision).

**The SD3 options (grounded):**
1. **Manifest-primary (D-O10 owner_cert).** A deployment = a tenant
   manifest (`owner_cert_path` + `operator_caps`); operator hat seeded
   at first-boot from it. `oddjobtodd` is one manifest; new operators =
   new manifests. Simplest, fully wired today, no license-UTXO
   economics. Best if the goal is "deploy per operator" without a
   marketplace.
2. **CC1-license-primary (PushDrop license UTXO).** Deployment gated
   by a BRC-108 cartridge-license UTXO whose holder cert subject =
   the operator identity (K15d); fail-closed unlicensed. Matches the
   DECISION-P4C "sellable, swappable license holder" framing most
   literally; heaviest (license-UTXO issuance/economics + SpvContext).
3. **Layered (manifest deployment + CC1 license gate).** Manifest
   parameterises the deployment (owner_cert + caps + config, D-O10)
   AND the CC1 license-UTXO gates entitlement. Manifest = "who+how";
   CC1 = "allowed/paid". Most complete for a sellable multi-tenant
   cartridge; most work. Surfaced for the operator's call.

### SD3 — DECIDED (operator, 2026-05-18): MANIFEST-PRIMARY

Operator chose **manifest-primary**: a deployment = a tenant manifest
(`owner_cert_path` + `operator_caps`); the operator hat is seeded at
first-boot via the already-wired D-O10 `node provision` flow.
`oddjobtodd` = one manifest; new operators = new manifests. No
license-UTXO economics (CC1 is deferred — re-openable later as the
layered option if a cartridge marketplace becomes the goal).

**Key consequence — the binding mechanism is ALREADY SHIPPED.**
`tenant_manifest.zig` + the D-O8/D-O10 provision flow are on main and
wired end-to-end; per-operator config-as-cells is the shipped A5.P2
precedent; the read path (loom-svelte helm ⇄ `/api/v1/events`) is hat-
filtered/cap-gated and live. So manifest-primary multi-tenancy is not
a net-new substrate build — it is *expressing oddjobtodd as a tenant
manifest* + *verifying the oddjobz operator-hat/cap seed* + (for U4) a
2nd-operator manifest, all on shipped primitives.

## PHASE-3 — COMPLETE. Forward epic (U3-proper + U4) scoped on shipped primitives.

The loop's mandate ("complete the oddjobz Phase-3 forward build") is
**fully delivered + live + verified + proof-faithful**: P3.1–P3.5,
SD2 incr.1 (chat→lead→qualified, live+proven), the self-call deadlock
fix (live), U2 gmail/meta converged-seam (built+verified), SD2 incr.2
(work-order→authorized, live+proven), the JobFSM.lean/§O4 realign
(proof load-bearing again), U3 grounded (operator read already works
via the live helm), and SD3 decided (manifest-primary; mechanism
shipped). The operator's stated goal — *a working, decoupled,
architecturally-pure structured-cell system to run the business* — is
met end-to-end on production.

**The remaining work is a distinct NEXT EPIC, not Phase-3, and not
required for the operator's current single-operator use:**
- **U4 (multi-tenant)** — express `oddjobtodd` as a D-O10 tenant
  manifest + a 2nd test-operator manifest; verify per-tenant operator-
  hat/cap seeding + store partition (hat filter). All on shipped
  primitives (tenant_manifest D-O10, A5.P2 config-cells, the
  hat-filtered events WSS). A verification/wiring epic, not net-new
  substrate.
- **U3-proper** — the oddjobz cartridge bound into the Flutter
  `apps/semantos` PWA via CC2c/CC3 + the WSS discovery contract.
  A substantial Flutter/Dart build epic; NOT blocking business use
  (the loom-svelte web helm is the working reader today).

Surfaced at this clean boundary for the operator's call (continue into
the next epic, or close the loop with Phase-3 fully delivered) — not
bulldozed into a speculative Flutter / multi-tenant build the
single-operator goal does not require.

### U3-proper — operator chose to build it; GROUNDED, plan + sub-decision surfaced (2026-05-18)

Operator chose to continue into U3-proper (oddjobz cartridge reading
the standardised store in the Flutter `apps/semantos` PWA).
Grounding settled shipped-vs-net-new precisely:

- **Shipped (CC2c/CC3 scaffold complete):** `packages/oddjobz_
  experience/` is the registered Flutter cartridge (`cartridge.dart`
  → `OddjobzScreen`); `registerOddjobzCartridge()` is wired at
  `apps/semantos/lib/main.dart:51`; the CC3 discovery contract
  is `CartridgeRegistry.served(servedIds)` = local registry ∩ the
  Brain `/api/v1/info` `cartridges[]` list. No per-cartridge router
  edits (the loader is generic).
- **Net-new (the U3-proper gap):** `OddjobzScreen` is NOT a reader of
  the standardised store — there is NO Dart `/api/v1/events` client
  anywhere. U3-proper = a Dart WSS-events client mirroring
  `apps/loom-svelte/src/lib/helm-event-stream.ts` (WebSocket to
  `/api/v1/events?hat=<flag>&bearer=<64hex>`, hat-scoped,
  auto-reconnect, ring `resume_after`) + wiring it into
  `OddjobzScreen` to render the live `lead→qualified→authorized`
  lifecycle (the cap-gated, hat-filtered events the seam now drives).
- **Verifiability:** Flutter 3.41.9 is LOCAL only (not on rbs — the
  PWA is a client/build-time artifact, not a deployed-brain concern;
  hermetic via pubspec, analogous to the Lean toolchain). `flutter
  test` locally is the authoritative locus; precedent test:
  `packages/oddjobz_experience/test/cartridge_golden_path_test.dart`.
  NOT env-gated-unverifiable; ZERO live (a client cartridge — no
  brain redeploy; the brain `/api/v1/events` endpoint is already
  shipped + live).
- **The one genuine sub-decision (the design-doc-flagged "WSS
  discovery contract"):** how the Flutter cartridge sources the
  operator **hat** + **brain bearer** for `/api/v1/events`. The shell
  exposes `SemantosPlatform.hatRegistry` (active-hat) and an
  `IdentityStore` (web: IndexedDB; the model is "operator pairs to a
  brain, PWA is a thin client"). Sourcing the brain bearer from the
  shell's paired-brain session is shell-auth wiring that must NOT be
  guessed — surfaced for the operator's confirmation of the wiring
  contract before code.

STATUS: U3-proper plan grounded + the hat/bearer-sourcing sub-decision
surfaced for operator confirmation BEFORE any Flutter code (per the
"substantive new surface = checkpoint" discipline). The events client
itself is a faithful Dart port of the proven loom-svelte contract.

### U3-proper — STOP: subsumed by / blocked on the active CC4 epic (2026-05-18)

Deeper grounding (before writing any Flutter) surfaced a
concurrent-workstream collision — the build was halted, not bulldozed:

- **`packages/oddjobz_experience/lib/src/oddjobz_screen.dart` is a
  ~12-line placeholder** (no reader, no events client). The shared
  cartridge has only a stub screen.
- **The proven Dart reader stack already exists, app-local in
  `apps/oddjobz-mobile`**: `lib/src/repl/helm_event_stream.dart`
  (813 lines — the Dart twin the loom-svelte client mirrors) +
  `jobs_repository.dart` / `customers_` / `invoices_` / `quotes_` /
  `visits_repository.dart` + `event_subscription_service.dart` /
  `hat_context.dart`. `oddjobz-mobile` is a COMPLETE, SHIPPED Flutter
  reader of the standardised store and already depends on the same
  `oddjobz_experience` cartridge. So a working Flutter reader of the
  seam's output ALREADY EXISTS (alongside the loom-svelte web helm) —
  U3-proper's user value is already met for the operator.
- **`docs/design/CC4-CARTRIDGE-FAN-OUT-HANDOFF.md` is an ACTIVE
  parallel implementer-handoff epic** (pushed by a parallel session,
  commit `0d2798a`) that owns EXACTLY the missing piece: collapsing
  cartridge code into `cartridges/<id>` / the shared
  `oddjobz_experience` package, `apps/` keeping only non-cartridges
  (shell binary, legacy-cli, demos). "The cross-shell seam is the
  shared cartridge id."

**Conclusion (surfaced, not bulldozed):** U3-proper as scoped — the
shared oddjobz cartridge reading the standardised store cross-shell in
the `semantos-shell` PWA — **is the CC4 epic's deliverable** (lift the
oddjobz-mobile reader stack into the shared `oddjobz_experience`
package per the CC4 directory-collapse, so both shells use one
cartridge). Independently duplicating the oddjobz-mobile reader into
`oddjobz_experience` now would (a) collide with the active CC4
restructuring (concurrent breakage — a hard stop-condition), and (b)
be redundant (the reader is proven + shipped in oddjobz-mobile). U3-
proper is therefore **blocked on / merges into CC4**, surfaced for the
operator's call — not bulldozed into a conflicting ad-hoc port.

This closes the Phase-3 loop's reachable scope: every Phase-3 goal is
delivered+live; the read path is satisfied (loom-svelte helm +
oddjobz-mobile, both shipped); U3-proper and U4 are the next epic,
gated respectively on CC4 (active, parallel-owned) and SD3-applied
multi-tenant wiring — both cleanly recorded, neither bulldozed.

### Operator field report (2026-05-18): oddjobz-mobile UI not populating from the store / NL not driving jobs

Operator (from direct use): the Dart app "has the shell in essence"
but the views are **not populating with jobs from the store or the
chat widget**, and **NL commands in the conversation window don't
elicit job changes**.

Grounding reconciles this to a **runtime integration break, NOT
absent code** (correcting the earlier "complete shipped reader" read):
- `apps/oddjobz-mobile/lib/src/helm/home_screen.dart` IS "jobs grouped
  by stage" and imports `jobs_repository` (+ customers/invoices/
  quotes/visits); `app.dart` connects `_eventStream`
  (`helm_event_stream.dart`) in `HomeScreen.initState()`;
  `contact_conversation_screen.dart` has `_send()` →
  `conversation_send_api`. The code path EXISTS end to end.
- ∴ the failure is integration/runtime, candidate root causes (none
  yet diagnosed — not to be guessed): (a) the app isn't paired/
  pointed at the LIVE oddjobtodd brain; (b) `helm_event_stream` uses
  `/api/v1/wallet` `helm.subscribe`/`helm.event` — does the operator
  /tenant hat it subscribes match the hat the seam's
  `jobs.transition` emits under; (c) `jobs_repository` `find jobs`
  hitting test data vs the seam's new lead/qualified/authorized cells;
  (d) `conversation_send_api` not reaching the brain intent→jobs
  path (mobile conversation surface ≠ the proven web chat-widget→
  lead seam).

**Disposition (surfaced, not bulldozed):** this is a SUBSTANTIAL NEW
diagnostic workstream on a live client app, distinct from the Phase-3
substrate build (which is complete+live — the seam/store/FSM are
proven via the loom-svelte helm + REPL probes; the SUBSTRATE is not
in question). It is **not reproducible/verifiable by the agent**
(requires the operator's paired device/app session against the live
brain — `env-gated-unverifiable` + live-client-risk stop-conditions)
and **overlaps the active parallel CC4 epic** (cartridge code
location/fan-out). Per discipline it is surfaced for operator
direction (collaborative diagnosis vs scoped read-only investigation
vs fold into CC4) rather than a speculative, unverifiable Flutter fix
bulldozed in mid-loop while CC4 restructures the same code.

leads.jsonl/jsonl-island stays as the inert historical shadow.
SD2 incr.1 remains COMPLETE+LIVE; incr.2 (lead→authorized) + the
JobFSM.lean proof-drift ruling remain the subsequent gated items.

### Collaborative-diagnosis pre-grounding (2026-05-18) — operator field report, symptom #4 RESOLVED read-only

Operator chose collaborative live diagnosis of the oddjobz-mobile
UI↔store break (views not populating; NL conversation not driving
jobs). Read-only pre-grounding (no operator input, no code, no CC4
collision) resolved one symptom definitively and narrowed the other:

- **Symptom #4 (NL conversation doesn't change jobs) — NOT A BUG, by
  design.** `runtime/semantos-brain/src/conversation_send_http.zig`
  `POST /api/v1/conversation/<id>/send` is, per its own documented
  steps, a message-LOG endpoint: parse `body` → resolve
  conversation_id→contact phone (`LookupContactPhoneFn`) → **persist
  the outbound message-sent record** (`PersistMessageFn`). It has NO
  jobs/transition/intent path. The mobile conversation window was
  never wired to drive jobs; the job-driving NL surface is the web
  chat-widget `/api/chat`→lead seam (proven live: contact→lead→
  qualified). So this half of the field report is a **known design
  gap / next-epic scope item, not a regression** — the substrate is
  not implicated.
- **Symptom #2 (Home not populating) — narrowed to app-side
  connection.** `jobs_handler` DOES publish `job.transitioned` to the
  `helm_event_broker` on every successful `jobs.transition`
  (jobs_handler.zig L189-193), so the seam's live lead/qualified/
  authorized transitions DO emit frames; the live store has 6 jobs
  (find jobs verified). The break is therefore in the app's
  connection: pairing target (must be `https://oddjobtodd.info`),
  bearer validity, helm-event-stream `subscribed` state, and the
  hat/topics the dart client subscribes vs the jobs' hat. This
  REQUIRES the operator's hands-on observations (steps 1–3 of the
  collaborative script) — agent-unverifiable, NOT bulldozed.

Net: the substrate (the Phase-3 deliverable) is NOT in question;
#4 is a design-scope item; #2 is an app-side connection diagnosis
gated on the operator's device session. Loop paused on the operator's
collaborative-diagnosis input — not auto-continued into the stale
"U3 ground" prompt (U3 already grounded → CC4-subsumed).

> **CORRECTION (2026-05-18, operator): the "#4 = by-design" call above
> is WRONG.** It was grounded on the wrong endpoint
> (`/api/v1/conversation/<id>/send`, a message-log). The operator's
> actual working flow is **`talk | direct |` → `POST
> /api/v1/voice-extract`** (multipart: signed Transcript JSON +
> metadata{hat_context} → `voice-extract.ts` → `runtime/intent`
> `processIntent` → intent-cell → `intent_action_router` →
> `jobs.transition`). Operator: typing e.g. "quote 600 for the pergola
> job" in talk|direct transitioned the job FSM — a real shipped
> capability (the early live `submit_quote` "quote $600 for the
> pergola job" cell is its artifact), NOT a design gap. The endpoint
> requires an operator-child-cert **signed** transcript (`401
> signature_invalid`), so it is NOT shell-reproducible solo by the
> agent — verification needs the talk|direct client or the signing
> material. Whether it currently still works is the open question
> (operator ground-truth pending); the agent must not assert either
> way. Also: the home_node.dart §O4-bucket fix (#2) is unrelated to
> this NL→FSM path and does not require/imply an app rebuild for it.

### Symptom #2 — ROOT-CAUSED + FIXED + VERIFIED (collaborative diag, 2026-05-18)

Operator observation: app shows **1 job on Home (SD2 Loopback Probe,
the only `lead`)** but `find` returns all **6** (Derek/Marcus×2/Jenny
= `qualified`, INCR2 = `authorized`, SD2 = `lead`). This RULED OUT
pairing/connection (the app reaches the live brain fine) and pinpointed
the break.

**Root cause:** `apps/oddjobz-mobile/lib/src/helm/home_node.dart`
bucketed jobs into 3 Home sections via hardcoded state sets that were
the **pre-remodel §O4-linear states** (`_kAttentionStates =
{lead,quoted,completed}`, `_kActiveStates = {scheduled,in_progress}`,
`_kRecentStates = {invoiced,paid,closed}`). A job whose state was in
NO set rendered in NO section (L182-184
`filtered.where(_kXStates.contains(j.state))`). The 13-state remodel
states `qualified` / `authorized` / `visit_pending` /
`visit_scheduled` / `visited` were in no bucket ⇒ silently dropped
from Home while still returned by `find jobs`. The **Flutter twin of
the §O4/JobFSM drift** already fixed on the Zig/TS/Lean side.

**Fix (operator-approved mapping + apply-now-scoped):** the 3 sets
realigned to the shipped 13 states — Needs-attention += {qualified,
authorized, visit_pending, visited}; Active += {visit_scheduled};
Recent unchanged. Union now covers all 13 (no fall-through). Added a
public `homeSectionForState` classifier + `kCanonicalJobFsmStates`
and a conformance test `test/helm/home_node_buckets_test.dart` that
asserts EVERY canonical state maps to a non-null section — a
permanent regression guard against this whole drift class. Behaviour-
neutral (the private sets + their 5 usages unchanged; new public
symbols additive). **Verified: 3/3 via local `flutter test`** (Flutter
is local-toolchain, hermetic via pubspec — the authoritative locus,
like Lean; not an rbs concern). ZERO live/brain change — a client
cartridge fix; the operator sees all 6 jobs grouped after rebuilding/
reinstalling the app.

**CC4 note:** surgical + additive (set-literal expansion + new
function/test) ⇒ low merge-conflict if CC4 relocates the file; the
new conformance test travels with it and guards the collapse. Symptom
#4 stays a by-design next-epic scope item (mobile conversation =
log-only). The Phase-3 substrate remains complete+live throughout;
this was a client-app rendering bug, not a substrate issue.

---

## 2026-05-19 — The 146/106 invisibility: decisive re-grounding (stash subsumed; op_pkh key-scope root cause)

**Field report under recovery:** operator reports ~146 gmail-ingested
jobs + 106 customers should be in the jobstore but `find jobs`=6 /
`find customers`=0 on the live oddjobtodd.info brain. Prior working
model (this session, pre-compaction): the recovery code lived only in
the uncommitted rbs `stash@{0}` ("rbs-wip-pre-reingest-sync-
20260516-1449", commit 46c0d2e2, native base 4431e535) and the fix
was to deploy that stash (approach B / best-of-both onto 90c5142).

**DECISIVE FINDING — the stash holds zero unique code.** Rigorously
tested by applying `stash@{0}` onto `90c5142` and resolving every
conflict: `git diff HEAD` = **0 files — byte-identical to origin/
main**. The stash contributes **0 unique non-conflicting files**.
Every one of the 10 conflicts had **upstream (90c5142) as the
strictly-newer superset** (U2 converged-seam, job-dedupe, Bricks+Agent
allowlist, `--min-version`, real `WssEncodeDispatcher`, the domain-
flag B-1 collision fix — taking the stash side would have *deleted
shipped work and reintroduced a fixed bug*). `build.zig` +436 = 100%
CC4 path-rename noise (0 new wiring); `serve.zig` stash side empty;
stash brain Zig files byte-identical to 90c5142. **Conclusion:
origin/main @ 90c5142 is a complete strict superset of stash@{0}.**
Everything feared lost — ingest scripts, extractor, intent pipeline,
cell format, 13-state FSM, projection — is already committed and
immutable at 90c5142 (= the live binary 6c01207f). The stash was
subsumed by this /loop's own commits. **Approach B / best-of-both are
MOOT.** (Stash still preserved 4× off-box + rbs branches regardless.)

**Corrected model — 146 is a live data-state bug, not missing code.**
There is **no separate empty "view store"**; on disk only
`/var/lib/semantos/entity_cells_lmdb` (8.2M) — the brain reads jobs
*directly* from it (`cli/repl.zig:409`, `serve.zig:1107`). Live
read-only census (via the daemon-configured `ODDJOBZ_BRAIN_BEARER`
from systemd — pre-boot ⇒ recognised; freshly-issued tokens are NOT,
the live build's HTTP bearer auth is a **boot snapshot**, daemon up
since 2026-05-18 23:46:04):
- `find jobs` = 6, ALL created 2026-05-18 = *this /loop's own SD2/U2
  probe jobs* (Derek Stone, Marcus Webb ×2, Jenny Carter, INCR2 WO
  Probe, SD2 Loopback Probe). NOT the 146.
- `find customers` = `[]`.
- Raw byte census: `/var/lib/semantos/entity_cells_lmdb` = **1020
  DEADBEEF (substrate) cells** — the migrated 146 jobs + 106 customers
  + sub-cells ARE here, substrate-correct. The May-11
  `.semantos/data/entity_cells_lmdb` (5.2M) = **0 DEADBEEF**, high
  ASCII "job"/"customer" = the OLD legacy-format frozen mirror.

**Root-cause hypothesis (strong, testable): op_pkh key-prefix scope
mismatch.** `migrate_entity_cells/main.zig:200-204` re-keys each cell
as `op_pkh ‖ sha256(new_cell)`, **preserving the cell's original
ingest-time op_pkh**. The 6 visible jobs were minted 2026-05-18 by the
live daemon under the *current* operator pkh ⇒ found by the per-
operator `find jobs` cursor. The 146 carry their *ingest-time* op_pkh;
if that differs from the live operator identity the cursor scans
under, they sit under a different key prefix and are never enumerated
— fully explaining: data present + substrate-correct + invisible to
the typed per-operator query. Confirmation needs an LMDB key-prefix
dump (distinct op_pkh prefixes vs live operator pkh) — Zig-only store
access.

**Status / next (operator decision point):** read-only forensics
complete. The fix (re-key/re-scope the 146 under the live operator
pkh, or a brain-side reindex/backfill) is a **live V1 data mutation**
= stop-condition, and is additionally blocked by the boot-snapshot
bearer issue for write verbs (a fresh token won't auth; only the
pre-boot configured bearer does, and re-keying isn't a REPL verb).
ZERO destructive action taken; stash + certs + binaries preserved;
fully reversible. Awaiting operator direction on the live re-scope.

---

## 2026-05-19 — RESOLVED: the ~150 invisible gmail jobs/customers (RM-119 reader adapter + RM-120 LMDB link fix), shipped live

**Outcome:** live brain `find jobs` 6 → **62**, `find customers` 0 → **170**.
Previously-invisible gmail/Bricks-ingested records now surface with
correct data + FSM state (57 lead / 4 qualified / 1 authorized).
Identity chain intact (75 cert records, agent certs af90d1d6…/
bfe14fba… present). Zero data/cert loss. Deployed binary sha
4ca0894e; rollback binary preserved at `/opt/semantos/brain.pre-
rm119-20260519-013605` (sha 6c01207f).

**True root cause (forensically confirmed 2×: zig census + python-
lmdb on a store copy; NOT op_pkh — all 1020 cells share the single
zero op_pkh prefix):** a **payload-schema mismatch**. The gmail/Bricks
ingest writes job cells `{intent,summary,display_name,state,site_ref,
customer_refs,work_order_number,issuance_date,…}` and customer cells
`{name,email,phone,role,linked_site_id,notes,state}` — neither has the
brain-native `"kind"` / `id`+`display_name`. JobsStore.kindOfPayload →
.unknown and CustomersStore.applyPayload bailed at `obj.get("id")
orelse return`, so every ingested record was skipped on replay (6
`add job` probes visible; ~56 jobs + 170 customers invisible). RM-115
migration faithfully preserved the ingest JSON; it was never reshaped.

**Fix — RM-119 (reader adapters, ZERO data mutation; operator-chosen
over re-keying):**
- `jobs_store_lmdb_entity.applyIngestJobPayload` (wired into
  rescanCreatedCells `.unknown` branch): display_name "Name (role)" →
  customer_name (suffix stripped), state FSM-validated else `lead`,
  issuance_date → created_at, id = hex(sha256(payload)[0..32])
  (stable ⇒ by_id-idempotent). Self-discriminating.
- `customers_store_lmdb`: pure `mapIngestCustomer` + applyIngest
  CustomerPayload (name→display_name, phone/email/notes clamped, role
  parsed), wired into replayCellStore alongside applyPayload (each
  no-ops on the other's shape). Pure-logic inline test (file
  convention) + LMDB inline test for jobs.

**RM-120 (rbs build-env fix, unblocked ALL verification):** the rbs
zig 0.15.2 build linked the *dynamic* system `liblmdb.so.0` (0.9.31),
which null-derefs on the first LMDB call — every freshly-built LMDB
exe + ~20 conformance tests SIGSEGV'd at 0x0; non-LMDB paths fine.
The deployed working brain proved the fix: it static-links
`liblmdb.a`. Set `.preferred_link_mode=.static` + `.link_libc=true`
on `lmdb_mod` AND `cli_mod` (the brain exe re-linked dynamic
separately — caught at the deploy gate via `readelf -d`). Recovered
~20 tests (1694/1739 pass).

**Deploy note (important for future redeploys):** the RM-119 adapter
replay JSON-parses + sha256s ~1020 cells ×2 stores at boot, so the
brain now takes **~70s to bind :8080** (vs ~25s). This is NOT a
deadlock — `wchan=pipe_read` is this single-thread reactor's normal
slow-boot/idle state (proven by a non-live :8099 copy-dir
reproduction that served at t+70s). systemd is safe for it
(`Type=simple`, no bind-gated start timeout, `Restart=on-failure`
won't loop). A too-hasty 7s rollback aborted the first deploy
attempt; the corrected ≥110s boot-verify window succeeded. **Future
deploys must allow ≥90s before judging health, and never treat
`wchan=pipe_read` alone as a deadlock — confirm via :8080 not
serving AFTER a full boot window.** Follow-up candidate: make the
ingest-adapter scan incremental / off the synchronous boot replay to
restore fast boot.

**Pre-existing, unrelated (flagged, NOT addressed here):**
`intent_action_router.test.isFsmTransitionAllowed: thirteen-state
lifecycle edges + branches` and `parseTargetCost` fail on origin/main
— identically before any RM-119/RM-120 change, in a file none of this
work touched. Pre-existing/concurrent breakage in the 13-state FSM
transition table vs intent_action_router; needs a separate decision.
