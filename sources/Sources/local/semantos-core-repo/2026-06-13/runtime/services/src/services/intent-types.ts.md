---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/intent-types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.095521+00:00
---

# runtime/services/src/services/intent-types.ts

```ts
/**
 * Intent classification types — shared between IntentClassifier, FlowRegistry, and UI.
 */

/** Result of classifying a user message against an extension config. */
export interface IntentClassification {
  intent: string;
  confidence: number;
  objectType?: string;
  typePath?: string;
  flowId?: string;
  extractedFields?: Record<string, unknown>;
}

/**
 * Extended classification result from hierarchical intent resolution (Phase 13).
 * Superset of IntentClassification — backward-compatible with all existing consumers.
 *
 * Phase 24 adds optional embedding metadata for diagnostics. All new fields are
 * optional — existing consumers see no change.
 */
export interface ClassificationResult extends IntentClassification {
  /** The taxonomy path traversed, e.g. ["create", "job"] */
  path: string[];
  /** Number of LLM calls made during classification */
  llmCallCount: number;
  /** Whether the fast-path shortcut was used */
  fastPath: boolean;

  /** Phase 24: Embedding-based ranking metadata (absent when embeddings unavailable). */
  embeddingHint?: EmbeddingHint;
  /** Phase 24: Coherence warning if the classified node has a known misalignment. */
  coherenceWarning?: CoherenceWarning;
}

/**
 * Phase 24: Embedding similarity ranking that was shown to the LLM.
 * The LLM still makes the final classification — these scores are a quantitative prior.
 */
export interface EmbeddingHint {
  /** Top-ranked taxonomy nodes by embedding similarity to the user utterance. */
  rankedOptions: Array<{ path: string; score: number }>;
  /** Whether the LLM's chosen intent matched the embedding's top pick. */
  embeddingAgreed: boolean;
  /** Confidence adjustment applied: +0.05 (agree) or -0.10 (disagree). */
  confidenceAdjustment: number;
  /** Time taken for embedding lookup in ms. */
  embeddingLatencyMs: number;
}

/**
 * Phase 24: Warning surfaced when the classified node has a known
 * tree/embedding misalignment from TaxonomyCoherence.
 */
export interface CoherenceWarning {
  /** The classified node path. */
  nodePath: string;
  /** The node that is nearest in embedding space (but differs from tree-nearest). */
  embeddingNearest: string;
  /** Severity from TaxonomyCoherence. */
  severity: 'info' | 'warning' | 'critical';
  /** Human-readable message for the debug badge. */
  message: string;
}

/** Context provided to the classifier to build the system prompt. */
export interface ClassificationContext {
  extensionName: string;
  objectTypes: string[];
  taxonomyPaths: string[];
  flowIds: string[];
  activeHatName?: string;
  currentObjectType?: string;
  recentMessages?: string[];
}

/** Unknown intent — returned when classification fails or no API key is configured. */
export const UNKNOWN_INTENT: IntentClassification = {
  intent: 'unknown',
  confidence: 0,
};

/** Unknown classification result with hierarchy metadata. */
export const UNKNOWN_CLASSIFICATION: ClassificationResult = {
  intent: 'unknown',
  confidence: 0,
  path: [],
  llmCallCount: 0,
  fastPath: false,
};

```
