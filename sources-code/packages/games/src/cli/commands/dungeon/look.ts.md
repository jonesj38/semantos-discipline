---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/commands/dungeon/look.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.427190+00:00
---

# packages/games/src/cli/commands/dungeon/look.ts

```ts
/** `semantos game dungeon look` — describe surroundings. */

import { renderMap, describeSurroundings } from '../../../dungeon/renderer';
import type { CommandSpec } from '../../command-registry';
import { session } from '../../session';

export const dungeonLook: CommandSpec = {
  game: 'dungeon',
  action: 'look',
  summary: 'Describe the player\u2019s immediate surroundings.',
  args: [],
  handler() {
    if (!session.dungeonGame) return { error: 'No active game.' };
    const board = session.dungeonGame.getBoard();
    return {
      map: renderMap(board, session.dungeonGame.getVisibleTiles(), session.dungeonGame.getExploredTiles()),
      surroundings: describeSurroundings(board, session.dungeonGame.getVisibleTiles()),
    };
  },
};

```
