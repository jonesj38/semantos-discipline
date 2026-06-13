---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/cursor-store.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.133638+00:00
---

# runtime/legacy-ingest/src/cursor-store.ts

```ts
/**
 * Ingest cursor checkpoint store — LI2.
 *
 * Reference: docs/design/WALLET-LEGACY-INGEST.md §3 LI2 deliverable 3.
 *
 * Backfill is resumable: every page persists a checkpoint with the
 * provider's pagination cursor + the high-water `since` timestamp.
 * If `kill -9` interrupts a run, the next invocation continues from
 * the last checkpoint.
 *
 * Stored unencrypted — these are pagination tokens and timestamps,
 * not secrets. The OAuth tokens themselves are in the grant-store.
 */

import type { Cursor, ProviderId } from './types';
import type { GrantPersistence } from './grant-store';

export interface IngestCheckpoint {
  readonly providerId: ProviderId;
  readonly grantId: string;
  /** Provider pagination cursor; null on first page or when complete. */
  readonly cursor: Cursor;
  /** Lower-bound timestamp passed to listPage (ms). */
  readonly since: number | null;
  /** ms timestamp of the most recent persisted item. */
  readonly highWatermark: number;
  /** Pages walked so far. */
  readonly pagesProcessed: number;
  /** Items persisted so far. */
  readonly itemsPersisted: number;
  /** ISO timestamp of the last successful checkpoint. */
  readonly lastUpdatedAt: string;
  /** Whether the backfill has been observed to reach end-of-list. */
  readonly completed: boolean;
}

export interface CursorStoreOpts {
  persistence: GrantPersistence;
  prefix?: string;
}

export class CursorStore {
  private readonly persistence: GrantPersistence;
  private readonly prefix: string;

  constructor(opts: CursorStoreOpts) {
    this.persistence = opts.persistence;
    this.prefix = opts.prefix ?? 'legacy-ingest-cursor';
  }

  async get(providerId: ProviderId, grantId: string): Promise<IngestCheckpoint | null> {
    const blob = await this.persistence.read(this.keyFor(providerId, grantId));
    if (!blob) return null;
    return JSON.parse(new TextDecoder().decode(blob));
  }

  async put(checkpoint: IngestCheckpoint): Promise<void> {
    const blob = new TextEncoder().encode(JSON.stringify(checkpoint));
    await this.persistence.write(this.keyFor(checkpoint.providerId, checkpoint.grantId), blob);
  }

  async delete(providerId: ProviderId, grantId: string): Promise<void> {
    await this.persistence.delete(this.keyFor(providerId, grantId));
  }

  async listByProvider(providerId: ProviderId): Promise<IngestCheckpoint[]> {
    const keys = await this.persistence.list(`${this.prefix}/${providerId}/`);
    const out: IngestCheckpoint[] = [];
    for (const k of keys) {
      const blob = await this.persistence.read(k);
      if (blob) out.push(JSON.parse(new TextDecoder().decode(blob)));
    }
    return out;
  }

  private keyFor(providerId: ProviderId, grantId: string): string {
    return `${this.prefix}/${providerId}/${grantId}.json`;
  }
}

```
