---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/semantic-fs/metadata-scanner.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.866843+00:00
---

# core/protocol-types/src/semantic-fs/metadata-scanner.ts

```ts
/**
 * Metadata scanner — walks `objects/`, reads each cell's `.meta`
 * sidecar, and yields a {@link CellRef} for every key whose metadata
 * matches a caller-supplied async predicate.
 *
 * Keeps `_index/`, `.chunk.`, `.v` and `.meta` files out of the result
 * set so callers see only "real" cells.
 */

import type { StorageAdapter } from '../storage';
import { Linearity } from '../constants';
import type { CellRef } from '../cell-store/types';
import type { CellMeta } from './types';

const isCellKey = (k: string): boolean =>
  !k.endsWith('.meta') &&
  !k.includes('.chunk.') &&
  !k.includes('.v') &&
  !k.startsWith('_index/');

async function readMeta(adapter: StorageAdapter, key: string): Promise<CellMeta | null> {
  const bytes = await adapter.read(`${key}.meta`);
  if (!bytes) return null;
  try {
    return JSON.parse(new TextDecoder().decode(bytes)) as CellMeta;
  } catch {
    return null;
  }
}

function metaToRef(key: string, meta: CellMeta): CellRef {
  return {
    key,
    cellHash: meta.cellHash,
    contentHash: meta.contentHash,
    version: meta.version,
    timestamp: meta.timestamp,
    linearity: meta.linearity as Linearity,
  };
}

export interface ScanFilterOptions {
  /** Defaults to `objects/`. */
  prefix?: string;
}

/**
 * Read every cell key under `prefix`, run `predicate(key, meta)` and
 * collect those that pass. Returns CellRefs in storage-iteration order.
 */
export async function scanMetaFilter(
  adapter: StorageAdapter,
  predicate: (key: string, meta: CellMeta) => Promise<boolean>,
  options: ScanFilterOptions = {},
): Promise<CellRef[]> {
  const prefix = options.prefix ?? 'objects/';
  const allKeys = await adapter.list(prefix);
  const cellKeys = allKeys.filter(isCellKey);

  const refs: CellRef[] = [];
  for (const relativeKey of cellKeys) {
    const fullKey = prefix + relativeKey;
    const meta = await readMeta(adapter, fullKey);
    if (!meta) continue;
    if (await predicate(fullKey, meta)) refs.push(metaToRef(fullKey, meta));
  }
  return refs;
}

/**
 * Lower-level: list cell keys under `prefix` (with the standard
 * `_index/` / `.meta` / `.chunk.` / `.v` filters applied), optionally
 * cap at `depth` segments.
 */
export async function listCellKeys(
  adapter: StorageAdapter,
  prefix: string,
  options?: { depth?: number },
): Promise<string[]> {
  const normalized = prefix.replace(/\/+$/, '') + '/';
  const all = await adapter.list(normalized);
  let cells = all.filter(isCellKey);
  if (options?.depth !== undefined) {
    const max = options.depth;
    cells = cells.filter((k) => k.split('/').length <= max);
  }
  return cells.map((k) => normalized + k);
}

/**
 * Read every meta sidecar for the supplied keys, returning CellRefs in
 * the same order (skipping keys with no meta).
 */
export async function metaRefsFor(
  adapter: StorageAdapter,
  keys: string[],
): Promise<CellRef[]> {
  const out: CellRef[] = [];
  for (const key of keys) {
    const meta = await readMeta(adapter, key);
    if (meta) out.push(metaToRef(key, meta));
  }
  return out;
}

export { readMeta };

```
