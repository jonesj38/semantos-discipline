---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/commands/life/new.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.428690+00:00
---

# packages/games/src/cli/commands/life/new.ts

```ts
/** `semantos game life new` — create a Life board, optionally seeded. */

import { GameOfLifeEngine } from '../../../life/engine';
import { renderBoard as renderLifeBoard } from '../../../life/renderer';
import { PATTERNS, type PatternName } from '../../../life/types';
import type { CommandSpec } from '../../command-registry';
import { session } from '../../session';

export const lifeNew: CommandSpec = {
  game: 'life',
  action: 'new',
  summary: 'Create a Game-of-Life board, optionally seeded.',
  args: [
    { name: 'width', description: 'Board width (default 20).' },
    { name: 'height', description: 'Board height (default 20).' },
    { name: 'pattern', description: 'Named seed pattern (e.g. glider).' },
    { name: 'density', description: 'Random-fill density 0..1 if no pattern.' },
  ],
  async handler(cmd) {
    const width = Number(cmd.flags.width ?? 20);
    const height = Number(cmd.flags.height ?? 20);
    const pattern = cmd.flags.pattern as PatternName | undefined;
    const density = cmd.flags.density !== undefined ? Number(cmd.flags.density) : undefined;

    session.lifeGame = await GameOfLifeEngine.create(width, height);

    if (pattern && pattern in PATTERNS) {
      const centerR = Math.floor(height / 2);
      const centerC = Math.floor(width / 2);
      session.lifeGame.seed(pattern, centerR, centerC);
    } else if (density !== undefined) {
      session.lifeGame.seedRandom(density);
    }

    return {
      status: 'created',
      board: renderLifeBoard(session.lifeGame.getBoard()),
      patterns: Object.keys(PATTERNS),
    };
  },
};

```
