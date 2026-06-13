---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-ops/src/packer/op-packers/pack-data.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.835999+00:00
---

# core/cell-ops/src/packer/op-packers/pack-data.ts

```ts
/**
 * Generic DATA continuation cell construction.
 *
 * `createDataCell(buf)` returns a single cell when the data fits;
 * throws otherwise. `createDataCells(buf)` always splits.
 */

import { CONTINUATION_PAYLOAD_SIZE, CONTINUATION_TYPE } from '../constants';
import type { ContinuationCell } from '../types';

export function createDataCell(data: Buffer): ContinuationCell {
  if (data.length > CONTINUATION_PAYLOAD_SIZE) {
    throw new Error(
      `Data too large for single cell: ${data.length} bytes (max ${CONTINUATION_PAYLOAD_SIZE})`,
    );
  }
  return {
    type: CONTINUATION_TYPE.DATA,
    data: Buffer.from(data),
  };
}

export function createDataCells(data: Buffer): ContinuationCell[] {
  const cells: ContinuationCell[] = [];
  let offset = 0;
  while (offset < data.length) {
    const chunk = data.subarray(offset, offset + CONTINUATION_PAYLOAD_SIZE);
    cells.push({
      type: CONTINUATION_TYPE.DATA,
      data: Buffer.from(chunk),
    });
    offset += CONTINUATION_PAYLOAD_SIZE;
  }
  return cells;
}

```
