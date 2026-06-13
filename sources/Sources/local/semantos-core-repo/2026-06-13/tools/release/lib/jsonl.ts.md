---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/release/lib/jsonl.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.560273+00:00
---

# tools/release/lib/jsonl.ts

```ts
/**
 * JSONL helpers — re-exported from @semantos/cell-relay so the release
 * pipeline and the cell-relay-beam runtime stay agreed on the
 * append-only persistence shape.
 *
 * Plus one release-specific helper: `lastReleaseCell` filters by the
 * release op (the cell-relay package keeps its `lastCellOfOp` op-agnostic).
 */

import { RELEASE_OP, type SerializedCell } from './types';

export {
  jsonlPathFor,
  loadAllCells,
  appendCell,
  walkChain,
  indexByHash,
} from '../../../packages/cell-relay/src';

import { lastCellOfOp } from '../../../packages/cell-relay/src';

export function lastReleaseCell(cells: SerializedCell[]): SerializedCell | null {
  return lastCellOfOp(cells, RELEASE_OP);
}

```
