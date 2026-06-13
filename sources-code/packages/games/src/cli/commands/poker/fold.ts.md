---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/commands/poker/fold.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.423083+00:00
---

# packages/games/src/cli/commands/poker/fold.ts

```ts
/** `semantos game poker fold` — fold the current hand. */

import type { CommandSpec } from '../../command-registry';
import { runSimpleAction } from './act-helpers';

export const pokerFold: CommandSpec = {
  game: 'poker',
  action: 'fold',
  summary: 'Fold the current hand.',
  args: [],
  handler: () => runSimpleAction('fold'),
};

```
