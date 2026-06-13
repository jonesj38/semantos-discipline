---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/commands/poker/all-in.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.421887+00:00
---

# packages/games/src/cli/commands/poker/all-in.ts

```ts
/** `semantos game poker all-in` — push all chips. */

import type { CommandSpec } from '../../command-registry';
import { runSimpleAction } from './act-helpers';

export const pokerAllIn: CommandSpec = {
  game: 'poker',
  action: 'all-in',
  summary: 'Push every remaining chip.',
  args: [],
  handler: () => runSimpleAction('all-in'),
};

```
