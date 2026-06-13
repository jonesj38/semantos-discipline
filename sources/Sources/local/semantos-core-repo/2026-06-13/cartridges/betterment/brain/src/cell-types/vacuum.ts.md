---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/betterment/brain/src/cell-types/vacuum.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.568099+00:00
---

# cartridges/betterment/brain/src/cell-types/vacuum.ts

```ts
/** `betterment.practice.vacuum` — LINEAR cell. QSE vacuum-cleaner release+integrate cycle. */

import { defineCellType, type CellTypeDef } from './cell-type.js';
import { assertNonEmptyString, assertNumber } from './validators.js';

export interface BettermentVacuum {
  readonly releaseIntentions: string;
  readonly integrateIntentions: string;
  readonly elevation: number;
}

export const vacuumCellType: CellTypeDef<BettermentVacuum> = defineCellType({
  name: 'betterment.practice.vacuum',
  triple: { segment1: 'betterment', segment2: 'practice', segment3: 'vacuum', segment4: '' },
  linearity: 'LINEAR',
  validate(payload): asserts payload is BettermentVacuum {
    if (typeof payload !== 'object' || payload === null) {
      throw new Error('betterment.practice.vacuum: payload must be an object');
    }
    const p = payload as Record<string, unknown>;
    assertNonEmptyString(p.releaseIntentions, 'releaseIntentions');
    assertNonEmptyString(p.integrateIntentions, 'integrateIntentions');
    assertNumber(p.elevation, 'elevation');
  },
});

```
