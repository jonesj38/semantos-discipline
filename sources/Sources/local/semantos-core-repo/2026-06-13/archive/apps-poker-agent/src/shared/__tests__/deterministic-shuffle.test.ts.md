---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/shared/__tests__/deterministic-shuffle.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.801458+00:00
---

# archive/apps-poker-agent/src/shared/__tests__/deterministic-shuffle.test.ts

```ts
/**
 * Determinism tests + the bit-identical pin against the original
 * `p2p-agent-runner.ts` implementation. The legacy shuffleDeck is
 * inlined here verbatim so the suite catches any drift in the shared
 * impl that would silently break P2P consensus.
 */

import { describe, expect, test } from 'bun:test';
import { createHash } from 'crypto';
import {
  deterministicShuffle,
  randomShuffle,
  shuffleDeck,
} from '../deterministic-shuffle';
import { createDeck } from '../card-types';

// ── Verbatim legacy impl (from p2p-agent-runner.ts) ───────────────
function legacyShuffle<T>(deck: readonly T[], seed: string): T[] {
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

describe('deterministicShuffle', () => {
  test('1. same seed → identical output (1000 iterations)', () => {
    const deck = createDeck();
    const ref = deterministicShuffle(deck, 'abc');
    for (let i = 0; i < 1000; i++) {
      const out = deterministicShuffle(deck, 'abc');
      expect(out).toEqual(ref);
    }
  });

  test('2. different seeds → different output (≥99% distinct out of 100)', () => {
    const deck = createDeck();
    const seen = new Set<string>();
    for (let i = 0; i < 100; i++) {
      const out = deterministicShuffle(deck, `seed-${i}`);
      seen.add(out.map((c) => c.label).join(','));
    }
    // At least 99 unique permutations from 100 seeds.
    expect(seen.size).toBeGreaterThanOrEqual(99);
  });

  test('3. preserves card set (52 unique cards in/out)', () => {
    const deck = createDeck();
    const out = deterministicShuffle(deck, 'pin');
    expect(new Set(out.map((c) => c.label)).size).toBe(52);
  });

  test('4. bit-identical to legacy p2p-agent-runner impl across 100 seeds', () => {
    const deck = createDeck();
    for (let i = 0; i < 100; i++) {
      const seed = `pin-${i}`;
      expect(deterministicShuffle(deck, seed)).toEqual(legacyShuffle(deck, seed));
    }
  });

  test('5. does not mutate the input deck', () => {
    const deck = createDeck();
    const before = deck.map((c) => c.label).join(',');
    deterministicShuffle(deck, 'no-mutation');
    expect(deck.map((c) => c.label).join(',')).toEqual(before);
  });

  test('6. works on arbitrary array types', () => {
    const arr = [1, 2, 3, 4, 5];
    const out = deterministicShuffle(arr, 'numbers');
    expect(out.sort((a, b) => a - b)).toEqual([1, 2, 3, 4, 5]);
  });
});

describe('randomShuffle', () => {
  test('7. preserves card set', () => {
    const deck = createDeck();
    const out = randomShuffle(deck);
    expect(new Set(out.map((c) => c.label)).size).toBe(52);
  });

  test('8. typically produces a different order than the input', () => {
    const deck = createDeck();
    const original = deck.map((c) => c.label).join(',');
    let differed = 0;
    for (let i = 0; i < 5; i++) {
      const out = randomShuffle(deck).map((c) => c.label).join(',');
      if (out !== original) differed++;
    }
    expect(differed).toBeGreaterThan(0);
  });
});

describe('shuffleDeck convenience', () => {
  test('9. seed=undefined → randomShuffle', () => {
    const deck = createDeck();
    const out = shuffleDeck(deck);
    expect(new Set(out.map((c) => c.label)).size).toBe(52);
  });

  test('10. seed provided → deterministic', () => {
    const deck = createDeck();
    expect(shuffleDeck(deck, 'X')).toEqual(shuffleDeck(deck, 'X'));
  });
});

```
