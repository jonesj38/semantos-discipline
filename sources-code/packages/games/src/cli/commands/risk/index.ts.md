---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/commands/risk/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.429029+00:00
---

# packages/games/src/cli/commands/risk/index.ts

```ts
/** Aggregate of all `risk` commands for batch registration. */

import type { CommandSpec } from '../../command-registry';
import { riskNew } from './new';
import { riskBoard } from './board';
import { riskSummary } from './summary';
import { riskReinforce } from './reinforce';
import { riskAttack } from './attack';
import { riskEndAttack } from './endattack';
import { riskFortify } from './fortify';
import { riskEndFortify } from './endfortify';
import { riskStatus } from './status';

export const riskCommands: readonly CommandSpec[] = [
  riskNew,
  riskBoard,
  riskSummary,
  riskReinforce,
  riskAttack,
  riskEndAttack,
  riskFortify,
  riskEndFortify,
  riskStatus,
];

```
