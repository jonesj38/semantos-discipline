---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/commands/poker/table.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.420739+00:00
---

# packages/games/src/cli/commands/poker/table.ts

```ts
/** `semantos game poker table` — render the current table state. */

import { renderPokerTable } from '../../../cards/poker-renderer';
import type { CommandSpec } from '../../command-registry';
import { session } from '../../session';

export const pokerTable: CommandSpec = {
  game: 'poker',
  action: 'table',
  summary: 'Render the current poker table.',
  args: [],
  handler() {
    if (!session.pokerGame) return { error: 'No active game.' };
    const table = session.pokerGame.getTable();
    const players = session.pokerGame.getPlayers();
    return {
      table: renderPokerTable(table, players, 'player-0'),
      phase: table.phase,
      pot: table.pot,
    };
  },
};

```
