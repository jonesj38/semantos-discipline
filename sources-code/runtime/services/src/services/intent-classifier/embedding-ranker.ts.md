---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/intent-classifier/embedding-ranker.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.107299+00:00
---

# runtime/services/src/services/intent-classifier/embedding-ranker.ts

```ts
/**
 * Pure embedding-driven ranking helpers — score taxonomy options
 * against an utterance vector and surface the highest-scoring
 * candidates first.
 */

import type { FastPathEntry, IntentTaxonomyNode } from '../IntentTaxonomy';
import type { UtteranceEmbeddingResult } from './utterance-embedding-cache';

/**
 * Build a score lookup map from a ranked embedding result.
 */
export function buildScoreMap(embResult: UtteranceEmbeddingResult): Map<string, number> {
  const out = new Map<string, number>();
  for (const r of embResult.ranked) out.set(r.path, r.score);
  return out;
}

/**
 * Rank fast-path intents by embedding similarity. Higher-similarity
 * entries appear first; un-scored entries fall to the back.
 */
export function rankFastPathByEmbedding(
  intents: FastPathEntry[],
  embResult: UtteranceEmbeddingResult,
): FastPathEntry[] {
  const scoreMap = buildScoreMap(embResult);
  return intents
    .map((entry) => ({
      entry,
      score: scoreMap.get(entry.nodeId) ?? -1,
    }))
    .sort((a, b) => b.score - a.score)
    .map((s) => s.entry);
}

/**
 * Score each option for a given taxonomy level. Looks up the option's
 * own path first, then falls back to the best score among any child
 * paths matching the prefix.
 */
export function scoreOptionsForLevel(
  currentPath: string[],
  options: IntentTaxonomyNode[],
  embResult: UtteranceEmbeddingResult,
): Array<{ opt: IntentTaxonomyNode; score: number | undefined }> {
  const scoreMap = buildScoreMap(embResult);
  const scored = options.map((opt) => {
    const optPath = [...currentPath, opt.id].join('.');
    let score = scoreMap.get(optPath);
    if (score === undefined) {
      let bestChildScore = -1;
      for (const [rankedPath, rankedScore] of scoreMap) {
        if (rankedPath === optPath || rankedPath.startsWith(optPath + '.')) {
          if (rankedScore > bestChildScore) bestChildScore = rankedScore;
        }
      }
      if (bestChildScore >= 0) score = bestChildScore;
    }
    return { opt, score };
  });
  scored.sort((a, b) => (b.score ?? -1) - (a.score ?? -1));
  return scored;
}

```
