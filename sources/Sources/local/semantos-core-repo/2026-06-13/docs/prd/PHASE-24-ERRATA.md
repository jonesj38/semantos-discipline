---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-24-ERRATA.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.669410+00:00
---

# Phase 24 Errata — Embedding-Guided Classification

## Adversarial Review

### 1. Promise.race timeout — no leaked promises
The `embedWithTimeout` helper uses `resolve(null)` on timeout, not `reject`. The timed-out embedding API call continues to completion but its result is ignored and eventually garbage collected. No unhandled rejection risk.

### 2. Confidence calibration order is correct
In `tryFastPath`: the `FAST_PATH_CONFIDENCE_THRESHOLD` check at line 175 uses the raw LLM confidence. Calibration happens at lines 183–196, only executed after the threshold passes. A result with raw 0.91 that disagrees with embeddings becomes 0.81 in the returned result — this is by design. The threshold gates whether to USE the fast path; the returned confidence reflects embedding agreement.

### 3. No duplicate ranking computation
- Fast path: `embeddingRankings` computed once (lines 154–160), reused for re-sorting, topK, and agreement check.
- Hierarchy: `levelRankings` computed once per loop iteration, used for prompt building and agreement tracking.

### 4. Debug badge handles empty embeddingTopK
The badge checks `msg.intent.embeddingTopK && msg.intent.embeddingTopK.length > 0` before accessing `[0]`. Empty or undefined arrays render nothing.

### 5. NaN filtering on all similarityToQuery calls
- Fast path line 159: `.filter(r => !isNaN(r.score))`
- Hierarchy line 245: `.filter(r => !isNaN(r.score))`
Nodes without embeddings return NaN from `similarityToQuery` and are excluded from rankings.

### 6. checkNode called with string[] not dotted string
Line 305: `taxonomyCoherence.checkNode(path)` where `path` is `string[]`. Matches the Phase 23 signature.

### 7. Confidence always clamped to [0, 1]
- Fast path line 195: `Math.max(0, Math.min(1, calibratedConfidence))`
- Hierarchy line 298: `Math.max(0, Math.min(1, confidence))`

### 8. Double embed on fast-path fallthrough
When `tryFastPath` returns null and `traverseHierarchy` is called, the user message is embedded twice. This is acceptable:
- Each function is self-contained with its own timeout
- The PRD pseudocode shows this pattern
- Typical embed latency is <100ms; worst case is bounded by EMBEDDING_TIMEOUT_MS (500ms)
- Future optimization: hoist embed to `classifyIntent` and pass queryVector as parameter

### 9. Phase 23 anti-lock test update
Tests T23–T24 in `phase23-gate.test.ts` were updated to remove the "unmodified" assertion for `IntentClassifier.ts` and `IntentTaxonomy.ts`. Phase 24 intentionally adds embedding integration to these files. The tests now verify Phase 13 functions are retained and that raw cosine math stays in `cosine.ts`.

### 10. buildEmbeddingRankedPrompt prompt size
With 8 domain nodes and ~3 examples each, the ranked prompt stays well under 4096 tokens. The largest taxonomy level (domains) has 8 options with descriptions and examples — approximately 400 tokens total.

## Test Results

- Phase 24 gate tests (T1–T21): 21 pass, 0 fail
- Phase 13 taxonomy tests (T1–T10 + config): 17 pass, 0 fail
- Phase 13 classifier tests (T11–T24): 14 pass, 0 fail
- Phase 23 embedding tests (T1–T24): 24 pass, 0 fail
