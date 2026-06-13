---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/commands/risk/reinforce.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.429891+00:00
---

# packages/games/src/cli/commands/risk/reinforce.ts

```ts
/** `semantos game risk reinforce --territory <i> --armies <n>` — place armies. */

import { TERRITORIES } from '../../../risk/map';
import type { CommandSpec } from '../../command-registry';
import { session } from '../../session';

export const riskReinforce: CommandSpec = {
  game: 'risk',
  action: 'reinforce',
  summary: 'Place armies on a territory you own.',
  args: [
    { name: 'territory', description: 'Territory index.', required: true },
    { name: 'armies', description: 'Armies to place (default 1).' },
  ],
  handler(cmd) {
    if (!session.riskGame) return { error: 'No active game.' };
    const territory = Number(cmd.flags.territory ?? cmd.flags.expression ?? -1);
    const armies = Number(cmd.flags.armies ?? 1);
    try {
      const result = session.riskGame.reinforce(territory, armies);
      return {
        placed: `${armies} armies on ${TERRITORIES[territory].name}`,
        remaining: result.armiesRemaining,
        phase: session.riskGame.currentPhase(),
      };
    } catch (e) {
      return { error: e instanceof Error ? e.message : String(e) };
    }
  },
};

```
