---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/cell-store/storage-adapter-facade.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.891959+00:00
---

# core/protocol-types/src/cell-store/storage-adapter-facade.ts

```ts
/**
 * Thin facade over `StorageAdapter` exposing the named operations the
 * cell-store actually performs: read/write a cell's primary key, read
 * its meta sidecar, archive the previous version, list under prefixes
 * for index lookups.
 *
 * The wrapper exists so future evolutions (caching, batching, async
 * write-behind) have a single seam to plug into without touching the
 * facade's pump methods.
 */

import type { StorageAdapter } from '../storage';
import type { CellMeta } from './types';

export class StorageAdapterFacade {
  constructor(private readonly adapter: StorageAdapter) {}

  /** Read the canonical cell bytes at `key`. */
  readCell(key: string): Promise<Uint8Array | null> {
    return this.adapter.read(key);
  }

  /** Write canonical cell bytes at `key`. */
  writeCell(key: string, bytes: Uint8Array): Promise<void> {
    return this.adapter.write(key, bytes);
  }

  /** Read a continuation chunk by its ordered key. */
  readChunk(key: string): Promise<Uint8Array | null> {
    return this.adapter.read(key);
  }

  /** Write a continuation chunk. */
  writeChunk(key: string, bytes: Uint8Array): Promise<void> {
    return this.adapter.write(key, bytes);
  }

  /** Read the JSON meta sidecar associated with `key`. */
  async readMeta(key: string): Promise<CellMeta | null> {
    const bytes = await this.adapter.read(`${key}.meta`);
    if (!bytes) return null;
    try {
      return JSON.parse(new TextDecoder().decode(bytes)) as CellMeta;
    } catch {
      return null;
    }
  }

  /** Write the JSON meta sidecar associated with `key`. */
  writeMeta(key: string, meta: CellMeta): Promise<void> {
    return this.adapter.write(
      `${key}.meta`,
      new TextEncoder().encode(JSON.stringify(meta)),
    );
  }

  /**
   * Archive the previous version of `key` under `key.v{version}` (and
   * its meta sidecar). No-op if the previous bytes are missing.
   */
  async archivePrevious(key: string, version: number): Promise<void> {
    const prevCell = await this.adapter.read(key);
    if (prevCell) await this.adapter.write(`${key}.v${version}`, prevCell);
    const prevMeta = await this.adapter.read(`${key}.meta`);
    if (prevMeta) await this.adapter.write(`${key}.v${version}.meta`, prevMeta);
  }

  /** Read raw bytes at any key (used by index lookups). */
  read(key: string): Promise<Uint8Array | null> {
    return this.adapter.read(key);
  }

  /** Write raw bytes at any key. */
  write(key: string, bytes: Uint8Array): Promise<void> {
    return this.adapter.write(key, bytes);
  }

  /** List relative keys under a prefix. */
  list(prefix: string): Promise<string[]> {
    return this.adapter.list(prefix);
  }
}

```
