---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/commands/risk/endfortify.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.431608+00:00
---

# packages/games/src/cli/commands/risk/endfortify.ts

```ts
/** `semantos game risk endfortify` — end the turn. */

import type { CommandSpec } from '../../command-registry';
import { session } from '../../session';

export const riskEndFortify: CommandSpec = {
  game: 'risk',
  action: 'endfortify',
  summary: 'End the fortify phase and advance to the next player.',
  args: [],
  handler() {
    if (!session.riskGame) return { error: 'No active game.' };
    try {
      session.riskGame.endFortify();
      return {
        phase: session.riskGame.currentPhase(),
        currentPlayer: session.riskGame.currentPlayerId() + 1,
        reinforcements: session.riskGame.getReinforcements(),
      };
    } catch (e) {
      return { error: e instanceof Error ? e.message : String(e) };
    }
  },
};

```
