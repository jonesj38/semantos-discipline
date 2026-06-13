---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/commands/risk/fortify.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.431029+00:00
---

# packages/games/src/cli/commands/risk/fortify.ts

```ts
/** `semantos game risk fortify --from <i> --to <i> --armies <n>` — move armies. */

import { TERRITORIES } from '../../../risk/map';
import type { CommandSpec } from '../../command-registry';
import { session } from '../../session';

export const riskFortify: CommandSpec = {
  game: 'risk',
  action: 'fortify',
  summary: 'Move armies between two of your connected territories.',
  args: [
    { name: 'from', description: 'Source territory index.', required: true },
    { name: 'to', description: 'Destination territory index.', required: true },
    { name: 'armies', description: 'Armies to move (default 1).' },
  ],
  handler(cmd) {
    if (!session.riskGame) return { error: 'No active game.' };
    const from = Number(cmd.flags.from ?? -1);
    const to = Number(cmd.flags.to ?? -1);
    const armies = Number(cmd.flags.armies ?? 1);
    try {
      session.riskGame.fortify(from, to, armies);
      return {
        moved: `${armies} armies from ${TERRITORIES[from].name} to ${TERRITORIES[to].name}`,
        phase: session.riskGame.currentPhase(),
        currentPlayer: session.riskGame.currentPlayerId() + 1,
      };
    } catch (e) {
      return { error: e instanceof Error ? e.message : String(e) };
    }
  },
};

```
