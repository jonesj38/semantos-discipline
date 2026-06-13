---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/commands/chess/fen.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.417757+00:00
---

# packages/games/src/cli/commands/chess/fen.ts

```ts
/** `semantos game chess fen` — emit Forsyth-Edwards notation. */

import { toFEN } from '../../../chess/fen';
import type { CommandSpec } from '../../command-registry';
import { session } from '../../session';

export const chessFen: CommandSpec = {
  game: 'chess',
  action: 'fen',
  summary: 'Emit FEN notation for the current chess position.',
  args: [],
  handler() {
    if (!session.chessGame) return { error: 'No active game.' };
    return { fen: toFEN(session.chessGame.getBoard()) };
  },
};

```
