---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/commands/dungeon/move.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.424307+00:00
---

# packages/games/src/cli/commands/dungeon/move.ts

```ts
/** `semantos game dungeon move --direction <n|s|e|w>` — move the player. */

import { renderMap, renderStatus, describeSurroundings } from '../../../dungeon/renderer';
import { isDirection } from '../../../dungeon/types';
import type { CommandSpec } from '../../command-registry';
import { session } from '../../session';

export const dungeonMove: CommandSpec = {
  game: 'dungeon',
  action: 'move',
  summary: 'Move the player one tile in a cardinal direction.',
  args: [
    { name: 'direction', description: 'n, s, e, or w.', required: true },
  ],
  handler(cmd) {
    if (!session.dungeonGame) return { error: 'No active game. Run: semantos game dungeon new' };
    const dir = (cmd.flags.direction ?? cmd.flags.expression ?? 'n') as string;
    if (!isDirection(dir)) return { error: `Invalid direction: ${dir}. Use: n, s, e, w` };
    try {
      const result = session.dungeonGame.move(dir);
      return {
        map: renderMap(result.board, session.dungeonGame.getVisibleTiles(), session.dungeonGame.getExploredTiles()),
        info: renderStatus(result.board),
        message: result.message,
        surroundings: describeSurroundings(result.board, session.dungeonGame.getVisibleTiles()),
        status: result.status,
      };
    } catch (e) {
      return { error: e instanceof Error ? e.message : String(e) };
    }
  },
};

```
