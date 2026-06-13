---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/commands/life/step.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.427530+00:00
---

# packages/games/src/cli/commands/life/step.ts

```ts
/** `semantos game life step --count <n>` — advance N generations. */

import { renderBoard as renderLifeBoard } from '../../../life/renderer';
import type { CommandSpec } from '../../command-registry';
import { session } from '../../session';

export const lifeStep: CommandSpec = {
  game: 'life',
  action: 'step',
  summary: 'Advance Game-of-Life by N generations.',
  args: [
    { name: 'count', description: 'Number of generations to step (default 1).' },
  ],
  handler(cmd) {
    if (!session.lifeGame) return { error: 'No active game. Run: semantos game life new' };
    const count = Number(cmd.flags.count ?? cmd.flags.expression ?? 1);
    const results = session.lifeGame.run(count);
    const last = results[results.length - 1];
    return {
      board: renderLifeBoard(session.lifeGame.getBoard()),
      steps: results.length,
      born: last?.born ?? 0,
      died: last?.died ?? 0,
      population: session.lifeGame.population(),
      generation: session.lifeGame.generation(),
      stable: session.lifeGame.isStable(),
    };
  },
};

```
