---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cards/war.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.411762+00:00
---

# packages/games/src/cards/war.ts

```ts
/**
 * War — the simplest card game, implemented with LINEAR cell cards.
 *
 * Rules:
 *   1. Shuffle a 52-card deck and deal 26 cards to each player.
 *   2. Each round, both players reveal their top card.
 *   3. Higher rank wins both cards (loser's card is consumed).
 *   4. On a tie: each player places 3 face-down cards and 1 face-up card.
 *      The higher face-up card wins all cards at stake.
 *   5. Game ends when one player has all surviving cards or a player
 *      cannot fulfill a war.
 *
 * Consumed cards (LINEAR destruction) are removed from play permanently.
 * The winner collects the opponent's played card to the bottom of their pile.
 */

import { CardGameEngine } from './engine';
import type { CreateOptions } from '../../../game-sdk/src/engine';
import type { Card, Hand, WarRoundResult } from './types';

export type GameStatus = 'playing' | 'finished';
export type Player = 'player1' | 'player2';

export class WarGame {
  private engine: CardGameEngine;
  private player1Hand: Hand;
  private player2Hand: Hand;
  private _status: GameStatus = 'playing';
  private _winner: Player | null = null;
  private rounds: WarRoundResult[] = [];

  private constructor(
    engine: CardGameEngine,
    player1Hand: Hand,
    player2Hand: Hand,
  ) {
    this.engine = engine;
    this.player1Hand = player1Hand;
    this.player2Hand = player2Hand;
  }

  /**
   * Create a new War game.
   * Builds a deck, shuffles it, and deals 26 cards to each player.
   */
  static async create(opts?: CreateOptions): Promise<WarGame> {
    const engine = await CardGameEngine.create(opts);
    let deck = engine.createDeck();
    deck = engine.shuffle(deck);

    const { dealt: p1Cards, remaining } = engine.deal(deck, 26);
    const { dealt: p2Cards } = engine.deal(remaining, 26);

    const player1Hand: Hand = { cards: p1Cards, ownerId: 'player1' };
    const player2Hand: Hand = { cards: p2Cards, ownerId: 'player2' };

    return new WarGame(engine, player1Hand, player2Hand);
  }

  /**
   * Play a single round of War.
   * Returns the round result, or null if the game is already finished.
   */
  playRound(): WarRoundResult | null {
    if (this._status === 'finished') return null;

    // Check if either player is out of cards
    if (this.player1Hand.cards.length === 0) {
      this._status = 'finished';
      this._winner = 'player2';
      return null;
    }
    if (this.player2Hand.cards.length === 0) {
      this._status = 'finished';
      this._winner = 'player1';
      return null;
    }

    // Both players play their top card
    const p1Card = this.player1Hand.cards.shift()!;
    const p2Card = this.player2Hand.cards.shift()!;
    p1Card.faceUp = true;
    p2Card.faceUp = true;

    // Collect all cards at stake for potential war
    const atStake: { card: Card; from: Player }[] = [
      { card: p1Card, from: 'player1' },
      { card: p2Card, from: 'player2' },
    ];

    const result = this.resolveComparison(p1Card, p2Card, atStake);
    this.rounds.push(result);

    this.checkGameOver();
    return result;
  }

  /**
   * Resolve a card comparison, handling war (ties) recursively.
   */
  private resolveComparison(
    p1Card: Card,
    p2Card: Card,
    atStake: { card: Card; from: Player }[],
  ): WarRoundResult {
    const cmp = this.compareRanks(p1Card.rank, p2Card.rank);

    if (cmp > 0) {
      // Player 1 wins — consume player 2's card, player 1 keeps theirs
      this.consumeLoserCards(atStake, 'player1');
      return {
        player1Card: p1Card,
        player2Card: p2Card,
        winner: 'player1',
        cardsAtStake: atStake.length,
        wasWar: atStake.length > 2,
      };
    }

    if (cmp < 0) {
      // Player 2 wins
      this.consumeLoserCards(atStake, 'player2');
      return {
        player1Card: p1Card,
        player2Card: p2Card,
        winner: 'player2',
        cardsAtStake: atStake.length,
        wasWar: atStake.length > 2,
      };
    }

    // Tie — WAR!
    // Each player puts 3 face-down cards and 1 face-up card
    const warCardsNeeded = 4; // 3 face-down + 1 face-up

    if (this.player1Hand.cards.length < warCardsNeeded) {
      // Player 1 can't fulfill war — player 2 wins the game
      this._status = 'finished';
      this._winner = 'player2';
      return {
        player1Card: p1Card,
        player2Card: p2Card,
        winner: 'player2',
        cardsAtStake: atStake.length,
        wasWar: true,
      };
    }

    if (this.player2Hand.cards.length < warCardsNeeded) {
      // Player 2 can't fulfill war — player 1 wins the game
      this._status = 'finished';
      this._winner = 'player1';
      return {
        player1Card: p1Card,
        player2Card: p2Card,
        winner: 'player1',
        cardsAtStake: atStake.length,
        wasWar: true,
      };
    }

    // Place 3 face-down cards from each player into the stake
    for (let i = 0; i < 3; i++) {
      atStake.push({ card: this.player1Hand.cards.shift()!, from: 'player1' });
      atStake.push({ card: this.player2Hand.cards.shift()!, from: 'player2' });
    }

    // Draw the face-up war cards
    const p1WarCard = this.player1Hand.cards.shift()!;
    const p2WarCard = this.player2Hand.cards.shift()!;
    p1WarCard.faceUp = true;
    p2WarCard.faceUp = true;
    atStake.push({ card: p1WarCard, from: 'player1' });
    atStake.push({ card: p2WarCard, from: 'player2' });

    // Recursively resolve (handles multiple consecutive ties)
    return this.resolveComparison(p1WarCard, p2WarCard, atStake);
  }

  /**
   * Consume the loser's cards (LINEAR destruction) and give the
   * winner's cards back to the bottom of their pile.
   */
  private consumeLoserCards(
    atStake: { card: Card; from: Player }[],
    winner: Player,
  ): void {
    const winnerHand = winner === 'player1' ? this.player1Hand : this.player2Hand;

    for (const { card, from } of atStake) {
      if (from !== winner) {
        // Loser's card is consumed (LINEAR destruction)
        this.engine.playCard(card);
      } else {
        // Winner's card goes to the bottom of their pile
        winnerHand.cards.push(card);
      }
    }
  }

  /**
   * Compare two ranks. Ace (1) is high (beats King).
   * Returns positive if a > b, negative if a < b, 0 if equal.
   */
  private compareRanks(a: number, b: number): number {
    // Ace (1) is the highest rank
    const effectiveA = a === 1 ? 14 : a;
    const effectiveB = b === 1 ? 14 : b;
    return effectiveA - effectiveB;
  }

  /**
   * Check if the game is over (one player has no cards).
   */
  private checkGameOver(): void {
    if (this._status === 'finished') return;

    if (this.player1Hand.cards.length === 0) {
      this._status = 'finished';
      this._winner = 'player2';
    } else if (this.player2Hand.cards.length === 0) {
      this._status = 'finished';
      this._winner = 'player1';
    }
  }

  // ── Public Accessors ──────────────────────────────────────────

  /**
   * Play the full game until completion.
   * Returns all round results.
   */
  play(): WarRoundResult[] {
    const results: WarRoundResult[] = [];
    let maxRounds = 10_000; // safety valve to prevent infinite loops

    while (this._status === 'playing' && maxRounds-- > 0) {
      const result = this.playRound();
      if (result) results.push(result);
    }

    return results;
  }

  /** Current game status */
  status(): GameStatus {
    return this._status;
  }

  /** Winner of the game, or null if still playing */
  winner(): Player | null {
    return this._winner;
  }

  /** Number of cards player 1 currently holds */
  get player1CardCount(): number {
    return this.player1Hand.cards.length;
  }

  /** Number of cards player 2 currently holds */
  get player2CardCount(): number {
    return this.player2Hand.cards.length;
  }

  /** All round results so far */
  get roundHistory(): readonly WarRoundResult[] {
    return this.rounds;
  }
}

```
