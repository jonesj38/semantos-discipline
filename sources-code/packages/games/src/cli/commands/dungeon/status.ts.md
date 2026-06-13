---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/commands/dungeon/status.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.425743+00:00
---

# packages/games/src/cli/commands/dungeon/status.ts

```ts
/** `semantos game dungeon status` — player + game status report. */

import { renderStatus } from '../../../dungeon/renderer';
import type { CommandSpec } from '../../command-registry';
import { session } from '../../session';

export const dungeonStatus: CommandSpec = {
  game: 'dungeon',
  action: 'status',
  summary: 'Player status, run status, and history length.',
  args: [],
  handler() {
    if (!session.dungeonGame) return { error: 'No active game. Run: semantos game dungeon new' };
    const board = session.dungeonGame.getBoard();
    return {
      info: renderStatus(board),
      status: session.dungeonGame.status(),
      historyLength: session.dungeonGame.history().length,
    };
  },
};

```
