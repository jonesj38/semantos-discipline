---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/betterment/brain/src/cell-types/intention.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.568383+00:00
---

# cartridges/betterment/brain/src/cell-types/intention.ts

```ts
/** `betterment.practice.intention` — AFFINE cell. A held intention. */

import { defineCellType, type CellTypeDef } from './cell-type.js';
import {
  assertNonEmptyString,
  assertNumber,
  assertOptionalIsoDateString,
} from './validators.js';

export interface BettermentIntention {
  readonly statement: string;
  readonly dimensions: string;  // dimension label(s), e.g. 'MENTAL'
  readonly elevation: number;
  readonly targetDate?: string; // ISO 8601
}

export const intentionCellType: CellTypeDef<BettermentIntention> = defineCellType({
  name: 'betterment.practice.intention',
  triple: { segment1: 'betterment', segment2: 'practice', segment3: 'intention', segment4: '' },
  linearity: 'AFFINE',
  validate(payload): asserts payload is BettermentIntention {
    if (typeof payload !== 'object' || payload === null) {
      throw new Error('betterment.practice.intention: payload must be an object');
    }
    const p = payload as Record<string, unknown>;
    assertNonEmptyString(p.statement, 'statement');
    assertNonEmptyString(p.dimensions, 'dimensions');
    assertNumber(p.elevation, 'elevation');
    assertOptionalIsoDateString(p.targetDate, 'targetDate');
  },
});

```
