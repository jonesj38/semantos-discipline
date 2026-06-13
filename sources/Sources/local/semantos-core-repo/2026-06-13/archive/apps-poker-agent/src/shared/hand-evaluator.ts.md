---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/shared/hand-evaluator.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.769664+00:00
---

# archive/apps-poker-agent/src/shared/hand-evaluator.ts

```ts
/**
 * Poker hand evaluator — wraps the canonical implementation in
 * `packages/games/cards/hand-evaluator.ts`.
 *
 * The poker-agent's `Card` shape (`{ suit, rank, label }`, rank 2..14)
 * differs from the canonical extensions shape (`{ entity, suit, rank,
 * faceUp }`, rank 1..13 with 1=Ace). We translate at the boundary —
 * rank 14 (Ace high in agent) maps to rank 1 in the canonical encoding.
 *
 * Public API:
 *   - `evaluatePokerHand(cards)`     → EvaluatedHand
 *   - `comparePokerHands(a, b)`      → number (positive: a > b)
 *   - `pickWinner([{playerId, hand}])` → playerId of best hand
 */

import {
  compareHands as canonicalCompare,
  evaluateHand as canonicalEvaluate,
} from '../../../../packages/games/src/cards/hand-evaluator';
import type {
  EvaluatedHand,
  HandRank,
} from '../../../../packages/games/src/cards/poker-types';
import type { Card as CanonicalCard, Rank as CanonicalRank } from '../../../../packages/games/src/cards/types';

import type { Card } from './card-types';

export type { EvaluatedHand, HandRank };

/**
 * Convert poker-agent's Card (rank 2..14, A=14) into the canonical
 * extensions Card (rank 1..13, A=1). The `entity` + `faceUp` fields
 * are stubbed — the evaluator only reads `suit` + `rank`.
 */
function toCanonical(card: Card): CanonicalCard {
  const r = card.rank;
  const canonicalRank: CanonicalRank = r === 14 ? 1 : (r as CanonicalRank);
  return {
    entity: { id: 'agent-card', kind: 'card' } as unknown as CanonicalCard['entity'],
    suit: card.suit,
    rank: canonicalRank,
    faceUp: true,
  };
}

/** Evaluate the best 5-card hand from 5–7 poker-agent cards. */
export function evaluatePokerHand(cards: Card[]): EvaluatedHand {
  return canonicalEvaluate(cards.map(toCanonical));
}

/** Positive: a > b · Negative: a < b · 0: tie. */
export function comparePokerHands(a: EvaluatedHand, b: EvaluatedHand): number {
  return canonicalCompare(a, b);
}

export interface PlayerHand {
  playerId: string;
  cards: Card[];
}

export interface ShowdownEntry {
  playerId: string;
  hand: EvaluatedHand;
}

/**
 * Score every player's best 5-card hand. Folded players (`cards.length
 * < 5`) are skipped. Returns a list of `{ playerId, hand }` entries
 * sorted high-to-low so the winner is `result[0]`.
 */
export function rankPlayers(players: PlayerHand[]): ShowdownEntry[] {
  const ranked: ShowdownEntry[] = [];
  for (const p of players) {
    if (p.cards.length < 5) continue;
    ranked.push({ playerId: p.playerId, hand: evaluatePokerHand(p.cards) });
  }
  ranked.sort((a, b) => comparePokerHands(b.hand, a.hand));
  return ranked;
}

/** Picks the single highest-ranked player, or null on no eligible hands. */
export function pickWinner(players: PlayerHand[]): string | null {
  const ranked = rankPlayers(players);
  return ranked.length === 0 ? null : ranked[0].playerId;
}

```
