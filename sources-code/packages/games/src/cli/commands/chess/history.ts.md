---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/commands/chess/history.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.419228+00:00
---

# packages/games/src/cli/commands/chess/history.ts

```ts
/** `semantos game chess history` — return the move list + cell DAG history. */

import type { CommandSpec } from '../../command-registry';
import { session } from '../../session';

export const chessHistory: CommandSpec = {
  game: 'chess',
  action: 'history',
  summary: 'Return the move list and underlying cell history.',
  args: [],
  handler() {
    if (!session.chessGame) return { error: 'No active game.' };
    return {
      moves: session.chessMoves,
      boardCells: session.chessGame.history(),
      cellCount: session.chessGame.history().length,
    };
  },
};

```
