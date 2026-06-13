---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/game-state-db/db-types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.774605+00:00
---

# archive/apps-poker-agent/src/game-state-db/db-types.ts

```ts
/**
 * Single import location for SQLite-handle types.
 *
 * Stores import `DatabaseHandle` from here so cross-tier consumers
 * (`apps/settlement`) see the `bun:sqlite` reference exactly once
 * — at the facade's value import — rather than ten times across
 * the per-table store files. The minimal interface below is the
 * subset of `bun:sqlite`'s `Database` that the stores actually use.
 */

export interface PreparedStatement {
  run(...args: unknown[]): { lastInsertRowid: number | bigint };
  get(...args: unknown[]): unknown;
  all(...args: unknown[]): unknown[];
}

export interface DatabaseHandle {
  prepare(sql: string): PreparedStatement;
  exec(sql: string): void;
  close(): void;
}

```
