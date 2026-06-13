---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/commands/dungeon/descend.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.425457+00:00
---

# packages/games/src/cli/commands/dungeon/descend.ts

```ts
/** `semantos game dungeon descend` — go down one floor via the staircase. */

import { renderMap, renderStatus } from '../../../dungeon/renderer';
import type { CommandSpec } from '../../command-registry';
import { session } from '../../session';

export const dungeonDescend: CommandSpec = {
  game: 'dungeon',
  action: 'descend',
  summary: 'Descend to the next dungeon floor.',
  args: [],
  handler() {
    if (!session.dungeonGame) return { error: 'No active game.' };
    try {
      const result = session.dungeonGame.descend();
      return {
        map: renderMap(result.board, session.dungeonGame.getVisibleTiles(), session.dungeonGame.getExploredTiles()),
        info: renderStatus(result.board),
        message: result.message,
        status: result.status,
      };
    } catch (e) {
      return { error: e instanceof Error ? e.message : String(e) };
    }
  },
};

```
