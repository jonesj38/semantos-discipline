---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-world-client/src/sqlite-header-store.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.820498+00:00
---

# archive/apps-world-client/src/sqlite-header-store.ts

```ts
// M2.2 — SqliteHeaderStore: SQLite-backed header store for the browser tier.
//
// Implements the same semantic contract as the Zig `LocalHeaderStore` vtable
// (core/cell-engine/src/header_store.zig), backed by `SqliteOpfsDb` instead of
// an in-memory ArrayList.
//
// Schema:
//   header_store (
//     height  INTEGER PRIMARY KEY,
//     hash    BLOB NOT NULL,          -- 32-byte block hash
//     prev_hash BLOB NOT NULL,        -- 32-byte prev_hash (for reorg validation)
//     header  BLOB NOT NULL           -- 80-byte raw serialised header
//   )
//
// Invariants enforced:
//   • appendValidated checks prev_hash continuity and monotone height order.
//   • rollbackFrom uses DELETE WHERE height >= from_height.
//   • allByHeight / snapshot return rows ORDER BY height ASC.

import type { SqliteOpfsDb } from "./sqlite-opfs.js";

export interface HeaderRecord {
  height: number;
  hash: Uint8Array;
  prevHash: Uint8Array;
  header: Uint8Array;
}

interface HeaderRow {
  height: number;
  hash: Uint8Array | Buffer;
  prev_hash: Uint8Array | Buffer;
  header: Uint8Array | Buffer;
}

function toUint8Array(v: Uint8Array | Buffer | null | undefined): Uint8Array {
  if (v == null) return new Uint8Array(0);
  if (v instanceof Uint8Array) return v;
  return new Uint8Array(v.buffer, v.byteOffset, v.byteLength);
}

export class SqliteHeaderStore {
  private readonly db: SqliteOpfsDb;

  constructor(db: SqliteOpfsDb) {
    this.db = db;
  }

  /** Create the table if it doesn't exist. Safe to call multiple times. */
  async init(): Promise<void> {
    await this.db.exec(`
      CREATE TABLE IF NOT EXISTS header_store (
        height    INTEGER PRIMARY KEY,
        hash      BLOB NOT NULL,
        prev_hash BLOB NOT NULL,
        header    BLOB NOT NULL
      )
    `);
  }

  /**
   * Append a validated header.
   * Enforces:
   *   - height == tip.height + 1 (or store empty → any height allowed as origin)
   *   - prevHash == tip.hash (when store non-empty)
   * Throws 'height_out_of_order' or 'prev_hash_mismatch' on violation.
   */
  async appendValidated(rec: HeaderRecord): Promise<void> {
    const currentTip = await this.tip();

    if (currentTip !== null) {
      if (rec.height !== currentTip.height + 1) {
        throw new Error("height_out_of_order");
      }
      if (!bytesEqual(rec.prevHash, currentTip.hash)) {
        throw new Error("prev_hash_mismatch");
      }
    }

    await this.db.exec(
      `INSERT INTO header_store (height, hash, prev_hash, header) VALUES (?, ?, ?, ?)`,
      [rec.height, rec.hash, rec.prevHash, rec.header],
    );
  }

  /** Return the record at the given height, or null if not found. */
  async getByHeight(height: number): Promise<HeaderRecord | null> {
    const rows = await this.db.query<HeaderRow>(
      `SELECT height, hash, prev_hash, header FROM header_store WHERE height = ?`,
      [height],
    );
    if (rows.length === 0) return null;
    return rowToRecord(rows[0]);
  }

  /** Return the record with the given 32-byte hash, or null if not found. */
  async getByHash(hash: Uint8Array): Promise<HeaderRecord | null> {
    const rows = await this.db.query<HeaderRow>(
      `SELECT height, hash, prev_hash, header FROM header_store WHERE hash = ?`,
      [hash],
    );
    if (rows.length === 0) return null;
    return rowToRecord(rows[0]);
  }

  /** Return the record with the greatest height, or null if empty. */
  async tip(): Promise<HeaderRecord | null> {
    const rows = await this.db.query<HeaderRow>(
      `SELECT height, hash, prev_hash, header FROM header_store ORDER BY height DESC LIMIT 1`,
    );
    if (rows.length === 0) return null;
    return rowToRecord(rows[0]);
  }

  /**
   * Return all records in ascending height order.
   * Used as the cursor / iteration primitive (mirrors Zig snapshot but ordered).
   */
  async allByHeight(): Promise<HeaderRecord[]> {
    const rows = await this.db.query<HeaderRow>(
      `SELECT height, hash, prev_hash, header FROM header_store ORDER BY height ASC`,
    );
    return rows.map(rowToRecord);
  }

  /**
   * Snapshot: alias for allByHeight(), matches Zig `snapshot()` semantics.
   * Returns records in ascending height order.
   */
  async snapshot(): Promise<HeaderRecord[]> {
    return this.allByHeight();
  }

  /**
   * Replay: replace all store contents with the provided records.
   * Records must be in monotone ascending height order.
   * Does not re-validate prev_hash links (trusts the caller, matching Zig behaviour).
   */
  async replay(records: HeaderRecord[]): Promise<void> {
    await this.db.exec(`DELETE FROM header_store`);
    for (const rec of records) {
      await this.db.exec(
        `INSERT INTO header_store (height, hash, prev_hash, header) VALUES (?, ?, ?, ?)`,
        [rec.height, rec.hash, rec.prevHash, rec.header],
      );
    }
  }

  /**
   * Drop every record with height >= from_height.
   * Returns the count of dropped records.
   */
  async rollbackFrom(fromHeight: number): Promise<number> {
    const countRows = await this.db.query<{ n: number }>(
      `SELECT COUNT(*) AS n FROM header_store WHERE height >= ?`,
      [fromHeight],
    );
    const count = countRows[0]?.n ?? 0;
    if (count === 0) return 0;
    await this.db.exec(`DELETE FROM header_store WHERE height >= ?`, [fromHeight]);
    return count;
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Internal helpers
// ──────────────────────────────────────────────────────────────────────────────

function rowToRecord(row: HeaderRow): HeaderRecord {
  return {
    height: row.height,
    hash: toUint8Array(row.hash as Uint8Array | Buffer),
    prevHash: toUint8Array(row.prev_hash as Uint8Array | Buffer),
    header: toUint8Array(row.header as Uint8Array | Buffer),
  };
}

function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) return false;
  }
  return true;
}

```
