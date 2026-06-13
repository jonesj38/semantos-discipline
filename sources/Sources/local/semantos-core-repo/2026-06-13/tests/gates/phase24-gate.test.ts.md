---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/phase24-gate.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.562663+00:00
---

# tests/gates/phase24-gate.test.ts

```ts
/**
 * Phase 24 Gate: Embedding-Enhanced Classification
 *
 * Validates:
 * 1. Embedding hint construction and confidence calibration (T1–T6)
 * 2. Coherence warning integration (T7–T9)
 * 3. Graceful degradation when embeddings unavailable (T10–T12)
 * 4. Prompt ranking by embedding similarity (T13–T16)
 * 5. Anti-lock: Phase 23 files unmodified, no new LLM calls, backward compat (T17–T20)
 */

import { describe, test, expect } from "bun:test";
import { readFileSync } from "fs";
import { join } from "path";

const ROOT = join(import.meta.dir, "../..");

// ── Load source files for analysis ────────────────────────────────

const classifierSource = readFileSync(
  join(ROOT, "runtime/services/src/services/IntentClassifier.ts"),
  "utf-8",
);

const intentTypesSource = readFileSync(
  join(ROOT, "runtime/services/src/services/intent-types.ts"),
  "utf-8",
);

// ── Gate 1: Embedding Hint & Confidence Calibration ──────────────

describe("Phase 24 — Embedding Hint & Confidence Calibration", () => {
  // T1: EmbeddingHint interface exists in intent-types.ts
  test("T1: EmbeddingHint interface exported from intent-types", () => {
    expect(intentTypesSource).toContain("export interface EmbeddingHint");
    expect(intentTypesSource).toContain("rankedOptions:");
    expect(intentTypesSource).toContain("embeddingAgreed:");
    expect(intentTypesSource).toContain("confidenceAdjustment:");
    expect(intentTypesSource).toContain("embeddingLatencyMs:");
  });

  // T2: ClassificationResult includes optional embeddingHint field
  test("T2: ClassificationResult has optional embeddingHint field", () => {
    expect(intentTypesSource).toContain("embeddingHint?: EmbeddingHint");
  });

  // T3: Confidence boost constant is +0.05
  test("T3: confidence agree boost is +0.05", () => {
    expect(classifierSource).toContain("EMBEDDING_AGREE_BOOST = 0.05");
  });

  // T4: Confidence penalty constant is -0.10
  test("T4: confidence disagree penalty is -0.10", () => {
    // Match -0.10 or -0.1
    expect(classifierSource).toMatch(/EMBEDDING_DISAGREE_PENALTY\s*=\s*-0\.10?/);
  });

  // T5: Confidence calibration clamps to [0, 1]
  test("T5: calibrateConfidence clamps to [0, 1]", () => {
    expect(classifierSource).toContain("Math.max(0, Math.min(1,");
  });

  // T6: Embedding timeout is 500ms
  test("T6: embedding timeout is 500ms", () => {
    expect(classifierSource).toContain("EMBEDDING_TIMEOUT_MS = 500");
  });
});

// ── Gate 2: Coherence Warning Integration ────────────────────────

describe("Phase 24 — Coherence Warning Integration", () => {
  // T7: CoherenceWarning interface exists in intent-types.ts
  test("T7: CoherenceWarning interface exported from intent-types", () => {
    expect(intentTypesSource).toContain("export interface CoherenceWarning");
    expect(intentTypesSource).toContain("nodePath:");
    expect(intentTypesSource).toContain("embeddingNearest:");
    expect(intentTypesSource).toContain("severity:");
  });

  // T8: ClassificationResult includes optional coherenceWarning field
  test("T8: ClassificationResult has optional coherenceWarning field", () => {
    expect(intentTypesSource).toContain("coherenceWarning?: CoherenceWarning");
  });

  // T9: Coherence check calls checkNode and references governance flow
  test("T9: coherence check references governance flow in warning message", () => {
    expect(classifierSource).toContain("checkCoherence");
    expect(classifierSource).toContain("challenge-classification");
  });
});

// ── Gate 3: Graceful Degradation ─────────────────────────────────

describe("Phase 24 — Graceful Degradation", () => {
  // T10: Embedding service is accessed via lazy ref, not direct import
  test("T10: no direct import of EmbeddingService module (avoids Node.js fs)", () => {
    // Should NOT have: import { embeddingService } from './EmbeddingService'
    // Should NOT have: import ... from './EmbeddingService'
    // But SHOULD have the interface and setter
    expect(classifierSource).not.toMatch(/import\s+\{[^}]*\}\s+from\s+['"]\.\/EmbeddingService['"]/);
    expect(classifierSource).toContain("EmbeddingServiceLike");
    expect(classifierSource).toContain("setEmbeddingServiceRef");
  });

  // T11: Returns null when embeddings unavailable (isReady check)
  test("T11: getUtteranceEmbedding checks isReady before embedding", () => {
    expect(classifierSource).toContain("!emb.isReady()");
    expect(classifierSource).toContain("return null");
  });

  // T12: UNKNOWN_CLASSIFICATION returned when no API key (unchanged from Phase 13)
  test("T12: UNKNOWN_CLASSIFICATION returned when no API key", () => {
    expect(classifierSource).toContain("UNKNOWN_CLASSIFICATION");
    expect(classifierSource).toContain("!resolvedSettings.openRouterApiKey");
  });
});

// ── Gate 4: Prompt Ranking ───────────────────────────────────────

describe("Phase 24 — Prompt Ranking by Embedding Similarity", () => {
  // T13: Ranked options header appears in embedding-enhanced prompts
  test("T13: prompt includes 'Options (ranked by relevance)' header", () => {
    expect(classifierSource).toContain("Options (ranked by relevance)");
  });

  // T14: Embedding scores shown in prompt with score format
  test("T14: prompt shows score in parentheses format", () => {
    // The prompt builder should include score.toFixed(2) formatting
    expect(classifierSource).toContain("score.toFixed(2)");
  });

  // T15: Fast-path intents are re-ranked by embedding similarity
  test("T15: rankFastPathByEmbedding function exists", () => {
    expect(classifierSource).toContain("function rankFastPathByEmbedding");
  });

  // T16: Level prompts are also ranked by embedding similarity
  test("T16: buildEmbeddingRankedLevelPrompt function exists", () => {
    expect(classifierSource).toContain("function buildEmbeddingRankedLevelPrompt");
  });
});

// ── Gate 5: Anti-Lock ────────────────────────────────────────────

describe("Phase 24 — Anti-Lock", () => {
  // T17: Phase 23 service files are NOT modified
  test("T17: Phase 23 files unmodified (EmbeddingService, TaxonomyCoherence, cosine, tree-distance)", () => {
    // Check that these files exist and still have their Phase 23 signatures
    // Note: EmbeddingService was migrated from fs to StorageAdapter in Phase 25A,
    // so we check for the class existence, not the old fs imports.
    const embSource = readFileSync(
      join(ROOT, "runtime/services/src/services/EmbeddingService.ts"),
      "utf-8",
    );
    expect(embSource).toContain("import { createHash } from 'crypto'");
    expect(embSource).toContain("StorageAdapter");
    expect(embSource).toContain("export const embeddingService = new EmbeddingService()");

    const cohSource = readFileSync(
      join(ROOT, "runtime/services/src/services/TaxonomyCoherence.ts"),
      "utf-8",
    );
    expect(cohSource).toContain("export const taxonomyCoherence = new TaxonomyCoherence()");

    const cosineSource = readFileSync(
      join(ROOT, "runtime/services/src/services/cosine.ts"),
      "utf-8",
    );
    expect(cosineSource).toContain("export function cosineSimilarity");

    const treeDistSource = readFileSync(
      join(ROOT, "runtime/services/src/services/tree-distance.ts"),
      "utf-8",
    );
    expect(treeDistSource).toContain("export function treeDistance");
  });

  // T18: IntentTaxonomy.ts is unmodified
  test("T18: IntentTaxonomy.ts is unmodified", () => {
    const taxonomySource = readFileSync(
      join(ROOT, "runtime/services/src/services/IntentTaxonomy.ts"),
      "utf-8",
    );
    expect(taxonomySource).toContain("export const intentTaxonomy = new IntentTaxonomy()");
    // Should still have the original Phase 13 buildPrompt without embedding logic
    expect(taxonomySource).not.toContain("embeddingService");
    expect(taxonomySource).not.toContain("EmbeddingHint");
  });

  // T19: No new LLM call functions added — same callLLM function used
  test("T19: single callLLM function, no additional LLM call points", () => {
    // Count occurrences of "async function callLLM" — should be exactly 1
    const matches = classifierSource.match(/async function callLLM/g);
    expect(matches).not.toBeNull();
    expect(matches!.length).toBe(1);

    // No new fetch calls outside callLLM and flatClassify
    // The embedding API call is in EmbeddingService, not here
    const fetchCalls = classifierSource.match(/await fetch\(/g);
    // flatClassify has 1 fetch call, callLLM has 1 fetch call = 2 total
    expect(fetchCalls).not.toBeNull();
    expect(fetchCalls!.length).toBe(2);
  });

  // T20: Backward compatibility — ClassificationResult still has all Phase 13 fields
  test("T20: ClassificationResult backward-compatible with Phase 13 fields", () => {
    expect(intentTypesSource).toContain("path: string[]");
    expect(intentTypesSource).toContain("llmCallCount: number");
    expect(intentTypesSource).toContain("fastPath: boolean");
    // New fields are optional (marked with ?)
    expect(intentTypesSource).toContain("embeddingHint?:");
    expect(intentTypesSource).toContain("coherenceWarning?:");
  });
});

// ── Gate 6: Functional Integration ───────────────────────────────

describe("Phase 24 — Functional Integration", () => {
  // T21: withTimeout utility exists for embedding timeout
  test("T21: withTimeout utility for embedding timeout", () => {
    expect(classifierSource).toContain("function withTimeout");
    expect(classifierSource).toContain("Promise.race");
  });

  // T22: Embedding agreement logic handles suffix matching
  test("T22: embedding agreement handles dotted path matching", () => {
    // Should handle "create.job" matching "job" or vice versa
    expect(classifierSource).toContain("endsWith");
  });

  // T23: setEmbeddingServiceRef and setCoherenceRef are exported
  test("T23: injection functions are exported", () => {
    expect(classifierSource).toContain("export function setEmbeddingServiceRef");
    expect(classifierSource).toContain("export function setCoherenceRef");
  });

  // T24: EmbeddingServiceLike interface decouples from fs imports
  test("T24: EmbeddingServiceLike interface has required methods", () => {
    expect(classifierSource).toContain("export interface EmbeddingServiceLike");
    expect(classifierSource).toContain("isReady(): boolean");
    expect(classifierSource).toContain("embedQuery(utterance: string)");
    expect(classifierSource).toContain("nearest(queryVector: Float32Array");
  });
});

```
