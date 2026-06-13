---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-ops/src/packer/op-packers/pack-beef.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.836559+00:00
---

# core/cell-ops/src/packer/op-packers/pack-beef.ts

```ts
/**
 * Atomic BEEF cell construction.
 *
 * Expected raw layout (BRC):
 *   [4 bytes: 0x01010101 prefix]
 *   [32 bytes: subject TXID]
 *   [N bytes: standard BEEF]
 */

import {
  ATOMIC_BEEF_PREFIX,
  CONTINUATION_PAYLOAD_SIZE,
  CONTINUATION_TYPE,
} from '../constants';
import type { ContinuationCell } from '../types';

export function parseAtomicBeefHeader(raw: Buffer): { subjectTxid: Buffer } {
  if (raw.length < 36) {
    throw new Error(`Atomic BEEF too short: ${raw.length} bytes (minimum 36)`);
  }
  if (!raw.subarray(0, 4).equals(ATOMIC_BEEF_PREFIX)) {
    throw new Error(
      `Invalid Atomic BEEF prefix: expected 01010101, got ${raw.subarray(0, 4).toString('hex')}`,
    );
  }
  return { subjectTxid: Buffer.from(raw.subarray(4, 36)) };
}

export function createAtomicBeefCells(atomicBeefRaw: Buffer): ContinuationCell[] {
  parseAtomicBeefHeader(atomicBeefRaw);
  const cells: ContinuationCell[] = [];
  let offset = 0;
  while (offset < atomicBeefRaw.length) {
    const chunk = atomicBeefRaw.subarray(offset, offset + CONTINUATION_PAYLOAD_SIZE);
    cells.push({
      type: CONTINUATION_TYPE.ATOMIC_BEEF,
      data: Buffer.from(chunk),
    });
    offset += CONTINUATION_PAYLOAD_SIZE;
  }
  return cells;
}

```
