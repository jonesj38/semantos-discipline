---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/risk/renderer.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.409153+00:00
---

# packages/games/src/risk/renderer.ts

```ts
/**
 * ASCII Risk board renderer.
 *
 * Shows territories grouped by continent with owner colors and army counts.
 */

import type { RiskBoard } from './types';
import { PLAYER_COLORS } from './types';
import { TERRITORIES, CONTINENTS } from './map';

/** Render the Risk board as a territory listing grouped by continent. */
export function renderBoard(board: RiskBoard): string {
  const lines: string[] = [];

  lines.push(`Turn ${board.turnNumber}  Player ${board.currentPlayer + 1} (${PLAYER_COLORS[board.currentPlayer]})  Phase: ${board.phase}`);
  lines.push('');

  for (const continent of CONTINENTS) {
    const allOwned = continent.territories.every(
      tid => board.territories[tid].owner === board.currentPlayer,
    );
    const bonusTag = allOwned ? ` [+${continent.bonus}]` : '';
    lines.push(`── ${continent.name} (bonus: ${continent.bonus})${bonusTag} ──`);

    for (const tid of continent.territories) {
      const t = board.territories[tid];
      const terr = TERRITORIES[tid];
      const color = PLAYER_COLORS[t.owner];
      const armies = String(t.armies).padStart(2);
      lines.push(`  ${terr.abbr} ${terr.name.padEnd(22)} P${t.owner + 1}/${color.padEnd(6)} ${armies} armies`);
    }
    lines.push('');
  }

  return lines.join('\n');
}

/** Render a compact summary of territory ownership. */
export function renderSummary(board: RiskBoard, playerCount: number): string {
  const lines: string[] = [];

  lines.push(`Turn ${board.turnNumber}  Phase: ${board.phase}`);
  lines.push('');

  for (let p = 0; p < playerCount; p++) {
    const owned = board.territories.filter(t => t.owner === p);
    const totalArmies = owned.reduce((s, t) => s + t.armies, 0);
    const continents = CONTINENTS.filter(c =>
      c.territories.every(tid => board.territories[tid].owner === p),
    );
    const contNames = continents.map(c => c.name).join(', ') || 'none';

    lines.push(
      `  P${p + 1} (${PLAYER_COLORS[p].padEnd(6)}): ${String(owned.length).padStart(2)} territories, ${String(totalArmies).padStart(3)} armies | continents: ${contNames}`,
    );
  }

  return lines.join('\n');
}

```
