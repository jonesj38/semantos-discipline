---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/cell-store/cell-verifier.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.890029+00:00
---

# core/protocol-types/src/cell-store/cell-verifier.ts

```ts
/**
 * Verify the Merkle chain of a key — recomputes every persisted
 * version's `cellHash`, checks `prevStateHash` linkage between
 * adjacent versions, and (for chunked cells) recomputes each chunk's
 * SHA-256 against the manifest.
 *
 * Pure I/O wrapper — no mutations. Returns a list of human-readable
 * error strings; an empty list means the chain is intact.
 */

import { HEADER_SIZE, PAYLOAD_SIZE } from '../constants';
import { deserializeCellHeader } from '../cell-header';
import {
  hexFromBuffer,
  sha256,
} from './content-hasher';
import { unpackContinuationCell } from './cell-packer';
import { collectVersions } from './version-chain-walker';
import type { ChunkManifest } from './types';
import type { StorageAdapterFacade } from './storage-adapter-facade';

export interface VerifyResult {
  valid: boolean;
  errors: string[];
}

function findManifestEnd(cellBytes: Uint8Array): number {
  let jsonEnd = HEADER_SIZE;
  while (jsonEnd < HEADER_SIZE + PAYLOAD_SIZE && cellBytes[jsonEnd] !== 0) jsonEnd++;
  return jsonEnd;
}

function parseManifest(cellBytes: Uint8Array): ChunkManifest | null {
  try {
    return JSON.parse(
      new TextDecoder().decode(cellBytes.subarray(HEADER_SIZE, findManifestEnd(cellBytes))),
    ) as ChunkManifest;
  } catch {
    return null;
  }
}

export async function verifyChain(
  storage: StorageAdapterFacade,
  key: string,
): Promise<VerifyResult> {
  const errors: string[] = [];
  const refs = await collectVersions(storage, key);
  if (refs.length === 0) return { valid: false, errors: ['No cell found at key'] };

  for (let i = 0; i < refs.length; i++) {
    const ref = refs[i]!;
    const storageKey = i === 0 ? key : `${key}.v${ref.version}`;
    const cellBytes = await storage.readCell(storageKey);

    if (!cellBytes) {
      errors.push(`version ${ref.version}: cell bytes missing`);
      continue;
    }

    const computedHash = await sha256(cellBytes);
    if (computedHash !== ref.cellHash) {
      errors.push(
        `version ${ref.version}: cellHash mismatch (expected ${ref.cellHash.slice(0, 16)}..., got ${computedHash.slice(0, 16)}...)`,
      );
    }

    const header = deserializeCellHeader(cellBytes);

    if (i < refs.length - 1) {
      const prevRef = refs[i + 1]!;
      const prevStateHex = hexFromBuffer(header.prevStateHash);
      if (prevStateHex !== prevRef.cellHash) {
        errors.push(
          `version ${ref.version}: prevStateHash does not match version ${prevRef.version}`,
        );
      }
    }

    if (header.cellCount > 1) {
      const manifest = parseManifest(cellBytes);
      if (!manifest) {
        errors.push(`version ${ref.version}: manifest parse failed`);
        continue;
      }
      for (let ci = 0; ci < manifest.chunkCount; ci++) {
        const chunkKey = `${storageKey}.chunk.${String(ci).padStart(4, '0')}`;
        const chunkCell = await storage.readChunk(chunkKey);
        if (!chunkCell) {
          errors.push(`version ${ref.version}: chunk ${ci} missing`);
          continue;
        }
        const { chunk } = unpackContinuationCell(chunkCell);
        const chunkHash = await sha256(chunk);
        if (chunkHash !== manifest.chunkHashes[ci]) {
          errors.push(`version ${ref.version}: chunk ${ci} hash mismatch`);
        }
      }
    }
  }

  return { valid: errors.length === 0, errors };
}

```
