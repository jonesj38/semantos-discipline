---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/game-loop/deck-manager.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.781067+00:00
---

# archive/apps-poker-agent/src/game-loop/deck-manager.ts

```ts
/**
 * Deck manager — wraps the prompt-16 `shared/deterministic-shuffle`
 * with a stateful deal/draw cursor.
 *
 * Behaviour matches the legacy GameLoop methods byte-for-byte: the
 * deck is generated via `createDeck()`, shuffled with
 * `randomShuffle()` (Math.random Fisher-Yates), and drawn via a
 * monotonically-increasing index.
 *
 * `Deck` is intentionally mutable so the legacy `drawCard()` /
 * `dealHole()` semantics carry over. Determinism callers should pass
 * `seed` to use `deterministicShuffle` instead.
 */

import {
  createDeck,
  deterministicShuffle,
  randomShuffle,
  type Card,
} from '../shared';

import type { CardDescriptor } from './types';

export interface Deck {
  cards: CardDescriptor[];
  /** Index of the next undrawn card. */
  index: number;
}

export interface ShuffleOptions {
  /** Pass for deterministic Fisher-Yates (P2P consensus). */
  seed?: string;
}

/** Build + shuffle a fresh 52-card deck. */
export function newDeck(opts: ShuffleOptions = {}): Deck {
  const fresh = createDeck();
  const cards =
    opts.seed === undefined
      ? randomShuffle(fresh)
      : (deterministicShuffle(fresh as Card[], opts.seed) as Card[]);
  return { cards, index: 0 };
}

/** Draw the next card and advance the cursor. Throws if exhausted. */
export function drawCard(deck: Deck): CardDescriptor {
  if (deck.index >= deck.cards.length) {
    throw new Error(`deck exhausted (${deck.index}/${deck.cards.length})`);
  }
  return deck.cards[deck.index++];
}

/** Draw `n` cards and return them as a tuple. */
export function drawCards(deck: Deck, n: number): CardDescriptor[] {
  const out: CardDescriptor[] = [];
  for (let i = 0; i < n; i++) out.push(drawCard(deck));
  return out;
}

/** Hash the current deck order — used as a shuffleCommit on hand-start. */
export function deckCommitment(deck: Deck): string {
  return deck.cards.map((c) => c.label).join(',');
}

```
