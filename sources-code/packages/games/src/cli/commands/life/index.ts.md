---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/commands/life/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.427820+00:00
---

# packages/games/src/cli/commands/life/index.ts

```ts
/** Aggregate of all `life` commands for batch registration. */

import type { CommandSpec } from '../../command-registry';
import { lifeNew } from './new';
import { lifeStep } from './step';
import { lifeBoard } from './board';
import { lifeStatus } from './status';

export const lifeCommands: readonly CommandSpec[] = [
  lifeNew,
  lifeStep,
  lifeBoard,
  lifeStatus,
];

```
