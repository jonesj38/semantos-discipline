---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/commands/dungeon/take.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.426323+00:00
---

# packages/games/src/cli/commands/dungeon/take.ts

```ts
/** `semantos game dungeon take [--item <i>]` — pick up an item from current tile. */

import type { CommandSpec } from '../../command-registry';
import { session } from '../../session';

export const dungeonTake: CommandSpec = {
  game: 'dungeon',
  action: 'take',
  summary: 'Pick up an item from the current tile.',
  args: [
    { name: 'item', description: 'Optional item index when several are present.' },
  ],
  handler(cmd) {
    if (!session.dungeonGame) return { error: 'No active game.' };
    const idx = cmd.flags.item !== undefined ? Number(cmd.flags.item) : undefined;
    try {
      const result = session.dungeonGame.pickup(idx);
      return { message: result.message, status: result.status };
    } catch (e) {
      return { error: e instanceof Error ? e.message : String(e) };
    }
  },
};

```
