---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/commands/life/board.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.428113+00:00
---

# packages/games/src/cli/commands/life/board.ts

```ts
/** `semantos game life board` — render the current cells. */

import { renderBoard as renderLifeBoard } from '../../../life/renderer';
import type { CommandSpec } from '../../command-registry';
import { session } from '../../session';

export const lifeBoard: CommandSpec = {
  game: 'life',
  action: 'board',
  summary: 'Render the current Game-of-Life board.',
  args: [],
  handler() {
    if (!session.lifeGame) return { error: 'No active game.' };
    return { board: renderLifeBoard(session.lifeGame.getBoard()) };
  },
};

```
