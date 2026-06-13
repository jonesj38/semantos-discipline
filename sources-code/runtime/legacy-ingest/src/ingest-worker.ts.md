---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/ingest-worker.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.133920+00:00
---

# runtime/legacy-ingest/src/ingest-worker.ts

```ts
/**
 * Ingest worker — LI2.
 *
 * Reference: docs/design/WALLET-LEGACY-INGEST.md §3 LI2 deliverables 3 + 4.
 *
 * Two modes:
 *   - backfill — walk the provider in chronological order from a `since`
 *     timestamp until end-of-list. Resumable across crashes via the
 *     cursor-store. Yields per-page progress so the REPL can render a
 *     dashboard.
 *   - continuous — poll every N minutes for new items since the last
 *     watermark. Pushes into the same blob-store; AS4's legacy-ingest
 *     signal source picks them up.
 *
 * Rate-limit handling: if the provider throws GmailRateLimited (or
 * the equivalent), we wait the retryAfter seconds and resume.
 */

import type { LegacyGrant, LegacyProvider, ProviderId, RawItem } from './types';
import type { LegacyBlobStore } from './blob-store';
import type { CursorStore, IngestCheckpoint } from './cursor-store';
import { audit } from './audit';
import { GmailRateLimited } from './providers/gmail';

export interface IngestWorkerOpts {
  blobStore: LegacyBlobStore;
  cursorStore: CursorStore;
  /**
   * Resolves the latest LegacyGrant for a given provider. The worker
   * re-resolves before every page so token refreshes (background or
   * inline) take effect transparently.
   */
  grantResolver: (providerId: ProviderId) => Promise<LegacyGrant | null>;
  /** Optional per-page hook for progress reporting. */
  onProgress?: (progress: IngestProgress) => void;
  /**
   * Optional hook invoked after a full raw item is persisted. Hosts use this
   * to project provider-native messages into the unified Oddjobz message
   * patch trail without coupling the blob store to any one vertical.
   */
  onItemPersisted?: (item: RawItem) => Promise<void> | void;
}

export interface IngestProgress {
  readonly providerId: ProviderId;
  readonly grantId: string;
  readonly pagesProcessed: number;
  readonly itemsThisPage: number;
  readonly itemsPersisted: number;
  readonly cursor: string | null;
}

export interface BackfillOpts {
  /** Lower-bound timestamp (ms). Default: no bound (full backfill). */
  since?: number;
  /** Cap on pages; useful for tests + bounded runs. */
  maxPages?: number;
  /** Bypass `fetchFull` (for adapters that put bodies in `listPage`). */
  skipFetchFull?: boolean;
  /**
   * Provider-specific filter string passed verbatim to
   * `LegacyProvider.listPage`. For Gmail this becomes the `q` parameter
   * (Gmail-search syntax: `from:`, `subject:`, `label:`, …) and is
   * AND-combined with `since` if both are supplied. Providers without
   * a server-side query language may ignore the field.
   */
  query?: string;
}

export class IngestWorker {
  private readonly opts: IngestWorkerOpts;
  private readonly cancelFlags = new Map<string, boolean>();
  private readonly running = new Set<string>();

  constructor(opts: IngestWorkerOpts) {
    this.opts = opts;
  }

  /**
   * Run a backfill against `provider`. Idempotent — re-running picks
   * up from the last checkpoint. Returns the final checkpoint.
   */
  async backfill(
    provider: LegacyProvider,
    backfillOpts: BackfillOpts = {},
  ): Promise<IngestCheckpoint> {
    const grant = await this.opts.grantResolver(provider.id);
    if (!grant) throw new Error(`legacy-ingest: no grant for provider '${provider.id}'`);

    const key = `${provider.id}:${grant.grantId}`;
    if (this.running.has(key)) throw new Error(`already running: ${key}`);
    this.running.add(key);
    this.cancelFlags.set(key, false);

    try {
      let checkpoint = (await this.opts.cursorStore.get(provider.id, grant.grantId))
        ?? this.makeCheckpoint(provider.id, grant.grantId, backfillOpts.since ?? null);

      // If the prior run completed and the operator runs backfill again
      // with the same `since`, reset to start over.
      if (checkpoint.completed && backfillOpts.since !== undefined && backfillOpts.since !== checkpoint.since) {
        checkpoint = this.makeCheckpoint(provider.id, grant.grantId, backfillOpts.since);
      }

      let pagesThisRun = 0;
      while (true) {
        if (this.cancelFlags.get(key)) {
          await audit('ingest.cancel', 'ok', { providerId: provider.id, grantId: grant.grantId });
          break;
        }
        if (backfillOpts.maxPages !== undefined && pagesThisRun >= backfillOpts.maxPages) break;

        let pageResult;
        try {
          pageResult = await provider.listPage(grant.token, {
            cursor: checkpoint.cursor,
            since: checkpoint.since ?? undefined,
            query: backfillOpts.query,
          });
        } catch (err) {
          if (err instanceof GmailRateLimited) {
            await audit('ingest.rate-limited', 'denied', {
              providerId: provider.id,
              grantId: grant.grantId,
              detail: `retry_after_${err.retryAfterSeconds}s`,
            });
            await sleep(err.retryAfterSeconds * 1000);
            continue;
          }
          throw err;
        }

        const items = pageResult.items;
        let highWatermark = checkpoint.highWatermark;
        let persisted = 0;

        for (const preview of items) {
          let full: RawItem;
          try {
            full = backfillOpts.skipFetchFull
              ? preview
              : await provider.fetchFull(grant.token, preview);
          } catch (err) {
            if (err instanceof GmailRateLimited) {
              await sleep(err.retryAfterSeconds * 1000);
              full = await provider.fetchFull(grant.token, preview);
            } else {
              throw err;
            }
          }
          await this.opts.blobStore.put(full);
          await this.emitPersistedItem(full);
          persisted += 1;
          if (full.fetchedAt > highWatermark) highWatermark = full.fetchedAt;
        }

        checkpoint = {
          ...checkpoint,
          cursor: pageResult.nextCursor,
          highWatermark,
          pagesProcessed: checkpoint.pagesProcessed + 1,
          itemsPersisted: checkpoint.itemsPersisted + persisted,
          lastUpdatedAt: new Date().toISOString(),
          completed: pageResult.nextCursor === null,
        };
        await this.opts.cursorStore.put(checkpoint);
        pagesThisRun += 1;

        this.opts.onProgress?.({
          providerId: provider.id,
          grantId: grant.grantId,
          pagesProcessed: checkpoint.pagesProcessed,
          itemsThisPage: persisted,
          itemsPersisted: checkpoint.itemsPersisted,
          cursor: pageResult.nextCursor,
        });

        if (pageResult.nextCursor === null) {
          await audit('ingest.complete', 'ok', {
            providerId: provider.id,
            grantId: grant.grantId,
            detail: `pages=${checkpoint.pagesProcessed} items=${checkpoint.itemsPersisted}`,
          });
          break;
        }
      }

      return checkpoint;
    } finally {
      this.running.delete(key);
      this.cancelFlags.delete(key);
    }
  }

  /** Cancel the in-flight backfill for a grant. The next page boundary checks. */
  cancel(providerId: ProviderId, grantId: string): boolean {
    const key = `${providerId}:${grantId}`;
    if (!this.running.has(key)) return false;
    this.cancelFlags.set(key, true);
    return true;
  }

  isRunning(providerId: ProviderId, grantId: string): boolean {
    return this.running.has(`${providerId}:${grantId}`);
  }

  /**
   * Continuous-poll loop. Calls backfill with `since = highWatermark`
   * every `intervalMs`. Stop with the returned function.
   */
  startContinuous(
    provider: LegacyProvider,
    intervalMs: number,
  ): () => void {
    let stopped = false;
    let timer: ReturnType<typeof setTimeout> | null = null;

    const loop = async (): Promise<void> => {
      if (stopped) return;
      try {
        const grant = await this.opts.grantResolver(provider.id);
        if (grant) {
          const cp = await this.opts.cursorStore.get(provider.id, grant.grantId);
          await this.backfill(provider, { since: cp?.highWatermark ?? Date.now() });
        }
      } catch (err) {
        await audit('ingest.continuous.error', 'error', {
          providerId: provider.id,
          detail: err instanceof Error ? err.message : 'unknown',
        });
      } finally {
        if (!stopped) timer = setTimeout(() => void loop(), intervalMs);
      }
    };

    timer = setTimeout(() => void loop(), 0);
    return () => {
      stopped = true;
      if (timer) clearTimeout(timer);
    };
  }

  private makeCheckpoint(
    providerId: ProviderId,
    grantId: string,
    since: number | null,
  ): IngestCheckpoint {
    return {
      providerId,
      grantId,
      cursor: null,
      since,
      highWatermark: 0,
      pagesProcessed: 0,
      itemsPersisted: 0,
      lastUpdatedAt: new Date().toISOString(),
      completed: false,
    };
  }

  private async emitPersistedItem(item: RawItem): Promise<void> {
    if (!this.opts.onItemPersisted) return;
    try {
      await this.opts.onItemPersisted(item);
    } catch (err) {
      await audit('ingest.item-persisted-hook.error', 'error', {
        providerId: item.providerId,
        detail: `${item.providerItemId}: ${err instanceof Error ? err.message : String(err)}`,
      });
    }
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

```
