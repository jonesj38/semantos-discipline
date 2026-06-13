---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/commands/poker/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.419861+00:00
---

# packages/games/src/cli/commands/poker/index.ts

```ts
/** Aggregate of all `poker` commands for batch registration. */

import type { CommandSpec } from '../../command-registry';
import { pokerNew } from './new';
import { pokerDeal } from './deal';
import { pokerFold } from './fold';
import { pokerCheck } from './check';
import { pokerCall } from './call';
import { pokerAllIn } from './all-in';
import { pokerBet } from './bet';
import { pokerRaise } from './raise';
import { pokerTable } from './table';
import { pokerHand } from './hand';
import { pokerStatus } from './status';

// Order matters — the unknown-action error message lists actions in
// registration order, so we keep the original switch-statement order:
// new, deal, fold, check, call, bet, raise, all-in, table, hand, status.
export const pokerCommands: readonly CommandSpec[] = [
  pokerNew,
  pokerDeal,
  pokerFold,
  pokerCheck,
  pokerCall,
  pokerBet,
  pokerRaise,
  pokerAllIn,
  pokerTable,
  pokerHand,
  pokerStatus,
];

```
