---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cards/engine.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.412056+00:00
---

# packages/games/src/cards/engine.ts

```ts
/**
 * CardGameEngine — creates and manages playing cards as LINEAR cells.
 *
 * Each card is a LINEAR GameEntity. When a card is "played" (consumed),
 * its cell ID is recorded and it cannot be used again. This demonstrates
 * LINEAR resource semantics: a card exists exactly once and is used
 * exactly once.
 */

import { GameCellEngine, type CreateOptions } from '../../../game-sdk/src/engine';
import { GameEntityType, type GameEntity } from '../../../game-sdk/src/types';

import {
  SUITS,
  RANKS,
  type Suit,
  type Rank,
  type Card,
  type Deck,
} from './types';

/** LINEAR linearity value (must be consumed exactly once) */
const LINEAR = 1;

/** Shared owner ID for the "dealer" / house */
const DEALER_OWNER = new Uint8Array(16); // all-zeros = dealer

export class CardGameEngine {
  readonly cellEngine: GameCellEngine;

  /** Set of cell IDs that have been consumed (played) */
  private consumedCells = new Set<string>();

  private constructor(cellEngine: GameCellEngine) {
    this.cellEngine = cellEngine;
  }

  /**
   * Create a CardGameEngine instance.
   * Initializes the underlying WASM cell engine.
   */
  static async create(opts?: CreateOptions): Promise<CardGameEngine> {
    const cellEngine = await GameCellEngine.create(opts);
    return new CardGameEngine(cellEngine);
  }

  // ── Deck Operations ─────────────────────────────────────────

  /**
   * Create a standard 52-card deck.
   * Each card is a LINEAR cell entity (4 suits x 13 ranks).
   */
  createDeck(): Deck {
    const cards: Card[] = [];

    for (const suit of SUITS) {
      for (const rank of RANKS) {
        const entity = this.cellEngine.createEntity({
          entityType: GameEntityType.ITEM,
          ownerId: DEALER_OWNER,
          linearity: LINEAR,
          metadata: { suit, rank, cardType: 'playing-card' },
          state: 'in-deck',
        });

        cards.push({
          entity,
          suit,
          rank,
          faceUp: false,
        });
      }
    }

    return { cards };
  }

  /**
   * Shuffle a deck using Fisher-Yates algorithm.
   * Shuffles card references in-place — no new cells are created.
   * Returns a new Deck with the shuffled order.
   */
  shuffle(deck: Deck): Deck {
    const cards = [...deck.cards];

    for (let i = cards.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [cards[i], cards[j]] = [cards[j], cards[i]];
    }

    return { cards };
  }

  /**
   * Deal cards from the top of the deck.
   * Returns the dealt cards and the remaining deck.
   */
  deal(deck: Deck, count: number): { dealt: Card[]; remaining: Deck } {
    if (count > deck.cards.length) {
      throw new Error(
        `Cannot deal ${count} cards from a deck with ${deck.cards.length} cards`,
      );
    }

    const dealt = deck.cards.slice(0, count);
    const remaining = { cards: deck.cards.slice(count) };

    return { dealt, remaining };
  }

  // ── Card Consumption (LINEAR destruction) ───────────────────

  /**
   * Play (consume) a card. This is LINEAR destruction —
   * the card's cell ID is recorded as consumed and cannot be reused.
   */
  playCard(card: Card): void {
    const cellId = card.entity.id;

    if (this.consumedCells.has(cellId)) {
      throw new Error(`Card ${cellId} has already been consumed (LINEAR violation)`);
    }

    this.consumedCells.add(cellId);
  }

  /**
   * Check whether a cell ID has been consumed.
   */
  isConsumed(cellId: string): boolean {
    return this.consumedCells.has(cellId);
  }
}

```
