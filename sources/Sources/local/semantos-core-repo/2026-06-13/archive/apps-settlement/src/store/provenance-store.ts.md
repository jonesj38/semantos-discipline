---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-settlement/src/store/provenance-store.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.711575+00:00
---

# archive/apps-settlement/src/store/provenance-store.ts

```ts
/**
 * ProvenanceStore — SQLite persistence for the Border Router settlement layer.
 *
 * Follows the PaskianStore pattern (bun:sqlite, WAL mode, prepared statements).
 * Stores cells, batches, Merkle proofs, and anchor records.
 *
 * Tables:
 *   cells         — validated cells received from multicast
 *   batches       — time-windowed batch aggregations
 *   merkle_proofs — per-cell Merkle proofs within a batch
 *   anchors       — BSV anchor transaction records
 *   dedup_log     — content-hash deduplication window
 *
 * Cross-references:
 *   packages/paskian/src/store.ts — PaskianStore (same pattern)
 *   packages/cell-ops/src/merkleEnvelope.ts — Merkle proof format
 */

import { Database } from 'bun:sqlite';

import type { CollectedCell, CellBatch, MerkleAnchor } from '../services/border-router-types';

// ── Row types (SQLite shapes) ────────────────────────────────────────

interface CellRow {
  cell_id: string;
  cell_bytes: Uint8Array;
  semantic_path: string;
  content_hash: Uint8Array;
  source_addr: string;
  received_at: number;
  linearity: number;
  batch_id: string | null;
}

interface BatchRow {
  batch_id: string;
  cell_count: number;
  opened_at: number;
  closed_at: number;
  merkle_root: Uint8Array | null;
  status: string;
}

interface MerkleProofRow {
  cell_id: string;
  batch_id: string;
  proof_blob: Uint8Array;
  leaf_index: number;
}

interface AnchorRow {
  batch_id: string;
  merkle_root: Uint8Array;
  txid: string | null;
  anchor_payload: string | null;
  submitted_at: number | null;
  confirmed_at: number | null;
  status: string;
  error: string | null;
}

interface DedupRow {
  content_hash_hex: string;
  first_seen_at: number;
  seen_count: number;
}

interface StatsResult {
  total_cells: number;
  total_batches: number;
  total_anchored: number;
  unique_players: number;
}

// ── Store ────────────────────────────────────────────────────────────

export class ProvenanceStore {
  private db: Database;

  constructor(dbPath?: string) {
    this.db = new Database(dbPath ?? ':memory:');
    this.db.exec('PRAGMA journal_mode=WAL');
    this.createTables();
  }

  private createTables(): void {
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS cells (
        cell_id         TEXT PRIMARY KEY,
        cell_bytes      BLOB NOT NULL,
        semantic_path   TEXT NOT NULL,
        content_hash    BLOB NOT NULL,
        source_addr     TEXT NOT NULL DEFAULT '',
        received_at     INTEGER NOT NULL,
        linearity       INTEGER NOT NULL DEFAULT 1,
        batch_id        TEXT
      );
      CREATE INDEX IF NOT EXISTS idx_cells_batch ON cells(batch_id);
      CREATE INDEX IF NOT EXISTS idx_cells_received ON cells(received_at);
      CREATE INDEX IF NOT EXISTS idx_cells_semantic ON cells(semantic_path);

      CREATE TABLE IF NOT EXISTS batches (
        batch_id        TEXT PRIMARY KEY,
        cell_count      INTEGER NOT NULL DEFAULT 0,
        opened_at       INTEGER NOT NULL,
        closed_at       INTEGER NOT NULL DEFAULT 0,
        merkle_root     BLOB,
        status          TEXT NOT NULL DEFAULT 'open'
                        CHECK(status IN ('open','closed','anchored','failed'))
      );
      CREATE INDEX IF NOT EXISTS idx_batches_status ON batches(status);

      CREATE TABLE IF NOT EXISTS merkle_proofs (
        cell_id         TEXT NOT NULL,
        batch_id        TEXT NOT NULL,
        proof_blob      BLOB NOT NULL,
        leaf_index      INTEGER NOT NULL,
        PRIMARY KEY(cell_id, batch_id)
      );

      CREATE TABLE IF NOT EXISTS anchors (
        batch_id        TEXT PRIMARY KEY,
        merkle_root     BLOB NOT NULL,
        txid            TEXT,
        anchor_payload  TEXT,
        submitted_at    INTEGER,
        confirmed_at    INTEGER,
        status          TEXT NOT NULL DEFAULT 'pending'
                        CHECK(status IN ('pending','submitted','confirmed','failed')),
        error           TEXT
      );
      CREATE INDEX IF NOT EXISTS idx_anchors_status ON anchors(status);
      CREATE INDEX IF NOT EXISTS idx_anchors_txid ON anchors(txid);

      CREATE TABLE IF NOT EXISTS dedup_log (
        content_hash_hex TEXT PRIMARY KEY,
        first_seen_at    INTEGER NOT NULL,
        seen_count       INTEGER NOT NULL DEFAULT 1
      );
    `);
  }

  // ── Cell operations ────────────────────────────────────────────────

  insertCell(cell: CollectedCell, batchId?: string): void {
    this.db.prepare(`
      INSERT OR IGNORE INTO cells
        (cell_id, cell_bytes, semantic_path, content_hash, source_addr, received_at, linearity, batch_id)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      cell.cellId,
      cell.cellBytes,
      cell.semanticPath,
      cell.contentHash,
      cell.sourceAddr,
      cell.receivedAt,
      cell.linearity,
      batchId ?? null,
    );
  }

  getCell(cellId: string): CollectedCell | null {
    const row = this.db.prepare(
      'SELECT * FROM cells WHERE cell_id = ?',
    ).get(cellId) as CellRow | null;
    return row ? this.rowToCell(row) : null;
  }

  getCellsByBatch(batchId: string): CollectedCell[] {
    const rows = this.db.prepare(
      'SELECT * FROM cells WHERE batch_id = ? ORDER BY received_at',
    ).all(batchId) as CellRow[];
    return rows.map(r => this.rowToCell(r));
  }

  assignCellsToBatch(cellIds: string[], batchId: string): void {
    const stmt = this.db.prepare(
      'UPDATE cells SET batch_id = ? WHERE cell_id = ?',
    );
    const txn = this.db.transaction(() => {
      for (const cellId of cellIds) {
        stmt.run(batchId, cellId);
      }
    });
    txn();
  }

  getRecentCells(limit: number = 50, offset: number = 0): CollectedCell[] {
    const rows = this.db.prepare(
      'SELECT * FROM cells ORDER BY received_at DESC LIMIT ? OFFSET ?',
    ).all(limit, offset) as CellRow[];
    return rows.map(r => this.rowToCell(r));
  }

  // ── Dedup operations ───────────────────────────────────────────────

  isDuplicate(contentHashHex: string): boolean {
    const row = this.db.prepare(
      'SELECT seen_count FROM dedup_log WHERE content_hash_hex = ?',
    ).get(contentHashHex) as DedupRow | null;
    if (row) {
      this.db.prepare(
        'UPDATE dedup_log SET seen_count = seen_count + 1 WHERE content_hash_hex = ?',
      ).run(contentHashHex);
      return true;
    }
    return false;
  }

  markSeen(contentHashHex: string): void {
    this.db.prepare(`
      INSERT OR IGNORE INTO dedup_log (content_hash_hex, first_seen_at, seen_count)
      VALUES (?, ?, 1)
    `).run(contentHashHex, Date.now());
  }

  pruneDedup(windowMs: number): number {
    const cutoff = Date.now() - windowMs;
    const result = this.db.prepare(
      'DELETE FROM dedup_log WHERE first_seen_at < ?',
    ).run(cutoff);
    return result.changes;
  }

  // ── Batch operations ───────────────────────────────────────────────

  createBatch(batchId: string, openedAt: number): void {
    this.db.prepare(`
      INSERT INTO batches (batch_id, opened_at, status)
      VALUES (?, ?, 'open')
    `).run(batchId, openedAt);
  }

  closeBatch(batchId: string, closedAt: number, cellCount: number): void {
    this.db.prepare(`
      UPDATE batches SET closed_at = ?, cell_count = ?, status = 'closed'
      WHERE batch_id = ?
    `).run(closedAt, cellCount, batchId);
  }

  setBatchMerkleRoot(batchId: string, merkleRoot: Buffer): void {
    this.db.prepare(`
      UPDATE batches SET merkle_root = ? WHERE batch_id = ?
    `).run(merkleRoot, batchId);
  }

  setBatchAnchored(batchId: string): void {
    this.db.prepare(`
      UPDATE batches SET status = 'anchored' WHERE batch_id = ?
    `).run(batchId);
  }

  setBatchFailed(batchId: string): void {
    this.db.prepare(`
      UPDATE batches SET status = 'failed' WHERE batch_id = ?
    `).run(batchId);
  }

  getBatch(batchId: string): CellBatch | null {
    const row = this.db.prepare(
      'SELECT * FROM batches WHERE batch_id = ?',
    ).get(batchId) as BatchRow | null;
    if (!row) return null;
    return {
      batchId: row.batch_id,
      cells: [], // load separately via getCellsByBatch if needed
      openedAt: row.opened_at,
      closedAt: row.closed_at,
    };
  }

  getBatchWithMeta(batchId: string): (BatchRow & { anchor_txid?: string }) | null {
    const row = this.db.prepare(`
      SELECT b.*, a.txid as anchor_txid
      FROM batches b
      LEFT JOIN anchors a ON a.batch_id = b.batch_id
      WHERE b.batch_id = ?
    `).get(batchId) as (BatchRow & { anchor_txid?: string }) | null;
    return row ?? null;
  }

  getRecentBatches(limit: number = 20, offset: number = 0): BatchRow[] {
    return this.db.prepare(
      'SELECT * FROM batches ORDER BY opened_at DESC LIMIT ? OFFSET ?',
    ).all(limit, offset) as BatchRow[];
  }

  // ── Merkle proof operations ────────────────────────────────────────

  addMerkleProof(cellId: string, batchId: string, proofBlob: Buffer, leafIndex: number): void {
    this.db.prepare(`
      INSERT OR REPLACE INTO merkle_proofs (cell_id, batch_id, proof_blob, leaf_index)
      VALUES (?, ?, ?, ?)
    `).run(cellId, batchId, proofBlob, leafIndex);
  }

  getMerkleProof(cellId: string, batchId: string): MerkleProofRow | null {
    return this.db.prepare(
      'SELECT * FROM merkle_proofs WHERE cell_id = ? AND batch_id = ?',
    ).get(cellId, batchId) as MerkleProofRow | null;
  }

  getMerkleProofsByBatch(batchId: string): MerkleProofRow[] {
    return this.db.prepare(
      'SELECT * FROM merkle_proofs WHERE batch_id = ? ORDER BY leaf_index',
    ).all(batchId) as MerkleProofRow[];
  }

  // ── Anchor operations ──────────────────────────────────────────────

  recordAnchor(anchor: MerkleAnchor, payload?: string): void {
    this.db.prepare(`
      INSERT OR REPLACE INTO anchors
        (batch_id, merkle_root, txid, anchor_payload, submitted_at, status, error)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    `).run(
      anchor.batchId,
      anchor.merkleRoot,
      anchor.txid,
      payload ?? null,
      anchor.anchoredAt,
      anchor.status,
      anchor.error ?? null,
    );
  }

  updateAnchorStatus(batchId: string, status: MerkleAnchor['status'], txid?: string, error?: string): void {
    if (txid) {
      this.db.prepare(`
        UPDATE anchors SET status = ?, txid = ?, submitted_at = ? WHERE batch_id = ?
      `).run(status, txid, Date.now(), batchId);
    } else if (error) {
      this.db.prepare(`
        UPDATE anchors SET status = ?, error = ? WHERE batch_id = ?
      `).run(status, error, batchId);
    } else {
      this.db.prepare(
        'UPDATE anchors SET status = ? WHERE batch_id = ?',
      ).run(status, batchId);
    }
  }

  confirmAnchor(batchId: string, confirmedAt: number): void {
    this.db.prepare(`
      UPDATE anchors SET status = 'confirmed', confirmed_at = ? WHERE batch_id = ?
    `).run(confirmedAt, batchId);
    this.setBatchAnchored(batchId);
  }

  getAnchor(batchId: string): AnchorRow | null {
    return this.db.prepare(
      'SELECT * FROM anchors WHERE batch_id = ?',
    ).get(batchId) as AnchorRow | null;
  }

  getAnchorByTxid(txid: string): AnchorRow | null {
    return this.db.prepare(
      'SELECT * FROM anchors WHERE txid = ?',
    ).get(txid) as AnchorRow | null;
  }

  getRecentAnchors(limit: number = 20, offset: number = 0): AnchorRow[] {
    return this.db.prepare(
      'SELECT * FROM anchors ORDER BY submitted_at DESC LIMIT ? OFFSET ?',
    ).all(limit, offset) as AnchorRow[];
  }

  // ── Stats ──────────────────────────────────────────────────────────

  getStats(): StatsResult {
    const cells = this.db.prepare(
      'SELECT COUNT(*) as cnt FROM cells',
    ).get() as { cnt: number };

    const batches = this.db.prepare(
      'SELECT COUNT(*) as cnt FROM batches WHERE status != \'open\'',
    ).get() as { cnt: number };

    const anchored = this.db.prepare(
      'SELECT COUNT(*) as cnt FROM anchors WHERE status IN (\'submitted\', \'confirmed\')',
    ).get() as { cnt: number };

    const players = this.db.prepare(
      'SELECT COUNT(DISTINCT source_addr) as cnt FROM cells',
    ).get() as { cnt: number };

    return {
      total_cells: cells.cnt,
      total_batches: batches.cnt,
      total_anchored: anchored.cnt,
      unique_players: players.cnt,
    };
  }

  getCellCount(): number {
    const row = this.db.prepare(
      'SELECT COUNT(*) as cnt FROM cells',
    ).get() as { cnt: number };
    return row.cnt;
  }

  // ── Lifecycle ──────────────────────────────────────────────────────

  close(): void {
    this.db.close();
  }

  // ── Row mappers ────────────────────────────────────────────────────

  private rowToCell(row: CellRow): CollectedCell {
    return {
      cellId: row.cell_id,
      cellBytes: row.cell_bytes instanceof Uint8Array ? row.cell_bytes : new Uint8Array(row.cell_bytes as ArrayBuffer),
      semanticPath: row.semantic_path,
      contentHash: Buffer.from(row.content_hash),
      sourceAddr: row.source_addr,
      receivedAt: row.received_at,
      linearity: row.linearity,
    };
  }
}

```
