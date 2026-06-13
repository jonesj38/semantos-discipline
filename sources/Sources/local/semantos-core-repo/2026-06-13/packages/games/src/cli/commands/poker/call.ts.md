---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/commands/poker/call.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.420164+00:00
---

# packages/games/src/cli/commands/poker/call.ts

```ts
/** `semantos game poker call` — call the current bet. */

import type { CommandSpec } from '../../command-registry';
import { runSimpleAction } from './act-helpers';

export const pokerCall: CommandSpec = {
  game: 'poker',
  action: 'call',
  summary: 'Match the current outstanding bet.',
  args: [],
  handler: () => runSimpleAction('call'),
};

```
