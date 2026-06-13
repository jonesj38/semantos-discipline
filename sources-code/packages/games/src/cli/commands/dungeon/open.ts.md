---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/commands/dungeon/open.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.424593+00:00
---

# packages/games/src/cli/commands/dungeon/open.ts

```ts
/** `semantos game dungeon open --direction <n|s|e|w>` — open a door. */

import { renderMap } from '../../../dungeon/renderer';
import { isDirection } from '../../../dungeon/types';
import type { CommandSpec } from '../../command-registry';
import { session } from '../../session';

export const dungeonOpen: CommandSpec = {
  game: 'dungeon',
  action: 'open',
  summary: 'Open the door in the given direction.',
  args: [
    { name: 'direction', description: 'n, s, e, or w.', required: true },
  ],
  handler(cmd) {
    if (!session.dungeonGame) return { error: 'No active game.' };
    const dir = (cmd.flags.direction ?? cmd.flags.expression ?? 'n') as string;
    if (!isDirection(dir)) return { error: `Invalid direction: ${dir}. Use: n, s, e, w` };
    try {
      const result = session.dungeonGame.openDoor(dir);
      return {
        map: renderMap(result.board, session.dungeonGame.getVisibleTiles(), session.dungeonGame.getExploredTiles()),
        message: result.message,
        status: result.status,
      };
    } catch (e) {
      return { error: e instanceof Error ? e.message : String(e) };
    }
  },
};

```
