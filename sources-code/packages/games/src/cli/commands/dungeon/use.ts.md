---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/commands/dungeon/use.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.424879+00:00
---

# packages/games/src/cli/commands/dungeon/use.ts

```ts
/** `semantos game dungeon use --item <i>` — use a held item. */

import { renderStatus } from '../../../dungeon/renderer';
import type { CommandSpec } from '../../command-registry';
import { session } from '../../session';

export const dungeonUse: CommandSpec = {
  game: 'dungeon',
  action: 'use',
  summary: 'Use a held inventory item by index.',
  args: [
    { name: 'item', description: 'Inventory item index.', required: true },
  ],
  handler(cmd) {
    if (!session.dungeonGame) return { error: 'No active game.' };
    const idx = Number(cmd.flags.item ?? cmd.flags.expression ?? 0);
    try {
      const result = session.dungeonGame.useItem(idx);
      return {
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
