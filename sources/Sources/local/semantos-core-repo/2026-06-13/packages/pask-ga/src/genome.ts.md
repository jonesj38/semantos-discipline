---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/pask-ga/src/genome.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.444364+00:00
---

# packages/pask-ga/src/genome.ts

```ts
/**
 * Genomes — the persistent identity of a node, separate from any single
 * cluster's view of it. A node carrying genome G is "the same node" in
 * every cluster it appears in; that's what makes cross-cluster identity
 * meaningful when networks merge.
 *
 * Representation: fixed-length f64 vector. Distance is Euclidean.
 * Mutation = small Gaussian noise per dim. Crossover = uniform splice.
 *
 * The genomeKey() is sha256(genome bytes), truncated to fit
 * MAX_CELL_ID_LEN (64) once cluster-namespaced. We pre-truncate here.
 */

import { createHash } from 'node:crypto';
import type { Rng } from './rng';

export const GENOME_DIM = 16;

export type Genome = Float64Array;

export function newGenome(rng: Rng, scale = 1.0): Genome {
  const g = new Float64Array(GENOME_DIM);
  for (let i = 0; i < GENOME_DIM; i++) g[i] = (rng() - 0.5) * 2 * scale;
  return g;
}

/** Euclidean distance between two genomes. */
export function distance(a: Genome, b: Genome): number {
  let s = 0;
  for (let i = 0; i < GENOME_DIM; i++) {
    const d = (a[i] ?? 0) - (b[i] ?? 0);
    s += d * d;
  }
  return Math.sqrt(s);
}

/** Per-dimension Gaussian-ish mutation in place. Returns a new genome. */
export function mutate(g: Genome, rng: Rng, rate = 0.05): Genome {
  const out = new Float64Array(g);
  for (let i = 0; i < GENOME_DIM; i++) {
    // Box-Muller-ish noise; cheap approximation by averaging uniforms.
    const noise = (rng() + rng() + rng() - 1.5) * 2; // ~N(0, 1) scaled
    out[i]! += noise * rate;
  }
  return out;
}

/** Uniform-splice crossover: each position independently from a or b. */
export function crossover(a: Genome, b: Genome, rng: Rng): Genome {
  const out = new Float64Array(GENOME_DIM);
  for (let i = 0; i < GENOME_DIM; i++) out[i] = rng() < 0.5 ? (a[i] ?? 0) : (b[i] ?? 0);
  return out;
}

/** Stable hash key for a genome. Truncated to leave room for cluster prefix. */
export function genomeKey(g: Genome): string {
  const bytes = new Uint8Array(g.buffer, g.byteOffset, g.byteLength);
  return createHash('sha256').update(bytes).digest('hex').slice(0, 24); // 24 hex chars
}

```
