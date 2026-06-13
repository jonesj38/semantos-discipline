---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/textbook/20-universal-intent.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.642530+00:00
---

# Universal Intent and the evidence chain

Part VI of this textbook covers the three boot steps that give a sovereign node its temporal posture: step 12 anchors time as a stack of hash chains, step 13 restores keys from a recovery payload, and step 14 opens metered resource flows. This chapter concerns the mechanism that threads through all three: the Intent pipeline.

Every state change a sovereign node performs — creating a cell, publishing a document, opening an MFP channel, casting a governance vote — begins as an act of intent. The pipeline described here is the single path every such act takes, regardless of which input modality produced it. It is the substrate's claim that no act mutates state without traversing this path, and that every traversal leaves a durable record in the evidence chain.

This chapter walks the full pipeline structure, names the eight Intent producers, explains the compression gradient each producer rides, and closes with a worked trace of one user-turn through all eight pipeline stages, every event tagged with the same correlation ID.

---

## Why a unified substrate

Before this pipeline existed, state mutation in the substrate was fragmented. Natural-language turns went one way; shell verbs went another; UI button clicks called store reducers directly; governance ballots had their own ad-hoc authorisation. The evidence chain — the hash-chain of cells that constitutes the substrate's auditable history — received only some of those mutations. Most never reached the cell engine at all.

The problem is not academic. If a governance ballot can change a permission without producing a cell, there is no cryptographic record of that change. If a UI button can move a card without checking capability, the substrate's K2 (authorisation) invariant is only advisory. If an incoming network cell is accepted without re-verifying the sender's governance context, the integrity of the evidence chain is contingent on the sender's honesty.

The Intent pipeline closes each of those gaps by treating every input mode as a producer of a single canonical type: `Intent`. Every `Intent` rides the same compilation path through SIR and OIR to opcode bytes. Every byte sequence is executed by the cell engine under its full set of opcodes. Every execution, whether it succeeds or fails, produces a cell that joins the evidence chain. Every stage boundary emits a structured log event keyed by the same correlation ID.

The result is a substrate in which there is exactly one way to mutate state: produce an Intent, process it, anchor the result.

---

## The compression gradient

The pipeline is an instance of the compression gradient that runs through this substrate. The gradient's direction is from high entropy (a natural-language sentence, a UI event, a voice transcript) to low entropy (a bounded sequence of opcode bytes for a deterministic automaton). Each layer reduces the representational space, makes structure explicit, and exposes a validation surface.

In the context of the Intent pipeline, the gradient has four named layers:

1. **Intent** — a structured TypeScript record with a jural category, taxonomy coordinates, action verb, constraints, target, and provenance fields. This is the canonical shape all producers converge on, regardless of input mode.

2. **SIR** (Semantic IR) — the Intent compiled into a semantic intermediate representation. SIR carries a governance context (`trustClass`, `proofRequirement`, `executionAuthority`, `domainBinding`, `identity`) and a typed constraint structure. It is the layer at which trust-tier and allowed-emit-ops enforcement happen statically, before any bytes are produced.

3. **OIR** (Opcode IR) — SIR lowered to A-normal form (ANF). Every sub-expression is bound to a name; operands are names or constants only. OIR is immediately lowerable to bytecode via the `emit()` pass.

4. **Opcode bytes** — the byte sequence the cell engine executes. The Plexus extension opcode range is `0x4C`–`0xD0`. Capability checks (`OP_CHECKCAPABILITY`, `0xC3`), domain checks (`OP_CHECKDOMAINFLAG`, `0xC6`), and linearity checks (`OP_CHECKLINEARTYPE`) are enforced dynamically here, against actual on-chain state, after the static checks at the SIR layer passed.

Each layer admits a canonical form, a validation rule, an explicit loss boundary, and an emit pass to the next layer. The signed bundle that eventually reaches the evidence chain is the terminal point of the gradient — a cell whose bytes are committed, hash-chained, and receipt-signed.

---

## The Intent type

The canonical Intent shape is:

```ts
interface Intent {
  id: string;                  // UUID v7, time-ordered, unique per Intent
  correlationId?: string;      // UUID v7; auto-filled by processIntent if absent
  summary: string;             // free-form, for log display only
  category: JuralCategory;     // one of the seven: declaration | obligation |
                               //   permission | prohibition | power |
                               //   condition | transfer
  taxonomy: TaxonomyCoordinates;
  action: string;              // extension-vocabulary verb
  constraints: SIRConstraint[];
  target?: SIRTarget;
  transferTo?: SIRIdentity;
  fulfillment?: SIRFulfillment;
  confidence: number;          // 0–1, computed deterministically
  source: 'nl' | 'voice' | 'shell' | 'ui' | 'host-exec' |
          'network' | 'governance' | 'scheduler';
  producerMeta?: Record<string, unknown>;
}
```

The `correlationId` is the durable handle for the entire act. It propagates unchanged through every stage event, every retry, every static check, every kernel opcode, and into the receipt that anchors the resulting cell. One failed turn is one log query: `grep <correlationId>`.

The `category` field carries the jural category. The seven categories — declaration, obligation, permission, prohibition, power, condition, transfer — are adapted from Hohfeld's analysis of jural relations and are the minimum vocabulary sufficient to type every act the substrate performs. The SIR layer uses the category to route governance context; `lowerSIR` enforces that the hat's trust ceiling matches the category's requirement before emitting bytes.

---

## The eight Intent producers

The pipeline defines eight sources (`source` values on the Intent type). Each is an independent producer that maps from its native input format to an `Intent` and hands it to `processIntent(intent, ctx)`. The pipeline does not know how the Intent was produced; producers take responsibility for their mapping.

### NL (natural language)

The natural-language producer calls an LLM with a strict JSON-schema output constraint derived from the `Intent` type. The system prompt is parameterised by the active extension's grammar — the LLM receives the available action vocabulary, taxonomy nodes, and constraint shapes for this extension only, not a hardcoded vocabulary.

Confidence is computed deterministically from four signals: required fields supplied, constraints passing `validateConstraintFields` against the active extension's field schema, action verbs present in the extension vocabulary, and taxonomy paths resolving to known nodes. The composite score (0–1) drives trust class:

- `≥ 0.9` → `interpretive` (use directly)
- `0.6–0.9` → `cosmetic` (require confirmation before execution)
- `< 0.6` → reject; surface a clarifying question to the user

The `authoritative` trust class is never assigned by the NL path. Only inputs that arrive with a real cryptographic proof — already-signed cells, host-exec chains — can claim `authoritative`.

On parse failure, the producer retries once with the validation error appended to the LLM context. On second failure, it surfaces to the user.

### Voice

Voice input routes through the same NL producer above. The Phase 38E voice-capture stack lands a transcript; the transcript enters the NL → Intent path. No separate voice pipeline exists. Voice is one more NL producer.

### Shell verb dispatch

The shell parser produces a `ShellCommand`. A small mapper converts it to an Intent:

```ts
parseCommand("new core.Document --title='Leaky tap report'")
  → ShellCommand
  → shellCommandToIntent
  → Intent {
      action: 'create',
      target: { typePath: 'core.Document' },
      category: 'declaration',
      source: 'shell',
      …
    }
```

Read-only verbs (`inspect`, `list`, `whoami`) return `null` from the mapper and continue on direct paths. Everything that mutates state goes through the pipeline. The router feature flag (`INTENT_PIPELINE=1`) enables the pipeline path in the shell; the direct path is the safe default until parity is proven.

### UI component bindings

UI elements declare the Intent they produce when activated:

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

`emit` is `processIntent` with the UI caller as response handler. The resulting `IntentResult` carries a `uiHint` that tells the UI whether to show a toast, open an approval dialog, re-render an inspector, or stay silent. The pipeline produces the structured hint; the UI layer renders it.

### Patch / host-exec

The host-exec `HostCommand` semantics are formalised as an Intent producer. A `HostCommand` is an Intent with `category: 'power'` and `source: 'host-exec'`. Patches and transitions issued internally also produce Intents via the same path.

### Governance ballots, stakes, and disputes

Governance flows map to Intents by jural category:

- `category: 'power'` — ballots that change rules
- `category: 'declaration'` — disputes that assert facts
- `category: 'transfer'` — stakes that move value

All three are the same Intent shape; they differ only in governance metadata. The SIR layer enforces that a tenant hat cannot propose a landlord-tier budget approval even if it tries — the trust-tier check at `lowerSIR` rejects it structurally.

### Network ingress (incoming cells)

A cell received from another node arrives as opcode bytes already. It enters the pipeline at the SIR verification stage, not the emit stage. The pipeline re-derives the SIR claim from the bytes and verifies it against the sender's claimed governance context. This is the reverse path: inbound bytes → SIR → governance check → accept or reject. The same correlation ID discipline applies.

### Scheduler

Scheduled jobs produce Intents with `source: 'scheduler'`. The scheduler holds a pending Intent record and calls `processIntent` at the trigger time. No other path is special-cased for scheduled execution; the pipeline is mode-agnostic.

---

## Pipeline stages

The pipeline is a single function, `processIntent(intent, ctx)`. Eight stage boundaries emit structured log events; on the happy path, seven fire in sequence. The eighth, `intent_rejected`, fires at any stage that rejects and replaces all remaining happy-path events.

```
Intent
  │
  ▼  [1] intent_extracted
  │     Producer adapter returns Intent
  │
  ▼  buildSIR(intent, hatContext)
  │
  ▼  [2] sir_built
  │     SIRProgram with governance context
  │
  ▼  lowerSIR()  — static checks: trust tier, allowed emit ops,
  │                identity cert, domain binding
  ▼  [3] sir_lowered
  │     IRProgram ready for emit
  │
  ▼  emit()
  │
  ▼  [4] ir_emitted
  │     Opcode bytes (0x4C–0xD0 range)
  │
  ▼  cellEngine.executeScript(bytes)
  │     OP_CHECKCAPABILITY (0xC3)  — dynamic: hat holds the cap
  │     OP_CHECKDOMAINFLAG (0xC6)  — dynamic: hat in the domain
  │     OP_CHECKLINEARTYPE          — dynamic: linearity invariant
  │
  ▼  [5] script_executed
  │     Kernel result: ok / rejected
  │
  ▼  StorageAdapter.write(cell)
  │
  ▼  [6] cell_written
  │     Cell joins the evidence chain
  │
  ▼  processIntent returns IntentResult
  │
  ▼  [7] intent_completed
        Result delivered to caller

  [8] intent_rejected  (replaces remaining events on any failure)
```

The pipeline is a single function. Every input mode is a producer; every output is a consumer of `IntentResult`.

---

## What checks happen where

The pattern across the pipeline is: claim statically, enforce dynamically.

| Check | Stage | Mode |
|---|---|---|
| Hat is signed in | `buildHatContext` (precondition) | abort pipeline |
| Hat cert is valid | `lowerSIR` via SIR identity field | static |
| Trust tier ≤ hat's ceiling | `lowerSIR` `enforceTrustTier` | static |
| Required capability claimed | `lowerSIR` | static |
| Required capability holds at runtime | `OP_CHECKCAPABILITY` (0xC3) | dynamic, kernel |
| Domain claimed | `lowerSIR` domainBinding validation | static |
| Domain holds at runtime | `OP_CHECKDOMAINFLAG` (0xC6) | dynamic, kernel |
| Allowed emit-ops (extension whitelist) | `lowerSIR` `enforceAllowedEmitOps` | static |
| Linearity (LINEAR / AFFINE / RELEVANT) | `OP_CHECKLINEARTYPE` + cell header | dynamic, kernel |
| Action verb in extension vocabulary | confidence scoring + LLM retry | producer-side |
| Network-received cells re-verify | reverse-direction `lowerSIR` of decoded SIR | static |

Static checks at the SIR layer are cheap and immediate: they catch malformed intent before bytes are emitted. Dynamic checks in the cell engine are the cryptographic enforcement that runs against actual on-chain state. Both layers fire for every mutation. A `sir_lowered` event records the allowed-emit-op set on the happy path; an `intent_rejected` event with `stage: "sir"` records why a claim was refused on the failure path. Either way the correlation ID ties the trace.

---

## The conversation turn: triage, patches, and ratification

Not every user-turn should trigger the full pipeline. A reply of "thanks, got it" should not invoke an LLM, a SIR compiler, or a cell engine. The triage layer sits between the NL and voice producers and `processIntent`, classifying each turn before any expensive work runs.

Three outcomes are possible:

```ts
type TriageOutcome =
  | { kind: 'no_intent';  reason: string }
  | { kind: 'proposes';   intent: Intent }
  | { kind: 'ratifies';   pendingPatchId: PatchId; attestation: Signature }
```

**NO_INTENT** — a conversation patch is written (cheap, no SIR, no kernel), the pipeline halts, and a `conversation_patch_written` stage event fires. This is the path "thanks, got it" takes.

**PROPOSES_INTENT** — the full pipeline runs. The resulting Intent carries a `companionOf` pointer to the source conversation patch. The derived patch is marked `ratificationState: 'pending'`.

**RATIFIES_INTENT** — the message is a cryptographic acceptance of an earlier pending proposal. SIR, OIR, and the kernel are skipped entirely; a `RatificationPatch` is written pointing at the pending patch's ID. The ratification is the formal proof on the earlier authoritative-tier state transition. A `ratification_issued` stage event fires.

The ratification path is what makes authoritative-tier attestation cheap at runtime. A landlord's approval of a quote does not need a fresh SIR program; it needs a cryptographic signature referencing the pending proposal patch. The substrate guarantees every eventual state change traces to a conversation patch via a typed `companionOf` graph link — not a text search, not a log scan.

Each message is a patch authored by a hat. Trust tier is a per-patch property; `lowerSIR` rejects cross-role authoritative claims structurally.

---

## The evidence chain

The evidence chain is the ordered sequence of cells that records the substrate's history for a given object. Every cell has:

- A content hash (`prevStateHash`) linking it to its predecessor
- A linearity class (LINEAR, AFFINE, RELEVANT, UNRESTRICTED) enforced by K1
- A domain flag binding enforced by K3
- An owner identifier and timestamp
- The opcode bytes that produced it, as the cryptographic assertion of authorisation

The pipeline contributes to the evidence chain via the `StorageAdapter.write(cell)` call at stage 6 (`cell_written`). The storage adapter is a black box to the pipeline — cloud, on-device, USB, or octave-linked multi-cell storage is the adapter's concern. The pipeline emits one `cell_written` event per logical cell regardless of backend.

Conversation patches, ratification patches, and derived patches also accumulate on the evidence chain via the `writeConversationPatch` primitive and `issueRatification`. The full per-object history — conversation, derived, ratification — is the auditable record that compliance tooling and governance flows inspect.

When a cell is received from another node over the mesh, it arrives as a SignedBundle (a BRC-100-signed envelope carrying identity key, nonce, timestamp, and signature). The pipeline's network-ingress path re-derives the SIR claim from the bytes and verifies it before accepting the cell into the local evidence chain.

---

## Observability: the stage event wire format

Every stage boundary emits one `StageEvent` to the configured logger:

```ts
interface StageEvent {
  ts: string;                  // ISO 8601, microsecond precision
  correlationId: string;       // matches Intent.correlationId throughout
  intentId: string;            // matches Intent.id
  stage: StageName;
  durationMs: number;          // wall time in this stage
  hatId: string | null;        // signing hat, null for system intents
  source: Intent['source'];    // input mode
  data: Record<string, unknown>;  // stage-specific payload (table below)
}
```

Stage-specific data fields:

| Stage | Key data fields |
|---|---|
| `intent_extracted` | `source`, `confidence`, `producerMeta` |
| `sir_built` | `trustClass`, `domainBinding`, `constraintCount` |
| `sir_lowered` | `allowedEmitOps[]`, `identityCertId` |
| `ir_emitted` | `opCount`, `linearVarCount` |
| `script_executed` | `kernelOk`, `opcount`, `stackDepth`, `gasUsed` |
| `cell_written` | `cellId`, `parentCellId`, `evidenceChainHeight` |
| `intent_completed` | `ok`, `presentation`, `invalidateCount` |
| `intent_rejected` | `stage`, `code`, `message` |
| `conversation_patch_written` | `objectId`, `patchId` |
| `triage_decided` | `outcome`, `classifierLatencyMs` |
| `ratification_issued` | `pendingPatchId`, `ratificationPatchId` |

The default sink is JSONL on stderr — zero infrastructure, greppable immediately, and shippable to any log collector without code changes.

Why correlation IDs at the Intent layer rather than just per-cell? Three reasons. First, one Intent can produce zero cells (rejected at SIR), one cell (happy path), or eventually multiple cells (composed Intents). Cell ID alone cannot anchor the turn. Second, producers log before the SIR layer — LLM raw output, retries, validation failures — and pre-cell events need an ID. Third, network ingress runs the reverse path; the inbound event chain needs the same correlation discipline. The correlation ID is the durable handle from producer-side LLM call through every retry, every static check, every kernel opcode, to the cell-engine receipt and back out to whatever caller presented the result.

---

## The IntentResult

The pipeline's return value carries enough structure for any caller to do the right thing:

```ts
interface IntentResult {
  ok: boolean;
  correlationId: string;      // same value as Intent.correlationId
  cell: Cell | null;          // null if rejected before bytes
  kernelResult: ScriptResult;
  receipt: Receipt;            // cryptographic evidence-chain entry
  uiHint: {
    presentation: 'toast' | 'inspector' | 'inline' | 'silent';
    invalidate: string[];     // object IDs that should re-render
    followUp?: { kind: 'confirm' | 'clarify'; prompt: string };
  };
  rejection?: {
    stage: 'sir' | 'kernel';
    code: string;
    message: string;
  };
}
```

The `correlationId` on `IntentResult` is the same value set on the originating Intent. Callers can correlate the result back to every log event without keeping the original Intent in scope.

Callers use the result as follows:

- Shell / REPL: print rendered ScriptWords and the kernel result
- UI: use `uiHint.invalidate` to re-render and `uiHint.presentation` for the modal-vs-toast decision
- Voice: speak back the result summary
- Network sender: broadcast the cell and receipt to the destination
- Governance UI: display the receipt as evidence in the ballot's audit trail

The pipeline does not render UI. It produces enough structured information for any presentation layer to render correctly.

---

## Module layout

The pipeline lives in `runtime/intent/` — a package separate from the shell because this is a universal substrate concern, not a shell-specific one:

```
runtime/intent/
  src/
    index.ts           — public API: processIntent, types
    types.ts           — Intent, IntentContext, IntentResult, HatContext
    sir-builder.ts     — buildSIR(intent, hatContext): SIRProgram
    pipeline.ts        — processIntent orchestrator
    hat-context.ts     — buildHatContext(ctx): HatContext
    confidence.ts      — score(intent, schema): number
    receipt.ts         — buildReceipt(cell, kernelResult, hat): Receipt
    ui-hint.ts         — deriveUIHint(intent, kernelResult): UIHint
    logger.ts          — Logger interface + default JSONL-stderr sink
    conversation-patch.ts  — writeConversationPatch primitive
    triage.ts          — triage() + Classifier interface
    ratification.ts    — issueRatification
    handle-message.ts  — full conversation-turn orchestrator
```

Producer adapters live in their input-mode's own package, keeping the intent core mode-agnostic:

```
runtime/shell/src/intent-adapters/
  shell-to-intent.ts          — ShellCommand → Intent
  run-shell-intent.ts         — shell-to-pipeline bridge
  shell-pipeline-deps.ts      — createShellPipelineDeps factory

extensions/extraction/src/intent-adapters/
  llm-to-intent.ts            — LLM JSON → Intent (with retry loop)
  llm-classifier.ts           — LLM-backed Classifier implementation

apps/loom-react/src/intent-adapters/
  ui-to-intent.ts             — React event handlers → Intent
```

---

## What is built and what is stub

Slices 1 through 3 of the pipeline are merged. The following runs end-to-end:

- Shell mutation verbs (`transition`, `new`, `publish`, `stake`, `transfer`) map to Intent via `shell-to-intent.ts`. Read-only verbs return `null` and use their existing direct handlers.
- `processIntent` drives Intent → `buildSIR` → `lowerSIR` → `emit` → `executeScript` → receipt + UIHint. Every stage boundary emits a structured event keyed by correlation ID.
- `buildHatContext` and `defaultTrustCeiling` wrap `IdentityStore.getActiveFacet` and cap the hat's claimable trust class (unpublished → `cosmetic`; published → `interpretive`; `authoritative` requires explicit opt-in).
- Real cell engine (`core/cell-engine.wasm`), real storage (`NodeFsAdapter`), and real BRC-42 signing are wired via `createShellPipelineDeps` under the `INTENT_PIPELINE=1` feature flag.
- The LLM-backed `Classifier` runs the triage layer for NL/voice turns; system prompt caching keeps the per-call cost low across the 5-minute TTL window.
- `handleMessage` is the full conversation-turn orchestrator: it writes the conversation patch, runs triage, and dispatches to `processIntent`, `issueRatification`, or no-op as appropriate.

The remaining wiring (full router-level verb switchover; UI and governance paths through `handleMessage`; Phase 35B federation) is scheduled with the deliverables that gate those paths in the Unification Matrix.

---

## Worked trace: one user-turn end-to-end

The following traces a single user-turn — a tenant reporting a maintenance issue via a natural-language message — through all eight pipeline stages. Every event carries the same correlation ID.

### Setup

- Actor: a tenant hat, `hat-alice`, holding capability 3 (content creation) in governance domain `0x00010001` (property management tenant domain)
- Extension: property management vertical
- Message: "the kitchen tap has been dripping for three days"
- Triage classifier outcome: `proposes` with `action: "report_issue"`, jural category `declaration`

### Trace table

```
┌────────────────────────────────────────────────────────────────────────────────────┐
│  correlation-id: 01JMX8V4N2-7F3A-0000-B1C2-3D4E5F6A7B8C                         │
├──────────────────┬──────────────────────────┬──────────────────────────────────────┤
│  timestamp (μs)  │  stage                   │  selected data                       │
├──────────────────┼──────────────────────────┼──────────────────────────────────────┤
│  14:22:01.421000 │  conversation_patch_      │  objectId: "obj-lease-4421"          │
│                  │  written                 │  patchId:  "patch-conv-0091"         │
│                  │                          │  kind:     "conversation"            │
├──────────────────┼──────────────────────────┼──────────────────────────────────────┤
│  14:22:01.433000 │  triage_decided          │  outcome:  "proposes"                │
│                  │                          │  classifierLatencyMs: 1812           │
│                  │                          │  action:   "report_issue"            │
├──────────────────┼──────────────────────────┼──────────────────────────────────────┤
│  14:22:01.453000 │  intent_extracted        │  source:     "nl"                    │
│                  │  (NL producer N=1)       │  confidence: 0.94                    │
│                  │                          │  category:   "declaration"           │
│                  │                          │  action:     "report_issue"          │
│                  │                          │  hatId:      "hat-alice"             │
├──────────────────┼──────────────────────────┼──────────────────────────────────────┤
│  14:22:01.467000 │  sir_built               │  trustClass:    "interpretive"       │
│                  │                          │  domainBinding: 0x00010001           │
│                  │                          │  constraintCount: 2                  │
│                  │                          │  proofRequirement: "none"            │
├──────────────────┼──────────────────────────┼──────────────────────────────────────┤
│  14:22:01.469000 │  sir_lowered             │  allowedEmitOps: ["OP_NEW",          │
│                  │                          │                   "OP_TRANSITION"]   │
│                  │                          │  identityCertId: "cert-alice-0029"   │
│                  │                          │  trustTierCheck: "pass"              │
├──────────────────┼──────────────────────────┼──────────────────────────────────────┤
│  14:22:01.471000 │  ir_emitted              │  opCount:       7                    │
│                  │                          │  linearVarCount: 1                   │
│                  │                          │  bytes (hex): 01 03 c3 01 01 c6 9a  │
├──────────────────┼──────────────────────────┼──────────────────────────────────────┤
│  14:22:01.474000 │  script_executed         │  kernelOk:   true                    │
│                  │                          │  opcount:    7                       │
│                  │                          │  stackDepth: 0                       │
│                  │                          │  gasUsed:    0 (authoring mode)      │
├──────────────────┼──────────────────────────┼──────────────────────────────────────┤
│  14:22:01.477000 │  cell_written            │  cellId: "cell-000042-0103c301-      │
│                  │                          │           01c69a00"                  │
│                  │                          │  parentCellId: "cell-000041-…"       │
│                  │                          │  evidenceChainHeight: 42             │
├──────────────────┼──────────────────────────┼──────────────────────────────────────┤
│  14:22:01.479000 │  intent_completed        │  ok:             true                │
│                  │                          │  presentation:   "toast"             │
│                  │                          │  invalidateCount: 1                  │
│                  │                          │  correlationId:  [same as header]    │
└──────────────────┴──────────────────────────┴──────────────────────────────────────┘
```

### Stage-by-stage narrative

**Stage 1 — conversation_patch_written.** Before the triage classifier runs, the turn is recorded as a conversation patch on object `obj-lease-4421`. This is the cheap-path anchor: even if the pipeline rejects the intent, a human-readable record of the turn exists in the evidence chain.

**Stage 2 — triage_decided.** The LLM-backed classifier receives the message "the kitchen tap has been dripping for three days" against the property management grammar (10-action vocabulary: `report_issue`, `request_quote`, `approve_quote`, etc.). It returns `proposes` with `action: "report_issue"`. Classifier latency is 1,812 ms. The `proposes` outcome sends control to the NL producer.

**Stage 3 — intent_extracted (NL producer, producer N=1).** The NL producer maps the classifier output to a fully typed `Intent`. `category` is `declaration` — the issue report is a statement of fact, not a transfer of value or exercise of power. `confidence` is 0.94 — all required fields are present, the action verb resolves in the grammar, the taxonomy path is known. The `correlationId` is set here (auto-filled by `processIntent`); it will not change for the remainder of the turn.

**Stage 4 — sir_built.** `buildSIR(intent, hatContext)` populates the governance context. `trustClass` is `interpretive` (confidence ≥ 0.9, hat is published). `domainBinding` is `0x00010001`. Two constraints are compiled: a capability constraint (capability 3, content creation) and a taxonomy coordinate constraint (issue reports in the property management lexicon). `proofRequirement` is `"none"` — a declaration at interpretive tier does not require a formal cryptographic proof.

**Stage 5 — sir_lowered.** `lowerSIR()` runs the static checks. The hat's maximum trust class is `interpretive` (published, not `authoritative`); the claimed class matches. Capability 3 is in the hat's declared capability set. The domain `0x00010001` is within the hat's domain flag scope. The allowed emit-ops for the property management extension are `["OP_NEW", "OP_TRANSITION"]`; the SIR program requests only `OP_NEW`. All static checks pass. The identity cert ID is logged for the audit trail.

**Stage 6 — ir_emitted.** `emit()` lowers the OIR to 7 opcode bytes: `PUSHDATA(3) OP_CHECKCAPABILITY PUSHDATA(1) OP_CHECKDOMAINFLAG OP_BOOLAND`. These are the authoritative bytes — `0xc3` (OP_CHECKCAPABILITY) and `0xc6` (OP_CHECKDOMAINFLAG) are present; they encode the static claims made at the SIR layer into the cell's bytecode payload.

**Stage 7 — script_executed.** The cell engine executes the opcode bytes. In authoring mode (this is a new cell, not a verification of an inbound one), the pipeline runs a trivially-balanced frame to prove wiring; the authoritative IR bytes flow to storage. The kernel returns `ok: true`. `gasUsed` is reported as 0 in authoring mode; the linearity invariant K1 is satisfied because the new cell does not consume a pre-existing LINEAR resource.

**Stage 8 — cell_written.** `StorageAdapter.write(cell)` persists the cell. `cellId` is derived from the cell's content hash; `evidenceChainHeight` advances to 42. The cell's `prevStateHash` links it to cell 41 in the evidence chain for this object. The cell carries a receipt: a 71-byte DER ECDSA signature over the canonical preimage (`correlationId × hatId × cellId × kernelOk × opcount × issuedAt × finishedAt`).

**stage — intent_completed.** `processIntent` returns `IntentResult` with `ok: true`. `presentation` is `"toast"` — a small notification is appropriate for a successful issue report. `invalidateCount` is 1 — the lease object's inspector should re-render to show the new issue. `correlationId` is surfaced on the result so the UI can correlate the result back to the log stream without keeping the original Intent in scope.

### The anchored cell

The cell that lands in the evidence chain at position 42 carries:

- Its `prevStateHash` linking it to the prior cell
- Linearity class `UNRESTRICTED` (an issue report is not a consumable resource)
- Domain flag `0x00010001`
- Owner `hat-alice` / cert `cert-alice-0029`
- Opcode bytes `01 03 c3 01 01 c6 9a` as the cryptographic assertion that capability 3 was checked and domain `0x00010001` was verified
- A BRC-42-signed receipt anchoring the entire turn

Every subsequent act on this lease object — a contractor quote, an approval, a payment, a closure — will produce its own cell, each hash-chained to its predecessor. The evidence chain for the lease is a cryptographically-ordered sequence of typed acts, each traceable back to the hat that authored it and the governance context it claimed.

A query of the form `grep 01JMX8V4N2-7F3A-0000-B1C2-3D4E5F6A7B8C` against the JSONL log stream returns all nine events for this turn in timestamp order, from the conversation patch write through the intent completion. The cell ID in the `cell_written` event is the durable anchor in the evidence chain. Between the log stream and the evidence chain, the turn is fully reconstructible.
