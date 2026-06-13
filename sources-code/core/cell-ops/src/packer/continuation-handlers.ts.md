---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-ops/src/packer/continuation-handlers.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.831196+00:00
---

# core/cell-ops/src/packer/continuation-handlers.ts

```ts
/**
 * Build / parse the 8-byte continuation cell header.
 *
 * Layout (LE):
 *   [0]    cellType        u8
 *   [1..3) cellIndex       u16  (1-based)
 *   [3..5) totalCells      u16  (excludes Cell 0)
 *   [5..7) payloadSize     u16  (≤ CONTINUATION_PAYLOAD_SIZE)
 *   [7]    reserved        u8
 *
 * Pure functions — no IO, no project imports beyond constants/types.
 */

import { CONTINUATION_HEADER_SIZE } from './constants';
import type { ContinuationHeader, ContinuationType } from './types';

export function buildContinuationHeader(h: ContinuationHeader): Buffer {
  const buf = Buffer.alloc(CONTINUATION_HEADER_SIZE, 0);
  buf.writeUInt8(h.cellType, 0);
  buf.writeUInt16LE(h.cellIndex, 1);
  buf.writeUInt16LE(h.totalCells, 3);
  buf.writeUInt16LE(h.payloadSize, 5);
  buf.writeUInt8(h.reserved, 7);
  return buf;
}

export function parseContinuationHeader(cell: Buffer): ContinuationHeader {
  if (cell.length < CONTINUATION_HEADER_SIZE) {
    throw new Error(
      `continuation header needs ${CONTINUATION_HEADER_SIZE} bytes; got ${cell.length}`,
    );
  }
  return {
    cellType: cell.readUInt8(0) as ContinuationType,
    cellIndex: cell.readUInt16LE(1),
    totalCells: cell.readUInt16LE(3),
    payloadSize: cell.readUInt16LE(5),
    reserved: cell.readUInt8(7),
  };
}

```
