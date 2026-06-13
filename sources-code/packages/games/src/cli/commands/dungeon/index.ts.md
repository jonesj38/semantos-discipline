---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/commands/dungeon/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.423999+00:00
---

# packages/games/src/cli/commands/dungeon/index.ts

```ts
/** Aggregate of all `dungeon` commands for batch registration. */

import type { CommandSpec } from '../../command-registry';
import { dungeonNew } from './new';
import { dungeonMove } from './move';
import { dungeonAttack } from './attack';
import { dungeonTake } from './take';
import { dungeonUse } from './use';
import { dungeonOpen } from './open';
import { dungeonDescend } from './descend';
import { dungeonInventory } from './inventory';
import { dungeonLook } from './look';
import { dungeonMap } from './map';
import { dungeonStatus } from './status';
import { dungeonHistory } from './history';

export const dungeonCommands: readonly CommandSpec[] = [
  dungeonNew,
  dungeonMove,
  dungeonAttack,
  dungeonTake,
  dungeonUse,
  dungeonOpen,
  dungeonDescend,
  dungeonInventory,
  dungeonLook,
  dungeonMap,
  dungeonStatus,
  dungeonHistory,
];

```
