---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-world-client/src/sqlite-pask-snapshot-store.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.818590+00:00
---

# archive/apps-world-client/src/sqlite-pask-snapshot-store.ts

```ts
// M2.8 — SqlitePaskSnapshotStore: SQLite-backed Pask snapshot store for the browser tier.
//
// Implements the same vtable contract as the Zig `LmdbPaskSnapshotStore`
// (runtime/semantos-brain/src/lmdb/pask_snapshot_store_lmdb.zig), backed by `SqliteOpfsDb`.
// Uses OPFS in production, in-memory fallback in tests/Node.
//
// Schema (two tables, mirroring the LMDB two-DB design):
//
//   pask_snapshots (
//     cert_id  BLOB NOT NULL,
//     version  INTEGER NOT NULL,
//     data     BLOB NOT NULL,
//     PRIMARY KEY (cert_id, version)
//   )
//
//   pask_snapshot_current (
//     cert_id  BLOB PRIMARY KEY,
//     version  INTEGER NOT NULL
//   )
//
// Pask snapshot binary format:
//   bytes 0–3  : magic  0x4B534150 ("PASK") big-endian u32
//   bytes 4–7  : length big-endian u32, equals data.byteLength
//   bytes 8+   : snapshot content
//
// magic_ok is true iff bytes 0–3 == [0x4B, 0x53, 0x41, 0x50]
//   AND the length field equals data.byteLength.

import type { SqliteOpfsDb } from "./sqlite-opfs.js";

// ──────────────────────────────────────────────────────────────────────────────
// Public types (mirror the Zig SnapshotMeta struct)
// ──────────────────────────────────────────────────────────────────────────────

export interface SnapshotMeta {
  version: bigint;
  size: number;
  magic_ok: boolean;
}

// ──────────────────────────────────────────────────────────────────────────────
// Internal DB row types
// ──────────────────────────────────────────────────────────────────────────────

interface SnapshotRow {
  cert_id: Uint8Array | Buffer;
  version: number | bigint;
  data: Uint8Array | Buffer;
}

interface CurrentRow {
  version: number | bigint;
}

// ──────────────────────────────────────────────────────────────────────────────
// Constants
// ──────────────────────────────────────────────────────────────────────────────

const MAGIC = [0x4b, 0x53, 0x41, 0x50] as const;
const MAGIC_OFFSET = 0;
const LENGTH_OFFSET = 4;
const HEADER_SIZE = 8;

// ──────────────────────────────────────────────────────────────────────────────
// SqlitePaskSnapshotStore
// ──────────────────────────────────────────────────────────────────────────────

export class SqlitePaskSnapshotStore {
  private readonly db: SqliteOpfsDb;

  constructor(db: SqliteOpfsDb) {
    this.db = db;
  }

  /** Create tables if they do not exist. Safe to call multiple times. */
  async init(): Promise<void> {
    await this.db.exec(`
      CREATE TABLE IF NOT EXISTS pask_snapshots (
        cert_id BLOB NOT NULL,
        version INTEGER NOT NULL,
        data    BLOB NOT NULL,
        PRIMARY KEY (cert_id, version)
      )
    `);
    await this.db.exec(`
      CREATE TABLE IF NOT EXISTS pask_snapshot_current (
        cert_id BLOB PRIMARY KEY,
        version INTEGER NOT NULL
      )
    `);
  }

  /**
   * Load the current (latest) snapshot for cert_id into out.
   *
   * Returns SnapshotMeta describing the snapshot, or null if no snapshot exists.
   * Copies data into `out` (caller must provide a buffer at least as large as
   * the stored data; excess bytes are left untouched).
   */
  async loadCurrent(certId: Uint8Array, out: Uint8Array): Promise<SnapshotMeta | null> {
    // Lookup current version pointer
    const currentRows = await this.db.query<CurrentRow>(
      `SELECT version FROM pask_snapshot_current WHERE cert_id = ?`,
      [certId],
    );
    if (currentRows.length === 0) return null;

    const version = BigInt(currentRows[0].version);

    // Load the snapshot data for this version
    const snapRows = await this.db.query<SnapshotRow>(
      `SELECT data FROM pask_snapshots WHERE cert_id = ? AND version = ?`,
      [certId, version],
    );
    if (snapRows.length === 0) return null;

    const data = toUint8Array(snapRows[0].data);

    // Copy into caller-supplied buffer
    out.set(data.subarray(0, out.byteLength));

    return buildMeta(version, data);
  }

  /**
   * Commit a new snapshot for cert_id.
   *
   * Validates:
   *   - magic bytes 0–3 == [0x4B, 0x53, 0x41, 0x50]  → throws 'invalid_magic'
   *   - length field (bytes 4–7 BE u32) == data.byteLength  → throws 'invalid_length'
   *
   * Returns the new version number (1-indexed, monotone increasing per cert_id).
   */
  async commitSnapshot(certId: Uint8Array, data: Uint8Array): Promise<bigint> {
    validateSnapshot(data);

    // Compute next version
    const currentRows = await this.db.query<CurrentRow>(
      `SELECT version FROM pask_snapshot_current WHERE cert_id = ?`,
      [certId],
    );
    const nextVersion =
      currentRows.length === 0 ? 1n : BigInt(currentRows[0].version) + 1n;

    // Insert snapshot row
    await this.db.exec(
      `INSERT INTO pask_snapshots (cert_id, version, data) VALUES (?, ?, ?)`,
      [certId, nextVersion, data],
    );

    // Upsert current pointer
    await this.db.exec(
      `INSERT INTO pask_snapshot_current (cert_id, version)
       VALUES (?, ?)
       ON CONFLICT(cert_id) DO UPDATE SET version = excluded.version`,
      [certId, nextVersion],
    );

    return nextVersion;
  }

  /**
   * Roll back to a specific version.
   *
   * Deletes all snapshot rows with version > target and updates the current
   * pointer to target. If target >= current (rolling forward into the future),
   * the call is a no-op — existing snapshots are left intact.
   */
  async rollbackTo(certId: Uint8Array, version: bigint): Promise<void> {
    // Look up the current version
    const currentRows = await this.db.query<CurrentRow>(
      `SELECT version FROM pask_snapshot_current WHERE cert_id = ?`,
      [certId],
    );
    if (currentRows.length === 0) return; // nothing to roll back

    const current = BigInt(currentRows[0].version);

    // Rolling forward (target > current) is a no-op
    if (version >= current) return;

    // Verify the target version actually exists
    const targetRows = await this.db.query<{ n: number }>(
      `SELECT COUNT(*) AS n FROM pask_snapshots WHERE cert_id = ? AND version = ?`,
      [certId, version],
    );
    if ((targetRows[0]?.n ?? 0) === 0) {
      // Target doesn't exist — leave state intact (spec says "leaves v1 intact")
      return;
    }

    // Delete rows newer than the target
    await this.db.exec(
      `DELETE FROM pask_snapshots WHERE cert_id = ? AND version > ?`,
      [certId, version],
    );

    // Update current pointer
    await this.db.exec(
      `UPDATE pask_snapshot_current SET version = ? WHERE cert_id = ?`,
      [version, certId],
    );
  }

  /**
   * Return snapshot history for cert_id, most-recent first, up to limit entries.
   *
   * Each entry is a SnapshotMeta (no data blob). Returns an empty array if no
   * snapshots exist for cert_id.
   */
  async snapshotHistory(certId: Uint8Array, limit: number): Promise<SnapshotMeta[]> {
    const rows = await this.db.query<{ version: number | bigint; data: Uint8Array | Buffer }>(
      `SELECT version, data FROM pask_snapshots
       WHERE cert_id = ?
       ORDER BY version DESC
       LIMIT ?`,
      [certId, limit],
    );

    return rows.map((row) => {
      const data = toUint8Array(row.data);
      return buildMeta(BigInt(row.version), data);
    });
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

/**
 * Validate Pask snapshot magic and length field.
 * Throws 'invalid_magic' or 'invalid_length' on failure.
 */
function validateSnapshot(data: Uint8Array): void {
  if (
    data.length < HEADER_SIZE ||
    data[MAGIC_OFFSET] !== MAGIC[0] ||
    data[MAGIC_OFFSET + 1] !== MAGIC[1] ||
    data[MAGIC_OFFSET + 2] !== MAGIC[2] ||
    data[MAGIC_OFFSET + 3] !== MAGIC[3]
  ) {
    throw new Error("invalid_magic");
  }

  const view = new DataView(data.buffer, data.byteOffset, data.byteLength);
  const declared = view.getUint32(LENGTH_OFFSET, false /* big-endian */);
  if (declared !== data.byteLength) {
    throw new Error("invalid_length");
  }
}

/**
 * Check if data has valid magic bytes and matching length field.
 * Same logic as validateSnapshot but returns boolean instead of throwing.
 */
function checkMagicOk(data: Uint8Array): boolean {
  if (data.length < HEADER_SIZE) return false;
  if (
    data[MAGIC_OFFSET] !== MAGIC[0] ||
    data[MAGIC_OFFSET + 1] !== MAGIC[1] ||
    data[MAGIC_OFFSET + 2] !== MAGIC[2] ||
    data[MAGIC_OFFSET + 3] !== MAGIC[3]
  ) {
    return false;
  }
  const view = new DataView(data.buffer, data.byteOffset, data.byteLength);
  const declared = view.getUint32(LENGTH_OFFSET, false);
  return declared === data.byteLength;
}

function buildMeta(version: bigint, data: Uint8Array): SnapshotMeta {
  return {
    version,
    size: data.byteLength,
    magic_ok: checkMagicOk(data),
  };
}

```
