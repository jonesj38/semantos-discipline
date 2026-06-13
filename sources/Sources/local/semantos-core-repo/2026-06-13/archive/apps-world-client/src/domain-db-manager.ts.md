---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-world-client/src/domain-db-manager.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.816610+00:00
---

# archive/apps-world-client/src/domain-db-manager.ts

```ts
// M2.6 — DomainDbManager: per-domain ATTACH DATABASE manager for the browser tier.
//
// Spec: Recovery-payload ATTACH DATABASE per domain flag — one .sqlite file per
// governance domain; detach/encrypt/re-attach round-trip tested.
//
// Five canonical governance domain types (docs/textbook/06-domain-flags-sovereign-boundaries.md
// and docs/canon/cybernetic-orders.md):
//   Trust (0x54), Estate (0x45), Realm (0x52), Corporate (0x43), Cooperative (0x4F)
//
// In production (OPFS mode), each domain gets a separate OPFS file:
//   ATTACH DATABASE 'file:domain_54.sqlite?vfs=opfs' AS domain_54;
//
// In test mode (memory VFS fallback), named in-memory DBs are used:
//   ATTACH DATABASE 'file:domain_54.sqlite?mode=memory&cache=shared' AS domain_54;
//
// Schema in each attached domain DB:
//   domain_cells (
//     cell_hash    BLOB PRIMARY KEY,  -- 32 bytes
//     domain_flag  INTEGER NOT NULL,  -- 4-byte domain flag value
//     cell_data    BLOB NOT NULL,     -- full 1024-byte cell
//     created_at_ms INTEGER NOT NULL
//   )
//   INDEX domain_cells_flag ON domain_cells(domain_flag)
//
// detachAndSerialize uses sqlite3_js_db_export() (CAPI) to export the attached
// DB's pages as a Uint8Array, simulating the "encrypt before storing" step.
//
// reattachFromBytes uses sqlite3_deserialize() (CAPI) to re-load the pages into
// a fresh named in-memory DB and re-attaches it.

import type { SqliteOpfsDb } from "./sqlite-opfs.js";

// ──────────────────────────────────────────────────────────────────────────────
// Public constants
// ──────────────────────────────────────────────────────────────────────────────

export const DOMAIN_FLAGS = {
  TRUST: 0x54,
  ESTATE: 0x45,
  REALM: 0x52,
  CORPORATE: 0x43,
  COOPERATIVE: 0x4f,
} as const;

export type DomainFlag = (typeof DOMAIN_FLAGS)[keyof typeof DOMAIN_FLAGS];

// ──────────────────────────────────────────────────────────────────────────────
// Internal helpers
// ──────────────────────────────────────────────────────────────────────────────

/**
 * Convert a domain flag number to the alias name used in SQL ATTACH statements.
 * e.g. 0x54 → "domain_54"
 */
function domainAlias(domainFlag: number): string {
  return `domain_${domainFlag.toString(16).padStart(2, "0")}`;
}

/**
 * Build the ATTACH DATABASE URI for a given domain flag.
 * In OPFS mode: file:domain_54.sqlite?vfs=opfs
 * In memory mode: file:domain_54.sqlite?mode=memory&cache=shared
 */
function domainUri(domainFlag: number, storageMode: "opfs" | "memory"): string {
  const name = `domain_${domainFlag.toString(16).padStart(2, "0")}.sqlite`;
  if (storageMode === "opfs") {
    return `file:${name}?vfs=opfs`;
  }
  return `file:${name}?mode=memory&cache=shared`;
}

/**
 * DDL statements for the domain_cells table and its index.
 * These are run as separate exec() calls since the schema qualifier (alias.)
 * only applies to the table reference, not the index name in CREATE INDEX.
 */
function domainCellsDdl(alias: string): string[] {
  return [
    `CREATE TABLE IF NOT EXISTS ${alias}.domain_cells (
      cell_hash     BLOB PRIMARY KEY,
      domain_flag   INTEGER NOT NULL,
      cell_data     BLOB NOT NULL,
      created_at_ms INTEGER NOT NULL
    )`,
    // In SQLite, CREATE INDEX uses schema before the index name (not the table name):
    //   CREATE INDEX [schema.]index_name ON table_name(col)
    // The table name is unqualified here because it resolves within the schema.
    `CREATE INDEX IF NOT EXISTS ${alias}.domain_cells_flag ON domain_cells(domain_flag)`,
  ];
}

// ──────────────────────────────────────────────────────────────────────────────
// DomainDbManager
// ──────────────────────────────────────────────────────────────────────────────

/**
 * Manages per-governance-domain attached SQLite databases.
 *
 * Each governance domain (Trust, Estate, Realm, Corporate, Cooperative) gets
 * its own separate SQLite file accessed via ATTACH DATABASE. This enforces
 * sovereignty boundaries at the storage layer.
 */
export class DomainDbManager {
  private readonly _opfsDb: SqliteOpfsDb;
  /** Track which domain flags are currently attached. */
  private readonly _attached: Set<number> = new Set();

  constructor(db: SqliteOpfsDb) {
    this._opfsDb = db;
  }

  /**
   * ATTACH the SQLite file for the given domain flag.
   * Creates the domain_cells schema in the attached DB.
   * If already attached, returns the alias without error (idempotent).
   *
   * @returns The alias name used for the attached schema.
   */
  async attachDomain(domainFlag: number): Promise<string> {
    if (this._attached.has(domainFlag)) {
      return domainAlias(domainFlag);
    }

    const alias = domainAlias(domainFlag);
    const uri = domainUri(domainFlag, this._opfsDb.storageMode);

    await this._opfsDb.exec(`ATTACH DATABASE '${uri}' AS ${alias}`);
    this._attached.add(domainFlag);

    // Create schema in the attached DB (run each statement separately)
    for (const ddl of domainCellsDdl(alias)) {
      await this._opfsDb.exec(ddl);
    }

    return alias;
  }

  /**
   * DETACH the SQLite file for the given domain flag.
   * No-op if not currently attached.
   */
  async detachDomain(domainFlag: number): Promise<void> {
    if (!this._attached.has(domainFlag)) return;

    const alias = domainAlias(domainFlag);
    await this._opfsDb.exec(`DETACH DATABASE ${alias}`);
    this._attached.delete(domainFlag);
  }

  /**
   * Returns true if the domain is currently attached.
   */
  isDomainAttached(domainFlag: number): boolean {
    return this._attached.has(domainFlag);
  }

  /**
   * Insert a cell into the domain's database.
   * Throws if the domain is not attached.
   * Throws on duplicate cell_hash (no overwrite).
   */
  async putCell(domainFlag: number, cellHash: Uint8Array, cellData: Uint8Array): Promise<void> {
    if (!this._attached.has(domainFlag)) {
      throw new Error(
        `Domain 0x${domainFlag.toString(16)} is not attached — call attachDomain() first`,
      );
    }

    const alias = domainAlias(domainFlag);
    const nowMs = Date.now();

    await this._opfsDb.exec(
      `INSERT INTO ${alias}.domain_cells (cell_hash, domain_flag, cell_data, created_at_ms)
       VALUES (?, ?, ?, ?)`,
      [cellHash, domainFlag, cellData, nowMs],
    );
  }

  /**
   * Read a cell from the domain's database.
   * Returns null if the domain is not attached or the cell is not found.
   */
  async getCell(domainFlag: number, cellHash: Uint8Array): Promise<Uint8Array | null> {
    if (!this._attached.has(domainFlag)) {
      return null;
    }

    const alias = domainAlias(domainFlag);

    interface CellRow {
      cell_data: Uint8Array | Buffer;
    }

    const rows = await this._opfsDb.query<CellRow>(
      `SELECT cell_data FROM ${alias}.domain_cells WHERE cell_hash = ?`,
      [cellHash],
    );

    if (rows.length === 0) return null;

    return toUint8Array(rows[0].cell_data);
  }

  /**
   * DETACHes the domain DB and returns a serialized (exported) byte array.
   * Simulates the "encrypt before storing" step.
   *
   * Uses sqlite3_js_db_export(db, alias) from the CAPI to extract the DB pages.
   */
  async detachAndSerialize(domainFlag: number): Promise<Uint8Array> {
    if (!this._attached.has(domainFlag)) {
      throw new Error(
        `Domain 0x${domainFlag.toString(16)} is not attached — call attachDomain() first`,
      );
    }

    const alias = domainAlias(domainFlag);

    // Export the attached schema's pages as a Uint8Array via CAPI.
    const sqlite3 = this._opfsDb.sqlite3;
    const rawDb = this._opfsDb.db;
    const bytes: Uint8Array = sqlite3.capi.sqlite3_js_db_export(rawDb, alias);

    // Copy so we own the buffer independently of WASM heap.
    const snapshot = new Uint8Array(bytes.byteLength);
    snapshot.set(bytes);

    // Now detach.
    await this._opfsDb.exec(`DETACH DATABASE ${alias}`);
    this._attached.delete(domainFlag);

    return snapshot;
  }

  /**
   * Re-ATTACHes a domain DB from previously serialized bytes.
   * Simulates the decrypt+reattach step.
   *
   * In memory mode: creates a fresh named in-memory DB from the bytes using
   * sqlite3_deserialize(), then ATTACHes it.
   *
   * In OPFS mode (production): would write the bytes back to OPFS then attach.
   * For now the in-memory path covers testing.
   */
  async reattachFromBytes(domainFlag: number, data: Uint8Array): Promise<void> {
    // If somehow still attached, detach first.
    if (this._attached.has(domainFlag)) {
      await this.detachDomain(domainFlag);
    }

    const alias = domainAlias(domainFlag);
    const uri = domainUri(domainFlag, this._opfsDb.storageMode);
    const sqlite3 = this._opfsDb.sqlite3;
    const rawDb = this._opfsDb.db;

    if (this._opfsDb.storageMode === "memory") {
      // For memory mode: first attach a fresh in-memory DB, then deserialize
      // the exported bytes into it using sqlite3_deserialize.
      //
      // sqlite3_deserialize signature:
      //   sqlite3_deserialize(db, schema, data_ptr, dbSize, bufSize, flags)
      //
      // We use sqlite3.wasm.allocFromTypedArray to copy our bytes into WASM heap.

      // Step 1: ATTACH a blank in-memory DB under the alias.
      await this._opfsDb.exec(`ATTACH DATABASE '${uri}' AS ${alias}`);

      // Step 2: Allocate a WASM buffer and copy the serialized bytes into it.
      const wasm = sqlite3.wasm;
      const dataPtr = wasm.allocFromTypedArray(data);

      try {
        // Step 3: sqlite3_deserialize — SQLITE_DESERIALIZE_FREEONCLOSE (1) |
        //         SQLITE_DESERIALIZE_RESIZEABLE (2) = 3.
        // Pass dbSize = bufSize = data.byteLength.
        const SQLITE_DESERIALIZE_FREEONCLOSE = 1;
        const SQLITE_DESERIALIZE_RESIZEABLE = 2;
        const flags = SQLITE_DESERIALIZE_FREEONCLOSE | SQLITE_DESERIALIZE_RESIZEABLE;

        const rc = sqlite3.capi.sqlite3_deserialize(
          rawDb,
          alias,
          dataPtr,
          data.byteLength,
          data.byteLength,
          flags,
        );

        if (rc !== 0) {
          throw new Error(`sqlite3_deserialize failed with code ${rc}`);
        }

        // dataPtr is now owned by sqlite3 (FREEONCLOSE), do not free it.
      } catch (err) {
        // Only free if deserialize never took ownership (non-FREEONCLOSE path).
        // Since we passed FREEONCLOSE, sqlite3 owns the buffer on success.
        // On error, we need to free it ourselves.
        wasm.dealloc(dataPtr);
        throw err;
      }

      this._attached.add(domainFlag);
    } else {
      // OPFS mode: write bytes to OPFS file then attach normally.
      // Use OpfsDatabase.importDb to overwrite the file, then attach.
      const filename = `/${alias}.sqlite`;
      const OpfsDb = sqlite3.oo1.OpfsDb as {
        importDb: (name: string, data: Uint8Array) => Promise<number>;
      };
      await OpfsDb.importDb(filename, data);
      await this._opfsDb.exec(`ATTACH DATABASE 'file:${alias}.sqlite?vfs=opfs' AS ${alias}`);
      this._attached.add(domainFlag);
    }
  }

  /**
   * Returns an array of the currently attached domain flag values.
   */
  listAttachedDomains(): number[] {
    return [...this._attached];
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Internal helpers
// ──────────────────────────────────────────────────────────────────────────────

function toUint8Array(v: Uint8Array | Buffer | null | undefined): Uint8Array {
  if (v == null) return new Uint8Array(0);
  if (v instanceof Uint8Array && !(v instanceof Buffer)) return v;
  return new Uint8Array((v as Buffer).buffer, (v as Buffer).byteOffset, (v as Buffer).byteLength);
}

```
