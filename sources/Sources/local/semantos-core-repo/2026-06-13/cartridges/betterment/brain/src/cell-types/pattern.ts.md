---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/betterment/brain/src/cell-types/pattern.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.567793+00:00
---

# cartridges/betterment/brain/src/cell-types/pattern.ts

```ts
/** `betterment.practice.pattern` — RELEVANT cell. A recurring pattern. */

import { defineCellType, type CellTypeDef } from './cell-type.js';
import {
  assertEnum,
  assertNonEmptyString,
  assertNumber,
  assertOptionalNumber,
} from './validators.js';

export const PATTERN_CATEGORIES = ['emotional', 'behavioral', 'relational', 'somatic', 'cognitive'] as const;
export type PatternCategory = (typeof PATTERN_CATEGORIES)[number];

export const PATTERN_POLARITIES = ['supportive', 'limiting', 'neutral'] as const;
export type PatternPolarity = (typeof PATTERN_POLARITIES)[number];

export interface BettermentPattern {
  readonly description: string;
  readonly category: PatternCategory;
  readonly polarity: PatternPolarity;
  readonly dimensions: string;
  readonly occurrenceCount?: number;
  readonly strength?: number;
}

export const patternCellType: CellTypeDef<BettermentPattern> = defineCellType({
  name: 'betterment.practice.pattern',
  triple: { segment1: 'betterment', segment2: 'practice', segment3: 'pattern', segment4: '' },
  linearity: 'RELEVANT',
  validate(payload): asserts payload is BettermentPattern {
    if (typeof payload !== 'object' || payload === null) {
      throw new Error('betterment.practice.pattern: payload must be an object');
    }
    const p = payload as Record<string, unknown>;
    assertNonEmptyString(p.description, 'description');
    assertEnum(p.category, 'category', PATTERN_CATEGORIES);
    assertEnum(p.polarity, 'polarity', PATTERN_POLARITIES);
    assertNonEmptyString(p.dimensions, 'dimensions');
    assertOptionalNumber(p.occurrenceCount, 'occurrenceCount');
    assertOptionalNumber(p.strength, 'strength');
  },
});

```
