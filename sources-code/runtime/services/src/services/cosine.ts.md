---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/cosine.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.092112+00:00
---

# runtime/services/src/services/cosine.ts

```ts
/**
 * Cosine similarity and distance — pure TypeScript, zero dependencies.
 *
 * Corresponds to Lean EmbeddingMetric.dist via: dist = 1 - cosineSimilarity.
 * See proofs/lean/Semantos/Category.lean for the formal metric axioms.
 */

/**
 * Cosine similarity between two Float32Array vectors.
 * Returns 1.0 for identical vectors, 0.0 for orthogonal, -1.0 for antipodal.
 * Returns NaN if either vector has zero magnitude.
 */
export function cosineSimilarity(a: Float32Array, b: Float32Array): number {
  const len = a.length;
  if (len !== b.length) {
    throw new RangeError(
      `Vector length mismatch: ${len} vs ${b.length}`,
    );
  }

  let dot = 0;
  let magA = 0;
  let magB = 0;

  for (let i = 0; i < len; i++) {
    const ai = a[i];
    const bi = b[i];
    dot += ai * bi;
    magA += ai * ai;
    magB += bi * bi;
  }

  const denom = Math.sqrt(magA) * Math.sqrt(magB);
  if (denom === 0) return NaN;

  return dot / denom;
}

/**
 * Cosine distance: 1 - cosineSimilarity.
 * Ranges from 0 (identical) to 2 (antipodal).
 * This is the metric that corresponds to EmbeddingMetric.dist in Category.lean.
 */
export function cosineDistance(a: Float32Array, b: Float32Array): number {
  return 1 - cosineSimilarity(a, b);
}

```
