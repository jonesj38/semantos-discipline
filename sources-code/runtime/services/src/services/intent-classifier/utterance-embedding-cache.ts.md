---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/intent-classifier/utterance-embedding-cache.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.106430+00:00
---

# runtime/services/src/services/intent-classifier/utterance-embedding-cache.ts

```ts
/**
 * Utterance embedding — atom-backed per-utterance cache + timeout
 * race used at the start of every classification call.
 *
 * The cache lives across calls because re-embedding the same
 * utterance during fast-path → hierarchy fallback wastes 100s of ms.
 * Same utterance + same provider = same vector.
 */

import { atom, get, set, type Atom } from '@semantos/state';

import { getEmbeddingService } from './ports';

/** Maximum time to wait for an embedding call (ms). */
export const EMBEDDING_TIMEOUT_MS = 500;

/** Number of ranked options to surface to the LLM prompt. */
export const EMBEDDING_RANKED_OPTIONS = 8;

export interface UtteranceEmbeddingResult {
  vector: Float32Array;
  ranked: Array<{ path: string; score: number }>;
  latencyMs: number;
}

/**
 * Cache keyed by utterance text. Atom-backed so tests can subscribe;
 * production code uses {@link getUtteranceEmbedding} directly.
 */
export const utteranceEmbeddingCacheAtom: Atom<Map<string, UtteranceEmbeddingResult>> = atom(
  new Map(),
);

/** Test-only: clear the cache between cases. */
export function clearUtteranceEmbeddingCache(): void {
  set(utteranceEmbeddingCacheAtom, new Map());
}

function withTimeout<T>(p: Promise<T>, ms: number): Promise<T | null> {
  return Promise.race([p, new Promise<null>((r) => setTimeout(() => r(null), ms))]);
}

/**
 * Embed the user utterance with a timeout. Returns null if no
 * embedding service is bound, the call timed out, or it errored.
 * Mirrors the pre-split behaviour exactly.
 */
export async function getUtteranceEmbedding(
  message: string,
): Promise<UtteranceEmbeddingResult | null> {
  const cached = get(utteranceEmbeddingCacheAtom).get(message);
  if (cached) return cached;

  const emb = getEmbeddingService();
  if (!emb || !emb.isReady()) return null;

  const start = Date.now();
  try {
    const vector = await withTimeout(emb.embedQuery(message), EMBEDDING_TIMEOUT_MS);
    if (!vector) return null;
    const ranked = emb.nearest(vector, EMBEDDING_RANKED_OPTIONS);
    const latencyMs = Date.now() - start;
    const result: UtteranceEmbeddingResult = { vector, ranked, latencyMs };

    const next = new Map(get(utteranceEmbeddingCacheAtom));
    next.set(message, result);
    set(utteranceEmbeddingCacheAtom, next);

    return result;
  } catch {
    return null;
  }
}

```
