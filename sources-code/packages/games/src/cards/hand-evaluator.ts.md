---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cards/hand-evaluator.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.409769+00:00
---

# packages/games/src/cards/hand-evaluator.ts

```ts
/**
 * Texas Hold'em Hand Evaluator
 *
 * Evaluates the best 5-card hand from any combination of 5-7 cards.
 * Uses combinatorial selection (C(7,5) = 21 combinations at most).
 *
 * Rankings from highest to lowest:
 *   Royal Flush > Straight Flush > Four of a Kind > Full House >
 *   Flush > Straight > Three of a Kind > Two Pair > Pair > High Card
 */

import type { Card } from './types';
import { HandRank, HAND_RANK_NAMES, type EvaluatedHand } from './poker-types';

// ── Effective Rank ──────────────────────────────────────────

/** Ace = 14 for comparison purposes. */
function effectiveRank(rank: number): number {
  return rank === 1 ? 14 : rank;
}

/** Rank name for display. */
function rankName(rank: number): string {
  const names: Record<number, string> = {
    1: 'A', 2: '2', 3: '3', 4: '4', 5: '5', 6: '6', 7: '7',
    8: '8', 9: '9', 10: 'T', 11: 'J', 12: 'Q', 13: 'K',
  };
  return names[rank] ?? '?';
}

function suitSymbol(suit: string): string {
  const symbols: Record<string, string> = {
    hearts: 'h', diamonds: 'd', clubs: 'c', spades: 's',
  };
  return symbols[suit] ?? '?';
}

function cardStr(card: Card): string {
  return `${rankName(card.rank)}${suitSymbol(card.suit)}`;
}

// ── 5-Card Evaluation ──────────────────────────────────────

interface FiveCardResult {
  rank: HandRank;
  kickers: number[];
  description: string;
}

function evaluate5(cards: Card[]): FiveCardResult {
  const ranks = cards.map(c => effectiveRank(c.rank)).sort((a, b) => b - a);
  const suits = cards.map(c => c.suit);

  // Flush?
  const isFlush = suits.every(s => s === suits[0]);

  // Straight? (including wheel: A-2-3-4-5)
  let isStraight = false;
  let straightHigh = 0;

  // Check normal straight
  if (ranks[0] - ranks[4] === 4 && new Set(ranks).size === 5) {
    isStraight = true;
    straightHigh = ranks[0];
  }
  // Check wheel (A-5-4-3-2)
  if (!isStraight && ranks[0] === 14 && ranks[1] === 5 && ranks[2] === 4 && ranks[3] === 3 && ranks[4] === 2) {
    isStraight = true;
    straightHigh = 5; // 5-high straight
  }

  // Count rank frequencies
  const freq = new Map<number, number>();
  for (const r of ranks) {
    freq.set(r, (freq.get(r) ?? 0) + 1);
  }
  const counts = [...freq.entries()].sort((a, b) => b[1] - a[1] || b[0] - a[0]);

  // Royal Flush
  if (isFlush && isStraight && straightHigh === 14) {
    return { rank: HandRank.ROYAL_FLUSH, kickers: [14], description: 'Royal Flush' };
  }

  // Straight Flush
  if (isFlush && isStraight) {
    return { rank: HandRank.STRAIGHT_FLUSH, kickers: [straightHigh], description: `Straight Flush, ${straightHigh}-high` };
  }

  // Four of a Kind
  if (counts[0][1] === 4) {
    const quad = counts[0][0];
    const kicker = counts[1][0];
    return { rank: HandRank.FOUR_OF_A_KIND, kickers: [quad, kicker], description: `Four ${quad}s` };
  }

  // Full House
  if (counts[0][1] === 3 && counts[1][1] === 2) {
    return { rank: HandRank.FULL_HOUSE, kickers: [counts[0][0], counts[1][0]], description: `Full House, ${counts[0][0]}s full of ${counts[1][0]}s` };
  }

  // Flush
  if (isFlush) {
    return { rank: HandRank.FLUSH, kickers: ranks, description: `Flush, ${ranks[0]}-high` };
  }

  // Straight
  if (isStraight) {
    return { rank: HandRank.STRAIGHT, kickers: [straightHigh], description: `Straight, ${straightHigh}-high` };
  }

  // Three of a Kind
  if (counts[0][1] === 3) {
    const trips = counts[0][0];
    const kickers = counts.filter(c => c[1] === 1).map(c => c[0]);
    return { rank: HandRank.THREE_OF_A_KIND, kickers: [trips, ...kickers], description: `Three ${trips}s` };
  }

  // Two Pair
  if (counts[0][1] === 2 && counts[1][1] === 2) {
    const high = Math.max(counts[0][0], counts[1][0]);
    const low = Math.min(counts[0][0], counts[1][0]);
    const kicker = counts[2][0];
    return { rank: HandRank.TWO_PAIR, kickers: [high, low, kicker], description: `Two Pair, ${high}s and ${low}s` };
  }

  // Pair
  if (counts[0][1] === 2) {
    const pair = counts[0][0];
    const kickers = counts.filter(c => c[1] === 1).map(c => c[0]);
    return { rank: HandRank.PAIR, kickers: [pair, ...kickers], description: `Pair of ${pair}s` };
  }

  // High Card
  return { rank: HandRank.HIGH_CARD, kickers: ranks, description: `${ranks[0]}-high` };
}

// ── Combinatorial Selection ────────────────────────────────

/** Generate all C(n,5) combinations of indices. */
function* combinations5(n: number): Generator<number[]> {
  for (let a = 0; a < n - 4; a++) {
    for (let b = a + 1; b < n - 3; b++) {
      for (let c = b + 1; c < n - 2; c++) {
        for (let d = c + 1; d < n - 1; d++) {
          for (let e = d + 1; e < n; e++) {
            yield [a, b, c, d, e];
          }
        }
      }
    }
  }
}

// ── Comparison ──────────────────────────────────────────────

/** Compare two evaluated hands. Returns positive if a > b, negative if a < b, 0 if tie. */
export function compareHands(a: EvaluatedHand, b: EvaluatedHand): number {
  if (a.rank !== b.rank) return a.rank - b.rank;
  // Same rank — compare kickers
  for (let i = 0; i < Math.max(a.kickers.length, b.kickers.length); i++) {
    const ak = a.kickers[i] ?? 0;
    const bk = b.kickers[i] ?? 0;
    if (ak !== bk) return ak - bk;
  }
  return 0; // exact tie
}

// ── Public API ──────────────────────────────────────────────

/**
 * Evaluate the best 5-card hand from a set of 5-7 cards.
 * For Hold'em: pass 2 hole cards + 3-5 community cards.
 */
export function evaluateHand(cards: Card[]): EvaluatedHand {
  if (cards.length < 5) {
    throw new Error(`Need at least 5 cards to evaluate, got ${cards.length}`);
  }

  if (cards.length === 5) {
    const result = evaluate5(cards);
    return { ...result, bestFive: cards };
  }

  // Try all C(n,5) combinations, keep the best
  let best: EvaluatedHand | null = null;

  for (const indices of combinations5(cards.length)) {
    const five = indices.map(i => cards[i]);
    const result = evaluate5(five);
    const evaluated: EvaluatedHand = { ...result, bestFive: five };

    if (!best || compareHands(evaluated, best) > 0) {
      best = evaluated;
    }
  }

  return best!;
}

/**
 * Format a hand for display.
 */
export function formatHand(cards: Card[]): string {
  return cards.map(cardStr).join(' ');
}

export { rankName, suitSymbol, cardStr };

```
