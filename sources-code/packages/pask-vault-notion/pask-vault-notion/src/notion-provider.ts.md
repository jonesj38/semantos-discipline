---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/pask-vault-notion/pask-vault-notion/src/notion-provider.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.443378+00:00
---

# packages/pask-vault-notion/pask-vault-notion/src/notion-provider.ts

```ts
/**
 * NotionProvider — minimal interface over the Notion API surface.
 *
 * Keeping this thin lets the adapter work with the official
 * @notionhq/client, a mock for tests, or any compatible HTTP client.
 */

export interface NotionPropertyValue {
  type: string;
  /** Relation-type property: list of linked page IDs. */
  relation?: ReadonlyArray<{ id: string }>;
  /** Select-type property: single chosen option. */
  select?: { name: string } | null;
  /** Multi-select-type property: list of chosen options. */
  multi_select?: ReadonlyArray<{ name: string }>;
}

export interface NotionPage {
  readonly id: string;
  readonly last_edited_time: string;
  readonly parent:
    | { type: 'database_id'; database_id: string }
    | { type: 'page_id'; page_id: string }
    | { type: 'workspace'; workspace: true };
  readonly properties: Record<string, NotionPropertyValue>;
}

export interface NotionDatabase {
  readonly id: string;
  readonly last_edited_time: string;
}

export interface NotionWorkspaceInfo {
  /** Stable bot_id or workspace_id used as the cell namespace. */
  readonly workspaceId: string;
}

export interface NotionProvider {
  /** Returns stable workspace / integration identity. */
  getWorkspaceInfo(): Promise<NotionWorkspaceInfo>;

  /**
   * Paginates all pages and databases the integration can access.
   * Optionally filters to objects edited after `editedAfter` (Unix ms).
   */
  searchAll(opts?: {
    editedAfter?: number;
    cursor?: string;
  }): Promise<{
    pages: NotionPage[];
    databases: NotionDatabase[];
    nextCursor: string | null;
  }>;
}

```
