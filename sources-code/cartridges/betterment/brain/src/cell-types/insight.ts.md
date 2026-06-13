---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/betterment/brain/src/cell-types/insight.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.569536+00:00
---

# cartridges/betterment/brain/src/cell-types/insight.ts

```ts
/** `betterment.practice.insight` — RELEVANT cell. A retained insight. */

import { defineCellType, type CellTypeDef } from './cell-type.js';
import {
  assertEnum,
  assertNonEmptyString,
  assertNumber,
  assertOptionalEnum,
  assertOptionalNumber,
  assertOptionalString,
} from './validators.js';

export const INSIGHT_SOURCES = ['practice', 'connection', 'pattern', 'external', 'spontaneous'] as const;
export type InsightSource = (typeof INSIGHT_SOURCES)[number];

export const CONNECTION_TARGETS = [
  'highest-expression',
  'inner-child',
  'future-self',
  'ancestors',
  'highest-good',
  'custom',
] as const;
export type ConnectionTarget = (typeof CONNECTION_TARGETS)[number];

export interface BettermentInsight {
  readonly content: string;
  readonly source: InsightSource;
  readonly connectionTarget?: ConnectionTarget;
  readonly dimensions: string;
  readonly elevation: number;
  readonly significance?: number;
  readonly tags?: string;
}

export const insightCellType: CellTypeDef<BettermentInsight> = defineCellType({
  name: 'betterment.practice.insight',
  triple: { segment1: 'betterment', segment2: 'practice', segment3: 'insight', segment4: '' },
  linearity: 'RELEVANT',
  validate(payload): asserts payload is BettermentInsight {
    if (typeof payload !== 'object' || payload === null) {
      throw new Error('betterment.practice.insight: payload must be an object');
    }
    const p = payload as Record<string, unknown>;
    assertNonEmptyString(p.content, 'content');
    assertEnum(p.source, 'source', INSIGHT_SOURCES);
    assertOptionalEnum(p.connectionTarget, 'connectionTarget', CONNECTION_TARGETS);
    assertNonEmptyString(p.dimensions, 'dimensions');
    assertNumber(p.elevation, 'elevation');
    assertOptionalNumber(p.significance, 'significance');
    assertOptionalString(p.tags, 'tags');
  },
});

```
