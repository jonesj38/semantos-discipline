---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/commands/dungeon/history.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.426606+00:00
---

# packages/games/src/cli/commands/dungeon/history.ts

```ts
/** `semantos game dungeon history` — return the cell DAG history. */

import type { CommandSpec } from '../../command-registry';
import { session } from '../../session';

export const dungeonHistory: CommandSpec = {
  game: 'dungeon',
  action: 'history',
  summary: 'Return the underlying cell history list.',
  args: [],
  handler() {
    if (!session.dungeonGame) return { error: 'No active game.' };
    return {
      boardCells: session.dungeonGame.history(),
      cellCount: session.dungeonGame.history().length,
    };
  },
};

```
