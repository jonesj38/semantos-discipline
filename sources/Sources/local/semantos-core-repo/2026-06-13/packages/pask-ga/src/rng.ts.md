---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/pask-ga/src/rng.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.445168+00:00
---

# packages/pask-ga/src/rng.ts

```ts
/**
 * Mulberry32 — small, fast, seedable PRNG. Same seed → same sequence,
 * which is the determinism property the pask kernel below us already
 * upholds. GA decisions reproduce exactly given a seed.
 *
 * Not cryptographic; that's not the use case.
 */
export type Rng = () => number;

export function mulberry32(seed: number): Rng {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6D2B79F5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** Choose one element from `xs` weighted by `weights`. */
export function weightedPick<T>(rng: Rng, xs: readonly T[], weights: readonly number[]): T {
  if (xs.length === 0) throw new Error('weightedPick: empty');
  let total = 0;
  for (const w of weights) total += Math.max(0, w);
  if (total <= 0) return xs[Math.floor(rng() * xs.length)]!;
  let r = rng() * total;
  for (let i = 0; i < xs.length; i++) {
    r -= Math.max(0, weights[i] ?? 0);
    if (r <= 0) return xs[i]!;
  }
  return xs[xs.length - 1]!;
}

```
