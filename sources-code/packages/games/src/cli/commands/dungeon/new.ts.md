---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/commands/dungeon/new.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.426029+00:00
---

# packages/games/src/cli/commands/dungeon/new.ts

```ts
/** `semantos game dungeon new` — create a fresh dungeon. */

import { DungeonEngine } from '../../../dungeon/engine';
import { renderMap, renderStatus } from '../../../dungeon/renderer';
import type { CommandSpec } from '../../command-registry';
import { session } from '../../session';

export const dungeonNew: CommandSpec = {
  game: 'dungeon',
  action: 'new',
  summary: 'Generate a fresh dungeon and place the player.',
  args: [],
  async handler() {
    session.dungeonGame = await DungeonEngine.create();
    const board = session.dungeonGame.getBoard();
    return {
      status: 'created',
      map: renderMap(board, session.dungeonGame.getVisibleTiles(), session.dungeonGame.getExploredTiles()),
      info: renderStatus(board),
      message: board.messages[0],
    };
  },
};

```
