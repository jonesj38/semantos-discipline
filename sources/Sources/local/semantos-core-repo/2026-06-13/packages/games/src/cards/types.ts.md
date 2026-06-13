---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cards/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.410067+00:00
---

# packages/games/src/cards/types.ts

```ts
/**
 * Card Game Types
 *
 * Domain types for card games built on the cell engine.
 * Every card IS a LINEAR cell — dealt once, played once, consumed once.
 */

import type { GameEntity } from '../../../game-sdk/src/types';

// ── Suit & Rank ─────────────────────────────────────────────────

export type Suit = 'hearts' | 'diamonds' | 'clubs' | 'spades';

/** 1 = Ace, 2-10 = pip cards, 11 = Jack, 12 = Queen, 13 = King */
export type Rank = 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13;

export const SUITS: readonly Suit[] = ['hearts', 'diamonds', 'clubs', 'spades'] as const;

export const RANKS: readonly Rank[] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13] as const;

// ── Card ────────────────────────────────────────────────────────

export interface Card {
  /** The underlying LINEAR cell entity */
  entity: GameEntity;
  /** Card suit */
  suit: Suit;
  /** Card rank (1=Ace .. 13=King) */
  rank: Rank;
  /** Whether the card is face-up (visible) */
  faceUp: boolean;
}

// ── Deck & Hand ─────────────────────────────────────────────────

export interface Deck {
  /** Ordered array of cards (index 0 = top of deck) */
  cards: Card[];
}

export interface Hand {
  /** Ordered array of cards in this hand */
  cards: Card[];
  /** Identifier of the hand's owner */
  ownerId: string;
}

// ── Round Result (for War) ──────────────────────────────────────

export interface WarRoundResult {
  /** Card played by player 1 */
  player1Card: Card;
  /** Card played by player 2 */
  player2Card: Card;
  /** Who won this round */
  winner: 'player1' | 'player2' | 'tie';
  /** Number of cards at stake (> 2 during war) */
  cardsAtStake: number;
  /** True if this round involved a war (tie-break) */
  wasWar: boolean;
}

```
