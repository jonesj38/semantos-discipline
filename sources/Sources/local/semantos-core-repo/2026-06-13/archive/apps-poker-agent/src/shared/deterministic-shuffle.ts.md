---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/shared/deterministic-shuffle.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.770904+00:00
---

# archive/apps-poker-agent/src/shared/deterministic-shuffle.ts

```ts
/**
 * Deterministic deck shuffle — Fisher-Yates with a SHA-256-derived
 * stream of indices.
 *
 * Pinned to be **bit-identical** to the original implementation in
 * `p2p-agent-runner.ts`. Both players run this with the same seed and
 * land on exactly the same deck order — that's the whole point of the
 * P2P mode (no trusted dealer).
 *
 * Algorithm (must not change without coordinated upgrade across all
 * peers):
 *
 *   - hash = SHA-256(seed)
 *   - For i = N-1 down to 1:
 *       - if i % 8 === 0: hash = SHA-256(hash)
 *       - offset = (i % 8) * 4
 *       - j = hash.readUInt32BE(offset) % (i + 1)
 *       - swap deck[i] with deck[j]
 *
 * The caller is responsible for keeping seed reproducible. The seed
 * is a string; we convert to bytes with utf-8 (Node's default).
 */

import { createHash } from 'crypto';

import type { Card } from './card-types';

/**
 * Pure, deterministic shuffle. Same `seed` + same input deck → same
 * output deck on every invocation, every machine.
 */
export function deterministicShuffle<T>(deck: readonly T[], seed: string): T[] {
  const d = [...deck];
  let hash = createHash('sha256').update(seed).digest();
  for (let i = d.length - 1; i > 0; i--) {
    if (i % 8 === 0) {
      hash = createHash('sha256').update(hash).digest();
    }
    const offset = (i % 8) * 4;
    const j = hash.readUInt32BE(offset) % (i + 1);
    [d[i], d[j]] = [d[j], d[i]];
  }
  return d;
}

/**
 * Non-deterministic shuffle — Math.random Fisher-Yates. Pinned for
 * call sites that intentionally want randomness (single-player/
 * Claude-vs-Claude games where there is no need for cross-peer
 * agreement).
 *
 * Kept here so we have **one** Fisher-Yates implementation in the
 * poker-agent and not multiple subtly-different copies.
 */
export function randomShuffle<T>(deck: readonly T[]): T[] {
  const d = [...deck];
  for (let i = d.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [d[i], d[j]] = [d[j], d[i]];
  }
  return d;
}

/** Convenience wrapper that types `T` to `Card` for clarity in poker code. */
export function shuffleDeck(deck: readonly Card[], seed?: string): Card[] {
  return seed === undefined ? randomShuffle(deck) : deterministicShuffle(deck, seed);
}

```
