---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/commands/risk/summary.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.429608+00:00
---

# packages/games/src/cli/commands/risk/summary.ts

```ts
/** `semantos game risk summary` — per-player territory + army summary. */

import { renderSummary } from '../../../risk/renderer';
import type { CommandSpec } from '../../command-registry';
import { session } from '../../session';

export const riskSummary: CommandSpec = {
  game: 'risk',
  action: 'summary',
  summary: 'Per-player territory + army summary.',
  args: [],
  handler() {
    if (!session.riskGame) return { error: 'No active game.' };
    return {
      summary: renderSummary(session.riskGame.getBoard(), session.riskGame.getPlayers().length),
    };
  },
};

```
