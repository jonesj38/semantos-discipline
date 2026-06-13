---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/cell-store/content-indexer.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.891696+00:00
---

# core/protocol-types/src/cell-store/content-indexer.ts

```ts
/**
 * Content-hash index — sidecar `_index/content/{hash}` that maps a
 * payload SHA-256 to every key+version that wrote those bytes.
 *
 * This module owns the read/write/dedupe ceremony so the facade can
 * call it as `await indexer.append(...)` after each `put`. Pure-ish:
 * the only effect is two adapter calls per append.
 */

import type { ContentIndexEntry } from './types';
import type { StorageAdapterFacade } from './storage-adapter-facade';

export class ContentIndexer {
  constructor(private readonly storage: StorageAdapterFacade) {}

  /** Append `entry` to `_index/content/{contentHash}`, deduped. */
  async append(contentHash: string, entry: ContentIndexEntry): Promise<void> {
    const indexKey = `_index/content/${contentHash}`;
    const existing = await this.storage.read(indexKey);
    let entries: ContentIndexEntry[] = [];
    if (existing) {
      try {
        entries = JSON.parse(new TextDecoder().decode(existing)) as ContentIndexEntry[];
      } catch {
        entries = [];
      }
    }
    const dup = entries.some((e) => e.key === entry.key && e.version === entry.version);
    if (!dup) entries.push(entry);
    await this.storage.write(indexKey, new TextEncoder().encode(JSON.stringify(entries)));
  }

  /** Read all entries for a given content hash. */
  async lookup(contentHash: string): Promise<ContentIndexEntry[]> {
    const bytes = await this.storage.read(`_index/content/${contentHash}`);
    if (!bytes) return [];
    try {
      return JSON.parse(new TextDecoder().decode(bytes)) as ContentIndexEntry[];
    } catch {
      return [];
    }
  }
}

```
