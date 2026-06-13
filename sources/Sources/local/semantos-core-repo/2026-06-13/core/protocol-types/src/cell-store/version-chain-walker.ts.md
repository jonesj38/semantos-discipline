---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/cell-store/version-chain-walker.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.891143+00:00
---

# core/protocol-types/src/cell-store/version-chain-walker.ts

```ts
/**
 * Walk the version chain of a key — newest first, following the
 * `key.v{N}` archive convention written by the StorageAdapterFacade.
 *
 * Pure I/O wrapper: takes a storage facade and yields `CellRef`s. The
 * chain stops at the first missing meta sidecar.
 */

import { Linearity } from '../constants';
import type { CellRef } from './types';
import type { StorageAdapterFacade } from './storage-adapter-facade';

/**
 * Async generator yielding every persisted version of `key`, newest
 * first. Each yield maps directly to one historical cell.
 */
export async function* walkVersions(
  storage: StorageAdapterFacade,
  key: string,
): AsyncGenerator<CellRef> {
  const head = await storage.readMeta(key);
  if (!head) return;

  yield {
    key,
    cellHash: head.cellHash,
    contentHash: head.contentHash,
    version: head.version,
    timestamp: head.timestamp,
    linearity: head.linearity as Linearity,
  };

  let currentVersion = head.version - 1;
  while (currentVersion >= 1) {
    const versionedKey = `${key}.v${currentVersion}`;
    const meta = await storage.readMeta(versionedKey);
    if (!meta) return;
    yield {
      key: versionedKey,
      cellHash: meta.cellHash,
      contentHash: meta.contentHash,
      version: meta.version,
      timestamp: meta.timestamp,
      linearity: meta.linearity as Linearity,
    };
    currentVersion--;
  }
}

/** Materialize the generator into a `CellRef[]` (newest first). */
export async function collectVersions(
  storage: StorageAdapterFacade,
  key: string,
): Promise<CellRef[]> {
  const refs: CellRef[] = [];
  for await (const ref of walkVersions(storage, key)) refs.push(ref);
  return refs;
}

```
