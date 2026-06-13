---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/betterment/brain/src/cell-types/session.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.568954+00:00
---

# cartridges/betterment/brain/src/cell-types/session.ts

```ts
/** `betterment.practice.session` — LINEAR cell. A practice session. */

import { defineCellType, type CellTypeDef } from './cell-type.js';
import { assertIsoDateString, assertNumber, assertOptionalString } from './validators.js';

export interface BettermentSession {
  readonly date: string;        // ISO 8601
  readonly elevation: number;
  readonly reflection?: string;
}

export const sessionCellType: CellTypeDef<BettermentSession> = defineCellType({
  name: 'betterment.practice.session',
  triple: { segment1: 'betterment', segment2: 'practice', segment3: 'session', segment4: '' },
  linearity: 'LINEAR',
  validate(payload): asserts payload is BettermentSession {
    if (typeof payload !== 'object' || payload === null) {
      throw new Error('betterment.practice.session: payload must be an object');
    }
    const p = payload as Record<string, unknown>;
    assertIsoDateString(p.date, 'date');
    assertNumber(p.elevation, 'elevation');
    assertOptionalString(p.reflection, 'reflection');
  },
});

```
