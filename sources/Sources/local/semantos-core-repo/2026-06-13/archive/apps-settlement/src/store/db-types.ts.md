---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-settlement/src/store/db-types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.711006+00:00
---

# archive/apps-settlement/src/store/db-types.ts

```ts
/**
 * Single import location for SQLite-handle types used by the
 * Paskian store split (prompt 44).
 *
 * Per-concern stores import `DatabaseHandle` from here so the
 * `bun:sqlite` reference appears exactly once at the facade's value
 * import rather than across every store module. The minimal interface
 * below is the subset of `bun:sqlite`'s `Database` that the per-concern
 * stores actually use.
 *
 * Mirrors `apps/poker-agent/src/game-state-db/db-types.ts` (prompt 21).
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
