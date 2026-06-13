---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/commands/poker/raise.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.419566+00:00
---

# packages/games/src/cli/commands/poker/raise.ts

```ts
/** `semantos game poker raise --amount <chips>` — raise an existing bet. */

import type { CommandSpec } from '../../command-registry';
import { runAmountAction } from './act-helpers';

export const pokerRaise: CommandSpec = {
  game: 'poker',
  action: 'raise',
  summary: 'Raise the current bet.',
  args: [
    { name: 'amount', description: 'Total chips after the raise.', required: true },
  ],
  handler(cmd) {
    const amount = Number(cmd.flags.amount ?? cmd.flags.expression ?? 0);
    return runAmountAction('raise', amount);
  },
};

```
