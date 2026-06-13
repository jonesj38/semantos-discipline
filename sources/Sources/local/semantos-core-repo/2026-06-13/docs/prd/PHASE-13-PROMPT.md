---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-13-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.707297+00:00
---

# Phase 13 Execution Prompt — Hierarchical Intent Taxonomy

> Paste this prompt into a fresh session to execute Phase 13.

## Context

You are working in the `semantos-core` repo — the TypeScript application layer and React loom for Bitcoin-native semantic objects (npm: `@semantos/core`). The kernel (cell engine, 2-PDA, linearity enforcement) is Zig/WASM in the sibling `semantos` repo; this repo holds the type system, compiler, WASM bindings, and loom UI. Phase 9 extracted services from React, added LLM intent classification via OpenRouter, and built a flow registry/runner. Phase 9.5 added publication/visibility/governance. Phase 10 implemented the three-axis taxonomy (WHAT/HOW/WHY), reputation, and taxonomy governance. Phases 11/11.5 added formal verification (Lean 4 + TLA+). Phase 12 bridged formal proofs to implementation.

Your task is Phase 13: replace the flat intent classifier with a hierarchical intent taxonomy. The current `IntentClassifier.ts` sends a single system prompt containing ALL object types, taxonomy paths, and flow IDs — this scales poorly. You will build a multi-level taxonomy where each LLM call sees only 5-15 options, with a fast-path shortcut for obvious intents.

The core insight: the SNS type path and the intent path are the same tree. `create.trades.job.carpentry` is both a semantic object type and a conversational intent. Registering a extension's object types automatically registers its classifiable intents.

## CRITICAL: READ THESE FILES FIRST

Before writing a single line of code, read every file listed below. These are the real implementations you are building on top of. If you haven't read them, you will produce stubs, mocks, or code that doesn't integrate. That is not acceptable.

**Read first** (the PRD — your requirements):
- `docs/prd/PHASE-13-INTENT-TAXONOMY.md` — Full spec with deliverables D13.1–D13.6, TDD gate, performance constraints

**Read second** (the existing classifier you are replacing — understand it completely before modifying):
- `packages/loom/src/services/IntentClassifier.ts` — Current flat classification: `buildSystemPrompt()` dumps ALL types into one prompt, `classifyIntent()` makes a single LLM call
- `packages/loom/src/services/intent-types.ts` — `IntentClassification`, `ClassificationContext`, `UNKNOWN_INTENT`
- `packages/loom/src/services/FlowRegistry.ts` — `findFlow()` by intent string + capability check, `listFlows()`
- `packages/loom/src/services/FlowRunner.ts` — Multi-turn flow execution (receives resolved flow ID — your output must feed this)

**Read third** (the services and state you integrate with):
- `packages/loom/src/services/LoomStore.ts` — Renderer-agnostic state
- `packages/loom/src/services/ConfigStore.ts` — Config loading, taxonomy overlay application, immutable tree operations
- `packages/loom/src/services/SettingsStore.ts` — OpenRouter API key, model selection, temperature
- `packages/loom/src/services/IdentityStore.ts` — Identity and facet state

**Read fourth** (the types and config structures you must conform to):
- `packages/loom/src/config/extensionConfig.ts` — `ExtensionConfig`, `ConversationFlow`, `TaxonomyNode`, `TaxonomyTree`, `ObjectTypeDefinition`
- `packages/loom/src/types/workbench.ts` — `LoomObject`, `ObjectPatch`, `ConversationMessage`

**Read fifth** (the extension configs — your test data and integration targets):
- `configs/extensions/trades-services.json` — OddJobTodd: 7 object types, taxonomy, flows with `triggerIntents`
- `configs/extensions/core.json` — Base types + governance flows (Dispute, Ballot, Stake, Resolution)
- `configs/extensions/blockchain-risk.json` — BREM: different types, different phases
- `configs/taxonomy/seed.json` — Existing three-axis taxonomy seed

**Read sixth** (the UI you will add debug info to):
- `packages/loom/src/canvas/ConversationPanel.tsx` — Where classification results are consumed and debug badge will display

**Read seventh** (branching policy):
- `docs/BRANCHING-AND-CI-POLICY.md` — Branch as `phase-13-intent-taxonomy`. Commits as `phase-13/D13.N: description`.

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

Same rules as Phases 9–12. Plus:

### 1. NO STUBS

Every function must do real work. If a function body is `throw new Error("not implemented")` or `return undefined`, you have failed.

### 2. NO MOCKS IN PRODUCTION PATHS

Test files may use fixtures. Source files may not contain mock data, hardcoded responses, or fake classifications. The hierarchical classifier must call a real LLM endpoint (or gracefully degrade with "no API key configured"). It must never return a canned response.

### 3. NO EASY TESTS

Tests must use real extension configs (`trades-services.json` or `blockchain-risk.json`). Tests that check `expect(result).toBeDefined()` are worthless. Delete them and write real tests.

### 4. NO TESTS THAT MATCH BROKEN CODE

If your code produces the wrong output, FIX THE CODE. Do not change the test expectation.

### 5. RENDERER AGNOSTICISM IS NOT OPTIONAL

`IntentTaxonomy.ts` and `IntentClassifier.ts` are plain TypeScript in `src/services/`. They never import from React.

### 13. THE TAXONOMY IS NOT A SECOND TREE

The intent taxonomy and the SNS type registry are the SAME tree. If you create a parallel data structure that needs manual sync with extension configs, you are wrong. Extensions register their subtrees; the taxonomy is assembled from those registrations.

### 14. FAST PATH IS NOT OPTIONAL

If you implement hierarchy-only without the fast path, 80% of classifications will take 4 LLM calls instead of 1. The fast path must exist from the start and must be tested (T11, T14, T15, T16).

### 15. BACKWARD COMPATIBILITY IS NOT OPTIONAL

All existing `triggerIntents` strings in flow definitions (e.g. `"create.job"`, `"need.service"`) must continue to work. The taxonomy adds resolution, it does not replace the flow matching logic. Test T21 enforces this.

---

## PART 0: GIT HYGIENE

### 0.1 Assess

```bash
cd <path-to-semantos-core>
git status -u
git log --oneline -10
git branch -a
```

### 0.2 Commit or discard uncommitted work

Stage files explicitly, never `git add -A`. Discard stale files. Ignore `.claude/worktrees/`.

### 0.3 Verify Phase 12 is complete

```bash
# Services exist
ls packages/loom/src/services/IntentClassifier.ts
ls packages/loom/src/services/FlowRegistry.ts
ls packages/loom/src/services/FlowRunner.ts
ls packages/loom/src/services/LoomStore.ts
ls packages/loom/src/services/ConfigStore.ts
ls packages/loom/src/services/SettingsStore.ts

# Taxonomy seed exists
ls configs/taxonomy/seed.json

# Extension configs exist
ls configs/extensions/trades-services.json
ls configs/extensions/core.json
```

All files must exist and not be stubbed. If anything is missing, STOP.

### 0.4 Create Phase 13 branch

```bash
git checkout -b phase-13-intent-taxonomy
```

---

## Step 1: Taxonomy Registry (D13.1)

Create `packages/loom/src/services/IntentTaxonomy.ts`.

This is the core data structure. It holds the assembled taxonomy tree from all loaded extensions.

```typescript
export interface TaxonomyNode {
  id: string                          // e.g. "trades"
  label: string                       // human-readable for LLM prompt
  description: string                 // helps LLM classify correctly
  children?: TaxonomyNode[]           // sub-nodes
  flows?: string[]                    // flow IDs at this leaf
  examples?: string[]                 // example utterances for LLM
}

export interface TaxonomyLevel {
  domain: string
  options: TaxonomyNode[]
  systemPrompt: string               // level-specific LLM instruction
}

export class IntentTaxonomy {
  registerExtension(extensionId: string, subtree: TaxonomyNode): void
  unregisterExtension(extensionId: string): void
  getOptionsAt(path: string[]): TaxonomyNode[]
  getDomains(): TaxonomyNode[]
  getFastPathIntents(n?: number): string[]
  resolveToFlow(path: string[]): string | null
  buildPrompt(path: string[], userMessage: string): string
}

export const intentTaxonomy = new IntentTaxonomy()
```

Implementation notes:

- Domains (level 1) are loaded from `configs/taxonomy/core.json`. They are always present.
- Extensions register subtrees under specific domains. `trades.json` registers under `create`, `navigate`, and `transition`.
- `getOptionsAt([])` returns domains. `getOptionsAt(["create"])` returns extensions that registered a `create` subtree. `getOptionsAt(["create", "trades"])` returns trades object types.
- `resolveToFlow(["create", "trades", "job"])` walks the tree and returns the first flow ID found at that leaf.
- `buildPrompt()` constructs a focused LLM prompt showing ONLY the options at the given path depth, with descriptions and examples.
- `getFastPathIntents()` collects all leaf-level intents across all loaded extensions, returns the top N (default 20). Initially hardcoded ordering; will migrate to usage-frequency-based ordering in a future phase.

Commit: `phase-13/D13.1: taxonomy registry with register/lookup/prompt-build`

---

## Step 2: Taxonomy Config Files (D13.2)

Create three taxonomy config files.

### `configs/taxonomy/core.json`

The domain level. 8 domains: create, navigate, query, consume, inspect, govern, demo, transition. Each with id, label, description, and 3-4 example utterances. See PRD for exact content.

### `configs/taxonomy/trades.json`

Trades extension subtree. Structure:

```json
{
  "extensionId": "trades",
  "subtrees": {
    "create": { ... trades create objects ... },
    "navigate": { ... trades browse objects ... },
    "transition": { ... trades state machine ... }
  }
}
```

Flow IDs MUST match existing flow IDs in `configs/extensions/trades-services.json`. Cross-reference the `flows[].id` values.

### `configs/taxonomy/generic.json`

Generic catch-all. Covers `create` (linear/affine/relevant objects) and `demo` (compliance demonstrations: linearity, identity, audit, zone).

Commit: `phase-13/D13.2: taxonomy config files — core domains, trades extension, generic catch-all`

---

## Step 3: FlowRegistry Taxonomy Integration (D13.4)

Modify `packages/loom/src/services/FlowRegistry.ts` to add:

```typescript
registerTaxonomy(extensionId: string, taxonomyPath: string): void
getTaxonomyAt(path: string[]): TaxonomyNode | null
getFastPathIntents(n: number = 20): Array<{ intent: string; flowId: string; examples: string[] }>
```

`registerTaxonomy()` loads the taxonomy JSON, parses the subtrees, and calls `intentTaxonomy.registerExtension()` for each domain subtree.

The existing `findFlow()` continues to work unchanged — it matches by `triggerIntents` strings. The new taxonomy provides an additional resolution path that produces the same intent strings.

Commit: `phase-13/D13.4: FlowRegistry taxonomy registration and lookup`

---

## Step 4: Extension Config Extension (D13.5)

Modify `packages/loom/src/config/extensionConfig.ts`:

Add `taxonomyPath?: string` to `ExtensionConfig`. This is the path to the extension's taxonomy JSON file (e.g. `"configs/taxonomy/trades.json"`).

Update `validateExtensionConfig()` to accept the optional `taxonomyPath` field (no validation needed beyond type check — the taxonomy JSON is validated when loaded by `registerTaxonomy()`).

Commit: `phase-13/D13.5: taxonomyPath field on ExtensionConfig`

---

## Step 5: Hierarchical Intent Classifier (D13.3)

This is the core change. Modify `packages/loom/src/services/IntentClassifier.ts`.

### Extend intent-types.ts

Add to `packages/loom/src/services/intent-types.ts`:

```typescript
export interface ClassificationResult extends IntentClassification {
  path: string[]              // ["create", "trades", "job"]
  llmCallCount: number
  fastPath: boolean
}
```

### Restructure IntentClassifier.ts

The existing `classifyIntent()` becomes the public entry point. Internally it delegates to:

1. **`tryFastPath(message, threshold = 0.90)`**: Gets the top-N fast-path intents from `intentTaxonomy.getFastPathIntents()`. Builds a small prompt with ONLY those intents. Makes ONE LLM call. If confidence > threshold, returns immediately with `fastPath: true, llmCallCount: 1`.

2. **`traverseHierarchy(message, currentPath = [])`**: If fast path returns null or low confidence, traverse level by level. At each level, calls `classifyLevel()` with the options from `intentTaxonomy.getOptionsAt(currentPath)`. Appends the selected node's id to the path. Continues until a leaf (no children) or a node with flows is reached. Returns with `fastPath: false, llmCallCount: N`.

3. **`classifyLevel(message, options, systemPrompt)`**: Makes a single focused LLM call. The prompt contains ONLY the options at this level (5-15 items) with descriptions and examples. Returns the selected node and confidence.

4. **Backward compatibility**: After classification, the resolved intent string (e.g. `"create.trades.job"`) is also checked against `findFlow()` using the existing `triggerIntents` matching. This ensures all existing flow triggers continue to work.

The existing `buildSystemPrompt()` and `buildContextFromConfig()` functions are kept for backward compatibility but deprecated — they are only used if `intentTaxonomy` has no registered extensions (graceful degradation to flat classification).

Commit: `phase-13/D13.3: hierarchical intent classifier with fast-path and level-by-level traversal`

---

## Step 6: Classification Debug Badge (D13.6)

Modify `packages/loom/src/canvas/ConversationPanel.tsx`.

When `ClassificationResult` is available on a conversation message, and `INTENT_DEBUG` is enabled (check via `import.meta.env.VITE_INTENT_DEBUG` or a SettingsStore flag):

- Show an inline badge: intent path, LLM call count, fast vs hierarchical
- Example: `create.trades.job — 1 call — fast path` (green badge)
- Example: `create.trades.job.carpentry — 3 calls — hierarchical` (yellow badge)

This is development-only UI. Keep it minimal. A `<span>` with conditional rendering.

Commit: `phase-13/D13.6: classification debug badge in ConversationPanel`

---

## Step 7: Tests

### Unit tests — `tests/intent-taxonomy.test.ts`

Write tests T1–T10 from the PRD. Use real taxonomy configs (load `core.json`, `trades.json`, `generic.json`). Verify:

- Registration and unregistration
- Tree traversal at every depth
- Flow resolution
- Fast-path intent collection
- Prompt generation format

### Integration tests — `tests/intent-classifier-hierarchy.test.ts`

Write tests T11–T20. These require mocking the LLM endpoint (NOT mocking in production code — mock the HTTP call in the test fixture). Verify:

- Fast path fires for unambiguous messages
- Hierarchical path fires for ambiguous messages
- `llmCallCount` is correct
- Unloaded extensions don't appear
- Dynamic extension loading works
- Catch-all fallback works

### Regression tests (in same file or separate)

Write tests T21–T24. Load `trades-services.json`, register its taxonomy, verify all existing `triggerIntents` still resolve to the correct flows.

Commit: `phase-13/T1-T24: full test suite — unit, integration, regression`

---

## Step 8: Errata Sprint

After all tests pass, run the errata protocol in a fresh session:

1. Adversarial review of every new and modified file
2. Check for mutations not caught by tests
3. Check for race conditions in async traversal
4. Check that `unregisterExtension()` properly cleans up all references
5. Check that fast-path intent list updates when extensions are loaded/unloaded
6. Verify performance constraints (< 500ms per level, < 2000ms total)
7. Write errata doc as `docs/prd/PHASE-13-ERRATA.md`

---

## Completion Criteria

- [ ] `IntentTaxonomy.ts` exists with all methods implemented (no stubs)
- [ ] `configs/taxonomy/core.json`, `trades.json`, `generic.json` exist and are valid
- [ ] `IntentClassifier.ts` uses hierarchical resolution with fast-path
- [ ] `intent-types.ts` has `ClassificationResult` with `path`, `llmCallCount`, `fastPath`
- [ ] `FlowRegistry.ts` has `registerTaxonomy()`, `getTaxonomyAt()`, `getFastPathIntents()`
- [ ] `extensionConfig.ts` has `taxonomyPath` field
- [ ] `ConversationPanel.tsx` shows debug badge behind `INTENT_DEBUG` flag
- [ ] Tests T1–T24 all pass
- [ ] All existing flows trigger correctly (backward compatibility)
- [ ] Errata sprint complete with `PHASE-13-ERRATA.md`
- [ ] All commits follow `phase-13/D13.N:` naming convention
- [ ] Branch is `phase-13-intent-taxonomy`
