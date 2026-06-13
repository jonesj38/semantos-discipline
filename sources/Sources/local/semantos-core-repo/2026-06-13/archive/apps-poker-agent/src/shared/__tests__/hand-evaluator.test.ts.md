---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/shared/__tests__/hand-evaluator.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.801750+00:00
---

# archive/apps-poker-agent/src/shared/__tests__/hand-evaluator.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import {
  comparePokerHands,
  evaluatePokerHand,
  pickWinner,
  rankPlayers,
} from '../hand-evaluator';
import { HandRank } from '../../../../../packages/games/src/cards/poker-types';
import type { Card, Rank, Suit } from '../card-types';

function c(suit: Suit, rank: Rank, label = ''): Card {
  return { suit, rank, label: label || `${rank}${suit[0]}` };
}

describe('evaluatePokerHand', () => {
  test('1. detects a royal flush (A-high straight flush)', () => {
    const cards = [
      c('hearts', 14),
      c('hearts', 13),
      c('hearts', 12),
      c('hearts', 11),
      c('hearts', 10),
    ];
    const h = evaluatePokerHand(cards);
    expect(h.rank).toBe(HandRank.ROYAL_FLUSH);
  });

  test('2. detects four of a kind', () => {
    const cards = [
      c('hearts', 9),
      c('diamonds', 9),
      c('clubs', 9),
      c('spades', 9),
      c('hearts', 2),
    ];
    expect(evaluatePokerHand(cards).rank).toBe(HandRank.FOUR_OF_A_KIND);
  });

  test('3. detects a flush over a straight', () => {
    const flushCards = [
      c('hearts', 2),
      c('hearts', 5),
      c('hearts', 7),
      c('hearts', 9),
      c('hearts', 12),
    ];
    expect(evaluatePokerHand(flushCards).rank).toBe(HandRank.FLUSH);
  });

  test('4. detects a high-card hand', () => {
    const cards = [
      c('hearts', 14),
      c('diamonds', 13),
      c('clubs', 9),
      c('spades', 4),
      c('hearts', 2),
    ];
    expect(evaluatePokerHand(cards).rank).toBe(HandRank.HIGH_CARD);
  });

  test('5. picks the best 5 from 7 (Hold\'em)', () => {
    // Hole: 9c, 9d (pair). Board: 4 hearts + 1 heart = 5 hearts total → flush.
    const cards = [
      c('clubs', 9),
      c('diamonds', 9),
      c('hearts', 2),
      c('hearts', 5),
      c('hearts', 8),
      c('hearts', 11),
      c('hearts', 3),
    ];
    expect(evaluatePokerHand(cards).rank).toBe(HandRank.FLUSH);
  });
});

describe('comparePokerHands', () => {
  test('6. flush beats straight', () => {
    const flush = evaluatePokerHand([
      c('hearts', 2), c('hearts', 5), c('hearts', 7), c('hearts', 9), c('hearts', 12),
    ]);
    const straight = evaluatePokerHand([
      c('hearts', 6), c('diamonds', 7), c('clubs', 8), c('spades', 9), c('hearts', 10),
    ]);
    expect(comparePokerHands(flush, straight)).toBeGreaterThan(0);
  });

  test('7. higher pair wins via kicker comparison', () => {
    const pairKings = evaluatePokerHand([
      c('hearts', 13), c('diamonds', 13), c('clubs', 5), c('spades', 4), c('hearts', 2),
    ]);
    const pairQueens = evaluatePokerHand([
      c('hearts', 12), c('diamonds', 12), c('clubs', 5), c('spades', 4), c('hearts', 2),
    ]);
    expect(comparePokerHands(pairKings, pairQueens)).toBeGreaterThan(0);
  });
});

describe('rankPlayers + pickWinner', () => {
  test('8. ranks two players high-to-low', () => {
    const aces = [
      c('hearts', 14), c('diamonds', 14), c('clubs', 5), c('spades', 4), c('hearts', 2),
    ];
    const sevens = [
      c('hearts', 7), c('diamonds', 7), c('clubs', 5), c('spades', 4), c('hearts', 2),
    ];
    const ranked = rankPlayers([
      { playerId: 'p7', cards: sevens },
      { playerId: 'pA', cards: aces },
    ]);
    expect(ranked[0].playerId).toBe('pA');
    expect(ranked[1].playerId).toBe('p7');
  });

  test('9. pickWinner returns null when no player has 5 cards', () => {
    const w = pickWinner([
      { playerId: 'a', cards: [c('hearts', 2)] },
      { playerId: 'b', cards: [] },
    ]);
    expect(w).toBeNull();
  });

  test('10. pickWinner skips folded (<5 cards) entries', () => {
    const aces = [
      c('hearts', 14), c('diamonds', 14), c('clubs', 5), c('spades', 4), c('hearts', 2),
    ];
    const w = pickWinner([
      { playerId: 'folded', cards: [c('hearts', 2)] },
      { playerId: 'pA', cards: aces },
    ]);
    expect(w).toBe('pA');
  });
});

```
