---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/commands/poker/check.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.421322+00:00
---

# packages/games/src/cli/commands/poker/check.ts

```ts
/** `semantos game poker check` — check (no bet to call). */

import type { CommandSpec } from '../../command-registry';
import { runSimpleAction } from './act-helpers';

export const pokerCheck: CommandSpec = {
  game: 'poker',
  action: 'check',
  summary: 'Check when there is no bet to call.',
  args: [],
  handler: () => runSimpleAction('check'),
};

```
