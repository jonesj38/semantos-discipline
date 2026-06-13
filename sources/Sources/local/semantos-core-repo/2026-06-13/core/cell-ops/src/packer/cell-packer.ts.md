---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-ops/src/packer/cell-packer.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.830338+00:00
---

# core/cell-ops/src/packer/cell-packer.ts

```ts
/**
 * High-level multi-cell assembly + disassembly facade.
 *
 * `assembleSemanticObject(opts)` packs a semantic object (header +
 * payload) plus its verification continuations (BUMP, BEEF,
 * envelope, data) into one contiguous N×CELL_SIZE buffer.
 *
 * `disassembleSemanticObject(buffer)` reverses the process,
 * splitting continuation chunks back into typed components.
 */

import { CELL_SIZE, CONTINUATION_TYPE, HEADER_SIZE } from './constants';
import {
  packMultiCell,
  unpackMultiCell,
} from './multicell-assembler';
import { createAtomicBeefCells } from './op-packers/pack-beef';
import { createBumpCells } from './op-packers/pack-bump';
import { createDataCells } from './op-packers/pack-data';
import { createEnvelopeCells } from './op-packers/pack-envelope';
import type {
  ContinuationCell,
  PackedMultiCell,
} from './types';

import { unpackCell, type CellHeader } from '../cellHeader';
import type { MerkleEnvelope } from '../merkleEnvelope';

export interface AssembleOptions {
  header: Buffer;
  payload: Buffer;
  bumpRaw?: Buffer;
  atomicBeef?: Buffer;
  stateEnvelope?: MerkleEnvelope;
  extraData?: Buffer[];
}

export function assembleSemanticObject(opts: AssembleOptions): PackedMultiCell {
  const continuations: ContinuationCell[] = [];
  if (opts.bumpRaw) continuations.push(...createBumpCells(opts.bumpRaw));
  if (opts.atomicBeef) continuations.push(...createAtomicBeefCells(opts.atomicBeef));
  if (opts.stateEnvelope) continuations.push(...createEnvelopeCells(opts.stateEnvelope));
  if (opts.extraData) {
    for (const data of opts.extraData) continuations.push(...createDataCells(data));
  }
  return packMultiCell({
    header: opts.header,
    payload: opts.payload,
    continuations,
  });
}

export interface DisassembledObject {
  header: CellHeader;
  payload: Buffer;
  bumpRaw?: Buffer;
  atomicBeef?: Buffer;
  envelopeData?: Buffer;
  extraData: Buffer[];
}

export function disassembleSemanticObject(buffer: Buffer): DisassembledObject {
  const multi = unpackMultiCell(buffer);
  const padBytes = Math.max(0, CELL_SIZE - HEADER_SIZE - multi.payload.length);
  const { header: headerFields } = unpackCell(
    Buffer.concat([multi.header, multi.payload, Buffer.alloc(padBytes)]),
  );

  const bumpChunks: Buffer[] = [];
  const atomicBeefChunks: Buffer[] = [];
  const envelopeChunks: Buffer[] = [];
  const extraData: Buffer[] = [];

  for (const cont of multi.continuations) {
    switch (cont.type) {
      case CONTINUATION_TYPE.BUMP:
        bumpChunks.push(cont.data);
        break;
      case CONTINUATION_TYPE.ATOMIC_BEEF:
        atomicBeefChunks.push(cont.data);
        break;
      case CONTINUATION_TYPE.ENVELOPE:
        envelopeChunks.push(cont.data);
        break;
      case CONTINUATION_TYPE.DATA:
      case CONTINUATION_TYPE.STATE:
        extraData.push(cont.data);
        break;
    }
  }

  return {
    header: headerFields,
    payload: multi.payload,
    bumpRaw: bumpChunks.length > 0 ? Buffer.concat(bumpChunks) : undefined,
    atomicBeef: atomicBeefChunks.length > 0 ? Buffer.concat(atomicBeefChunks) : undefined,
    envelopeData: envelopeChunks.length > 0 ? Buffer.concat(envelopeChunks) : undefined,
    extraData,
  };
}

```
