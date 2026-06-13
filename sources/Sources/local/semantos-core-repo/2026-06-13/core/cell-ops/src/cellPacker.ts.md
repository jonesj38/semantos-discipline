---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-ops/src/cellPacker.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.825644+00:00
---

# core/cell-ops/src/cellPacker.ts

```ts
/**
 * @deprecated — use the split modules under
 * `core/cell-ops/src/packer/` instead.
 *
 * Prompt 41 split this 650-LOC file into focused modules:
 *
 *   - constants.ts            — CELL_SIZE / HEADER_SIZE / PAYLOAD_SIZE
 *                                / CONTINUATION_TYPE / CONTINUATION_*
 *   - types.ts                — wire types (ContinuationCell,
 *                                MultiCellObject, etc.)
 *   - varint.ts               — encodeVarInt, decodeVarInt,
 *                                sizeOfVarInt (zero project imports)
 *   - continuation-handlers.ts — buildContinuationHeader /
 *                                parseContinuationHeader
 *   - multicell-assembler.ts  — packMultiCell / unpackMultiCell
 *   - op-packers/pack-bump.ts  — BUMP cells + parseBumpHeader
 *   - op-packers/pack-beef.ts  — Atomic BEEF + parseAtomicBeefHeader
 *   - op-packers/pack-envelope.ts — state envelope cells
 *   - op-packers/pack-data.ts   — generic DATA cells
 *   - cell-packer.ts          — assembleSemanticObject /
 *                                disassembleSemanticObject (facade)
 *
 * Migration target imports:
 *
 *   import { assembleSemanticObject } from './packer';
 *   import { encodeVarInt } from './packer/varint';
 */

export {
  ATOMIC_BEEF_PREFIX,
  CELL_SIZE,
  CONTINUATION_HEADER_SIZE,
  CONTINUATION_PAYLOAD_SIZE,
  CONTINUATION_TYPE,
  HEADER_SIZE,
  PAYLOAD_SIZE,
} from './packer/index';

export type {
  AtomicBeefPayload,
  BumpHeader,
  ContinuationCell,
  ContinuationHeader,
  ContinuationType,
  MultiCellObject,
  PackedMultiCell,
} from './packer/index';

export {
  decodeVarInt,
  encodeVarInt,
  sizeOfVarInt,
  type DecodedVarInt,
} from './packer/index';

export {
  buildContinuationHeader,
  parseContinuationHeader,
  packMultiCell,
  unpackMultiCell,
  createAtomicBeefCells,
  parseAtomicBeefHeader,
  createBumpCells,
  parseBumpHeader,
  createDataCell,
  createDataCells,
  createEnvelopeCells,
  assembleSemanticObject,
  disassembleSemanticObject,
  type AssembleOptions,
  type DisassembledObject,
} from './packer/index';

```
