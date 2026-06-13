---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/refactor-monoliths/09-intent-classifier-split.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.768332+00:00
---

# 09 — Split `runtime/services/src/services/IntentClassifier.ts`

**Phase:** 5 (Runtime services) · **Depends on:** 01 · **Est. effort:** 1 day · **Branch:** `refactor/09-intent-classifier`

## Why

793 LOC: LLM-based classifier with hierarchical taxonomy traversal, embedding-enhanced ranking, coherence warnings. Uses module-level `setEmbeddingService` / `setCoherence` setters — lazy, optional, hard to test.

## Deliverables

Create under `runtime/services/src/services/intent-classifier/`:

- `intent-classifier-core.ts` — entry point: `classifyIntent(message, context, settings)`.
- `taxonomy-navigator.ts` — pure: `tryFastPath`, `traverseHierarchy`.
- `embedding-ranker.ts` — pure: `rankOptionsByEmbedding(options, embResult)`.
- `confidence-calibrator.ts` — pure: `calibrateConfidence(base, agreement)`.
- `coherence-checker.ts` — pure: `checkCoherence(path)`.
- `prompt-builders.ts` — all prompt templates, parameterized.
- `ports.ts` — `llmClientPort`, `embeddingServicePort`, `coherencePort`, `settingsPort`.
- `utterance-embedding-cache.ts` — atom-backed cache.
- `__tests__/*.test.ts`.

Edit:

- `runtime/services/src/services/IntentClassifier.ts` → thin facade.

## Acceptance criteria

- [ ] Module-level setters removed; all config via ports.
- [ ] Prompts in one place, parameterized; no string-literal prompts elsewhere.
- [ ] Fast-path, hierarchical, and flat-fallback branches all unit-tested.
- [ ] Tests that stub LLM + embedding with deterministic fixtures.
- [ ] `pnpm -r check` passes.

## Out of scope

- Changing classification behavior.
- Changing prompt text (copy wholesale into new parameterized templates).

## Test plan

Record 30 fixture (message, taxonomy, llmResponse, embResult) tuples from current behavior; assert identical classification output.
