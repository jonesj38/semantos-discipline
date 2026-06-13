---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-world-client/src/sqlite-derivation-state-store.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.817763+00:00
---

# archive/apps-world-client/src/sqlite-derivation-state-store.ts

```ts
// M2.4 — SqliteDerivationStateStore: SQLite-backed BRC-42 derivation index store.
//
// Implements the same semantic contract as the Zig `LocalStateStore` vtable
// (core/cell-engine/src/derivation_state.zig), backed by `SqliteOpfsDb`.
//
// Schema:
//   derivation_state (
//     path        TEXT PRIMARY KEY,
//     next_index  INTEGER NOT NULL DEFAULT 0,
//     ceiling     INTEGER             -- NULL means unbounded
//   )
//
// nextIndex() invariant:
//   The returned value is the current next_index, which is then atomically
//   incremented. If next_index >= ceiling (when ceiling IS NOT NULL), the
//   call throws 'ceiling_exceeded' BEFORE returning or persisting anything.
//   This mirrors the Zig contract: "The returned value is guaranteed never
//   to be returned again for the same context."

import type { SqliteOpfsDb } from "./sqlite-opfs.js";

export interface DerivationRecord {
  path: string;
  nextIndex: bigint;
  ceiling: bigint | null;
}

interface DerivationRow {
  path: string;
  next_index: number | bigint;
  ceiling: number | bigint | null;
}

export class SqliteDerivationStateStore {
  private readonly db: SqliteOpfsDb;

  constructor(db: SqliteOpfsDb) {
    this.db = db;
  }

  /** Create the table if it does not exist. Safe to call multiple times. */
  async init(): Promise<void> {
    await this.db.exec(`
      CREATE TABLE IF NOT EXISTS derivation_state (
        path       TEXT PRIMARY KEY,
        next_index INTEGER NOT NULL DEFAULT 0,
        ceiling    INTEGER
      )
    `);
  }

  /**
   * Return the last issued index for the given path, or null if the path
   * has never been used. Mirrors Zig's `get_index` / `current_index` — the
   * value most recently returned by nextIndex for this path.
   *
   * Internally next_index stores the *next* value to hand out, so the last
   * issued value is next_index - 1.  A freshly-inserted row with next_index=0
   * means no index has been issued yet → return null.
   */
  async getIndex(path: string): Promise<bigint | null> {
    const rows = await this.db.query<DerivationRow>(
      `SELECT next_index FROM derivation_state WHERE path = ?`,
      [path],
    );
    if (rows.length === 0) return null;
    const stored = BigInt(rows[0].next_index);
    // If next_index is 0 the path row was created by setCeiling but nextIndex
    // has never been called → treat as if path is unknown.
    if (stored === 0n) return null;
    return stored - 1n;
  }

  /**
   * Atomically allocate and persist the next derivation index.
   * Throws 'ceiling_exceeded' if next_index >= ceiling.
   * The returned bigint is guaranteed unique per path.
   */
  async nextIndex(path: string): Promise<bigint> {
    // Upsert to ensure the row exists.
    await this.db.exec(
      `INSERT INTO derivation_state (path, next_index, ceiling)
       VALUES (?, 0, NULL)
       ON CONFLICT(path) DO NOTHING`,
      [path],
    );

    const rows = await this.db.query<DerivationRow>(
      `SELECT next_index, ceiling FROM derivation_state WHERE path = ?`,
      [path],
    );

    const row = rows[0];
    const current = BigInt(row.next_index);
    const ceiling = row.ceiling != null ? BigInt(row.ceiling) : null;

    // Enforce ceiling BEFORE persisting — must never return index >= ceiling.
    if (ceiling !== null && current >= ceiling) {
      throw new Error("ceiling_exceeded");
    }

    // Atomically increment.
    await this.db.exec(
      `UPDATE derivation_state SET next_index = next_index + 1 WHERE path = ?`,
      [path],
    );

    return current;
  }

  /**
   * Set (or update) the ceiling for a path. Creates the row if absent.
   * A ceiling of null removes any existing ceiling (unbounded).
   */
  async setCeiling(path: string, ceiling: bigint | null): Promise<void> {
    await this.db.exec(
      `INSERT INTO derivation_state (path, next_index, ceiling)
       VALUES (?, 0, ?)
       ON CONFLICT(path) DO UPDATE SET ceiling = excluded.ceiling`,
      [path, ceiling],
    );
  }

  /**
   * Snapshot all (path, next_index, ceiling) records.
   */
  async snapshot(): Promise<DerivationRecord[]> {
    const rows = await this.db.query<DerivationRow>(
      `SELECT path, next_index, ceiling FROM derivation_state`,
    );
    return rows.map(rowToRecord);
  }

  /**
   * Replace all store contents with the provided records (does not merge).
   */
  async replay(records: DerivationRecord[]): Promise<void> {
    await this.db.exec(`DELETE FROM derivation_state`);
    for (const rec of records) {
      await this.db.exec(
        `INSERT INTO derivation_state (path, next_index, ceiling) VALUES (?, ?, ?)`,
        [rec.path, rec.nextIndex, rec.ceiling],
      );
    }
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Internal helpers
// ──────────────────────────────────────────────────────────────────────────────

function rowToRecord(row: DerivationRow): DerivationRecord {
  return {
    path: row.path,
    nextIndex: BigInt(row.next_index),
    ceiling: row.ceiling != null ? BigInt(row.ceiling) : null,
  };
}

```
