---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/commands/chess/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.417467+00:00
---

# packages/games/src/cli/commands/chess/index.ts

```ts
/** Aggregate of all `chess` commands for batch registration. */

import type { CommandSpec } from '../../command-registry';
import { chessNew } from './new';
import { chessMove } from './move';
import { chessBoard } from './board';
import { chessStatus } from './status';
import { chessFen } from './fen';
import { chessHistory } from './history';

export const chessCommands: readonly CommandSpec[] = [
  chessNew,
  chessMove,
  chessBoard,
  chessStatus,
  chessFen,
  chessHistory,
];

```
