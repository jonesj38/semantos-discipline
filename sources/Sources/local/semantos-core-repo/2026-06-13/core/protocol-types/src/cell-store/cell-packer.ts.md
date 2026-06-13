---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/cell-store/cell-packer.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.890581+00:00
---

# core/protocol-types/src/cell-store/cell-packer.ts

```ts
/**
 * Pure cell packer — converts a `CellHeader` + payload into the canonical
 * 1024-byte Cell 0 wire form, plus continuation-cell helpers.
 *
 * No I/O, no hashing, no storage. The CellStore facade calls these
 * after deciding what to write; tests can drive them directly.
 */

import type { CellHeader } from '../cell-header';
import { serializeCellHeader, deserializeCellHeader } from '../cell-header';
import {
  CELL_SIZE,
  HEADER_SIZE,
  PAYLOAD_SIZE,
  CONTINUATION_HEADER_SIZE,
} from '../constants';

export { serializeCellHeader, deserializeCellHeader };

export interface ContinuationHeaderFields {
  cellType: number;
  cellIndex: number;
  totalCells: number;
  payloadSize: number;
}

/**
 * Build an 8-byte continuation header matching multicell.zig.
 *
 *  Byte 0:    cellType   (u8)
 *  Bytes 1-2: cellIndex  (u16 LE, 1-based)
 *  Bytes 3-4: totalCells (u16 LE, excludes Cell 0)
 *  Bytes 5-6: payloadSize(u16 LE)
 *  Byte 7:    reserved   (u8, always 0)
 */
export function buildContinuationHeader(
  cellType: number,
  cellIndex: number,
  totalCells: number,
  payloadSize: number,
): Uint8Array {
  const buf = new Uint8Array(CONTINUATION_HEADER_SIZE);
  const dv = new DataView(buf.buffer);
  buf[0] = cellType;
  dv.setUint16(1, cellIndex, true);
  dv.setUint16(3, totalCells, true);
  dv.setUint16(5, payloadSize, true);
  buf[7] = 0;
  return buf;
}

export function parseContinuationHeader(cell: Uint8Array): ContinuationHeaderFields {
  const dv = new DataView(cell.buffer, cell.byteOffset, cell.byteLength);
  return {
    cellType: cell[0] as number,
    cellIndex: dv.getUint16(1, true),
    totalCells: dv.getUint16(3, true),
    payloadSize: dv.getUint16(5, true),
  };
}

/**
 * Pack a header + payload into a 1024-byte Cell 0. Throws when the
 * payload is larger than {@link PAYLOAD_SIZE} — chunked writers should
 * call this with the manifest payload, not the raw data.
 */
export function packCell(header: CellHeader, payload: Uint8Array): Uint8Array {
  if (payload.length > PAYLOAD_SIZE) {
    throw new Error(
      `packCell: payload (${payload.length} bytes) exceeds PAYLOAD_SIZE (${PAYLOAD_SIZE}). Use the chunker for larger inputs.`,
    );
  }
  const cell = new Uint8Array(CELL_SIZE);
  cell.set(serializeCellHeader(header), 0);
  cell.set(payload, HEADER_SIZE);
  return cell;
}

/**
 * Unpack a 1024-byte cell into header + payload. Returns the payload
 * region trimmed to `header.totalSize` for single cells, or the full
 * `PAYLOAD_SIZE` slice for chunked cells (the caller decides what to
 * do with the manifest bytes).
 */
export function unpackCell(cellBytes: Uint8Array): { header: CellHeader; payload: Uint8Array } {
  if (cellBytes.length < CELL_SIZE) {
    throw new Error(
      `unpackCell: expected at least ${CELL_SIZE} bytes, got ${cellBytes.length}`,
    );
  }
  const header = deserializeCellHeader(cellBytes);
  const payloadEnd =
    header.cellCount > 1
      ? HEADER_SIZE + PAYLOAD_SIZE
      : HEADER_SIZE + Math.min(header.totalSize, PAYLOAD_SIZE);
  const payload = cellBytes.slice(HEADER_SIZE, payloadEnd);
  return { header, payload };
}

/** Convenience: build a continuation cell from a chunk + header. */
export function packContinuationCell(
  cellType: number,
  cellIndex: number,
  totalCells: number,
  chunk: Uint8Array,
): Uint8Array {
  const cell = new Uint8Array(CELL_SIZE);
  const contHeader = buildContinuationHeader(cellType, cellIndex, totalCells, chunk.length);
  cell.set(contHeader, 0);
  cell.set(chunk, CONTINUATION_HEADER_SIZE);
  return cell;
}

/** Inverse of {@link packContinuationCell}. */
export function unpackContinuationCell(cellBytes: Uint8Array): {
  header: ContinuationHeaderFields;
  chunk: Uint8Array;
} {
  const header = parseContinuationHeader(cellBytes);
  const chunk = cellBytes.subarray(
    CONTINUATION_HEADER_SIZE,
    CONTINUATION_HEADER_SIZE + header.payloadSize,
  );
  return { header, chunk };
}

/**
 * Find the byte offset just past the manifest JSON in a chunked Cell 0.
 * The manifest is packed at the start of the payload region; we walk
 * until the first NUL byte (the manifest is a UTF-8 JSON blob, NUL-
 * padded to fill the rest of `PAYLOAD_SIZE`).
 */
export function findManifestEnd(cellBytes: Uint8Array): number {
  let jsonEnd = HEADER_SIZE;
  while (jsonEnd < HEADER_SIZE + PAYLOAD_SIZE && cellBytes[jsonEnd] !== 0) jsonEnd++;
  return jsonEnd;
}

/** Parse the chunked-cell manifest, or return null on malformed JSON. */
export function parseManifest<T = unknown>(cellBytes: Uint8Array): T | null {
  try {
    return JSON.parse(
      new TextDecoder().decode(cellBytes.subarray(HEADER_SIZE, findManifestEnd(cellBytes))),
    ) as T;
  } catch {
    return null;
  }
}

```
