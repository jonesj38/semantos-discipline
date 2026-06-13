---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/commands/chess/status.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.418624+00:00
---

# packages/games/src/cli/commands/chess/status.ts

```ts
/** `semantos game chess status` — report active/check/checkmate/draw. */

import type { CommandSpec } from '../../command-registry';
import { session } from '../../session';

export const chessStatus: CommandSpec = {
  game: 'chess',
  action: 'status',
  summary: 'Report the engine status (active, check, checkmate, draw).',
  args: [],
  handler() {
    if (!session.chessGame) return { error: 'No active game.' };
    return { status: session.chessGame.status() };
  },
};

```
