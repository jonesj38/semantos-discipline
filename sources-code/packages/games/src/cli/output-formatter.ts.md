---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/output-formatter.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.400601+00:00
---

# packages/games/src/cli/output-formatter.ts

```ts
/**
 * Pure formatters for game CLI output.
 *
 * Extracted from the legacy game-commands.ts so per-game handlers can
 * compose them without duplicating string-rendering logic. No IO, no
 * mutation, no engine references — just (data) → string.
 */

import type { Card } from '../cards/types';

/** Map a numeric card rank (1-13) to the standard one-character label. */
export function rankName(rank: number): string {
  const names: Record<number, string> = {
    1: 'A', 2: '2', 3: '3', 4: '4', 5: '5', 6: '6', 7: '7',
    8: '8', 9: '9', 10: 'T', 11: 'J', 12: 'Q', 13: 'K',
  };
  return names[rank] ?? '?';
}

/** Map a suit name to its unicode glyph. */
export function suitChar(suit: string): string {
  const symbols: Record<string, string> = {
    hearts: '\u2665', diamonds: '\u2666', clubs: '\u2663', spades: '\u2660',
  };
  return symbols[suit] ?? '?';
}

/** Format one card as `[<rank><suit>]`, e.g. `[A♠]`. */
export function formatCard(card: Card): string {
  return `[${rankName(card.rank)}${suitChar(card.suit)}]`;
}

/** Space-separated `[<rank><suit>]` cards. Empty string if the list is empty. */
export function formatCards(cards: readonly Card[]): string {
  return cards.map(formatCard).join(' ');
}

```
