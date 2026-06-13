---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-settlement/src/store/paskian-schema.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.712146+00:00
---

# archive/apps-settlement/src/store/paskian-schema.ts

```ts
/**
 * Paskian-store schema DDL — all CREATE TABLE / CREATE INDEX
 * statements for the Paskian constraint graph live here.
 *
 * The legacy `createTables()` was inline in the `PaskianStore`
 * constructor; the prompt-44 split moves it here so per-concern
 * stores hold no DDL — only their table-scoped CRUD. Cross-table
 * queries live in `query-surface.ts`.
 *
 * Idempotent (`IF NOT EXISTS`). Safe to run on every boot.
 */

import type { DatabaseHandle } from './db-types';

/** Schema version — bumped when DDL changes. */
export const PASKIAN_SCHEMA_VERSION = 1;

/** Combined DDL applied at startup. Idempotent. */
export const PASKIAN_SCHEMA_SQL = `
  CREATE TABLE IF NOT EXISTS paskian_nodes (
    cell_id           TEXT PRIMARY KEY,
    type_path         TEXT NOT NULL,
    h_state           REAL DEFAULT 0.0,
    stability         REAL DEFAULT 0.0,
    interaction_count INTEGER DEFAULT 0,
    is_stable         INTEGER DEFAULT 0,
    is_pruned         INTEGER DEFAULT 0,
    created_at        INTEGER NOT NULL,
    updated_at        INTEGER NOT NULL
  );

  CREATE TABLE IF NOT EXISTS paskian_edges (
    edge_id           TEXT PRIMARY KEY,
    from_cell         TEXT NOT NULL REFERENCES paskian_nodes(cell_id),
    to_cell           TEXT NOT NULL REFERENCES paskian_nodes(cell_id),
    constraint_weight REAL DEFAULT 0.0,
    delta_trend       REAL DEFAULT 0.0,
    interaction_count INTEGER DEFAULT 0,
    last_updated      INTEGER NOT NULL
  );

  CREATE TABLE IF NOT EXISTS constraint_deltas (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    edge_id           TEXT NOT NULL REFERENCES paskian_edges(edge_id),
    delta             REAL NOT NULL,
    interaction       TEXT NOT NULL DEFAULT '',
    cell_version      INTEGER DEFAULT 0,
    prev_state_hash   TEXT DEFAULT '',
    timestamp         INTEGER NOT NULL
  );

  CREATE TABLE IF NOT EXISTS stability_log (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    cell_id           TEXT NOT NULL REFERENCES paskian_nodes(cell_id),
    delta_h           REAL NOT NULL,
    is_stable         INTEGER NOT NULL,
    recorded_at       INTEGER NOT NULL
  );

  CREATE TABLE IF NOT EXISTS pruning_log (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    cell_id           TEXT NOT NULL,
    type_path         TEXT NOT NULL,
    reason            TEXT NOT NULL,
    final_h_state     REAL NOT NULL,
    pruned_at         INTEGER NOT NULL,
    anchor_txid       TEXT
  );

  CREATE INDEX IF NOT EXISTS idx_edges_from ON paskian_edges(from_cell);
  CREATE INDEX IF NOT EXISTS idx_edges_to ON paskian_edges(to_cell);
  CREATE INDEX IF NOT EXISTS idx_deltas_edge ON constraint_deltas(edge_id);
  CREATE INDEX IF NOT EXISTS idx_deltas_time ON constraint_deltas(timestamp);
  CREATE INDEX IF NOT EXISTS idx_stability_cell ON stability_log(cell_id);
`;

/**
 * Apply the Paskian schema to a fresh or existing database. Safe to
 * run on every boot — every CREATE uses `IF NOT EXISTS`.
 */
export function applyPaskianSchema(db: DatabaseHandle): void {
  db.exec(PASKIAN_SCHEMA_SQL);
}

```
