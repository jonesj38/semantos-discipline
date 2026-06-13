---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/betterment/brain/src/cell-types/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.567508+00:00
---

# cartridges/betterment/brain/src/cell-types/index.ts

```ts
/**
 * Betterment cell-type registry — barrel re-export of the 8 practice cell
 * validators.  Per SQ3 (T7 design), only practice cells carry TS-side
 * validators; the derived/computed cells (paskian.*, story.*,
 * accountability.*, state.*) are emitted by the in-app or kernel layers
 * with their own structural guarantees.
 *
 * Add a cell-type-by-typeHashHex map for runtime dispatch (mirrors
 * oddjobz's `cellTypeByHashHex` pattern — the brain receives a cell,
 * reads typeHash from the header at offset 30, looks up the def).
 */

import type { CellTypeDef } from './cell-type.js';
import { releaseCellType, type BettermentRelease } from './release.js';
import { sessionCellType, type BettermentSession } from './session.js';
import { intentionCellType, type BettermentIntention } from './intention.js';
import { insightCellType, type BettermentInsight } from './insight.js';
import { patternCellType, type BettermentPattern } from './pattern.js';
import { connectionCellType, type BettermentConnection } from './connection.js';
import { vacuumCellType, type BettermentVacuum } from './vacuum.js';
import { sealCellType, type BettermentSeal } from './seal.js';

export { defineCellType, type CellTypeDef, type CellTypeTriple, type ManifestLinearity } from './cell-type.js';

export {
  releaseCellType, type BettermentRelease, RELEASE_SOURCES, RELEASE_PROMPTS,
} from './release.js';
export { sessionCellType, type BettermentSession } from './session.js';
export { intentionCellType, type BettermentIntention } from './intention.js';
export {
  insightCellType, type BettermentInsight, INSIGHT_SOURCES, CONNECTION_TARGETS,
  type InsightSource, type ConnectionTarget,
} from './insight.js';
export {
  patternCellType, type BettermentPattern, PATTERN_CATEGORIES, PATTERN_POLARITIES,
} from './pattern.js';
export { connectionCellType, type BettermentConnection } from './connection.js';
export { vacuumCellType, type BettermentVacuum } from './vacuum.js';
export {
  sealCellType, type BettermentSeal, SEAL_VISUALIZATIONS, type SealVisualization,
} from './seal.js';

export type AnyBettermentPracticeCellTypeDef =
  | CellTypeDef<BettermentRelease>
  | CellTypeDef<BettermentSession>
  | CellTypeDef<BettermentIntention>
  | CellTypeDef<BettermentInsight>
  | CellTypeDef<BettermentPattern>
  | CellTypeDef<BettermentConnection>
  | CellTypeDef<BettermentVacuum>
  | CellTypeDef<BettermentSeal>;

/** All 8 practice cell types, in declaration order. */
export const BETTERMENT_PRACTICE_CELL_TYPES: readonly AnyBettermentPracticeCellTypeDef[] = Object.freeze([
  releaseCellType,
  sessionCellType,
  intentionCellType,
  insightCellType,
  patternCellType,
  connectionCellType,
  vacuumCellType,
  sealCellType,
]);

/** Runtime dispatch map: typeHashHex → cell type definition. */
export const bettermentCellTypeByHashHex: Readonly<Record<string, AnyBettermentPracticeCellTypeDef>> =
  Object.freeze(
    Object.fromEntries(
      BETTERMENT_PRACTICE_CELL_TYPES.map((t) => [t.typeHashHex, t]),
    ),
  );

```
