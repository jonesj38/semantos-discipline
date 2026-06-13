---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/commands/poker/bet.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.420453+00:00
---

# packages/games/src/cli/commands/poker/bet.ts

```ts
/** `semantos game poker bet --amount <chips>` — open a bet. */

import type { CommandSpec } from '../../command-registry';
import { runAmountAction } from './act-helpers';

export const pokerBet: CommandSpec = {
  game: 'poker',
  action: 'bet',
  summary: 'Open a bet on a no-action street.',
  args: [
    { name: 'amount', description: 'Bet size in chips.', required: true },
  ],
  handler(cmd) {
    const amount = Number(cmd.flags.amount ?? cmd.flags.expression ?? 0);
    return runAmountAction('bet', amount);
  },
};

```
