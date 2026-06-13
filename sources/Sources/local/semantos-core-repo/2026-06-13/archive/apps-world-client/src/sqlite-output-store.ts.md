---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-world-client/src/sqlite-output-store.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.823847+00:00
---

# archive/apps-world-client/src/sqlite-output-store.ts

```ts
// M2.3 — SqliteOutputStore: SQLite-backed UTXO store for the browser tier.
//
// Implements the same semantic contract as the Zig `LocalOutputStore` vtable
// (core/cell-engine/src/output_store.zig), backed by `SqliteOpfsDb`.
//
// Schema:
//   output_store (
//     txid                    BLOB NOT NULL,
//     vout                    INTEGER NOT NULL,
//     satoshis                INTEGER NOT NULL,
//     locking_script          BLOB NOT NULL,
//     derived_key_hash        BLOB NOT NULL,
//     derivation_protocol_hash BLOB NOT NULL,
//     derivation_counterparty BLOB NOT NULL,
//     derivation_index        INTEGER NOT NULL,
//     beef                    BLOB NOT NULL,
//     basket                  TEXT NOT NULL DEFAULT '',
//     tags                    TEXT NOT NULL DEFAULT '[]',
//     custom_instructions     BLOB NOT NULL DEFAULT X'',
//     confirmations           INTEGER NOT NULL DEFAULT 0,
//     status                  TEXT NOT NULL DEFAULT 'unspent',
//     spending_txid           BLOB NOT NULL DEFAULT X'0000...',
//     PRIMARY KEY (txid, vout)
//   )
//
// Mark-spent atomicity: executed inside an SQLite IMMEDIATE transaction.

import type { SqliteOpfsDb } from "./sqlite-opfs.js";

export type OutputStatus = "unspent" | "spent" | "reorged";

export interface Outpoint {
  txid: Uint8Array; // 32 bytes
  vout: number;
}

export interface OutputRecord {
  outpoint: Outpoint;
  satoshis: bigint;
  lockingScript: Uint8Array;
  derivedKeyHash: Uint8Array; // 32 bytes
  derivationProtocolHash: Uint8Array; // 16 bytes
  derivationCounterparty: Uint8Array; // 33 bytes
  derivationIndex: bigint;
  beef: Uint8Array;
  basket: string;
  tags: string[];
  customInstructions: Uint8Array;
  confirmations: number;
  status: OutputStatus;
  spendingTxid: Uint8Array; // 32 bytes
}

// ──────────────────────────────────────────────────────────────────────────────
// Raw DB row type (sqlite-wasm returns numbers for INTEGER, Buffer/Uint8Array for BLOB)
// ──────────────────────────────────────────────────────────────────────────────

interface OutputRow {
  txid: Uint8Array | Buffer;
  vout: number;
  satoshis: number | bigint;
  locking_script: Uint8Array | Buffer;
  derived_key_hash: Uint8Array | Buffer;
  derivation_protocol_hash: Uint8Array | Buffer;
  derivation_counterparty: Uint8Array | Buffer;
  derivation_index: number | bigint;
  beef: Uint8Array | Buffer;
  basket: string;
  tags: string;
  custom_instructions: Uint8Array | Buffer;
  confirmations: number;
  status: string;
  spending_txid: Uint8Array | Buffer;
}

// ──────────────────────────────────────────────────────────────────────────────
// SqliteOutputStore
// ──────────────────────────────────────────────────────────────────────────────

export class SqliteOutputStore {
  private readonly db: SqliteOpfsDb;

  constructor(db: SqliteOpfsDb) {
    this.db = db;
  }

  /** Create the table if it does not exist. Safe to call multiple times. */
  async init(): Promise<void> {
    await this.db.exec(`
      CREATE TABLE IF NOT EXISTS output_store (
        txid                     BLOB NOT NULL,
        vout                     INTEGER NOT NULL,
        satoshis                 INTEGER NOT NULL,
        locking_script           BLOB NOT NULL,
        derived_key_hash         BLOB NOT NULL,
        derivation_protocol_hash BLOB NOT NULL,
        derivation_counterparty  BLOB NOT NULL,
        derivation_index         INTEGER NOT NULL,
        beef                     BLOB NOT NULL,
        basket                   TEXT NOT NULL DEFAULT '',
        tags                     TEXT NOT NULL DEFAULT '[]',
        custom_instructions      BLOB NOT NULL DEFAULT X'00',
        confirmations            INTEGER NOT NULL DEFAULT 0,
        status                   TEXT NOT NULL DEFAULT 'unspent',
        spending_txid            BLOB NOT NULL,
        PRIMARY KEY (txid, vout)
      )
    `);
  }

  /**
   * Insert a fresh OutputRecord.
   * Throws 'duplicate_outpoint' if the outpoint already exists.
   */
  async addOutput(rec: OutputRecord): Promise<void> {
    const existing = await this.getOutput(rec.outpoint);
    if (existing !== null) {
      throw new Error("duplicate_outpoint");
    }

    await this.db.exec(
      `INSERT INTO output_store (
         txid, vout, satoshis, locking_script,
         derived_key_hash, derivation_protocol_hash, derivation_counterparty,
         derivation_index, beef, basket, tags, custom_instructions,
         confirmations, status, spending_txid
       ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        rec.outpoint.txid,
        rec.outpoint.vout,
        rec.satoshis,
        rec.lockingScript,
        rec.derivedKeyHash,
        rec.derivationProtocolHash,
        rec.derivationCounterparty,
        rec.derivationIndex,
        rec.beef,
        rec.basket,
        JSON.stringify(rec.tags),
        rec.customInstructions,
        rec.confirmations,
        rec.status,
        rec.spendingTxid,
      ],
    );
  }

  /**
   * Look up by outpoint. Returns null if not found.
   */
  async getOutput(outpoint: Outpoint): Promise<OutputRecord | null> {
    const rows = await this.db.query<OutputRow>(
      `SELECT * FROM output_store WHERE txid = ? AND vout = ?`,
      [outpoint.txid, outpoint.vout],
    );
    if (rows.length === 0) return null;
    return rowToRecord(rows[0]);
  }

  /**
   * List unspent outputs, optionally filtered by basket and/or tag.
   * basket = null → any basket; tag = null → any tags.
   */
  async listOutputs(basket: string | null, tag: string | null): Promise<OutputRecord[]> {
    let sql = `SELECT * FROM output_store WHERE status = 'unspent'`;
    const bind: unknown[] = [];

    if (basket !== null) {
      sql += ` AND basket = ?`;
      bind.push(basket);
    }

    const rows = await this.db.query<OutputRow>(sql, bind);
    let records = rows.map(rowToRecord);

    // Tag filter applied in TypeScript (tags stored as JSON array)
    if (tag !== null) {
      records = records.filter((r) => r.tags.includes(tag));
    }

    return records;
  }

  /**
   * Mark an output spent — sets status='spent', records spending_txid.
   * Uses an IMMEDIATE transaction for atomicity.
   * Throws 'unknown_outpoint' if not found.
   */
  async markSpent(outpoint: Outpoint, spendingTxid: Uint8Array): Promise<void> {
    const existing = await this.getOutput(outpoint);
    if (existing === null) {
      throw new Error("unknown_outpoint");
    }

    // IMMEDIATE transaction ensures atomicity even in concurrent contexts.
    await this.db.exec(`BEGIN IMMEDIATE`);
    try {
      await this.db.exec(
        `UPDATE output_store SET status = 'spent', spending_txid = ? WHERE txid = ? AND vout = ?`,
        [spendingTxid, outpoint.txid, outpoint.vout],
      );
      await this.db.exec(`COMMIT`);
    } catch (err) {
      await this.db.exec(`ROLLBACK`);
      throw err;
    }
  }

  /**
   * Drop BEEFs from records with confirmations >= min_confirmations.
   * Also fully delete rows where status='spent' AND confirmations >= 1000.
   * Returns the count of records modified (BEEFs dropped + rows deleted).
   */
  async pruneConfirmed(minConfirmations: number): Promise<number> {
    let pruned = 0;

    // 1. Drop BEEFs (set to empty) for records at or above threshold with non-empty beef
    const beefRows = await this.db.query<{ txid: Uint8Array | Buffer; vout: number }>(
      `SELECT txid, vout FROM output_store WHERE confirmations >= ? AND LENGTH(beef) > 0`,
      [minConfirmations],
    );
    for (const row of beefRows) {
      await this.db.exec(
        `UPDATE output_store SET beef = X'' WHERE txid = ? AND vout = ?`,
        [row.txid, row.vout],
      );
      pruned += 1;
    }

    // 2. Delete spent records with confirmations >= 1000
    const deleteCount = await this.db.query<{ n: number }>(
      `SELECT COUNT(*) AS n FROM output_store WHERE status = 'spent' AND confirmations >= 1000`,
    );
    const toDelete = deleteCount[0]?.n ?? 0;
    if (toDelete > 0) {
      await this.db.exec(
        `DELETE FROM output_store WHERE status = 'spent' AND confirmations >= 1000`,
      );
      pruned += toDelete;
    }

    return pruned;
  }

  /**
   * Return all records (for recovery/snapshot). Caller should not mutate the result.
   */
  async snapshot(): Promise<OutputRecord[]> {
    const rows = await this.db.query<OutputRow>(`SELECT * FROM output_store`);
    return rows.map(rowToRecord);
  }

  /**
   * Replace all store contents with the provided records (does not merge).
   */
  async replay(records: OutputRecord[]): Promise<void> {
    await this.db.exec(`DELETE FROM output_store`);
    for (const rec of records) {
      await this.addOutput(rec);
    }
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Internal helpers
// ──────────────────────────────────────────────────────────────────────────────

function toUint8Array(v: Uint8Array | Buffer | null | undefined): Uint8Array {
  if (v == null) return new Uint8Array(0);
  if (v instanceof Uint8Array && !(v instanceof Buffer)) return v;
  // Node Buffer is a Uint8Array subclass — copy to plain Uint8Array
  return new Uint8Array((v as Buffer).buffer, (v as Buffer).byteOffset, (v as Buffer).byteLength);
}

function rowToRecord(row: OutputRow): OutputRecord {
  let tags: string[] = [];
  try {
    tags = JSON.parse(row.tags ?? "[]");
  } catch {
    tags = [];
  }

  return {
    outpoint: {
      txid: toUint8Array(row.txid as Uint8Array | Buffer),
      vout: row.vout,
    },
    satoshis: BigInt(row.satoshis),
    lockingScript: toUint8Array(row.locking_script as Uint8Array | Buffer),
    derivedKeyHash: toUint8Array(row.derived_key_hash as Uint8Array | Buffer),
    derivationProtocolHash: toUint8Array(row.derivation_protocol_hash as Uint8Array | Buffer),
    derivationCounterparty: toUint8Array(row.derivation_counterparty as Uint8Array | Buffer),
    derivationIndex: BigInt(row.derivation_index),
    beef: toUint8Array(row.beef as Uint8Array | Buffer),
    basket: row.basket,
    tags,
    customInstructions: toUint8Array(row.custom_instructions as Uint8Array | Buffer),
    confirmations: row.confirmations,
    status: row.status as OutputStatus,
    spendingTxid: toUint8Array(row.spending_txid as Uint8Array | Buffer),
  };
}

```
