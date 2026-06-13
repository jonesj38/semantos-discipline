---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/semantic-fs/cell-reclassifier.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.867397+00:00
---

# core/protocol-types/src/semantic-fs/cell-reclassifier.ts

```ts
/**
 * Reclassification — moves an object from one taxonomy path to
 * another, leaving a tombstone behind that points to the new
 * location.
 *
 * Two writes happen:
 *   1. Tombstone at the old storage key — same payload format as
 *      {@link tombstone-resolver}: a UTF-8, NUL-terminated redirect
 *      string. The cell's `flags` bit `FLAGS_TOMBSTONE` is set.
 *   2. New version at the new storage key. Its `prevStateHash` links
 *      back to the tombstone's cellHash so the version chain spans
 *      the move.
 */

import type { CellStore } from '../cell-store/cell-store-facade';
import type { CellRef } from '../cell-store/types';
import { hexToBytes } from '../cell-store/content-hasher';
import type { TaxonomyResolver } from '../taxonomy-resolver';
import { parseSemanticPath } from './semantic-path-parser';
import { validateForWrite } from './semantic-path-validator';
import { computeTypeHash } from './type-hasher';
import { FLAGS_TOMBSTONE } from './types';

export interface ReclassifyResult {
  tombstone: CellRef;
  newVersion: CellRef;
}

export async function reclassifyCell(
  cellStore: CellStore,
  taxonomy: TaxonomyResolver,
  oldPath: string,
  newPath: string,
): Promise<ReclassifyResult> {
  const oldParsed = parseSemanticPath(oldPath, taxonomy);
  const newParsed = validateForWrite(newPath, taxonomy);

  const current = await cellStore.get(oldParsed.storageKey);
  if (!current) throw new Error(`Cannot reclassify: no cell at "${oldPath}"`);

  const redirectPayload = new TextEncoder().encode(newParsed.storageKey + '\0');
  const tombstone = await cellStore.put(oldParsed.storageKey, redirectPayload, {
    linearity: current.linearity,
    ownerId: current.header.ownerId,
    typeHash: current.header.typeHash,
    flags: FLAGS_TOMBSTONE,
  });

  const newTypeHash = await computeTypeHash(newParsed.taxonomyPath);
  const newVersion = await cellStore.put(newParsed.storageKey, current.payload, {
    linearity: current.linearity,
    ownerId: current.header.ownerId,
    typeHash: newTypeHash,
    prevStateHash: hexToBytes(tombstone.cellHash),
  });

  return { tombstone, newVersion };
}

```
