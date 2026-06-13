---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/commands/dungeon/map.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.425174+00:00
---

# packages/games/src/cli/commands/dungeon/map.ts

```ts
/** `semantos game dungeon map` — render only the explored map. */

import { renderMap } from '../../../dungeon/renderer';
import type { CommandSpec } from '../../command-registry';
import { session } from '../../session';

export const dungeonMap: CommandSpec = {
  game: 'dungeon',
  action: 'map',
  summary: 'Render the explored region of the dungeon map.',
  args: [],
  handler() {
    if (!session.dungeonGame) return { error: 'No active game.' };
    const board = session.dungeonGame.getBoard();
    return {
      map: renderMap(board, session.dungeonGame.getVisibleTiles(), session.dungeonGame.getExploredTiles()),
    };
  },
};

```
