---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/shared/card-types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.770273+00:00
---

# archive/apps-poker-agent/src/shared/card-types.ts

```ts
/**
 * Shared card-game primitives — `Card`, `Rank`, `Suit`, `Hand`.
 *
 * The poker-agent's existing call sites (`game-loop.ts`,
 * `p2p-agent-runner.ts`, `direct-poker-state-machine.ts`) all use the
 * same descriptor shape:
 *
 *   { suit: string; rank: number; label: string }
 *
 * This file pins that shape with a typed `Suit` union + helpers, so
 * subsequent prompts can rely on a single import path without
 * reverting to inline type definitions.
 *
 * The deeper `packages/games/cards/types.ts` shape (with `entity`,
 * `faceUp`, etc.) is the canonical type used by the cell-engine /
 * mental-poker stack. The poker-agent's lighter shape exists because
 * the agent never needs `entity` / `faceUp` — bridging happens in
 * `hand-evaluator.ts` when we have to call into the canonical engine.
 */

export type Suit = 'hearts' | 'diamonds' | 'clubs' | 'spades';

/** Rank in the canonical poker-agent encoding: 2..14 (A=14). */
export type Rank = 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14;

export interface Card {
  suit: Suit;
  rank: Rank;
  /** Pretty label, e.g. "Ah", "Td", "Kc". */
  label: string;
}

/** A hand is just a small list of cards. Texas Hold'em uses 5–7. */
export type Hand = Card[];

/** Lookup table: the rank index (2..14) → its display label. */
export const RANK_LABELS: Record<Rank, string> = {
  2: '2', 3: '3', 4: '4', 5: '5', 6: '6', 7: '7', 8: '8',
  9: '9', 10: '10', 11: 'J', 12: 'Q', 13: 'K', 14: 'A',
};

/** Single suit char used in card labels. */
export const SUIT_CHAR: Record<Suit, string> = {
  hearts: 'h',
  diamonds: 'd',
  clubs: 'c',
  spades: 's',
};

export const SUITS: readonly Suit[] = ['hearts', 'diamonds', 'clubs', 'spades'];

/** Build a 52-card deck in canonical order (suit-major, rank-minor). */
export function createDeck(): Card[] {
  const deck: Card[] = [];
  for (const suit of SUITS) {
    for (let rank = 2; rank <= 14; rank++) {
      const r = rank as Rank;
      deck.push({ suit, rank: r, label: `${RANK_LABELS[r]}${SUIT_CHAR[suit]}` });
    }
  }
  return deck;
}

/** Render a card as its label (e.g. "Ah"). */
export function cardLabel(card: Card): string {
  return card.label || `${RANK_LABELS[card.rank]}${SUIT_CHAR[card.suit]}`;
}

```
