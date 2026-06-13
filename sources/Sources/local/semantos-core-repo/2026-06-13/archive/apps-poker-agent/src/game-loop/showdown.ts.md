---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/game-loop/showdown.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.776455+00:00
---

# archive/apps-poker-agent/src/game-loop/showdown.ts

```ts
/**
 * Showdown helpers — extracted from the legacy
 * `simpleShowdown()` + chip-totals projection.
 *
 * Note: the legacy simpleShowdown is a rank-sum scorer (broken — it
 * doesn't actually evaluate poker hands). It's preserved bit-
 * identical for now to avoid changing match outcomes; the proper
 * `pickWinner` from `shared/hand-evaluator.ts` is available for a
 * future correctness PR.
 */

import type { CardDescriptor, SimplePlayer } from './types';

/**
 * Legacy rank-sum scorer. Returns the player with the highest
 * sum of (hole + community) ranks. Folded players score -1.
 *
 * Tie-break favours player 0 (matches the legacy `>=` behaviour).
 */
export function simpleShowdown(
  players: SimplePlayer[],
  community: CardDescriptor[],
): SimplePlayer {
  const scores = players.map((p) => {
    if (p.folded) return -1;
    const all = [...p.holeCards, ...community];
    return all.reduce((sum, c) => sum + c.rank, 0);
  });
  return scores[0] >= scores[1] ? players[0] : players[1];
}

/** Project a `{name, chips}` summary used by emit-event payloads. */
export function totalsByName(players: SimplePlayer[]): { name: string; chips: number }[] {
  return players.map((p) => ({ name: p.name, chips: p.chips }));
}

```
