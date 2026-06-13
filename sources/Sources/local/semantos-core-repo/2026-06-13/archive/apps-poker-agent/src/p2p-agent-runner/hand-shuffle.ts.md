---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/p2p-agent-runner/hand-shuffle.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.786365+00:00
---

# archive/apps-poker-agent/src/p2p-agent-runner/hand-shuffle.ts

```ts
/**
 * Deterministic deal for both P2P players.
 *
 * Both seats compute the same deck from `gameId:hand:N` so neither
 * needs to trust the other's shuffle. Routes through the prompt-16
 * `deterministicShuffle` (SHA-256 Fisher-Yates pinned bit-identical
 * to the legacy impl on 100 seeds — P2P consensus depends on it).
 */

import {
  createDeck,
  deterministicShuffle,
  type Card,
} from '../shared';

export interface DealResult {
  /** Full shuffled deck (both seats see this exact ordering). */
  deck: Card[];
  /** Two hole cards for seat 0. */
  seat0Cards: [Card, Card];
  /** Two hole cards for seat 1. */
  seat1Cards: [Card, Card];
  /** Cursor position after dealing hole cards (next: burn or community). */
  deckIdx: number;
}

/** Compute the seed string used for the per-hand shuffle. */
export function shuffleSeedFor(gameId: string, handNumber: number): string {
  return `${gameId}:hand:${handNumber}`;
}

/** Produce both seats' hole cards from the deterministic shuffle. */
export function dealForP2P(gameId: string, handNumber: number): DealResult {
  const deck = deterministicShuffle(createDeck(), shuffleSeedFor(gameId, handNumber));
  return {
    deck,
    seat0Cards: [deck[0], deck[1]] as [Card, Card],
    seat1Cards: [deck[2], deck[3]] as [Card, Card],
    deckIdx: 4,
  };
}

/**
 * Build a `draw()` function over the dealt deck. The P2P runner's
 * legacy code did this inline; extracting keeps the deck cursor
 * model isolated to one place.
 */
export function makeDeckCursor(deck: Card[], startIdx: number): {
  draw: () => Card;
  burn: () => void;
  index: () => number;
} {
  let idx = startIdx;
  return {
    draw: () => {
      if (idx >= deck.length) throw new Error('p2p deck exhausted');
      return deck[idx++];
    },
    burn: () => {
      idx++;
    },
    index: () => idx,
  };
}

```
