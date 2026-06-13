---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/intent-classifier/confidence-calibrator.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.106719+00:00
---

# runtime/services/src/services/intent-classifier/confidence-calibrator.ts

```ts
/**
 * Pure confidence calibration + embedding-agreement detection.
 */

import type { EmbeddingHint } from '../intent-types';
import type { UtteranceEmbeddingResult } from './utterance-embedding-cache';

/** Phase 24: Confidence adjustment when embedding agrees with LLM. */
export const EMBEDDING_AGREE_BOOST = 0.05;

/** Phase 24: Confidence penalty when embedding disagrees with LLM. */
export const EMBEDDING_DISAGREE_PENALTY = -0.1;

/** Apply a confidence adjustment, clamped to [0, 1]. */
export function calibrateConfidence(baseConfidence: number, adjustment: number): number {
  return Math.max(0, Math.min(1, baseConfidence + adjustment));
}

/**
 * Build an EmbeddingHint comparing the LLM's chosen intent against
 * the embedding's top pick. Mirrors the pre-split heuristic:
 *   - Direct equality
 *   - Suffix match either way (handles "create.job" vs "job")
 */
export function buildEmbeddingHint(
  embResult: UtteranceEmbeddingResult,
  chosenIntent: string,
): EmbeddingHint {
  const topEmbeddingPick = embResult.ranked.length > 0 ? embResult.ranked[0]!.path : null;
  const embeddingAgreed =
    topEmbeddingPick !== null &&
    (topEmbeddingPick === chosenIntent ||
      topEmbeddingPick.endsWith(`.${chosenIntent}`) ||
      chosenIntent.endsWith(`.${topEmbeddingPick}`));

  return {
    rankedOptions: embResult.ranked,
    embeddingAgreed,
    confidenceAdjustment: embeddingAgreed
      ? EMBEDDING_AGREE_BOOST
      : EMBEDDING_DISAGREE_PENALTY,
    embeddingLatencyMs: embResult.latencyMs,
  };
}

```
