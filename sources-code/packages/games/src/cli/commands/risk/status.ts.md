---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/commands/risk/status.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.430184+00:00
---

# packages/games/src/cli/commands/risk/status.ts

```ts
/** `semantos game risk status` — phase + summary report. */

import { renderSummary } from '../../../risk/renderer';
import type { CommandSpec } from '../../command-registry';
import { session } from '../../session';

export const riskStatus: CommandSpec = {
  game: 'risk',
  action: 'status',
  summary: 'Report status, phase, current player, and territory summary.',
  args: [],
  handler() {
    if (!session.riskGame) return { error: 'No active game.' };
    return {
      status: session.riskGame.status(),
      phase: session.riskGame.currentPhase(),
      currentPlayer: session.riskGame.currentPlayerId() + 1,
      reinforcements: session.riskGame.getReinforcements(),
      summary: renderSummary(session.riskGame.getBoard(), session.riskGame.getPlayers().length),
    };
  },
};

```
