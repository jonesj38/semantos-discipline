---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/shared/__tests__/card-types.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.802336+00:00
---

# archive/apps-poker-agent/src/shared/__tests__/card-types.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import { cardLabel, createDeck, RANK_LABELS, SUITS } from '../card-types';

describe('createDeck', () => {
  test('1. produces 52 unique cards', () => {
    const deck = createDeck();
    expect(deck).toHaveLength(52);
    const labels = new Set(deck.map(cardLabel));
    expect(labels.size).toBe(52);
  });

  test('2. covers every suit × rank pair', () => {
    const deck = createDeck();
    for (const suit of SUITS) {
      for (let rank = 2; rank <= 14; rank++) {
        const found = deck.find((c) => c.suit === suit && c.rank === rank);
        expect(found).toBeDefined();
      }
    }
  });

  test('3. labels match RANK_LABELS + suit-first-letter convention', () => {
    const deck = createDeck();
    const aceOfHearts = deck.find((c) => c.suit === 'hearts' && c.rank === 14);
    expect(aceOfHearts?.label).toBe('Ah');
    const tenOfClubs = deck.find((c) => c.suit === 'clubs' && c.rank === 10);
    expect(tenOfClubs?.label).toBe('10c');
    const twoOfSpades = deck.find((c) => c.suit === 'spades' && c.rank === 2);
    expect(twoOfSpades?.label).toBe('2s');
  });

  test('4. canonical order is suit-major, rank-minor (2..14 within each suit)', () => {
    const deck = createDeck();
    expect(deck[0]).toMatchObject({ suit: 'hearts', rank: 2 });
    expect(deck[12]).toMatchObject({ suit: 'hearts', rank: 14 });
    expect(deck[13]).toMatchObject({ suit: 'diamonds', rank: 2 });
    expect(deck[51]).toMatchObject({ suit: 'spades', rank: 14 });
  });

  test('5. RANK_LABELS encoding matches legacy format', () => {
    expect(RANK_LABELS[2]).toBe('2');
    expect(RANK_LABELS[10]).toBe('10');
    expect(RANK_LABELS[11]).toBe('J');
    expect(RANK_LABELS[12]).toBe('Q');
    expect(RANK_LABELS[13]).toBe('K');
    expect(RANK_LABELS[14]).toBe('A');
  });
});

```
