---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-ops/src/packer/op-packers/pack-bump.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.835718+00:00
---

# core/cell-ops/src/packer/op-packers/pack-bump.ts

```ts
/**
 * BRC-74 BUMP cell construction.
 *
 * Validates the header (blockHeight + treeHeight) but treats the
 * rest as opaque. Splits across BUMP-tagged continuation cells if
 * the raw bytes exceed CONTINUATION_PAYLOAD_SIZE (1016).
 */

import { CONTINUATION_PAYLOAD_SIZE, CONTINUATION_TYPE } from '../constants';
import type { BumpHeader, ContinuationCell } from '../types';
import { decodeVarInt } from '../varint';

export function parseBumpHeader(raw: Buffer): BumpHeader {
  if (raw.length < 2) {
    throw new Error(`BUMP too short: ${raw.length} bytes (minimum 2)`);
  }
  const { value: blockHeight, bytesRead } = decodeVarInt(raw, 0);
  const treeHeight = raw.readUInt8(bytesRead);
  if (treeHeight > 64) {
    throw new Error(`BUMP treeHeight ${treeHeight} exceeds maximum (64)`);
  }
  return { blockHeight, treeHeight, dataOffset: bytesRead + 1 };
}

export function createBumpCells(bumpRaw: Buffer): ContinuationCell[] {
  parseBumpHeader(bumpRaw);
  const cells: ContinuationCell[] = [];
  let offset = 0;
  while (offset < bumpRaw.length) {
    const chunk = bumpRaw.subarray(offset, offset + CONTINUATION_PAYLOAD_SIZE);
    cells.push({ type: CONTINUATION_TYPE.BUMP, data: Buffer.from(chunk) });
    offset += CONTINUATION_PAYLOAD_SIZE;
  }
  return cells;
}

```
