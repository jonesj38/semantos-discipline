---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cards/poker-types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.410656+00:00
---

# packages/games/src/cards/poker-types.ts

```ts
/**
 * Texas Hold'em No-Limit Poker Types
 *
 * Cards are LINEAR cells from the card framework.
 * Community cards are shared references. Folded hands are consumed.
 * Chips are tracked as metadata (not cells) for simplicity.
 */

import type { Card } from './types';

// ── Hand Rankings ─────────────────────────────────────────────

export enum HandRank {
  HIGH_CARD = 0,
  PAIR = 1,
  TWO_PAIR = 2,
  THREE_OF_A_KIND = 3,
  STRAIGHT = 4,
  FLUSH = 5,
  FULL_HOUSE = 6,
  FOUR_OF_A_KIND = 7,
  STRAIGHT_FLUSH = 8,
  ROYAL_FLUSH = 9,
}

export const HAND_RANK_NAMES: Record<HandRank, string> = {
  [HandRank.HIGH_CARD]: 'High Card',
  [HandRank.PAIR]: 'Pair',
  [HandRank.TWO_PAIR]: 'Two Pair',
  [HandRank.THREE_OF_A_KIND]: 'Three of a Kind',
  [HandRank.STRAIGHT]: 'Straight',
  [HandRank.FLUSH]: 'Flush',
  [HandRank.FULL_HOUSE]: 'Full House',
  [HandRank.FOUR_OF_A_KIND]: 'Four of a Kind',
  [HandRank.STRAIGHT_FLUSH]: 'Straight Flush',
  [HandRank.ROYAL_FLUSH]: 'Royal Flush',
};

export interface EvaluatedHand {
  rank: HandRank;
  /** Kickers for tiebreaking, highest first. */
  kickers: number[];
  /** The 5 cards that make up the best hand. */
  bestFive: Card[];
  /** Human-readable description. */
  description: string;
}

// ── Betting ──────────────────────────────────────────────────

export type BettingRound = 'preflop' | 'flop' | 'turn' | 'river';

export type PlayerActionType = 'fold' | 'check' | 'call' | 'bet' | 'raise' | 'all-in';

export interface PokerAction {
  type: PlayerActionType;
  amount?: number;
}

// ── Player ──────────────────────────────────────────────────

export interface PokerPlayer {
  id: string;
  name: string;
  chips: number;
  holeCards: Card[];
  /** Total chips wagered in the current hand. */
  currentBet: number;
  /** True if the player has folded this hand. */
  folded: boolean;
  /** True if the player is all-in. */
  allIn: boolean;
  /** True if the player has acted this betting round. */
  hasActed: boolean;
  /** Seat index at the table (0-based). */
  seat: number;
}

// ── Side Pot ────────────────────────────────────────────────

export interface SidePot {
  amount: number;
  /** Player IDs eligible to win this pot. */
  eligible: string[];
}

// ── Table State ─────────────────────────────────────────────

export type GamePhase = 'waiting' | 'preflop' | 'flop' | 'turn' | 'river' | 'showdown' | 'hand-complete';

export interface PokerTable {
  /** Small blind amount. */
  smallBlind: number;
  /** Big blind amount. */
  bigBlind: number;
  /** Index of the dealer button (into players array). */
  dealerIndex: number;
  /** Index of the player whose turn it is. */
  activeIndex: number;
  /** Community cards on the board. */
  communityCards: Card[];
  /** Current betting round phase. */
  phase: GamePhase;
  /** Main pot. */
  pot: number;
  /** Side pots from all-in situations. */
  sidePots: SidePot[];
  /** Current minimum bet (the big blind, or the last raise). */
  currentBet: number;
  /** Minimum raise amount (previous raise size). */
  minRaise: number;
  /** Hand number (increments each deal). */
  handNumber: number;
  /** Number of players still in the hand (not folded). */
  activePlayers: number;
}

// ── Showdown Result ─────────────────────────────────────────

export interface ShowdownResult {
  winners: {
    playerId: string;
    hand: EvaluatedHand;
    potWon: number;
  }[];
  /** All hands that went to showdown. */
  hands: {
    playerId: string;
    hand: EvaluatedHand;
  }[];
}

// ── Config ──────────────────────────────────────────────────

export interface PokerConfig {
  smallBlind: number;
  bigBlind: number;
  startingChips: number;
  maxPlayers: number;
}

export const DEFAULT_POKER_CONFIG: PokerConfig = {
  smallBlind: 5,
  bigBlind: 10,
  startingChips: 1000,
  maxPlayers: 9,
};

```
