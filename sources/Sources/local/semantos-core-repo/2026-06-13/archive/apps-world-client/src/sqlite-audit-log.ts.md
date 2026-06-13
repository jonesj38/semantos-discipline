---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-world-client/src/sqlite-audit-log.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.817487+00:00
---

# archive/apps-world-client/src/sqlite-audit-log.ts

```ts
// M2.5 — SqliteAuditLog: append-only SQLite audit log for BRC-100 envelope history.
//
// Backed by `SqliteOpfsDb` (OPFS in production, in-memory in Node tests).
//
// Schema (two tables):
//
//   audit_log (
//     id            INTEGER PRIMARY KEY AUTOINCREMENT,
//     cert_id       BLOB NOT NULL,
//     nonce         BLOB NOT NULL,         -- 8 bytes
//     envelope_hash BLOB NOT NULL,         -- 32 bytes
//     payload_type  TEXT NOT NULL,
//     payload_hash  BLOB NOT NULL,         -- 32 bytes
//     created_at_ms INTEGER NOT NULL,
//     signature     BLOB NOT NULL,
//     UNIQUE(cert_id, nonce)               -- nonce uniqueness per sender
//   )
//   INDEX audit_log_cert_id ON audit_log(cert_id)
//   INDEX audit_log_created ON audit_log(created_at_ms)
//
//   nonce_replay_cache (
//     cert_id    BLOB NOT NULL,
//     nonce      BLOB NOT NULL,
//     expires_at_ms INTEGER NOT NULL,
//     PRIMARY KEY (cert_id, nonce)
//   )
//
// Append-only guarantee: no UPDATE or DELETE methods are exposed.
// pruneExpiredNonces is the sole write path that removes rows — only
// from nonce_replay_cache (a TTL index, not the immutable audit log).

import type { SqliteOpfsDb } from "./sqlite-opfs.js";

// ──────────────────────────────────────────────────────────────────────────────
// Public types
// ──────────────────────────────────────────────────────────────────────────────

export interface AuditEntry {
  certId: Uint8Array;       // 32 bytes
  nonce: Uint8Array;        // 8 bytes
  envelopeHash: Uint8Array; // 32 bytes
  payloadType: string;
  payloadHash: Uint8Array;  // 32 bytes
  createdAtMs: bigint;
  signature: Uint8Array;
}

/** Nonce replay-cache TTL: 5 minutes. */
export const TTL_MS = 300_000;

// ──────────────────────────────────────────────────────────────────────────────
// Internal DB row type
// ──────────────────────────────────────────────────────────────────────────────

interface AuditRow {
  cert_id: Uint8Array | Buffer;
  nonce: Uint8Array | Buffer;
  envelope_hash: Uint8Array | Buffer;
  payload_type: string;
  payload_hash: Uint8Array | Buffer;
  created_at_ms: number | bigint;
  signature: Uint8Array | Buffer;
}

// ──────────────────────────────────────────────────────────────────────────────
// SqliteAuditLog
// ──────────────────────────────────────────────────────────────────────────────

export class SqliteAuditLog {
  private readonly db: SqliteOpfsDb;

  constructor(db: SqliteOpfsDb) {
    this.db = db;
  }

  /** Create tables and indexes if they do not exist. Safe to call multiple times. */
  async init(): Promise<void> {
    await this.db.exec(`
      CREATE TABLE IF NOT EXISTS audit_log (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        cert_id       BLOB NOT NULL,
        nonce         BLOB NOT NULL,
        envelope_hash BLOB NOT NULL,
        payload_type  TEXT NOT NULL,
        payload_hash  BLOB NOT NULL,
        created_at_ms INTEGER NOT NULL,
        signature     BLOB NOT NULL,
        UNIQUE(cert_id, nonce)
      )
    `);
    await this.db.exec(
      `CREATE INDEX IF NOT EXISTS audit_log_cert_id ON audit_log(cert_id)`,
    );
    await this.db.exec(
      `CREATE INDEX IF NOT EXISTS audit_log_created ON audit_log(created_at_ms)`,
    );
    await this.db.exec(`
      CREATE TABLE IF NOT EXISTS nonce_replay_cache (
        cert_id       BLOB NOT NULL,
        nonce         BLOB NOT NULL,
        expires_at_ms INTEGER NOT NULL,
        PRIMARY KEY (cert_id, nonce)
      )
    `);
  }

  /**
   * Append a BRC-100 envelope entry to the audit log.
   *
   * Throws 'duplicate_nonce' if the (cert_id, nonce) pair is present in the
   * nonce_replay_cache (i.e. within its TTL window).
   *
   * On success:
   *   - Inserts the entry into audit_log (UNIQUE constraint provides a hard
   *     permanent uniqueness guarantee for the cert_id+nonce pair).
   *   - Upserts a row into nonce_replay_cache with
   *     expires_at_ms = createdAtMs + TTL_MS.
   */
  async append(entry: AuditEntry): Promise<void> {
    // Check replay cache first — this is the TTL-bounded uniqueness gate.
    const cached = await this.db.query<{ expires_at_ms: number | bigint }>(
      `SELECT expires_at_ms FROM nonce_replay_cache WHERE cert_id = ? AND nonce = ?`,
      [entry.certId, entry.nonce],
    );
    if (cached.length > 0) {
      throw new Error("duplicate_nonce");
    }

    // Insert into audit_log. UNIQUE(cert_id, nonce) provides permanent protection
    // after TTL expiry (so the same cert_id+nonce can never be re-inserted even if
    // the cache row has been pruned — matching audit integrity semantics).
    try {
      await this.db.exec(
        `INSERT INTO audit_log
           (cert_id, nonce, envelope_hash, payload_type, payload_hash, created_at_ms, signature)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
        [
          entry.certId,
          entry.nonce,
          entry.envelopeHash,
          entry.payloadType,
          entry.payloadHash,
          entry.createdAtMs,
          entry.signature,
        ],
      );
    } catch (err: unknown) {
      // sqlite-wasm surfaces UNIQUE violations as errors containing "UNIQUE constraint failed"
      const msg = err instanceof Error ? err.message : String(err);
      if (msg.includes("UNIQUE")) {
        throw new Error("duplicate_nonce");
      }
      throw err;
    }

    // Write replay-cache entry with TTL.
    const expiresAtMs = entry.createdAtMs + BigInt(TTL_MS);
    await this.db.exec(
      `INSERT INTO nonce_replay_cache (cert_id, nonce, expires_at_ms)
       VALUES (?, ?, ?)
       ON CONFLICT(cert_id, nonce) DO UPDATE SET expires_at_ms = excluded.expires_at_ms`,
      [entry.certId, entry.nonce, expiresAtMs],
    );
  }

  /**
   * Return audit entries for the given cert_id, most-recent first.
   *
   * @param certId  32-byte certificate ID to filter by.
   * @param limit   Maximum number of records to return.
   * @param beforeMs  If provided, only records with created_at_ms < beforeMs
   *                  are included (pagination cursor).
   */
  async getHistory(
    certId: Uint8Array,
    limit: number,
    beforeMs?: bigint,
  ): Promise<AuditEntry[]> {
    let sql: string;
    let bind: unknown[];

    if (beforeMs !== undefined) {
      sql = `
        SELECT cert_id, nonce, envelope_hash, payload_type, payload_hash,
               created_at_ms, signature
        FROM audit_log
        WHERE cert_id = ? AND created_at_ms < ?
        ORDER BY created_at_ms DESC
        LIMIT ?
      `;
      bind = [certId, beforeMs, limit];
    } else {
      sql = `
        SELECT cert_id, nonce, envelope_hash, payload_type, payload_hash,
               created_at_ms, signature
        FROM audit_log
        WHERE cert_id = ?
        ORDER BY created_at_ms DESC
        LIMIT ?
      `;
      bind = [certId, limit];
    }

    const rows = await this.db.query<AuditRow>(sql, bind);
    return rows.map(rowToEntry);
  }

  /**
   * Remove nonce_replay_cache rows where expires_at_ms < nowMs.
   *
   * Returns the number of rows pruned.
   */
  async pruneExpiredNonces(nowMs: number): Promise<number> {
    const countRows = await this.db.query<{ n: number }>(
      `SELECT COUNT(*) AS n FROM nonce_replay_cache WHERE expires_at_ms < ?`,
      [nowMs],
    );
    const count = countRows[0]?.n ?? 0;
    if (count > 0) {
      await this.db.exec(
        `DELETE FROM nonce_replay_cache WHERE expires_at_ms < ?`,
        [nowMs],
      );
    }
    return count;
  }

  /**
   * Return the total number of records in audit_log.
   */
  async count(): Promise<number> {
    const rows = await this.db.query<{ n: number }>(
      `SELECT COUNT(*) AS n FROM audit_log`,
    );
    return rows[0]?.n ?? 0;
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

function rowToEntry(row: AuditRow): AuditEntry {
  return {
    certId: toUint8Array(row.cert_id as Uint8Array | Buffer),
    nonce: toUint8Array(row.nonce as Uint8Array | Buffer),
    envelopeHash: toUint8Array(row.envelope_hash as Uint8Array | Buffer),
    payloadType: row.payload_type,
    payloadHash: toUint8Array(row.payload_hash as Uint8Array | Buffer),
    createdAtMs: BigInt(row.created_at_ms),
    signature: toUint8Array(row.signature as Uint8Array | Buffer),
  };
}

```
