---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/p2p-agent-runner/__tests__/hand-shuffle.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.808986+00:00
---

# archive/apps-poker-agent/src/p2p-agent-runner/__tests__/hand-shuffle.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import {
  dealForP2P,
  makeDeckCursor,
  shuffleSeedFor,
} from '../hand-shuffle';

describe('shuffleSeedFor', () => {
  test('1. seed = "<gameId>:hand:<n>"', () => {
    expect(shuffleSeedFor('abc', 7)).toBe('abc:hand:7');
  });
});

describe('dealForP2P — bit-identical for both seats on the same gameId+hand', () => {
  test('2. both seats compute the same deck', () => {
    const a = dealForP2P('g-1', 1);
    const b = dealForP2P('g-1', 1);
    expect(a.deck.map((c) => c.label)).toEqual(b.deck.map((c) => c.label));
  });

  test('3. seat 0 + seat 1 hole cards do not overlap', () => {
    const r = dealForP2P('g-1', 1);
    const seat0 = r.seat0Cards.map((c) => c.label);
    const seat1 = r.seat1Cards.map((c) => c.label);
    expect(new Set([...seat0, ...seat1]).size).toBe(4);
  });

  test('4. determinism across 50 games × hands', () => {
    for (let i = 0; i < 50; i++) {
      const a = dealForP2P(`g${i}`, i % 7);
      const b = dealForP2P(`g${i}`, i % 7);
      expect(a.seat0Cards).toEqual(b.seat0Cards);
      expect(a.seat1Cards).toEqual(b.seat1Cards);
    }
  });

  test('5. cursor index after dealing is 4', () => {
    expect(dealForP2P('g', 1).deckIdx).toBe(4);
  });
});

describe('makeDeckCursor', () => {
  test('6. draw advances + burn skips', () => {
    const r = dealForP2P('g', 1);
    const cur = makeDeckCursor(r.deck, r.deckIdx);
    const c1 = cur.draw();
    cur.burn();
    const c2 = cur.draw();
    expect(c1.label).not.toEqual(c2.label);
    expect(cur.index()).toBe(r.deckIdx + 3);
  });

  test('7. throws when deck is exhausted', () => {
    const r = dealForP2P('g', 1);
    const cur = makeDeckCursor(r.deck, r.deck.length);
    expect(() => cur.draw()).toThrow('exhausted');
  });
});

```
