---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-world-client/src/sqlite-opfs.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.823297+00:00
---

# archive/apps-world-client/src/sqlite-opfs.ts

```ts
// M2.1 — SQLite-WASM-OPFS bring-up module.
//
// Acceptance: SQLite-WASM loads in browser; OPFS handle resolved;
// one round-trip query returns.
//
// Strategy:
//   1. In a browser with OPFS support (Chrome ≥ 102, Firefox ≥ 111, Safari ≥ 17):
//      load `@sqlite.org/sqlite-wasm` and open a database backed by the
//      Origin Private File System (OPFS) via the `opfs-sahpool` VFS.
//   2. In environments without OPFS (Node CI, older browsers):
//      fall back to the in-memory VFS. Data does not survive a page reload
//      in fallback mode — callers can detect this via `db.storageMode`.
//
// Browser quota notes (M2.1 open question #5):
//   Chrome: ~60 % of available disk, evictable
//   Firefox: no hard limit, but user can revoke
//   Safari: 1 GiB quota, persistent after user grants
// The per-domain ATTACH pattern (M2.6) is designed to stay within quotas.
//
// Per-domain isolation (M2.6, deferred): each governance domain gets its own
// .sqlite file via ATTACH DATABASE. This module manages the single root DB;
// M2.6 builds the per-domain facade on top.

import initSqlite, { type Database, type Sqlite3Static } from "@sqlite.org/sqlite-wasm";

export type StorageMode = "opfs" | "memory";

export interface SqliteOpfsDbOptions {
  /** File name used in OPFS (or the in-memory DB name). Must be unique per domain. */
  dbName: string;
  /** Override map size / page size (future). Ignored for now. */
  pageSize?: number;
}

export interface QueryRow {
  [column: string]: unknown;
}

/**
 * Thin wrapper around sqlite-wasm with OPFS storage and a memory fallback.
 *
 * Open/close lifecycle:
 *   const db = new SqliteOpfsDb({ dbName: 'semantos-octave0' });
 *   await db.open();   // loads WASM, resolves OPFS handle
 *   await db.exec('CREATE TABLE …');
 *   const rows = await db.query('SELECT …');
 *   await db.close();
 */
export class SqliteOpfsDb {
  readonly dbName: string;
  private _sqlite3: Sqlite3Static | null = null;
  private _db: Database | null = null;
  private _storageMode: StorageMode = "memory";
  private _open = false;

  constructor(opts: SqliteOpfsDbOptions) {
    this.dbName = opts.dbName;
  }

  get isOpen(): boolean {
    return this._open;
  }

  get storageMode(): StorageMode {
    return this._storageMode;
  }

  /**
   * Expose the underlying sqlite3 static instance (needed by M2.6 DomainDbManager
   * for CAPI access, e.g. sqlite3_js_db_export).
   */
  get sqlite3(): Sqlite3Static {
    this.assertOpen();
    return this._sqlite3!;
  }

  /**
   * Expose the underlying Database instance (needed by M2.6 DomainDbManager
   * for ATTACH/DETACH and capi calls).
   */
  get db(): Database {
    this.assertOpen();
    return this._db!;
  }

  /**
   * Initialise the WASM module and open the database.
   * Safe to call only once; subsequent calls throw.
   */
  async open(): Promise<void> {
    if (this._open) throw new Error("SqliteOpfsDb: already open");

    const sqlite3 = await initSqlite({ print: () => {}, printErr: console.error });
    this._sqlite3 = sqlite3;

    if (sqlite3.opfs !== undefined) {
      // OPFS available — durable storage.
      this._db = new sqlite3.oo1.OpfsDb(`/${this.dbName}.sqlite3`);
      this._storageMode = "opfs";
    } else {
      // Memory fallback — survives only for this page session.
      this._db = new sqlite3.oo1.DB(`:memory:`);
      this._storageMode = "memory";
    }

    this._open = true;
  }

  /**
   * Execute a SQL statement that returns no rows (DDL, INSERT, UPDATE, DELETE).
   */
  async exec(sql: string, bind?: unknown[]): Promise<void> {
    this.assertOpen();
    this._db!.exec({ sql, bind });
  }

  /**
   * Execute a SELECT and return typed rows.
   * Column names match the SQL column aliases.
   */
  async query<T extends QueryRow = QueryRow>(sql: string, bind?: unknown[]): Promise<T[]> {
    this.assertOpen();
    const rows: T[] = [];
    this._db!.exec({
      sql,
      bind,
      rowMode: "object",
      callback: (row: T) => rows.push({ ...row }),
    });
    return rows;
  }

  /**
   * Close the database and release WASM resources.
   */
  async close(): Promise<void> {
    if (!this._open) return;
    this._db?.close();
    this._db = null;
    this._open = false;
  }

  private assertOpen(): void {
    if (!this._open || !this._db) {
      throw new Error("SqliteOpfsDb: not open — call open() first");
    }
  }
}

```
