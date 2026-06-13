---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/commands/chess/board.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.418341+00:00
---

# packages/games/src/cli/commands/chess/board.ts

```ts
/** `semantos game chess board` — pretty-print the current board. */

import { renderBoard } from '../../../chess/renderer';
import type { CommandSpec } from '../../command-registry';
import { session } from '../../session';

export const chessBoard: CommandSpec = {
  game: 'chess',
  action: 'board',
  summary: 'Render the current chess board.',
  args: [],
  handler() {
    if (!session.chessGame) return { error: 'No active game.' };
    return { board: renderBoard(session.chessGame.getBoard()) };
  },
};

```
