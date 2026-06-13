---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/commands/risk/new.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.430467+00:00
---

# packages/games/src/cli/commands/risk/new.ts

```ts
/** `semantos game risk new --players <n>` — start a Risk match. */

import { RiskEngine } from '../../../risk/engine';
import { renderSummary } from '../../../risk/renderer';
import type { CommandSpec } from '../../command-registry';
import { session } from '../../session';

export const riskNew: CommandSpec = {
  game: 'risk',
  action: 'new',
  summary: 'Start a new Risk match.',
  args: [
    { name: 'players', description: 'Number of players (default 3).' },
  ],
  async handler(cmd) {
    const players = Number(cmd.flags.players ?? 3);
    session.riskGame = await RiskEngine.create(players);
    return {
      status: 'created',
      players,
      summary: renderSummary(session.riskGame.getBoard(), players),
      reinforcements: session.riskGame.getReinforcements(),
    };
  },
};

```
