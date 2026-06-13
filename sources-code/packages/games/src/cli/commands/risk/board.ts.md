---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/commands/risk/board.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.429325+00:00
---

# packages/games/src/cli/commands/risk/board.ts

```ts
/** `semantos game risk board` — render the territory map. */

import { renderBoard as renderRiskBoard } from '../../../risk/renderer';
import type { CommandSpec } from '../../command-registry';
import { session } from '../../session';

export const riskBoard: CommandSpec = {
  game: 'risk',
  action: 'board',
  summary: 'Render the Risk territory map.',
  args: [],
  handler() {
    if (!session.riskGame) return { error: 'No active game. Run: semantos game risk new' };
    return { board: renderRiskBoard(session.riskGame.getBoard()) };
  },
};

```
