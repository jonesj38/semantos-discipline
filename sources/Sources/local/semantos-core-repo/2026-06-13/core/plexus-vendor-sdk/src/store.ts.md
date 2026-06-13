---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/plexus-vendor-sdk/src/store.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.018751+00:00
---

# core/plexus-vendor-sdk/src/store.ts

```ts
/**
 * SQLite persistence layer for the Plexus DAG.
 *
 * Uses bun:sqlite for zero-dep embedded database.
 * Tables: certificates, edges, recovery_sessions, child_counters.
 */

import { Database } from 'bun:sqlite';

export interface CertRow {
  cert_id: string;
  parent_cert_id: string | null;
  email: string | null;
  public_key: string;
  child_index: number;
  resource_id: string | null;
  domain_flag: number | null;
  derivation_path: string;
  created_at: number;
  /**
   * KDF algorithm version for this tree (set on the root cert; NULL on legacy
   * rows ⇒ treated as 'plexus-kdf-v1'). See crypto.ts `KdfVersion`.
   */
  kdf_version?: string | null;
}

export interface EdgeRow {
  edge_id: string;
  initiator_cert_id: string;
  responder_cert_id: string;
  shared_secret_hash: string;
  created_at: number;
}

export interface RecoveryRow {
  session_id: string;
  email: string;
  challenges_json: string;
  answer_hashes_json: string;
  status: string;
}

export class PlexusStore {
  private db: Database;

  constructor(dbPath?: string) {
    this.db = new Database(dbPath ?? ':memory:');
    this.db.exec('PRAGMA journal_mode=WAL');
    this.createTables();
    this.migrate();
  }

  private createTables(): void {
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS certificates (
        cert_id TEXT PRIMARY KEY,
        parent_cert_id TEXT,
        email TEXT,
        public_key TEXT NOT NULL,
        child_index INTEGER NOT NULL DEFAULT -1,
        resource_id TEXT,
        domain_flag INTEGER,
        derivation_path TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        kdf_version TEXT
      );

      CREATE TABLE IF NOT EXISTS child_counters (
        parent_cert_id TEXT NOT NULL,
        next_index INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (parent_cert_id)
      );

      CREATE TABLE IF NOT EXISTS edges (
        edge_id TEXT PRIMARY KEY,
        initiator_cert_id TEXT NOT NULL,
        responder_cert_id TEXT NOT NULL,
        shared_secret_hash TEXT NOT NULL,
        created_at INTEGER NOT NULL
      );

      CREATE TABLE IF NOT EXISTS recovery_sessions (
        session_id TEXT PRIMARY KEY,
        email TEXT NOT NULL,
        challenges_json TEXT NOT NULL,
        answer_hashes_json TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending'
      );
    `);
  }

  /**
   * Additive migrations for databases created before a column existed.
   * `CREATE TABLE IF NOT EXISTS` never alters an existing table, so columns
   * added after first ship must be back-filled here. Legacy rows keep NULL.
   */
  private migrate(): void {
    const cols = this.db.prepare('PRAGMA table_info(certificates)').all() as Array<{ name: string }>;
    if (!cols.some(c => c.name === 'kdf_version')) {
      this.db.exec('ALTER TABLE certificates ADD COLUMN kdf_version TEXT');
    }
  }

  insertCertificate(row: CertRow): void {
    this.db.prepare(`
      INSERT OR REPLACE INTO certificates
        (cert_id, parent_cert_id, email, public_key, child_index, resource_id, domain_flag, derivation_path, created_at, kdf_version)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      row.cert_id, row.parent_cert_id, row.email, row.public_key,
      row.child_index, row.resource_id, row.domain_flag, row.derivation_path, row.created_at,
      row.kdf_version ?? null,
    );
  }

  getCertificate(certId: string): CertRow | null {
    return this.db.prepare('SELECT * FROM certificates WHERE cert_id = ?').get(certId) as CertRow | null;
  }

  getChildren(parentCertId: string): CertRow[] {
    return this.db.prepare(
      'SELECT * FROM certificates WHERE parent_cert_id = ? ORDER BY child_index',
    ).all(parentCertId) as CertRow[];
  }

  getNextChildIndex(parentCertId: string): number {
    const row = this.db.prepare(
      'SELECT next_index FROM child_counters WHERE parent_cert_id = ?',
    ).get(parentCertId) as { next_index: number } | null;
    return row?.next_index ?? 0;
  }

  incrementChildIndex(parentCertId: string): number {
    const current = this.getNextChildIndex(parentCertId);
    this.db.prepare(`
      INSERT INTO child_counters (parent_cert_id, next_index)
      VALUES (?, ?)
      ON CONFLICT(parent_cert_id) DO UPDATE SET next_index = ?
    `).run(parentCertId, current + 1, current + 1);
    return current;
  }

  insertEdge(row: EdgeRow): void {
    this.db.prepare(`
      INSERT OR REPLACE INTO edges
        (edge_id, initiator_cert_id, responder_cert_id, shared_secret_hash, created_at)
      VALUES (?, ?, ?, ?, ?)
    `).run(row.edge_id, row.initiator_cert_id, row.responder_cert_id, row.shared_secret_hash, row.created_at);
  }

  getEdge(edgeId: string): EdgeRow | null {
    return this.db.prepare('SELECT * FROM edges WHERE edge_id = ?').get(edgeId) as EdgeRow | null;
  }

  insertRecoverySession(row: RecoveryRow): void {
    this.db.prepare(`
      INSERT OR REPLACE INTO recovery_sessions
        (session_id, email, challenges_json, answer_hashes_json, status)
      VALUES (?, ?, ?, ?, ?)
    `).run(row.session_id, row.email, row.challenges_json, row.answer_hashes_json, row.status);
  }

  getRecoverySession(sessionId: string): RecoveryRow | null {
    return this.db.prepare('SELECT * FROM recovery_sessions WHERE session_id = ?').get(sessionId) as RecoveryRow | null;
  }

  updateRecoveryStatus(sessionId: string, status: string): void {
    this.db.prepare('UPDATE recovery_sessions SET status = ? WHERE session_id = ?').run(status, sessionId);
  }

  /** Find the root certificate for a given email. */
  getRootByEmail(email: string): CertRow | null {
    return this.db.prepare(
      'SELECT * FROM certificates WHERE email = ? AND parent_cert_id IS NULL',
    ).get(email) as CertRow | null;
  }

  close(): void {
    this.db.close();
  }
}

```
