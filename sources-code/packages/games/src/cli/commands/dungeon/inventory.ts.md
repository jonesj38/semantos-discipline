---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/commands/dungeon/inventory.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.423709+00:00
---

# packages/games/src/cli/commands/dungeon/inventory.ts

```ts
/** `semantos game dungeon inventory` — list carried items. */

import { renderInventory } from '../../../dungeon/renderer';
import type { CommandSpec } from '../../command-registry';
import { session } from '../../session';

export const dungeonInventory: CommandSpec = {
  game: 'dungeon',
  action: 'inventory',
  summary: 'List items currently carried by the player.',
  args: [],
  handler() {
    if (!session.dungeonGame) return { error: 'No active game.' };
    return { inventory: renderInventory(session.dungeonGame.getBoard().player) };
  },
};

```
