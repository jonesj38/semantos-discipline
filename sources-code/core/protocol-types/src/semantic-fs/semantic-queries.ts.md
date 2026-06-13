---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/semantic-fs/semantic-queries.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.865222+00:00
---

# core/protocol-types/src/semantic-fs/semantic-queries.ts

```ts
/**
 * Semantic queries — filter cells under `objects/` by header fields
 * (parentHash, typeHash, ownerId). Each function delegates to
 * {@link scanMetaFilter} with a header-aware predicate.
 *
 * No persistence side effects — just reads.
 */

import type { StorageAdapter } from '../storage';
import { deserializeCellHeader } from '../cell-header';
import { HEADER_SIZE } from '../constants';
import { hexFromBuffer } from '../cell-store/content-hasher';
import type { CellRef } from '../cell-store/types';
import { scanMetaFilter } from './metadata-scanner';
import { computeTypeHash } from './type-hasher';

async function readHeader(
  adapter: StorageAdapter,
  key: string,
): Promise<{ parentHash: string; typeHash: string; ownerId: string } | null> {
  const cellBytes = await adapter.read(key);
  if (!cellBytes || cellBytes.length < HEADER_SIZE) return null;
  const header = deserializeCellHeader(cellBytes);
  return {
    parentHash: hexFromBuffer(header.parentHash),
    typeHash: hexFromBuffer(header.typeHash),
    ownerId: hexFromBuffer(header.ownerId),
  };
}

/** Find all objects whose parent hash matches. */
export async function queryByParent(
  adapter: StorageAdapter,
  parentHash: string,
): Promise<CellRef[]> {
  return scanMetaFilter(adapter, async (key) => {
    const h = await readHeader(adapter, key);
    return h?.parentHash === parentHash;
  });
}

/**
 * Find all objects of a given taxonomy type. The dotted taxonomy path
 * is hashed via {@link computeTypeHash} and the resulting hex is
 * matched against each cell's header.
 */
export async function queryByType(
  adapter: StorageAdapter,
  taxonomyPath: string,
): Promise<CellRef[]> {
  const segments = taxonomyPath.split('.');
  const typeHashHex = hexFromBuffer(await computeTypeHash(segments));
  return scanMetaFilter(adapter, async (key) => {
    const h = await readHeader(adapter, key);
    return h?.typeHash === typeHashHex;
  });
}

/** Find all objects owned by `ownerId`. */
export async function queryByOwner(
  adapter: StorageAdapter,
  ownerId: Uint8Array,
): Promise<CellRef[]> {
  const ownerHex = hexFromBuffer(ownerId);
  return scanMetaFilter(adapter, async (key) => {
    const h = await readHeader(adapter, key);
    return h?.ownerId === ownerHex;
  });
}

```
