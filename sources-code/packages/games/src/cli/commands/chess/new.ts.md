---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/commands/chess/new.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.418905+00:00
---

# packages/games/src/cli/commands/chess/new.ts

```ts
/**
 * `semantos game chess new` — start a fresh chess game.
 *
 * Replaces the in-session board with a freshly-created
 * `SemanticChessEngine` and clears the move history.
 */

import { SemanticChessEngine } from '../../../chess/engine';
import { renderBoard } from '../../../chess/renderer';
import { toFEN } from '../../../chess/fen';
import type { CommandSpec } from '../../command-registry';
import { session } from '../../session';

export const chessNew: CommandSpec = {
  game: 'chess',
  action: 'new',
  summary: 'Start a fresh chess game.',
  args: [],
  async handler() {
    session.chessGame = await SemanticChessEngine.create();
    session.chessMoves = [];
    return {
      status: 'created',
      board: renderBoard(session.chessGame.getBoard()),
      fen: toFEN(session.chessGame.getBoard()),
    };
  },
};

```
