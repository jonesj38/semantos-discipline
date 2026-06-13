---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/game-loop/__tests__/deck-manager.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.804220+00:00
---

# archive/apps-poker-agent/src/game-loop/__tests__/deck-manager.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import { deckCommitment, drawCard, drawCards, newDeck } from '../deck-manager';

describe('newDeck', () => {
  test('1. returns 52 unique cards', () => {
    const deck = newDeck();
    expect(deck.cards.length).toBe(52);
    expect(new Set(deck.cards.map((c) => c.label)).size).toBe(52);
  });
  test('2. starts at index 0', () => {
    expect(newDeck().index).toBe(0);
  });
  test('3. seeded shuffle is deterministic', () => {
    const a = newDeck({ seed: 'pin' });
    const b = newDeck({ seed: 'pin' });
    expect(a.cards.map((c) => c.label)).toEqual(b.cards.map((c) => c.label));
  });
});

describe('drawCard / drawCards', () => {
  test('4. drawCard advances the cursor', () => {
    const deck = newDeck();
    drawCard(deck);
    expect(deck.index).toBe(1);
  });
  test('5. drawCards returns N cards', () => {
    const deck = newDeck();
    const out = drawCards(deck, 5);
    expect(out.length).toBe(5);
    expect(deck.index).toBe(5);
  });
  test('6. drawCard throws when exhausted', () => {
    const deck = newDeck();
    drawCards(deck, 52);
    expect(() => drawCard(deck)).toThrow('exhausted');
  });
});

describe('deckCommitment', () => {
  test('7. is a CSV of card labels', () => {
    const deck = newDeck({ seed: 'X' });
    const commit = deckCommitment(deck);
    expect(commit.split(',').length).toBe(52);
  });
  test('8. same seed → identical commitment', () => {
    expect(deckCommitment(newDeck({ seed: 'Y' }))).toBe(
      deckCommitment(newDeck({ seed: 'Y' })),
    );
  });
});

```
