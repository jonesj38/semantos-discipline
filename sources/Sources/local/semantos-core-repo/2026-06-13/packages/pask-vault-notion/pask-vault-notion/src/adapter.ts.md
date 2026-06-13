---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/pask-vault-notion/pask-vault-notion/src/adapter.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.443090+00:00
---

# packages/pask-vault-notion/pask-vault-notion/src/adapter.ts

```ts
/**
 * NotionAdapter — DB4 of the Dimensional Second Brain workstream.
 *
 * Polls a Notion workspace and feeds page/database events into the Pask
 * constraint graph. Cell-ID namespace:
 *
 *   nx:page:<workspace>/<page-id>
 *   nx:db:<workspace>/<database-id>
 *   nx:row:<db-id>/<row-id>       (page that lives inside a database)
 *   nx:tag:<workspace>/<value>    (select / multi_select property values)
 *
 * Relation properties produce edges (relatedCells) between page cells.
 * The adapter is read-only — no writes to Notion.
 */

import type { PaskGraph } from '@semantos/runtime-services';
import type { NotionProvider, NotionPage, NotionDatabase } from './notion-provider';
import { TokenBucket } from './rate-limiter';

// ── Options ────────────────────────────────────────────────────────────────

export interface NotionAdapterOptions {
  provider: NotionProvider;
  paskGraph: PaskGraph;
  /** Polling interval for incremental sync. Default: 5 minutes. */
  pollIntervalMs?: number;
  /** Number of API requests per second. Default: 3. */
  apiRatePerSec?: number;
}

// ── Cell-ID helpers ────────────────────────────────────────────────────────

function pageCell(workspaceId: string, pageId: string): string {
  return `nx:page:${workspaceId}/${pageId}`;
}

function dbCell(workspaceId: string, dbId: string): string {
  return `nx:db:${workspaceId}/${dbId}`;
}

function rowCell(dbId: string, pageId: string): string {
  return `nx:row:${dbId}/${pageId}`;
}

function tagCell(workspaceId: string, value: string): string {
  return `nx:tag:${workspaceId}/${value.toLowerCase().replace(/\s+/g, '-')}`;
}

// ── Relation extraction ────────────────────────────────────────────────────

function relatedCells(
  workspaceId: string,
  page: NotionPage,
): string[] {
  const cells: string[] = [];

  for (const prop of Object.values(page.properties)) {
    if (prop.type === 'relation' && prop.relation) {
      for (const r of prop.relation) {
        cells.push(pageCell(workspaceId, r.id));
      }
    } else if (prop.type === 'select' && prop.select?.name) {
      cells.push(tagCell(workspaceId, prop.select.name));
    } else if (prop.type === 'multi_select' && prop.multi_select) {
      for (const s of prop.multi_select) {
        cells.push(tagCell(workspaceId, s.name));
      }
    }
  }

  // If the page lives in a database, link it to the db cell too.
  if (page.parent.type === 'database_id') {
    cells.push(dbCell(workspaceId, page.parent.database_id));
  }

  return cells;
}

// ── Adapter ────────────────────────────────────────────────────────────────

export class NotionAdapter {
  private readonly graph: PaskGraph;
  private readonly provider: NotionProvider;
  private readonly bucket: TokenBucket;
  private readonly pollIntervalMs: number;

  private workspaceId: string | null = null;
  private lastSyncCursor: number | null = null; // Unix ms
  private pollTimer: ReturnType<typeof setInterval> | null = null;
  private stopped = false;

  constructor(opts: NotionAdapterOptions) {
    this.graph = opts.paskGraph;
    this.provider = opts.provider;
    this.bucket = new TokenBucket(
      opts.apiRatePerSec ?? 3,
      opts.apiRatePerSec ?? 3,
    );
    this.pollIntervalMs = opts.pollIntervalMs ?? 5 * 60 * 1000;
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  async start(): Promise<void> {
    this.stopped = false;
    const info = await this.provider.getWorkspaceInfo();
    this.workspaceId = info.workspaceId;
    await this.coldStart();
    this.pollTimer = setInterval(() => {
      this.incrementalSync().catch(() => {});
    }, this.pollIntervalMs);
  }

  stop(): void {
    this.stopped = true;
    if (this.pollTimer) clearInterval(this.pollTimer);
    this.pollTimer = null;
  }

  // ── Cold-start ────────────────────────────────────────────────────────────

  private async coldStart(): Promise<void> {
    if (!this.workspaceId) return;
    let cursor: string | undefined;
    const startMs = Date.now();

    do {
      if (this.stopped) return;
      await this.bucket.acquire();
      const batch = await this.provider.searchAll({ cursor });

      for (const page of batch.pages) {
        this.emitPage(page, 'seed');
      }
      for (const db of batch.databases) {
        this.emitDb(db, 'seed');
      }

      cursor = batch.nextCursor ?? undefined;
    } while (cursor);

    this.lastSyncCursor = startMs;
  }

  // ── Incremental sync ──────────────────────────────────────────────────────

  async incrementalSync(): Promise<void> {
    if (!this.workspaceId || this.stopped) return;
    const since = this.lastSyncCursor;
    const startMs = Date.now();
    let cursor: string | undefined;

    do {
      if (this.stopped) return;
      await this.bucket.acquire();
      const batch = await this.provider.searchAll({
        editedAfter: since ?? undefined,
        cursor,
      });

      for (const page of batch.pages) {
        this.emitPage(page, 'edit');
      }
      for (const db of batch.databases) {
        this.emitDb(db, 'edit');
      }

      cursor = batch.nextCursor ?? undefined;
    } while (cursor);

    this.lastSyncCursor = startMs;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  private emitPage(page: NotionPage, kind: 'seed' | 'edit'): void {
    if (!this.workspaceId) return;
    const nowMs = kind === 'seed'
      ? new Date(page.last_edited_time).getTime()
      : Date.now();
    const strength = kind === 'seed' ? 0.1 : 0.8;
    const related = relatedCells(this.workspaceId, page);

    // Pages inside a database are also addressable as rows.
    if (page.parent.type === 'database_id') {
      const rCell = rowCell(page.parent.database_id, page.id);
      this.graph.interact({ cellId: rCell, kind, strength, relatedCells: related, nowMs });
    } else {
      const pCell = pageCell(this.workspaceId, page.id);
      this.graph.interact({ cellId: pCell, kind, strength, relatedCells: related, nowMs });
    }
  }

  private emitDb(db: NotionDatabase, kind: 'seed' | 'edit'): void {
    if (!this.workspaceId) return;
    const nowMs = kind === 'seed'
      ? new Date(db.last_edited_time).getTime()
      : Date.now();
    const cell = dbCell(this.workspaceId, db.id);
    this.graph.interact({ cellId: cell, kind, strength: 0.1, nowMs });
  }

  // ── Open-in-Notion ────────────────────────────────────────────────────────

  /**
   * Build the Notion desktop / web URL for a cell ID.
   * Returns null if the cell is not a Notion cell.
   */
  notionUrl(cellId: string): string | null {
    const m = cellId.match(/^nx:(?:page|row|db):[\w-]+\/([\w-]+)$/);
    if (!m) return null;
    const id = m[1]!.replace(/-/g, '');
    return `notion://www.notion.so/${id}`;
  }
}

```
