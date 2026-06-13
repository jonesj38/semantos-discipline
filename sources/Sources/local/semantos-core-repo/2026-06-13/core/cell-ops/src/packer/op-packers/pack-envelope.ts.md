---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-ops/src/packer/op-packers/pack-envelope.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.836284+00:00
---

# core/cell-ops/src/packer/op-packers/pack-envelope.ts

```ts
/**
 * State merkle envelope cell construction. Custom format (NOT
 * BRC-62/95) — maps semantic state hashes to a merkle root
 * inscribed in the anchor transaction. We chunk the serialised
 * envelope across ENVELOPE-tagged continuation cells.
 */

import type { MerkleEnvelope } from '../../merkleEnvelope';
import { serializeMerkleEnvelope } from '../../merkleEnvelope';

import { CONTINUATION_PAYLOAD_SIZE, CONTINUATION_TYPE } from '../constants';
import type { ContinuationCell } from '../types';

export function createEnvelopeCells(envelope: MerkleEnvelope): ContinuationCell[] {
  const serialized = serializeMerkleEnvelope(envelope);
  const cells: ContinuationCell[] = [];
  let offset = 0;
  while (offset < serialized.length) {
    const chunk = serialized.subarray(offset, offset + CONTINUATION_PAYLOAD_SIZE);
    cells.push({
      type: CONTINUATION_TYPE.ENVELOPE,
      data: Buffer.from(chunk),
    });
    offset += CONTINUATION_PAYLOAD_SIZE;
  }
  return cells;
}

```
