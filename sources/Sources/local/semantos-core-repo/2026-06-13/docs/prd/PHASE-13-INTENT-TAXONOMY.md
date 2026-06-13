---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-13-INTENT-TAXONOMY.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.687901+00:00
---

# Phase 13: Hierarchical Intent Taxonomy

**Version**: 1.0
**Date**: March 2026
**Status**: Ready for implementation
**Duration**: 2 weeks (with 3-day buffer)
**Prerequisites**: Phases 9, 9.5, 10 complete (services extracted, LLM classification working, taxonomy governance in place)
**Master document**: `SEMANTOS_ZIG_WASM_PRD.md`
**Branch**: `phase-13-intent-taxonomy`

---

## Context

The loom currently sends a flat list of intent types to the LLM for classification. `IntentClassifier.ts` builds a single system prompt containing every object type, taxonomy path, and flow ID from the active extension config. As extensions grow this becomes unscalable — thousands of intents in a single prompt degrades classification accuracy, increases token cost, and creates a maintenance burden.

The solution is hierarchical intent resolution using an LTREE-style taxonomy where each level is a small focused LLM call with 5-15 options, only loaded extensions contribute intents, and the SNS type path IS the intent path — one taxonomy, not two. Ambiguous messages traverse the full tree; obvious messages shortcut directly.

### Core Insight

The SNS type registry and the intent taxonomy are the same tree expressed differently:

```
SNS type path:     trades.job.carpentry.door_replacement
Intent path:       create.trades.job.carpentry

library.book.isbn.9780140449136
                   navigate.library.book.isbn

gaming.item.sword.legendary
                   create.gaming.item.sword
```

An extension that registers its object types in the SNS automatically registers its classifiable intents. No dual maintenance. No sync problem.

---

## The Taxonomy Structure

### Level 1 — Domain (always present, ~8 options)

```
create     — instantiate a new semantic object
navigate   — find, list, browse existing objects
query      — ask questions about objects or state
consume    — use/spend a LINEAR object
inspect    — examine object details, evidence chain, anchor
govern     — manage participants, policies, channels
demo       — run compliance or capability demonstrations
transition — advance an object through a state machine
```

### Level 2 — Extension (loaded extensions only)

Dynamically populated from registered extensions. Example when trades and generic are loaded:

```
create →
  trades     — jobs, customers, sites, visits
  generic    — raw linear/affine/relevant objects

navigate →
  trades     — job queue, customer list, site map
```

### Level 3 — Object Type (extension-specific)

```
create.trades →
  job        — service request intake
  customer   — new customer record
  site       — physical location
  quote      — pricing instrument
```

### Level 4 — Specificity (optional, object-specific)

```
create.trades.job →
  carpentry | plumbing | electrical | painting |
  fencing | tiling | roofing | general
```

---

## Resolution Algorithm

### Fast Path (confidence > 0.90)

Most messages are unambiguous. Check against the top 20 most common intents first using a single small LLM call. If confidence exceeds threshold, return immediately without traversing the full tree.

```
"I want to create a job"          → create.trades.job (fast path)
"do I have any jobs"              → navigate.trades.jobs (fast path)
"consume this token"              → consume.generic (fast path)
"demo linearity"                  → demo.compliance (fast path)
```

### Hierarchical Path (confidence ≤ 0.90)

For ambiguous messages, traverse level by level:

```
Step 1: Classify domain     — user message + 8 domain options → domain + confidence
Step 2: Classify extension   — user message + loaded extensions for that domain → extension + confidence
Step 3: Classify object type — user message + object types for that extension → object type
Step 4: Match flow          — resolved path (e.g. create.trades.job) → FlowDefinition or null
```

### Catch-all Path

If no specific flow matches after full traversal, fall back to:

- `create.generic` → generic object creation flow
- `navigate.generic` → list all objects
- `query.generic` → freeform LLM answer with object context

---

## What NOT to Do

1. **Do NOT send all registered intents in a single prompt** — this is the current problem being fixed.
2. **Do NOT maintain a separate intent taxonomy apart from the extension** — they must stay in sync automatically.
3. **Do NOT make hierarchical traversal mandatory** — fast path must short-circuit for obvious intents.
4. **Do NOT hardcode extension names** — they must come from registered extensions dynamically.
5. **Do NOT break existing flows** — all current `triggerIntents` strings remain valid; they get mapped into the taxonomy tree automatically.
6. **Do NOT require a network call per level if the message is obviously unambiguous** — cache and shortcut aggressively.

---

## Deliverables

### D13.1 — Intent Taxonomy Registry

**New file**: `packages/loom/src/services/IntentTaxonomy.ts`

The taxonomy registry. Extensions register their subtrees here.

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

### D13.2 — Taxonomy Config Files

**New file**: `configs/taxonomy/core.json` — always-present domain level (8 domains with descriptions and examples).

**New file**: `configs/taxonomy/trades.json` — trades extension subtree (create, navigate, transition subtrees with object types and flow IDs).

**New file**: `configs/taxonomy/generic.json` — always-present catch-all (linear/affine/relevant create, compliance demo subtrees).

These are colocated in `configs/taxonomy/` alongside the existing `configs/taxonomy/seed.json`.

### D13.3 — Hierarchical Intent Classifier

**Modified file**: `packages/loom/src/services/IntentClassifier.ts`

Replace flat classification with hierarchical resolution. The existing `classifyIntent()` function becomes the entry point that tries fast path first, falls back to hierarchy.

**Modified file**: `packages/loom/src/services/intent-types.ts`

Extend `IntentClassification` → `ClassificationResult` with:

```typescript
export interface ClassificationResult extends IntentClassification {
  path: string[]              // ["create", "trades", "job"]
  llmCallCount: number        // for debugging/optimisation
  fastPath: boolean           // was fast path used?
}
```

### D13.4 — FlowRegistry Taxonomy Integration

**Modified file**: `packages/loom/src/services/FlowRegistry.ts`

Add taxonomy registration support:

```typescript
registerTaxonomy(extensionId: string, taxonomyPath: string): void
getTaxonomyAt(path: string[]): TaxonomyNode | null
getFastPathIntents(n: number = 20): Array<{ intent: string; flowId: string; examples: string[] }>
```

### D13.5 — Extension Config Extension

**Modified file**: `packages/loom/src/config/extensionConfig.ts`

Add taxonomy path to extension definition:

```typescript
export interface ExtensionConfig {
  // ... existing fields
  taxonomyPath?: string    // path to taxonomy JSON for this extension
}
```

### D13.6 — Classification Debug Badge

**Modified file**: `packages/loom/src/canvas/ConversationPanel.tsx`

Show classification debug info when `INTENT_DEBUG=true`:

```
"create.trades.job (carpentry) — 3 LLM calls — hierarchical path"
"create.trades.job — 1 LLM call — fast path"
```

---

## TDD Gate

All tests must pass before this phase is complete.

### Unit Tests — `tests/intent-taxonomy.test.ts`

| ID | Test |
|----|------|
| T1 | `registerExtension()` adds subtree to domain correctly |
| T2 | `unregisterExtension()` removes subtree cleanly |
| T3 | `getOptionsAt(["create"])` returns all registered create extensions |
| T4 | `getOptionsAt(["create", "trades"])` returns trades object types only |
| T5 | `getOptionsAt(["create", "unloaded_extension"])` returns empty array |
| T6 | `resolveToFlow(["create", "trades", "job"])` returns `"new-job-intake"` |
| T7 | `resolveToFlow(["demo", "compliance", "linearity"])` returns `"compliance-demo"` |
| T8 | `resolveToFlow(["create", "nonexistent"])` returns null |
| T9 | `getFastPathIntents(20)` returns top 20 across all loaded extensions |
| T10 | `buildPrompt(["create"], message)` produces correct LLM prompt format |

### Integration Tests — `tests/intent-classifier-hierarchy.test.ts`

| ID | Test |
|----|------|
| T11 | `"I want to create a job"` → fast path → `create.trades.job` (1 LLM call) |
| T12 | `"new plumbing work needed"` → fast path → `create.trades.job.plumbing` |
| T13 | `"create an object for my car"` → hierarchical → `create.library.vehicle` (3 calls) |
| T14 | `"do I have any jobs"` → fast path → `navigate.trades.jobs` |
| T15 | `"demo linearity"` → fast path → `demo.compliance.linearity` |
| T16 | `"show me the evidence chain for obj-1774"` → fast path → `inspect.generic` |
| T17 | Unloaded extension does not appear in options at any level |
| T18 | Loading a new extension makes its intents immediately classifiable |
| T19 | `llmCallCount` is 1 for fast path, ≤ 4 for hierarchical |
| T20 | Unknown intent falls back to appropriate catch-all flow |

### Regression Tests

| ID | Test |
|----|------|
| T21 | All existing flows still trigger correctly by their `triggerIntents` strings |
| T22 | `"I need a plumber for a leaking tap"` still routes to `new-job-intake` |
| T23 | `"do i have any jobs that i need to do"` now routes to `navigate.trades.jobs` |
| T24 | Compliance demo flow still triggers on `"demo linearity"` |

---

## Performance Constraints

| Metric | Target |
|--------|--------|
| Fast path LLM call | < 500ms (small prompt, top-N options only) |
| Single hierarchy level | < 500ms (small focused prompt) |
| Full 4-level traversal | < 2000ms (worst case, never in practice) |
| Taxonomy registration | < 10ms (synchronous, in-memory) |
| Taxonomy lookup | < 1ms (tree traversal, in-memory) |

---

## Implementation Phases

### Phase A — Taxonomy Registry (no LLM changes yet)

1. Create `IntentTaxonomy.ts` with register/lookup methods
2. Create `configs/taxonomy/core.json`
3. Create `configs/taxonomy/trades.json`
4. Create `configs/taxonomy/generic.json`
5. Wire `FlowRegistry.registerTaxonomy()` to load taxonomy files on extension activation
6. Tests T1–T10 pass

### Phase B — Hierarchical Classifier

1. Modify `IntentClassifier.ts` to use hierarchical resolution
2. Implement fast path with configurable confidence threshold
3. Implement level-by-level traversal with focused prompts
4. Add `llmCallCount` and `fastPath` to `ClassificationResult`
5. Tests T11–T20 pass

### Phase C — Regression and Integration

1. Run full regression suite
2. Verify `"do I have any jobs"` now routes correctly (was failing)
3. Verify `"create an object for my car"` routes to asset library when loaded
4. Tests T21–T24 pass

---

## What This Enables

Once implemented, adding a new extension to the loom is:

1. Write the extension (flows, object types)
2. Write the taxonomy JSON (where it sits in the tree)
3. Register both in the extension config

The intent classifier automatically understands the new extension's objects and operations. No changes to the classifier itself. No growing flat intent list. No prompt engineering required for new extensions.

The SNS type path and the intent path remain the same tree — `create.trades.job.carpentry` works as both a semantic object type and a conversational intent.

---

## Open Questions

| # | Question | Decision needed by |
|---|----------|--------------------|
| Q1 | Should fast-path intents be hardcoded or dynamically computed from usage frequency? Dynamic is better long-term but requires usage tracking. Start hardcoded, migrate to dynamic. | Phase A |
| Q2 | Should taxonomy JSON files live in `configs/taxonomy/` or alongside their extension in `configs/extensions/`? Colocation is cleaner. | Phase A |
| Q3 | When no extension is loaded except generic, should the domain level still show all domains or only domains with registered flows? Only registered domains — cleaner UX. | Phase A |
| Q4 | Should the classification debug badge (LLM call count, fast vs hierarchical) be on by default in dev or require a flag? Dev flag `INTENT_DEBUG=true`. | Phase B |

---

## File Reference Summary

### New Files

| File | Purpose |
|------|---------|
| `packages/loom/src/services/IntentTaxonomy.ts` | Taxonomy registry — register/lookup/prompt-build |
| `configs/taxonomy/core.json` | Domain-level taxonomy (8 domains, always present) |
| `configs/taxonomy/trades.json` | Trades extension subtree |
| `configs/taxonomy/generic.json` | Generic catch-all subtree |
| `tests/intent-taxonomy.test.ts` | Unit tests T1–T10 |
| `tests/intent-classifier-hierarchy.test.ts` | Integration tests T11–T20, regression T21–T24 |

### Modified Files

| File | Change |
|------|--------|
| `packages/loom/src/services/IntentClassifier.ts` | Replace flat classification with fast-path + hierarchical resolution |
| `packages/loom/src/services/intent-types.ts` | Add `ClassificationResult` extending `IntentClassification` |
| `packages/loom/src/services/FlowRegistry.ts` | Add `registerTaxonomy()`, `getTaxonomyAt()`, `getFastPathIntents()` |
| `packages/loom/src/config/extensionConfig.ts` | Add `taxonomyPath?: string` to `ExtensionConfig` |
| `packages/loom/src/canvas/ConversationPanel.tsx` | Add classification debug badge (behind `INTENT_DEBUG` flag) |

### Existing Files to Read (context)

| File | Alias | Why |
|------|-------|-----|
| `packages/loom/src/services/LoomStore.ts` | `SVC:STORE` | Renderer-agnostic state — integration point |
| `packages/loom/src/services/ConfigStore.ts` | `SVC:CONFIG` | Config loading — taxonomy overlay application |
| `packages/loom/src/services/FlowRunner.ts` | `SVC:RUNNER` | Flow execution — must receive resolved flow ID |
| `packages/loom/src/services/SettingsStore.ts` | `SVC:SETTINGS` | API key management for LLM calls |
| `configs/extensions/trades-services.json` | `CFG:TRADES` | Real extension data for testing |
| `configs/extensions/core.json` | `CFG:CORE` | Base types and governance flows |
| `configs/taxonomy/seed.json` | `CFG:SEED` | Existing taxonomy seed (three-axis) |
