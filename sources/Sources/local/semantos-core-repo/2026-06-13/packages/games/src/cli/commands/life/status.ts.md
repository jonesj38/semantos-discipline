---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/commands/life/status.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.428401+00:00
---

# packages/games/src/cli/commands/life/status.ts

```ts
/** `semantos game life status` — generation/population summary. */

import type { CommandSpec } from '../../command-registry';
import { session } from '../../session';

export const lifeStatus: CommandSpec = {
  game: 'life',
  action: 'status',
  summary: 'Report generation, population, stability, and history length.',
  args: [],
  handler() {
    if (!session.lifeGame) return { error: 'No active game.' };
    return {
      generation: session.lifeGame.generation(),
      population: session.lifeGame.population(),
      stable: session.lifeGame.isStable(),
      historyLength: session.lifeGame.history().length,
    };
  },
};

```
