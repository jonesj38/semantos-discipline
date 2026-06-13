---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-ops/src/packer/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.829496+00:00
---

# core/cell-ops/src/packer/index.ts

```ts
/**
 * core/cell-ops packer — public surface for the prompt-41 split.
 */

export {
  ATOMIC_BEEF_PREFIX,
  CELL_SIZE,
  CONTINUATION_HEADER_SIZE,
  CONTINUATION_PAYLOAD_SIZE,
  CONTINUATION_TYPE,
  HEADER_SIZE,
  PAYLOAD_SIZE,
} from './constants';

export type {
  AtomicBeefPayload,
  BumpHeader,
  ContinuationCell,
  ContinuationHeader,
  ContinuationType,
  MultiCellObject,
  PackedMultiCell,
} from './types';

export {
  decodeVarInt,
  encodeVarInt,
  sizeOfVarInt,
  type DecodedVarInt,
} from './varint';

export {
  buildContinuationHeader,
  parseContinuationHeader,
} from './continuation-handlers';

export {
  packMultiCell,
  unpackMultiCell,
  packEscalated,
  unpackEscalated,
  isEscalated,
  ESCALATION_CELL_COUNT_SENTINEL,
  OCTAVE0_FLAT_CAPACITY,
  OCTAVE1_CELL_SIZE,
  MAX_CONTINUATIONS,
  type EscalatedObject,
} from './multicell-assembler';

export {
  createAtomicBeefCells,
  parseAtomicBeefHeader,
} from './op-packers/pack-beef';
export {
  createBumpCells,
  parseBumpHeader,
} from './op-packers/pack-bump';
export {
  createDataCell,
  createDataCells,
} from './op-packers/pack-data';
export { createEnvelopeCells } from './op-packers/pack-envelope';

export {
  assembleSemanticObject,
  disassembleSemanticObject,
  type AssembleOptions,
  type DisassembledObject,
} from './cell-packer';

// ── Rung-2: cell merkle (D-OCT-merkle-hierarchy) ──────────────────────────────
// ── + path-merkle verifier generalization (D-OCT-path-merkle-unify) ───────────
export {
  sha256 as cellMerkleSha256,
  computeCellMerkleRoot,
  computeLeafHashes,
  computeMerkleRootFromHashes,
  generateInclusionProof,      // NEW: leaf-size-agnostic (routing segments etc.)
  generateCellInclusionProof,  // data side: 1024-byte cell leaves
  verifyInclusion,             // NEW: the unified leaf-size-agnostic verifier
  verifyCellInclusion,         // data side: delegates to verifyInclusion
  writeDomainPayloadRoot,
  readDomainPayloadRoot,
  packMerkleHierarchy,
  unpackMerkleHierarchy,
  isMerkleHierarchy,
  DOMAIN_PAYLOAD_ROOT_OFFSET,
  DOMAIN_PAYLOAD_ROOT_SIZE,
  type CellMerkleSibling,
  type CellMerkleProof,
  type MerkleHierarchyPacked,
  type MerkleHierarchyDescriptor,
} from './cell-merkle';

```
