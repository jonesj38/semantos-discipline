---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/betterment/brain/src/cell-types/connection.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.568669+00:00
---

# cartridges/betterment/brain/src/cell-types/connection.ts

```ts
/** `betterment.practice.connection` — LINEAR cell. External-intelligence intake. */

import { defineCellType, type CellTypeDef } from './cell-type.js';
import {
  assertEnum,
  assertNonEmptyString,
  assertNumber,
  assertOptionalString,
} from './validators.js';
import { CONNECTION_TARGETS, type ConnectionTarget } from './insight.js';

export interface BettermentConnection {
  readonly target: ConnectionTarget;
  readonly customTarget?: string;
  readonly question: string;
  readonly receivedIntelligence: string;
  readonly elevation: number;
}

export const connectionCellType: CellTypeDef<BettermentConnection> = defineCellType({
  name: 'betterment.practice.connection',
  triple: { segment1: 'betterment', segment2: 'practice', segment3: 'connection', segment4: '' },
  linearity: 'LINEAR',
  validate(payload): asserts payload is BettermentConnection {
    if (typeof payload !== 'object' || payload === null) {
      throw new Error('betterment.practice.connection: payload must be an object');
    }
    const p = payload as Record<string, unknown>;
    assertEnum(p.target, 'target', CONNECTION_TARGETS);
    assertOptionalString(p.customTarget, 'customTarget');
    assertNonEmptyString(p.question, 'question');
    assertNonEmptyString(p.receivedIntelligence, 'receivedIntelligence');
    assertNumber(p.elevation, 'elevation');
  },
});

```
