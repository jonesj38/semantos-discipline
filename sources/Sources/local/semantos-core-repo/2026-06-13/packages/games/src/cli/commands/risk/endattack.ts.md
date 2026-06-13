---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/commands/risk/endattack.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.430746+00:00
---

# packages/games/src/cli/commands/risk/endattack.ts

```ts
/** `semantos game risk endattack` — finish attack phase. */

import type { CommandSpec } from '../../command-registry';
import { session } from '../../session';

export const riskEndAttack: CommandSpec = {
  game: 'risk',
  action: 'endattack',
  summary: 'End the attack phase, advancing to fortify.',
  args: [],
  handler() {
    if (!session.riskGame) return { error: 'No active game.' };
    try {
      session.riskGame.endAttack();
      return { phase: session.riskGame.currentPhase() };
    } catch (e) {
      return { error: e instanceof Error ? e.message : String(e) };
    }
  },
};

```
