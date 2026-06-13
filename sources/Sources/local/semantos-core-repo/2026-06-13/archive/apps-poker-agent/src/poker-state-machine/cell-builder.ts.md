---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/poker-state-machine/cell-builder.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.769330+00:00
---

# archive/apps-poker-agent/src/poker-state-machine/cell-builder.ts

```ts
/**
 * Pure cell-builder for poker hand state.
 *
 * `buildCell()` writes the JSON-serialized state into a fresh
 * `CellStore` over a `MemoryAdapter` (single source of truth from
 * prompt 04) and returns the raw bytes + content hash. The caller
 * owns versioning + locking-script construction.
 *
 * `bumpCellVersion()` patches the version field at offset 20 of the
 * cell header in-place — extracted from the legacy `transition()` so
 * the operation is reusable + testable.
 */

import { createHash } from 'crypto';

import { CellStore } from '../../../../core/protocol-types/src/cell-store';
import { MemoryAdapter } from '../../../../core/protocol-types/src/adapters/memory-adapter';
import { Linearity } from '../../../../core/protocol-types/src/constants';

import type { HandStatePayload } from './types';

/** Semantic type hash for poker hand state cells. */
export const POKER_HAND_TYPE_HASH = createHash('sha256')
  .update('semantos/poker/hand-state/v1')
  .digest();

export interface BuildCellResult {
  cellBytes: Uint8Array;
  contentHash: Uint8Array;
}

export interface BuildCellOptions {
  /** Owner ID (16 bytes from gameId-derived hash). */
  ownerId: Uint8Array;
  /** Cell version, written into the bytes after construction. */
  version?: number;
}

/** Compute the canonical semantic path for a given hand state. */
export function semanticPath(state: HandStatePayload): string {
  return `game/poker/${state.gameId}/hand-${state.handNumber}/state`;
}

/** Derive the 16-byte owner ID from a gameId. */
export function deriveOwnerId(gameId: string): Uint8Array {
  return hexToBytes(createHash('sha256').update(gameId).digest('hex').slice(0, 32));
}

/**
 * Build a fresh CellToken byte buffer for the given state. Pure
 * (no wallet, no network). Uses the prompt-04 CellStore facade so
 * downstream cell-protocol changes propagate automatically.
 */
export async function buildCell(
  state: HandStatePayload,
  opts: BuildCellOptions,
): Promise<BuildCellResult> {
  const storage = new MemoryAdapter();
  const cellStore = new CellStore(storage);
  const path = semanticPath(state);

  const data = new TextEncoder().encode(JSON.stringify(state));
  const cellRef = await cellStore.put(path, data, {
    linearity: Linearity.LINEAR,
    ownerId: opts.ownerId,
    typeHash: POKER_HAND_TYPE_HASH,
  });

  const cellBytes = await storage.read(path);
  if (!cellBytes) throw new Error('Failed to read cell from MemoryAdapter');

  if (typeof opts.version === 'number') {
    bumpCellVersion(cellBytes, opts.version);
  }

  return {
    cellBytes,
    contentHash: hexToBytes(cellRef.contentHash),
  };
}

/**
 * Patch the version field at offset 20 of the cell header (LE u32).
 * Mutates `cellBytes` in place — same behaviour as the legacy
 * inline DataView write.
 */
export function bumpCellVersion(cellBytes: Uint8Array, version: number): void {
  const dv = new DataView(
    cellBytes.buffer,
    cellBytes.byteOffset,
    cellBytes.byteLength,
  );
  dv.setUint32(20, version, true);
}

/** Internal helper — convert a hex string into a Uint8Array. */
export function hexToBytes(hex: string): Uint8Array {
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) {
    out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }
  return out;
}

```
