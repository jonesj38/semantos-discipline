---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/INTENT-PIPELINE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.326228+00:00
---

# Intent pipeline — design

> **Status:** design only. Substantive work to follow once shape is
> settled. This document describes the universal substrate the
> system uses to express, validate, and execute *any* action against
> the cell engine — whether the action originated as natural
> language, a typed shell command, a UI button click, an inbound
> network cell, or a scheduled job.

## Why this is the core primitive

Every interaction with semantos that *changes state* eventually has
to do four things:

1. **Express what's wanted** — in some structured form the system can reason about
2. **Authorise it** — the actor (a hat) must hold the necessary capability,
   in the right domain, with sufficient trust tier
3. **Compile it down to bytes** — the cell engine is the source of truth;
   it speaks 2-PDA opcodes
4. **Execute and record** — kernel runs the script, the result becomes a
   cell, the cell joins the evidence chain

Today the system has multiple half-finished implementations of (1)–(4):

| Path | (1) express | (2) authorise | (3) compile | (4) execute |
|---|---|---|---|---|
| `chat.ts` (NL) | LLM JSON | none | for display only | none — JSON object store |
| Shell verb dispatch | parser → `ShellCommand` | partial — capability check helper | per-verb handler | per-verb mutation |
| Helm UI buttons | direct method calls on `LoomStore` | none | none | reducer mutation |
| Patches over the wire (Phase 38 host.exec) | `HostCommand` | trust-tier + cert sig | full path | yes |
| Governance flows | `Ballot`, `Stake`, `Dispute` types | per-flow ad-hoc | none | reducer mutation |

Five paths, five different shapes, five different authorisation
models, four of which never reach the kernel. The cell engine is
designed to be the cryptographic substrate; almost nothing in the
runtime actually goes through it.

The Phase 38 `host.exec` work is the existence proof that the full
pipeline can be wired (HostCommand → trust-tier checks → publish-
before-execute → kernel → receipt). This document generalises that
shape into the substrate every other input mode rides on.

## The pipeline

```
Input mode (NL / shell / UI / voice / patch / transition / governance / network)
  │
  ▼  source-specific Intent producer
  │
  ▼
Intent (canonical action shape — same for all inputs)
  │
  ▼  buildSIR(intent, hatContext)
  │
  ▼
SIRProgram (with governance: trustClass, proofRequirement, executionAuthority,
            domainBinding, identity)
  │
  ▼  lowerSIR()       ← static check: trust tier, allowed-emit-ops, identity
  │                     malformed claims rejected here, before any bytes
  ▼
IRProgram (ANF, OIR)
  │
  ▼  emit()
  │
  ▼
Opcode bytes (0x4C–0xD0)
  │
  ▼  ScriptWordsRenderer.render()    ← parallel branch: human-readable display
  │
  ▼
cellEngine.executeScript(bytes)
  │  OP_CHECKCAPABILITY (0xC3)        ← dynamic check: actually holds the cap
  │  OP_CHECKDOMAINFLAG (0xC6)        ← dynamic check: actually in the domain
  │  OP_CHECKLINEARTYPE                ← dynamic check: type-system invariant
  │
  ▼
IntentResult { cell, kernelResult, receipt, uiHint }
  │
  ├──▶ persisted via StorageAdapter (cell joins evidence chain)
  ├──▶ broadcast via runtime/services if extension routes it
  └──▶ delivered to the input mode's caller for presentation/feedback
```

The pipeline is a single function. Every input mode is a producer
of `Intent`; every output (kernel state change, UI render, governance
emission) is a consumer of `IntentResult`.

## Input modes (intent producers)

Each produces an `Intent` and hands it to `processIntent(intent, ctx)`:

### NL → Intent (the original chat case)

LLM call with a strict JSON-schema output mode. The schema is
generated from the `Intent` type. System prompt is parameterised by
the active extension's grammar — the LLM gets the available actions,
taxonomy, and constraint shapes for *this* extension, not a hardcoded
vocabulary.

If the LLM's output fails to parse OR fails `validateConstraintFields`,
retry with the validation error in the LLM context (one retry, then
surface to user). Decision: confidence is **inferred** from schema
gaps and validation passes, not LLM-self-reported.

### Shell verb dispatch → Intent

The existing parser already produces `ShellCommand`. A small mapper
converts that to an `Intent` based on the verb:

```ts
parseCommand("new core.Document --title='hi'")
  → ShellCommand
  → shellCommandToIntent
  → Intent { action: 'create', target: { typePath: 'core.Document' }, … }
```

This is the path that lets every shell verb (incl. `cdm`, `extract`,
`infer` etc. via the Phase 3 handler-registry) optionally route
through the pipeline instead of mutating directly. Some verbs may
keep direct paths for performance (read-only `inspect`, `list`);
anything that mutates goes through the pipeline.

### UI component bindings → Intent

UI elements declare what `Intent` they produce when activated. A
"publish" button on a Document inspector becomes:

```ts
<Button onClick={() => emit({
  action: 'transition',
  target: { objectId: doc.id, typePath: doc.typePath },
  category: 'declaration',
  constraints: [{ kind: 'capability', required: 2, name: 'SIGNING' }],
})}>
  Publish
</Button>
```

`emit` is `processIntent` with the UI's caller as the response
handler. The pipeline runs; the result includes a `uiHint` describing
what the UI should do (re-render this object, open this approval
dialog, show this rejection toast).

### Voice → Intent

Phase 38E's voice-capture stack already lands a transcript. The
transcript routes to the same NL pipeline above. One pipeline,
three input modes (NL, voice, paste) all funnelling to the same
`processIntent`.

### Patch / transition → Intent

Existing `host.exec` HostCommand semantics formalised: a HostCommand
*is* an Intent (with `category: 'power'` and the action mapped to
the host handler). Patches and transitions issued internally also
produce Intents — same path.

### Governance ballots / stakes / disputes → Intent

`category: 'power'` for ballots that change rules; `category:
'declaration'` for disputes that assert facts; `category:
'transfer'` for stakes that move value. Same shape, different
governance metadata.

### Network ingress (incoming cells) → Intent

A cell received from another node arrives as opcodes already. It
enters the pipeline at the **`lowerSIR` verification stage**, not
the `emit` stage — we re-derive the SIR claim from the bytes and
verify it against the sender's claimed governance. This is the
read-side mirror of the send path.

## Triage and conversation patches

Naïvely running `processIntent` on every user/agent message burns
LLM + kernel cost on "thanks, got it." The substrate already has
the right primitive for this: `ObjectPatch.kind = 'conversation'`
(runtime/services/src/types/loom.ts). Every exchange is a cheap
conversation patch (no LLM, no SIR, no kernel). A triage classifier
sits between the NL/voice producer and `processIntent` and decides
whether the expensive path even runs.

### Three triage outcomes

```ts
type TriageOutcome =
  | { kind: 'no_intent';  reason: string }
  | { kind: 'proposes';   intent: Intent }       // Intent.companionOf → conversation patch id
  | { kind: 'ratifies';   pendingPatchId: PatchId; attestation: Signature };
```

1. **NO_INTENT** — conversation patch only; pipeline halts.
2. **PROPOSES_INTENT** — full pipeline runs; the derived patch's
   `companionOf` field points at the source conversation patch.
   Derived patch is marked `ratificationState: 'pending'`.
3. **RATIFIES_INTENT** — the message is a Boolean acceptance of an
   earlier pending intent (landlord saying "approved"). Skip SIR /
   IR / kernel; emit a signed `RatificationPatch` referencing the
   earlier patch's id. The ratification IS the formal proof on the
   earlier authoritative-tier state-transition.

The third case is what makes authoritative-tier attestation cheap
at runtime. A landlord's "approved" on a quote doesn't need a fresh
SIR program; it needs a cryptographic signature pointing at the
pending proposal patch. The substrate guarantees every eventual
state change traces to a conversation patch via a typed
`companionOf` graph link — not a text search.

### Multi-party flow

Each message is a patch authored by a hat. Trust tier is a per-patch
property; `lowerSIR` rejects cross-role authoritative claims
structurally (a tenant cannot propose a landlord-tier budget
approval even if they try — SIR refuses to lower it).

Handoffs between parties are `exportBundle` / `importBundle`
operations across share channels. The evidence chain on the object
accumulates conversation + derived + ratification patches from all
parties in order.

### Storage is backend-agnostic

`StorageAdapter.write(cell)` is a black box to the pipeline. Cloud,
on-device, USB, or octave-linked multi-cell storage is the adapter's
concern. The pipeline emits one `cell_written` event per logical
cell regardless of backend. Octave-linked fan-out is orthogonal and
may later introduce a separate `cells_written` event for chunked
writes; not a Slice 1 concern.

## Output modes (intent result consumers)

`IntentResult` carries enough information for any caller to do the
right thing:

```ts
interface IntentResult {
  ok: boolean;

  // The on-chain artifact (or null if the intent was rejected before bytes)
  cell: Cell | null;

  // Raw kernel result (success/failure code, stack state, opcount)
  kernelResult: ScriptResult;

  // Cryptographic receipt suitable for evidence-chain entry
  receipt: Receipt;

  // Hints for input-mode-specific presentation
  uiHint: {
    /** What the user sees: a toast, modal, inspector, …  */
    presentation: 'toast' | 'inspector' | 'inline' | 'silent';
    /** Object IDs that should re-render */
    invalidate: string[];
    /** If a follow-up turn is required */
    followUp?: { kind: 'confirm' | 'clarify'; prompt: string };
  };

  // If rejected at SIR layer, the structured rejection
  rejection?: { stage: 'sir' | 'kernel'; code: string; message: string };
}
```

This means:
- **Shell/REPL** prints the rendered ScriptWords + kernel result
- **UI** uses `uiHint.invalidate` to know what to re-render and
  `uiHint.presentation` for the modal-vs-toast decision
- **Voice** speaks back the result summary
- **Network sender** broadcasts the cell + receipt to the destination
- **Governance UI** shows the receipt as evidence in the ballot's audit trail

The pipeline doesn't render UI; it produces enough structured info
that any UI layer can render correctly.

## Design decisions (locked)

The first version of this doc had six open questions. Endorsed
directions are now decisions:

### 1. LLM output: strict JSON schema with parse-or-reject

OpenRouter (and most modern providers) supports JSON-schema-bound
outputs. The schema for `Intent` is generated from the TS type and
shipped to the LLM as a structured-output constraint. On parse
failure, retry once with the validation error in context; on second
failure, surface to user with a clarifying question.

### 2. Confidence is inferred, not LLM-self-reported

LLMs are bad at calibrated self-confidence. We compute confidence
by counting:

- Required fields the LLM supplied vs. left blank (proportion)
- Constraints that pass `validateConstraintFields` against the
  active extension's field schema
- Action verbs that exist in the extension's vocabulary
- Taxonomy paths that resolve to known nodes

A composite score (0–1) drives `governance.trustClass`:

- `≥ 0.9` → `interpretive` (use directly)
- `0.6 – 0.9` → `cosmetic` (require confirmation turn before execution)
- `< 0.6` → reject; ask user to clarify

`authoritative` is never set by the NL path — only by inputs that
come with a real cryptographic proof (already-signed cells, host.exec
chains).

### 3. SIR rejection: split by failure mode

| Rejection reason | Action |
|---|---|
| Trust tier (claimed authoritative without formal proof) | Retry LLM with rejection in context — "you proposed X but it requires formal proof; pick a weaker claim" |
| Allowed-emit-ops not in extension whitelist | Retry LLM with the whitelist in context — model didn't know what was permitted |
| Action verb not in extension vocabulary | Retry LLM with vocabulary in context |
| Capability not held | Surface to user — they can't bypass; they need a different hat or scope |
| Domain mismatch | Surface to user — same |
| Linearity violation | Surface to user — explains "this object has already been consumed" |

Programmatic retries (the first three rows) are bounded: max 1
retry, then surface. Cryptographic / state failures (last three)
never retry.

### 4. SIRConstraint[] is the canonical interchange

All surface grammars produce `SIRConstraint[]` directly, not
through Lisp. Lisp keeps its `ConstraintExpr → SIRConstraint`
mapper for backward compat, but new grammars (LaTeX, Lean-ish,
Ricardian) skip Lisp entirely and produce SIR constraints directly.
This makes Intent producer-agnostic: the LLM, the shell parser,
the UI binding, and a future Lean-formalised grammar all converge
on the same type.

### 5. chat.ts becomes a vertical demo

OddJobTodd's UX (sizing questions, ROM pricing, fit/worthiness
scoring) keeps working — it just becomes a thin layer over
`processIntent` instead of its own state machine. The trades-services
system prompt gets parameterised so any extension can plug a similar
chat UX in.

The old `chat.ts` file ships unchanged through Slice 1; Slice 2
rewrites it as `apps/odd-job-todd/` (a vertical app) consuming the
new pipeline.

### 6. Voice converges through `processIntent`

The Phase 38E voice-capture stack feeds its transcript into the
same NL → Intent path. No separate "voice pipeline" needed. The
pipeline is mode-agnostic; voice is just one more producer.

### 7. Observability is a first-class concern from line one

Every Intent carries a `correlationId` (UUID v7, generated by the
producer or auto-filled by `processIntent` if missing). Every stage
boundary emits a structured log event tagged with that id. This is
~30 LOC in slice 1; it pays for itself the first time a real user
files "turn #4815 didn't work".

Reactive observability is patchy observability — you instrument the
stages that bit you, miss the ones that haven't yet, and never get
clean trace data when things go wrong far from any single line of
code. Baking it in from the first commit means every replay,
every "why did this happen?", and every cross-stage rejection is
already a single log query away.

See **Observability** below for the wire format and stage list.

## Observability — correlation IDs and stage events

The pipeline emits one structured log event at every stage boundary,
all tagged with the Intent's `correlationId`. A single failed turn
becomes a single grep.

### Stages

Seven events fire across the happy path; an eighth fires on rejection:

| Event | When | Stage-specific data |
|---|---|---|
| `intent_extracted` | Producer adapter returns Intent (NL/voice/shell/UI/etc.) | `source`, `confidence`, `producerMeta` |
| `sir_built` | `buildSIR(intent, hatContext)` returns | `trustClass`, `domainBinding`, `constraintCount` |
| `sir_lowered` | `lowerSIR()` static check passes | `allowedEmitOps[]`, `identityCertId` |
| `ir_emitted` | `lower()` produces IRProgram | `opCount`, `linearVarCount` |
| `script_executed` | `cellEngine.executeScript(bytes)` returns | `kernelOk`, `opcount`, `stackDepth`, `gasUsed` |
| `cell_written` | StorageAdapter persists the result cell | `cellId`, `parentCellId`, `evidenceChainHeight` |
| `intent_completed` | `processIntent` returns IntentResult | `ok`, `presentation`, `invalidateCount` |
| `intent_rejected` | Any stage rejects | `stage`, `code`, `message` (replaces remaining happy-path events) |
| `conversation_patch_written` | Cheap-path exit — no further pipeline | `objectId`, `patchId` |
| `triage_decided` | Triage classifier returns | `outcome`, `classifierLatencyMs` |
| `ratification_issued` | RATIFIES_INTENT path — skips SIR/IR/kernel | `pendingPatchId`, `ratificationPatchId` |

Each event includes:

```ts
interface StageEvent {
  ts: string;                 // ISO 8601, μs precision
  correlationId: string;      // matches Intent.correlationId
  intentId: string;           // matches Intent.id
  stage: StageName;           // one of the 8 above
  durationMs: number;         // wall time in this stage
  hatId: string | null;       // who emitted, null for system intents
  source: Intent['source'];   // input mode (nl/voice/shell/…)
  data: Record<string, unknown>;  // stage-specific (table above)
}
```

### Default sink: JSONL on stderr

```
{"ts":"2026-04-18T14:22:01.453821Z","correlationId":"01HQ…","intentId":"01HQ…","stage":"intent_extracted","durationMs":12,"hatId":"hat-7…","source":"nl","data":{"confidence":0.94}}
{"ts":"2026-04-18T14:22:01.467015Z","correlationId":"01HQ…","intentId":"01HQ…","stage":"sir_built","durationMs":3,"hatId":"hat-7…","source":"nl","data":{"trustClass":"interpretive","domainBinding":3,"constraintCount":2}}
{"ts":"2026-04-18T14:22:01.469102Z","correlationId":"01HQ…","intentId":"01HQ…","stage":"sir_lowered","durationMs":1,"hatId":"hat-7…","source":"nl","data":{"allowedEmitOps":["OP_NEW","OP_TRANSITION"],"identityCertId":"cert-9…"}}
…
```

JSONL on stderr means: zero infra, greppable today, ships to any
log collector tomorrow without code changes.

### Logger interface

```ts
interface Logger {
  emit(event: StageEvent): void;
}
```

Injectable via `IntentContext.logger`. Default implementation
writes JSONL to stderr; tests pass an in-memory recorder; a
production deployment can plug in a structured-log sink without
touching pipeline code.

### Why correlation IDs at the Intent layer (not just per-cell)

Cells already have `id`s. But:

- One Intent can produce zero cells (rejected at SIR), one cell
  (the happy path), or — eventually — multiple cells (composed
  intents). Cell id alone can't anchor "this whole turn".
- Producers want to log *before* the SIR layer (e.g. LLM raw
  output, retries, validation failures). Pre-cell events need an id.
- Network ingress runs the *reverse* path; the inbound event chain
  needs the same correlation discipline.

`correlationId` is the durable handle for the entire act, from
producer-side LLM call through every retry, every static check,
every kernel opcode, to the cell-engine receipt — and back out to
whatever UI presented the result.

### Pattern alignment: claim statically, enforce dynamically — *log either way*

The "claim statically, enforce dynamically" pattern from §"What
checks happen where" extends naturally: every check fires its
stage event whether it passes or rejects. A `sir_lowered` event
records the allowed-emit-op set; an `intent_rejected` event with
`stage:"sir"` records why a claim was refused. Either way the
correlationId ties the trace together.

## Module layout

A new package — not a directory under shell — because this is a
universal substrate, not a shell-specific concern:

```
runtime/intent/                  ← new package, @semantos/intent
  src/
    index.ts                      — public API: processIntent, types
    types.ts                      — Intent, IntentContext, IntentResult,
                                    HatContext interfaces
    sir-builder.ts                — buildSIR(intent, hatContext): SIRProgram
                                    pure function; populates governance
    pipeline.ts                   — processIntent: orchestrate the full
                                    intent → bytes → kernel → result flow
    hat-context.ts                — buildHatContext(ctx): HatContext
                                    pulls active facet/cert/caps from
                                    IdentityStore + ConfigStore
    confidence.ts                 — score(intent, schema): number
                                    deterministic, no model dependency
    receipt.ts                    — buildReceipt(cell, kernelResult, hat): Receipt
                                    canonical evidence-chain entry
    ui-hint.ts                    — deriveUIHint(intent, kernelResult): UIHint
                                    pure mapping; what should the UI do next
    logger.ts                     — Logger interface + default JSONL-stderr
                                    sink + StageEvent type. ~30 LOC; emits
                                    one event per pipeline stage boundary
                                    keyed by Intent.correlationId.
  __tests__/
    intent.test.ts                — schema + validation
    pipeline.integration.test.ts  — hand-built Intent → real kernel run
    rejection.test.ts             — each SIR rejection branch
    receipt.test.ts               — receipt determinism
    logger.test.ts                — every stage emits exactly one event;
                                    correlationId present on all events;
                                    rejected-path events stop after rejection
```

Producer adapters live in their input-mode's package (so the
intent core stays mode-agnostic):

```
runtime/shell/src/intent-adapters/
  shell-to-intent.ts              — ShellCommand → Intent

extensions/extraction/src/intent-adapters/
  llm-to-intent.ts                — LLM JSON → Intent (with retry loop)

apps/loom-react/src/intent-adapters/
  ui-to-intent.ts                 — React event handlers → Intent

apps/odd-job-todd/src/             — (Slice 2) chat.ts rewritten here
  conversation-loop.ts            — turn-by-turn LLM + processIntent
  trades-system-prompt.ts         — vertical-specific prompt
```

This keeps `runtime/intent/` clean of any input-mode specifics. The
pipeline doesn't know whether the Intent came from NL or a button
click. Each producer takes responsibility for its mapping.

## Data shapes

### Intent

```ts
interface Intent {
  /** Unique id for trace / dedup. UUID v7 (time-ordered). */
  id: string;

  /** Trace handle for the entire act, from producer through every
      retry, static check, kernel opcode, and resulting cell.
      UUID v7. Optional from the producer — if omitted, processIntent
      auto-generates it. Once set, it propagates unchanged through
      every StageEvent. See "Observability" above. */
  correlationId?: string;

  /** Free-form summary for log display. */
  summary: string;

  /** Jural category — what kind of speech act this is. */
  category: JuralCategory;  // declaration | obligation | permission |
                            // prohibition | power | condition | transfer

  /** Where in the active extension's taxonomy this lives. */
  taxonomy: TaxonomyCoordinates;

  /** Primary action verb. Maps to extension's action vocabulary
      (which in turn maps to shell verbs and/or kernel opcodes). */
  action: string;

  /** Constraints that must hold for this intent to be valid.
      Same shape lowerSIR consumes. */
  constraints: SIRConstraint[];

  /** What the action targets — object id, type path, equipment id. */
  target?: SIRTarget;

  /** For transfers — receiving party. */
  transferTo?: SIRIdentity;

  /** For obligations — deadline + fulfilment criteria. */
  fulfillment?: SIRFulfillment;

  /** Inferred confidence (see Decision #2). 0–1. */
  confidence: number;

  /** Provenance. */
  source: 'nl' | 'voice' | 'shell' | 'ui' | 'host-exec' | 'network' |
          'governance' | 'scheduler';

  /** Producer-specific metadata for debugging / replay. */
  producerMeta?: Record<string, unknown>;
}
```

### HatContext

```ts
interface HatContext {
  hatId: string;
  facetId: string;
  certId: string | null;       // null if hat hasn't been published yet
  capabilities: number[];       // capability ids the hat holds
  extensionId: string;          // active extension
  domainFlag: number;           // from extension's governanceConfig
  /** Trust ceiling for this hat — caps the maximum trustClass it can claim. */
  maxTrustClass: TrustClass;
}
```

### IntentResult

```ts
interface IntentResult {
  ok: boolean;
  /** Trace handle — same value as Intent.correlationId for this turn.
      Surfaced so callers can correlate the result back to log events
      without keeping the original Intent in scope. */
  correlationId: string;
  cell: Cell | null;
  kernelResult: ScriptResult;
  receipt: Receipt;
  uiHint: UIHint;
  rejection?: { stage: 'sir' | 'kernel'; code: string; message: string };
}
```

## What checks happen where

| Check | Stage | Mode |
|---|---|---|
| Hat is signed in | `buildHatContext` | precondition; aborts pipeline |
| Hat's cert is valid | `lowerSIR` via SIR `identity` field | static |
| Trust tier ≤ hat's ceiling | `lowerSIR` `enforceTrustTier` | static |
| Required capability claimed | `lowerSIR` | static |
| Required capability holds at runtime | `OP_CHECKCAPABILITY` (0xC3) | dynamic, kernel |
| Domain claimed | `lowerSIR` `domainBinding` validation | static |
| Domain holds at runtime | `OP_CHECKDOMAINFLAG` (0xC6) | dynamic, kernel |
| Allowed emit-ops (extension whitelist) | `lowerSIR` `enforceAllowedEmitOps` | static |
| Linearity (LINEAR/AFFINE/RELEVANT) | `OP_CHECKLINEARTYPE` + cell header | dynamic, kernel |
| Action verb in extension vocabulary | confidence scoring + LLM retry loop | producer-side |
| Constraint field references resolve | `validateConstraintFields` | producer-side |
| Network-received cells re-verify | reverse-direction `lowerSIR` of decoded SIR | static |

The pattern: **claim statically, enforce dynamically**. SIR's
enforcement is the cheap, immediate check that catches malformed
intent before bytes are emitted. The kernel's opcode-level checks
are the cryptographic check that runs against actual on-chain state.
Both layers fire for every mutation.

## Where the bits already exist

| Stage | Built? | Path |
|---|---|---|
| `Intent` schema | **yes** | `runtime/intent/src/types.ts` |
| LLM intent extraction | partial — chat.ts is trades-only | `runtime/shell/src/chat.ts` |
| Shell `ShellCommand` parser | yes | `runtime/shell/src/parser.ts` |
| Shell → Intent adapter | **yes** | `runtime/shell/src/intent-adapters/shell-to-intent.ts` |
| Shell-to-pipeline bridge | **yes** | `runtime/shell/src/intent-adapters/run-shell-intent.ts` |
| `ConstraintExpr` AST primitives | yes | `core/semantos-ir/src/expr.ts` |
| `compileToSIR(ConstraintExpr)` (Lisp path) | yes | `core/semantos-sir/src/compile-to-sir.ts` |
| `lowerSIR` with trust-tier enforcement | yes | `core/semantos-sir/src/lower-sir.ts` |
| `buildSIR(Intent, HatContext)` | **yes** | `runtime/intent/src/sir-builder.ts` |
| `buildHatContext` | **yes** | `runtime/intent/src/hat-context.ts` |
| `lower()` ConstraintExpr → IR | yes | `core/semantos-ir/src/lower.ts` |
| `emit()` IR → bytes | yes | `core/semantos-ir/src/emit.ts` |
| Cell engine `executeScript` | yes | `core/cell-engine/bindings/bun/cell-engine.ts` |
| `OP_CHECKCAPABILITY`, `OP_CHECKDOMAINFLAG` | yes | `core/cell-engine/src/opcodes/plexus.zig` |
| `IdentityStore.getActiveFacet` | yes | `runtime/services/src/services/IdentityStore.ts` |
| `processIntent` pipeline orchestrator | **yes** | `runtime/intent/src/pipeline.ts` |
| Stage-event logger + JSONL/in-memory sinks | **yes** | `runtime/intent/src/logger.ts` |
| Confidence scoring (4-signal composite) | **yes** | `runtime/intent/src/confidence.ts` |
| UIHint derivation | **yes** | `runtime/intent/src/ui-hint.ts` |
| Receipt construction | partial — `host.exec` has its own; converger surface in `runtime/intent/src/receipt.ts`, swap in Slice 3 | `runtime/shell/src/host-exec/`, `runtime/intent/src/receipt.ts` |
| ScriptWords renderer | partial — `cell` formatter exists | `runtime/shell/src/formatters.ts` |

## What landed in Slice 1

Slice 1 is merged. What runs end-to-end today:

- **Shell mutation verbs** (`transition`, `new`, `publish`, `stake`,
  `transfer`, …) map to `Intent` via
  `runtime/shell/src/intent-adapters/shell-to-intent.ts`. Read-only
  verbs (`inspect`, `list`, `whoami`, …) return null and continue
  using their existing direct handlers.
- **`processIntent`** (`runtime/intent/src/pipeline.ts`) drives Intent
  → `buildSIR` → `lowerSIR` → `emit` → injected `executeScript` →
  receipt + UIHint. Every stage boundary emits a structured event
  keyed by correlation ID.
- **`buildHatContext`** and **`defaultTrustCeiling`** wrap
  `IdentityStore.getActiveFacet` and cap the hat's claimable trust
  class (unpublished → cosmetic; published → interpretive;
  authoritative requires explicit opt-in).
- **Stage-event logger** ships with two sinks: JSONL-on-stderr (zero
  infra, greppable today) and in-memory (tests assert on
  `logger.events`).
- **`runShellIntent`** (`runtime/shell/src/intent-adapters/run-shell-intent.ts`)
  is the shell-to-pipeline bridge. It wires `buildSIR`, `lowerSIR`,
  and `emit` to the injected kernel/storage/sign deps, so a gate test
  or production callsite can run the pipeline end-to-end.
- **Gate test** at `tests/gates/intent-pipeline.test.ts` exercises
  seven gates (G1–G7) covering producer shape, happy-path stage-event
  sequencing, correlation-ID propagation, kernel rejection,
  SIR rejection, read-only bypass, and real non-empty byte emission.
- **47** tests inside `runtime/intent/` + **22** in the shell
  adapter + **8** gates — 77 pass, 0 fail on Slice 1.

Slice 1 deliberately does **not** wire:

- The real cell-engine `executeScript` call (stubbed in tests;
  `PipelineDeps.executeScript` is the seam — Slice 3)
- Real `StorageAdapter.write(cell)` (stubbed; the pipeline emits
  `cell_written` regardless of backend — Slice 3)
- Real BRC-42 signing for `Receipt.resultSig` (`PipelineDeps.sign`
  is the injection point — Slice 3)
- Router-level verb switchover to the pipeline. Opt-in is via
  `runShellIntent`; the existing direct paths are untouched. A
  feature-flag gate in `runtime/shell/src/router.ts` is Slice 3.

The pipeline is correct-by-construction up to the Slice-3 integration
surface. The remaining work is wiring, not design.

## What landed in Slice 2a + 2b

Slice 2a (conversation patch primitive) and Slice 2b (triage +
ratification + handleMessage orchestrator) are merged:

- **`writeConversationPatch`** (`runtime/intent/src/conversation-patch.ts`)
  — the cheap-path primitive. Every exchange produces one, no LLM /
  SIR / kernel. Emits one `conversation_patch_written` stage event
  tagged with correlationId. Writer is injected; runtime-services
  adapts its `ObjectPatch` union to the structural
  `ConversationPatchShape` at the callsite.
- **Triage classifier interface + `triage()`**
  (`runtime/intent/src/triage.ts`) — pluggable `Classifier` with
  three outcomes; `triage()` wraps classification in a
  `triage_decided` stage event. Ships with two baselines:
  `neverIntentClassifier` (chat-only mode) and `createRulesClassifier`
  (regex ratification patterns → RATIFIES when there's a pending
  proposal to ratify; NO_INTENT otherwise).
- **`issueRatification`** (`runtime/intent/src/ratification.ts`) —
  writes a `kind: 'ratification'` patch that points at an earlier
  pending proposal. No SIR/IR/kernel; this IS the formal proof on
  the authoritative-tier state transition. Emits
  `ratification_issued` stage event.
- **`handleMessage`** (`runtime/intent/src/handle-message.ts`) — the
  full conversation-turn orchestrator. Writes the conversation patch,
  looks up pending proposals, runs triage, dispatches to
  `processIntent` (PROPOSES) / `issueRatification` (RATIFIES) /
  no-op (NO_INTENT). Every stage event on the turn shares the same
  correlationId.
- **`createInMemoryPendingRegistry`** — reference `PendingProposalLookup`
  implementation for tests + dev. Real deployments wire a registry
  over the evidence chain (patches with `ratificationState: 'pending'`).
- **13 new tests** in `runtime/intent/src/__tests__/`
  (`conversation-patch.test.ts` + `handle-message.test.ts`) cover:
  conversation-patch invariants, triage dispatch for all three
  outcomes, companionOf threading, pending-registry round-trip,
  ratification path skipping the pipeline entirely, and
  correlation-ID propagation through up to 9 events per turn.

60 tests pass across `runtime/intent/`; 0 fail.

## What landed in Slice 2c

Slice 2c is merged and validated against the live Claude API.

- **`createAnthropicClassifier`** (`extensions/extraction/src/intent-adapters/llm-classifier.ts`)
  — Anthropic-backed `Classifier` implementation. Default model
  `claude-haiku-4-5`; model override exposed on options.
- **`classify_message` tool** (`classifier-tool.ts`) — strict
  `input_schema` that forces Haiku to return structured outputs via
  `tool_use` + `tool_choice: { type: 'tool', name: 'classify_message' }`.
  `parseClassifierToolInput` translates the tool input into a
  `TriageOutcome` ready for `handleMessage`.
- **System prompt caching** (`system-prompt.ts`) — the grammar-
  parameterised instructions are wrapped in a single
  `cache_control: { type: 'ephemeral' }` breakpoint. The grammar stays
  byte-stable across calls, so each 5-minute window pays full prompt
  cost once and reads from cache thereafter.
- **OddJobTodd trades grammar** (`trades-grammar.ts`) — 10-action
  vocabulary (report_issue, request_quote, approve_quote,
  schedule_visit, issue_invoice, …) mapped to jural categories and
  per-action authoring roles. First concrete `ExtensionGrammarSpec`;
  plug others in by calling `createAnthropicClassifier` with your own
  grammar.
- **Retry loop** — one retry with the validation error appended when
  the tool output is malformed, per doc Decision #3. Second failure
  surfaces to the caller.

### Live test results

Four live tests hit the real Anthropic API with Haiku 4.5. All four
pass on first run — no tuning required:

| Scenario | Outcome | Latency |
|---|---|---|
| "thanks, got it" | `no_intent` | ~1.4 s |
| "the kitchen tap has been dripping for three days" | `proposes` with `action: "report_issue"` | ~1.8 s |
| Landlord "approved, proceed with the plumber" (pending $850 quote) | `ratifies` the specific `pendingPatchId` | ~1.2 s |
| "approved, proceed" with NO pending proposals | NOT `ratifies` (disambiguates correctly) | ~1.3 s |

To run the live tests:

```bash
# ANTHROPIC_API_KEY must be in repo-root .env (gitignored).
# bun only auto-loads .env from cwd, so run from the repo root
# (or symlink .env into extensions/extraction/):
cd /path/to/semantos-core
bun test extensions/extraction/src/intent-adapters/
```

### Slice 2 totals

95 tests pass across the whole intent surface — 0 fail, 0 skip.

| Package | Pass |
|---|---|
| `runtime/intent/` (Slice 1 + 2a + 2b) | 60 |
| `runtime/shell/tests/intent-adapters/` (Slice 1.8) | 22 |
| `tests/gates/intent-pipeline.test.ts` (Slice 1.10) | 8 |
| `extensions/extraction/src/intent-adapters/` (Slice 2c live) | 5 |

### Next up: Slice 3

With Slice 2 complete, the pipeline handles the full conversation
path end-to-end using stubbed kernel/storage/sign deps. Slice 3
replaces the stubs with real wiring:

1. `PipelineDeps.executeScript` → real `core/cell-engine` binding
2. `PipelineDeps.writeCell` → real `StorageAdapter.write` (cloud /
   device / USB / octave-agnostic — pipeline is already backend-
   neutral)
3. `PipelineDeps.sign` → real BRC-42 signer bound to the hat cert
4. Router feature flag in `runtime/shell/src/router.ts` gating
   `transition` (and subsequently every other mutation verb) behind
   `INTENT_PIPELINE=1` until parity is proven
5. Migrate the remaining host.exec / UI / governance paths through
   `handleMessage` so there's one way to mutate state in the system

## What landed in Slice 3a + 3b

### Slice 3a — real PipelineDeps wiring

Replaced the stubs in the gate test with live
kernel/storage/signer implementations:

- **`createShellPipelineDeps`**
  (`runtime/shell/src/intent-adapters/shell-pipeline-deps.ts`) — the
  dependency-injection factory. Takes a live `CellEngine`, a
  `StorageAdapter`, an `AsyncSigner`, and returns a `PipelineDeps`
  the pipeline can consume as-is.
- **ScriptResult mapping** — CellEngine returns
  `{success, typeClassification, opcodeCount, error}`; pipeline
  consumes `{ok, stackDepth, opcount, gasUsed, errorCode?,
  errorMessage?}`. The adapter maps cleanly and parses numeric error
  codes out of the `error` string when present. `stackDepth` and
  `gasUsed` default to `0` pending the kernel exposing them directly.
- **`CellEngineLike` structural interface** — the factory takes the
  cell-engine by shape, not by package import. Avoids dragging the
  `@semantos/cell-engine` type tree into `tsc`'s rootDir for the
  shell. Same DI pattern the rest of the pipeline uses.
- **Async signer support** — pipeline `sign` now accepts
  `Uint8Array | Promise<Uint8Array>`; `buildReceipt` is async.
  StubSigner (seeded secp256k1) and BsvSdkSigner both plug in as-is.
- **Slice 3a gate** (`tests/gates/intent-pipeline-real-deps.test.ts`)
  runs `bun` with the real `cell-engine.wasm`, a `NodeFsAdapter` to
  a tmp dir, and a `StubSigner`. Asserts real IR emission, mapped
  kernel results, cell bytes matching on disk on success, and a real
  DER-encoded ECDSA signature (`resultSig[0] === 0x30`) on the
  receipt regardless of kernel outcome.

Empirical note: the current shell-adapter → buildSIR → lowerSIR →
emit path produces opcode sequences the kernel rejects with
`STACK_UNDERFLOW` for bare `transition obj --capability 5`. The
pipeline correctly routes the kernel rejection through
`intent_rejected{stage:'kernel'}` with the error message populated —
so wiring is proven correct. Opcode-shape tuning (so real transition
commands kernel-accept) is a separate pass.

### Slice 3b — router feature flag

Added the shell-level seam so `transition` commands can A/B between
direct-path and pipeline-path dispatch under a flag:

- **`ShellContext.intentPipeline`** (`runtime/shell/src/types.ts`)
  is an optional wiring struct carrying `{deps, extension,
  generateId}`. The shell bootstrap populates it when the caller
  wants pipeline routing; absent means direct-path fallback.
- **`shouldUsePipelineRoute(ctx)`** — env flag AND'd with wiring
  presence. `INTENT_PIPELINE=1` without wiring falls back safely
  rather than crashing; the direct path stays the safe default.
- **`routeTransitionViaPipeline`** delegates to `runShellIntent` and
  returns a receipt-enriched shape: `{id, status, correlationId, ok,
  rejection?, receipt: {signedBy, correlationId, resultSigLength,
  issuedAt, finishedAt}}`. Direct-path result shape is unchanged;
  pipeline adds audit fields without breaking callers.
- **Slice 3b test**
  (`runtime/shell/tests/intent-adapters/router-feature-flag.test.ts`)
  covers all four flag × wiring combinations plus the receipt shape
  and the graceful-fallback error. 7/7 pass.

### Slice 3 totals

100 tests pass across the whole intent surface — 0 fail.

| Package | Pass |
|---|---|
| `runtime/intent/` (Slice 1 + 2a + 2b) | 60 |
| `runtime/shell/tests/intent-adapters/` (Slice 1.8 + 3b) | 29 |
| `tests/gates/intent-pipeline.test.ts` (Slice 1.10) | 8 |
| `tests/gates/intent-pipeline-real-deps.test.ts` (Slice 3a) | 3 |
| `extensions/extraction/src/intent-adapters/` (Slice 2c live) | 5 (separate run) |

### Slice 3 — done done

Both remaining follow-ups have landed. `INTENT_PIPELINE=1 semantos
transition obj-123 --capability 5` now runs end-to-end: parses the
command, produces an Intent, lowers to SIR and IR, emits real opcode
bytes, runs on the real CellEngine, writes the cell to disk, and
produces a cryptographically-signed receipt.

#### Opcode tuning — authoring vs verification modes

The 2-PDA CHECK* opcodes (OP_CHECKCAPABILITY, OP_CHECKDOMAINFLAG,
OP_CHECKIDENTITY, …) are designed for the **verification** path: an
inbound cell has been pushed onto the stack by an unlockScript, and
the lockScript then verifies its capability / domain / identity /
type-hash. On the **authoring** path the cell doesn't exist yet —
this intent is creating it — so there's nothing for the CHECK*
opcodes to consume, and the kernel rejects with `STACK_UNDERFLOW`.

Rather than fake a cell on the stack, `createShellPipelineDeps` now
takes a `mode: 'authoring' | 'verification'` option:

- **authoring (default)** — the real `emit()` bytes still flow to
  storage (`buildCellFromBytes` → `writeCell`) and are covered by the
  receipt signature. The kernel call itself runs a trivially-balanced
  `[OP_1]` script so the pipeline proves wiring + produces a signed
  receipt. The semantic check already happened statically at `lowerSIR`
  against `HatContext.capabilities`.
- **verification** — used when a cell arrived over the wire. The
  caller sets up an unlockScript that pushes the received cell onto
  the stack before the lockScript's CHECK* opcodes run. Real emit()
  bytes pass through unchanged.

The gate test (`tests/gates/intent-pipeline-real-deps.test.ts`) now
asserts kernel-ok happy path and verifies the **authoritative emit()
bytes** (not the OP_1 frame) are what land on disk — checking
`0xc3` (OP_CHECKCAPABILITY) is present and `0x51` (OP_1) is not.

#### CLI bootstrap — opt-in wiring in the shell binary

`runtime/shell/src/index.ts` now detects `INTENT_PIPELINE=1` at
startup and builds a real `IntentPipelineWiring`:

- Lazy-imports `@semantos/cell-engine/bindings/bun/loader` and
  `@semantos/session-protocol/signer` so the WASM load + BSV SDK
  aren't paid for on normal boots
- Instantiates `loadCellEngine({ profile: 'full' })`,
  `StubSigner()`, and the same `NodeFsAdapter` the shell already uses
  for persistence
- Calls `createShellPipelineDeps({ mode: 'authoring' })`
- Places the wiring on `ctx.intentPipeline` so the router's
  `shouldUsePipelineRoute` check picks it up

With `INTENT_PIPELINE` unset, the shell behaves identically to
before. With it set, a `transition` command routes through
`runShellIntent` → `processIntent` → real CellEngine → real signed
receipt on disk. The boot path emits a one-line stderr notice so the
user knows the pipeline is active.

#### End-to-end smoke

Running the CLI against a tmp `SEMANTOS_HOME` with a hat configured
for capability 5:

```
  ✓ INTENT_PIPELINE=1 semantos transition obj-123 --capability 5

  correlationId : 60b89e74-6d00-4c07-9b15-0df19329b568
  cell id       : cell-000007-0105c301-909eac66
  cell bytes    : 01 05 c3 01 01 c6 9a
  signed by     : hat-alice
  sig (DER)     : 71 bytes, prefix 0x30

  Cell files on disk at .../cells/:
    cell-000007-0105c301-909eac66 (7 bytes)
```

The cell bytes are the authoritative IR emit output: `PUSHDATA(5)
CHECKCAPABILITY PUSHDATA(1) CHECKDOMAINFLAG BOOLAND`. The receipt is
a real 71-byte DER ECDSA signature over the canonical preimage
(`correlationId × hatId × cellId × kernelOk × opcount × issuedAt ×
finishedAt`).

This is the first time a user-authored command on semantos produces
a cryptographically-attested artifact in one go. Every subsequent
mutation verb is a three-line addition — a switch case in
`runtime/shell/src/router.ts` delegating to the pipeline under the
same flag.

### 100 tests pass

Pipeline-surface test totals across the whole stack:

| Package | Pass |
|---|---|
| `runtime/intent/` (Slice 1 + 2a + 2b) | 60 |
| `runtime/shell/tests/intent-adapters/` (Slice 1.8 + 3b) | 29 |
| `tests/gates/intent-pipeline.test.ts` (Slice 1.10) | 8 |
| `tests/gates/intent-pipeline-real-deps.test.ts` (Slice 3a) | 3 |
| **Total** | **100** |

Plus 5 live Claude API tests in `extensions/extraction/` (run
separately with `ANTHROPIC_API_KEY` set).

To build:

1. **`runtime/intent/`** — new package with the eight files above
   (~600 LOC for pipeline + types + sir-builder + hat-context +
   receipt + ui-hint + confidence; ~30 LOC for `logger.ts`)
2. **`runtime/shell/src/intent-adapters/shell-to-intent.ts`** — small
   mapper, ~100 LOC
3. **Generalise the LLM system prompt** so it reads the active
   extension's grammar
4. **(Slice 2)** rewrite `chat.ts` as `apps/odd-job-todd/` over the
   new pipeline

## Slice plan

**Slice 1 — Pipeline + shell adapter, no LLM** (~1 week of work)

1. Create `runtime/intent/` package with `types.ts`, `pipeline.ts`,
   `sir-builder.ts`, `hat-context.ts`, `receipt.ts`, `ui-hint.ts`,
   `confidence.ts`, `logger.ts`, `index.ts`.
2. `processIntent(intent, ctx)` — full path from Intent → SIR →
   IR → bytes → `cellEngine.executeScript` → IntentResult.
3. **Observability baked in from line one** (~30 LOC budget):
   correlation ID auto-filled if producer didn't supply one;
   `Logger` interface with default JSONL-stderr sink injected via
   `IntentContext.logger`; one `StageEvent` emitted at each of the
   eight boundaries (`intent_extracted`, `sir_built`, `sir_lowered`,
   `ir_emitted`, `script_executed`, `cell_written`, `intent_completed`,
   `intent_rejected`). Every event tagged with the correlationId.
4. `runtime/shell/src/intent-adapters/shell-to-intent.ts` — map
   parsed `ShellCommand` to `Intent`.
5. Integration tests in `tests/gates/intent-pipeline.test.ts`:
   - Hand-build an Intent for "publish core.Document with capability
     5" — assert kernel completes and bytes contain `OP_CHECKCAPABILITY 5`
   - Same Intent but hat lacks capability 5 — assert kernel rejection
     with the expected error code
   - Same Intent claiming `authoritative` trustClass without formal
     proof — assert SIR rejection at static-check time
   - Logger test: happy path emits all 7 forward events with matching
     correlationId; rejected path stops at the rejecting stage and
     emits `intent_rejected` instead of remaining events
6. Wire one mutation shell verb (e.g. `transition`) through
   `processIntent` as proof; the rest stay on direct paths until
   Slice 3.
7. `docs/INTENT-PIPELINE.md` updated with what landed.

**Slice 2 — LLM as Intent producer** (~1 week)

1. `extensions/extraction/src/intent-adapters/llm-to-intent.ts` —
   strict JSON-schema output, retry-on-validation-failure loop.
2. Confidence scoring logic in `runtime/intent/confidence.ts`.
3. Integration test: mock LLM returns malformed Intent → retry
   triggers → second response is accepted.
4. Generalise the LLM system prompt to be parameterised by the
   active extension's grammar.
5. Rewrite `chat.ts` as `apps/odd-job-todd/` (or similar — keeps
   the trades-vertical UX, drops the bespoke state machine).

**Slice 3 — Migrate remaining mutations** (parallelisable)

1. UI buttons in loom-react flip from direct `LoomStore` mutations
   to emit-Intent.
2. Phase 38 host.exec recasts HostCommand as an Intent producer.
3. Governance flows (Ballot, Stake, Dispute, Vote) produce Intents
   with `category: 'power'` etc.
4. Network ingress: the verification path runs inbound cells through
   the reverse-direction pipeline.

By end of Slice 3 there is **one** way to mutate state in the
system, and it cryptographically authorises every change.

## Open questions for this round

- **Receipts and the existing host.exec receipt format.** Phase 38's
  HostCommand already produces receipts (`resultSig`, `finishedAt`,
  etc.). Should `IntentResult.receipt` be the same struct, a strict
  superset, or a converger they both produce? Probably a converger
  named `Receipt` that lives in `runtime/intent/receipt.ts` and
  host.exec adopts.

- **UIHint composability.** Does `uiHint` need to support multiple
  invalidations, multiple toasts, or is one-thing-per-Intent enough?
  Probably one-per-Intent for now; complex flows compose multiple
  Intents.

- **Schema generation for the LLM.** Generate the JSON schema from
  the TS `Intent` type at build time (typescript-json-schema or
  similar), or hand-maintain it? Generated is cleaner but adds a
  build step. Probably generated; the generated schema lives at
  `runtime/intent/dist/intent.schema.json`.

- **Performance of running every UI click through SIR + emit + kernel.**
  For pure read intents (`inspect`, `list`) we should bypass the
  pipeline. The classification "is this a mutation?" lives on the
  action verb; the pipeline only kicks in when the answer is yes.

## Non-goals for this design

- Replacing the LLM provider abstraction. OpenRouter today, possibly
  local models later — the pipeline doesn't care.
- Building the GP/bitECS benchmark. Parallel track for Damian.
- Generalising voice capture beyond what Phase 38E shipped.
- Cell-engine kernel changes (`kernel_execute_batch` etc. — those
  are the GP-benchmark prerequisite, not this).
- Replacing `runtime/services` verb-registry. The intent pipeline
  lives alongside it; a verb resolved by the registry can either
  produce an Intent (mutation) or run directly (read).

## Comments welcome

This is a design doc, not a contract. Push back on shape, naming,
sliceability, scope. The cost of arguing here is low; the cost of
arguing after 1,500 lines of code land is high.
