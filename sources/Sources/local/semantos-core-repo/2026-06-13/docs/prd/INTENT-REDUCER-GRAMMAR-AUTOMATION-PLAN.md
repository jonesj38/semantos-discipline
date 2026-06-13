---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/INTENT-REDUCER-GRAMMAR-AUTOMATION-PLAN.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.661801+00:00
---

# Intent Reducer & Grammar Automation — Tracking Matrix

**Status:** In progress  
**Date:** 2026-05-09  
**Audience:** Todd, Bert  
**Depends on:** M5.10 (Bert's intent reducer), DB pipeline M5.1–M5.3 (SIR schema), runtime/intent pipeline (merged)

---

## 0. Architecture direction

**Canonical location:** `semantos-core`. All extraction, conversation logic, intent reduction, and grammar automation live here and are exported as packages.

**oddjobtodd deprecation:** `apps/oddjobtodd/` (Next.js Vercel app) is being deprecated. New features go into `extensions/oddjobz/` in semantos-core. The exported package is `@semantos/oddjobz`.

**Already ported (do not duplicate):**
- `AccumulatedJobState` → `extensions/oddjobz/src/conversation/accumulated-job-state.ts` (D-O7)
- LLM extraction resource → `extensions/oddjobz/src/lead-extract.ts` (D-O6b)

**Import direction rule:** `runtime/intent` imports from `@semantos/oddjobz` (for `AccumulatedJobState`), never from `apps/oddjobtodd`. `extensions/oddjobz` imports from `runtime/intent` for the reducer. No circular imports.

**I-13 target:** Wire reducer into `extensions/oddjobz/src/conversation/chat-service.ts` (to be created), not into `apps/oddjobtodd/src/lib/services/chatService.ts`.

---

## 1. What this plan tracks

Three tightly coupled workstreams that form the full closed loop from natural-language utterance to on-chain cell:

1. **Intent reducer** — the stepped compiler that closes the open seam between LLM extraction output (`taggedFacts[]`) and the canonical `Intent` type that `processIntent` consumes. Implements the trivium/quadrivium decomposition described in `docs/textbook/32-trivium-quadrivium-intent-reducer.md`.

2. **Pask-backed TaxonomyMapper** — replaces the Levenshtein name-similarity heuristic in `extensions/extraction/src/inference/grammar-diff.ts` with Pask interaction-propagation, so taxonomy coordinate assignment is learned from trial API calls rather than hardcoded string matching.

3. **Grammar automation entry point** — a single async function that takes an API spec (URL, Swagger doc, or live endpoint) and produces a validated, AFFINE `ExtensionManifest` draft by running the full inference pipeline: probe → EntityGraph → Pask TaxonomyMapper → GrammarDiff → GrammarComposer → validateExtensionGrammar.

---

## 2. Tracking matrix

### Pre-conditions (must land before any I-2..I-8 worktrees open)

| ID | Deliverable | File | Status | Notes |
|---|---|---|---|---|
| I-0a | Add `trustClass?: TrustClass` and `proofRequirement?: ProofRequirement` to `ExtensionGrammarSpec` | `extensions/extraction/src/intent-adapters/trades-grammar.ts` | **done** | Astronomy pass needs these; imported from `@semantos/semantos-sir` |
| I-0b | Rename local `ExtensionGrammar` interface → `ConfidenceContext` in `confidence.ts` | `runtime/intent/src/confidence.ts` | **done** | Resolved name-collision with `@semantos/protocol-types`; re-export in `index.ts` updated |
| I-0c | Create `runtime/intent/src/reducer/types.ts` — freeze `Pass`, `PassFn`, `PassResult`, `ReducerOptions`, `ReducerResult`, `ReducerInputState`, `GrammarSpec` | `runtime/intent/src/reducer/types.ts` | **done** | All pass worktrees import from this; `GrammarSpec` is minimal structural interface (lower-layer rule); `AccumulatedJobState` satisfies `ReducerInputState` |
| I-0d | Confirm `@semantos/oddjobz` package exports `AccumulatedJobState` so `runtime/intent` can import it | `extensions/oddjobz/src/conversation/index.ts` | **done** | Already exported; `AccumulatedJobState` satisfies `ReducerInputState` structurally |

### Workstream I: Intent Reducer (trivium/quadrivium stepped compiler)

| ID | Deliverable | File | Status | Deps | Owner |
|---|---|---|---|---|---|
| I-1 | `Intent` type audit — confirm all fields align with `taggedFacts` output shape | — | **done** | — | Todd |
| I-2 | Trivium pass 1: Grammar — `taggedFacts → taxonomy.what` (structural entity identification) | `runtime/intent/src/reducer/grammar-pass.ts` | **done** | I-1 | — |
| I-3 | Trivium pass 2: Logic — `taggedFacts + action → taxonomy.how` (relational binding) | `runtime/intent/src/reducer/logic-pass.ts` | **done** | I-2 | — |
| I-4 | Trivium pass 3: Rhetoric — `taggedFacts → TaggedCategory + action` (speech act classification) | `runtime/intent/src/reducer/rhetoric-pass.ts` | **done** | I-3 | — |
| I-5 | Quadrivium pass 1: Arithmetic — numeric fields → `SIRConstraint { kind: 'value' \| 'interlock' }[]` | `runtime/intent/src/reducer/arithmetic-pass.ts` | **done** | I-4 | — |
| I-6 | Quadrivium pass 2: Geometry — location fields → `taxonomy.where` + spatial constraints | `runtime/intent/src/reducer/geometry-pass.ts` | **done** | I-5 | — |
| I-7 | Quadrivium pass 3: Music — urgency/deadline fields → `SIRConstraint { kind: 'temporal' }[]` | `runtime/intent/src/reducer/music-pass.ts` | **done** | I-6 | — |
| I-8 | Quadrivium pass 4: Astronomy — domain flag + confidence → `GovernanceContext` | `runtime/intent/src/reducer/astronomy-pass.ts` | **done** | I-7 | — |
| I-9 | Pass composer — sequential reduction through all 7 passes with dedup + geometric-mean confidence | `runtime/intent/src/reducer/index.ts` | **done** | I-2..I-8 | — |
| I-10 | Rejection relay — maps SIR rejection codes to responsible passes | `runtime/intent/src/reducer/rejection-relay.ts` | **done** | I-9 | — |
| I-11 | Integration test: trades vertical — `ReducerInputState → Intent` round-trip | `runtime/intent/src/__tests__/reducer-trades.test.ts` | **done** | 19/19 passing — 5 scenarios (report, approve, schedule, invoice, ambiguous) |
| I-12 | Integration test: SCADA vertical — same round-trip with ControlSystemsLexicon | `runtime/intent/src/__tests__/reducer-scada.test.ts` | **done** | 15/15 passing — 5 scenarios + lexicon isolation tests |
| I-13 | Wire reducer into oddjobz chat service (semantos-core, not oddjobtodd) | `extensions/oddjobz/src/conversation/chat-service.ts` | **done** | I-11 | — |

### Workstream G: Grammar Automation

| ID | Deliverable | File | Status | Deps | Owner |
|---|---|---|---|---|---|
| G-1 | Pask store seed — pre-load known grammar fields as cells in a dedicated Pask store | `extensions/extraction/src/inference/pask-seed.ts` | done | — | — |
| G-2 | Pask TaxonomyMapper — replace Levenshtein matching in grammar-diff with `Store.interact()` propagation | `extensions/extraction/src/inference/pask-taxonomy-mapper.ts` | done | G-1 | — |
| G-3 | API probe runner — issues sample HTTP calls to a live endpoint; builds EntityGraph from response shapes | `extensions/extraction/src/inference/api-probe.ts` | done | — | — |
| G-4 | Swagger/OpenAPI ingester — builds EntityGraph from static spec file (alternative input path to G-3) | `extensions/extraction/src/inference/swagger-ingester.ts` | done | — | — |
| G-5 | Grammar automation entry point — orchestrates G-3/G-4 → Pask TaxonomyMapper → GrammarDiff → GrammarComposer | `extensions/extraction/src/auto-grammar.ts` | done | G-2, G-3, G-4 | — |
| G-6 | AFFINE manifest wrapper — wraps composed grammar in an `ExtensionManifest` with draft governance config | `extensions/extraction/src/manifest-wrapper.ts` | done | G-5 | — |
| G-7 | CLI entry point — Bun script `bun run auto-grammar -- --swagger <file> --domain-flag 42` | `extensions/extraction/bin/auto-grammar.ts` | done | G-6 | — |
| G-8 | Integration test: PropertyMe swagger → ExtensionGrammar roundtrip | `extensions/extraction/src/inference/__tests__/propertyme-auto.test.ts` | done | G-5 | 7/7 |
| G-9 | Integration test: SCADA probe → ExtensionGrammar roundtrip | `extensions/extraction/src/inference/__tests__/scada-auto.test.ts` | done | G-5 | 6/6 |
| G-10 | Governance graduation: AFFINE draft → RELEVANT published via L1 ballot | governance ballot machinery | pending | G-6 | — |

### Workstream MT: Multi-turn Torture Suite

| ID | Deliverable | File | Status |
|---|---|---|---|
| MT-1..MT-12 | 39-test multi-turn conversation torture suite | `extensions/oddjobz/src/conversation/__tests__/chat-service-torture.test.ts` | **done** — 39/39 passing |

### Workstream L: LLM Tagger Path

| ID | Deliverable | File | Status | Notes |
|---|---|---|---|---|
| L-1 | Extend `buildTradesTaggedFactsSection()` — add jural lexicon with 5 categories + examples | `extensions/oddjobz/src/prompts/extraction-prompt.ts` | **done** | LLM now emits both `jural` and `trades-job-types` facts; rhetoric-pass has reliable signal |
| L-2 | `extractConversationTurn()` — LLM call layer over extraction prompt | `extensions/oddjobz/src/conversation/turn-extractor.ts` | **done** | Uses `claude-haiku-4-5`; parameterised client for DI |
| L-3 | Response parser + tagged-fact validator | `extensions/oddjobz/src/conversation/turn-extractor.ts` | **done** | Strips markdown fences, extracts first balanced JSON object, sanitises `taggedFacts[]` |
| L-4 | `runConversationTurn()` pipeline — composes `extractConversationTurn → mergeExtraction → processConversationTurn` | `extensions/oddjobz/src/conversation/pipeline.ts` | **done** | Single-call surface for callers with raw messages |
| L-5 | Fixture unit tests — `parseExtractionResponse` with 9 captured response shapes (no API) | `extensions/oddjobz/src/conversation/__tests__/turn-extractor.test.ts` | **done** — 9/9 passing |
| L-6 | Live integration tests — gated on `ANTHROPIC_API_KEY`; 4 live + 2 end-to-end round-trips | `extensions/oddjobz/src/conversation/__tests__/turn-extractor.test.ts` | **done** — 6 tests, skip without key |

### Workstream T: Textbook & Canon

| ID | Deliverable | File | Status |
|---|---|---|---|
| T-1 | Chapter 31: Extension Grammar | `docs/textbook/31-extension-grammar.md` | **done** |
| T-2 | Chapter 32: Trivium/Quadrivium Intent Reducer | `docs/textbook/32-trivium-quadrivium-intent-reducer.md` | **done** |
| T-3 | Chapter 33: Automated Grammar Synthesis | `docs/textbook/33-automated-grammar-synthesis.md` | **done** |
| T-4 | Canon lexicons.yml — add trades, jural, brap, calendar entries | `docs/canon/lexicons.yml` | **done** |
| T-5 | Canon deliverables.yml — add I-1..I-13, G-1..G-10 entries | `docs/canon/deliverables.yml` | **done** |
| T-6 | SEMANTOS-DOC-PLAN.md — add Part IX (chapters 31–33) | `docs/SEMANTOS-DOC-PLAN.md` | **done** |

---

## 3. Dependency graph (critical path)

```
I-1 → I-2 → I-3 → I-4 ─┐
                          ├→ I-9 → I-10 → I-11 → I-13
I-5 → I-6 → I-7 → I-8 ─┘           └→ I-12

G-1 → G-2 ─┐
             ├→ G-5 → G-6 → G-7
G-3 ────────┘       └→ G-8, G-9
G-4 ────────┘

G-10 depends on governance ballot machinery (separate)
I-13 depends on I-11 and chatService being available in oddjobtodd
```

The critical path is **I-1 → I-9** (the trivium/quadrivium pass composer). Everything else fans out from there. Bert's M5.10 intent reducer should target the `I-9` interface: `reduceToIntent(state: AccumulatedJobState, grammar: ExtensionGrammarSpec, options?: ReducerOptions): Promise<Intent>`.

---

## 4. Interface contracts (what Bert targets for M5.10)

### `reduceToIntent`

```ts
// runtime/intent/src/reducer/index.ts

export interface ReducerOptions {
  /** Per-pass confidence thresholds. Defaults: grammar=0.6, logic=0.5, rhetoric=0.7. */
  thresholds?: Partial<Record<Pass, number>>;
  /** If supplied, the previous SIR rejection is relayed to each pass as context. */
  priorRejection?: IntentRejection;
  /** Cap on trust class (hat ceiling propagated from HatContext). */
  maxTrustClass?: TrustClass;
}

export type Pass =
  | 'grammar'      // trivium 1: taxonomy.what
  | 'logic'        // trivium 2: taxonomy.how
  | 'rhetoric'     // trivium 3: TaggedCategory + action
  | 'arithmetic'   // quadrivium 1: value constraints
  | 'geometry'     // quadrivium 2: spatial / taxonomy.where
  | 'music'        // quadrivium 3: temporal constraints
  | 'astronomy';   // quadrivium 4: governance context

export interface PassResult {
  pass: Pass;
  /** Partial Intent fields contributed by this pass. */
  contribution: Partial<Intent>;
  /** 0–1 confidence for this pass's output. */
  confidence: number;
  /** Flags raised (low confidence fields, missing required fields, etc.). */
  flags: string[];
}

export interface ReducerResult {
  intent: Intent;
  passResults: PassResult[];
  /** Composite confidence — geometric mean of per-pass confidences. */
  confidence: number;
  /** Any flags raised across all passes. */
  flags: string[];
}

export async function reduceToIntent(
  state: AccumulatedJobState,
  grammar: ExtensionGrammarSpec,
  options?: ReducerOptions,
): Promise<ReducerResult>;
```

### `ExtensionGrammarSpec` (already exists in `extensions/extraction/src/intent-adapters/trades-grammar.ts`)

The reducer receives the grammar spec as the domain context. The `grammar.lexicon` determines which `TaggedCategory.lexicon` the rhetoric pass emits. The `grammar.actions` constrain which `action` strings are valid. The `grammar.objectTypes` constrain which `taxonomy.what` paths are valid.

---

## 5. Open questions

| # | Question | Resolution target |
|---|---|---|
| 1 | Does `AccumulatedJobState` carry enough field-level provenance (source utterance per field) to feed back into SIR rejection relay? | I-10 design |
| 2 | Should Pask TaxonomyMapper use a dedicated Pask store per-grammar or a shared store seeded with all known grammars? | G-2 design |
| 3 | How does `grammar.domainFlag` propagate into the astronomy pass's `GovernanceContext.domainBinding.flag`? Direct copy — but should the hat context override this? | I-8 design |
| 4 | AFFINE → RELEVANT graduation for auto-generated grammars: require human review only, or also require a passing gate test? | G-10 design |
| 5 | Should the Swagger ingester (G-4) attempt to infer Pask-style relationships from `$ref` and `allOf` chains, or treat those as flat field lists? | G-4 design |
