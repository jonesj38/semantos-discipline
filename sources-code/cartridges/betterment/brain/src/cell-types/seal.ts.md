---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/betterment/brain/src/cell-types/seal.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.566926+00:00
---

# cartridges/betterment/brain/src/cell-types/seal.ts

```ts
/** `betterment.practice.seal` — LINEAR cell. Gold-seal integration. */

import { defineCellType, type CellTypeDef } from './cell-type.js';
import {
  assertEnum,
  assertNonEmptyString,
  assertNumber,
  assertOptionalString,
} from './validators.js';

export const SEAL_VISUALIZATIONS = ['light', 'powder', 'ointment', 'block', 'molten', 'custom'] as const;
export type SealVisualization = (typeof SEAL_VISUALIZATIONS)[number];

export interface BettermentSeal {
  readonly sealVisualization: SealVisualization;
  readonly sealedReleaseIds: string;
  readonly sealedVacuumId?: string;
  readonly elevation: number;
}

export const sealCellType: CellTypeDef<BettermentSeal> = defineCellType({
  name: 'betterment.practice.seal',
  triple: { segment1: 'betterment', segment2: 'practice', segment3: 'seal', segment4: '' },
  linearity: 'LINEAR',
  validate(payload): asserts payload is BettermentSeal {
    if (typeof payload !== 'object' || payload === null) {
      throw new Error('betterment.practice.seal: payload must be an object');
    }
    const p = payload as Record<string, unknown>;
    assertEnum(p.sealVisualization, 'sealVisualization', SEAL_VISUALIZATIONS);
    assertNonEmptyString(p.sealedReleaseIds, 'sealedReleaseIds');
    assertOptionalString(p.sealedVacuumId, 'sealedVacuumId');
    assertNumber(p.elevation, 'elevation');
  },
});

```
