---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-settlement/src/api/rest-server.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.715281+00:00
---

# archive/apps-settlement/src/api/rest-server.ts

```ts
/**
 * RestServer — Paskian Overlay REST API for the Border Router.
 *
 * Serves the provenance DAG, batch history, anchor proofs, and live stats
 * via Express.js with CORS support.
 *
 * Endpoints:
 *   GET /health                — health check
 *   GET /api/stats             — live statistics
 *   GET /api/cells             — recent cells (paginated)
 *   GET /api/cells/:cellId     — single cell detail
 *   GET /api/batches           — batch list (paginated)
 *   GET /api/batches/:batchId  — batch detail + anchor info
 *   GET /api/batches/:batchId/cells — cells in a batch
 *   GET /api/batches/:batchId/proofs — Merkle proofs for a batch
 *   GET /api/anchors           — anchor list (paginated)
 *   GET /api/anchors/:batchId  — anchor detail
 *   POST /api/admin/flush      — force-close current batch
 */

import express from 'express';
import cors from 'cors';
import type { Server } from 'node:http';

import type { ProvenanceStore } from '../store/provenance-store';
import type { BatchAggregator } from '../services/batch-aggregator';

// ── Response wrapper ─────────────────────────────────────────────────

interface ApiResponse<T = unknown> {
  success: boolean;
  data?: T;
  error?: string;
  timestamp: number;
}

function ok<T>(data: T): ApiResponse<T> {
  return { success: true, data, timestamp: Date.now() };
}

function err(message: string, status: number = 500): ApiResponse {
  return { success: false, error: message, timestamp: Date.now() };
}

// ── RestServer ───────────────────────────────────────────────────────

export class RestServer {
  private app: express.Application;
  private server: Server | null = null;
  private port: number;
  private store: ProvenanceStore;
  private aggregator: BatchAggregator | null;
  private startTime: number;
  private getEngineAddress: (() => string | null) | null;
  private getCollectorStats: (() => { collected: number; deduplicated: number; invalid: number }) | null;

  constructor(
    port: number,
    store: ProvenanceStore,
    opts?: {
      aggregator?: BatchAggregator;
      getEngineAddress?: () => string | null;
      getCollectorStats?: () => { collected: number; deduplicated: number; invalid: number };
    },
  ) {
    this.port = port;
    this.store = store;
    this.aggregator = opts?.aggregator ?? null;
    this.getEngineAddress = opts?.getEngineAddress ?? null;
    this.getCollectorStats = opts?.getCollectorStats ?? null;
    this.startTime = Date.now();

    this.app = express();
    this.app.use(cors());
    this.app.use(express.json());
    this.setupRoutes();
  }

  async start(): Promise<void> {
    return new Promise((resolve) => {
      this.server = this.app.listen(this.port, () => {
        console.log(`[RestServer] Listening on port ${this.port}`);
        resolve();
      });
    });
  }

  async stop(): Promise<void> {
    if (!this.server) return;
    return new Promise((resolve) => {
      this.server!.close(() => {
        console.log('[RestServer] Stopped');
        resolve();
      });
    });
  }

  getBaseUrl(): string {
    return `http://localhost:${this.port}`;
  }

  getExpressApp(): express.Application {
    return this.app;
  }

  // ── Routes ─────────────────────────────────────────────────────────

  private setupRoutes(): void {
    const { app } = this;

    // Health check
    app.get('/health', (_req, res) => {
      res.json(ok({
        status: 'ok',
        uptime_ms: Date.now() - this.startTime,
        version: '0.1.0',
      }));
    });

    // Live statistics
    app.get('/api/stats', (_req, res) => {
      const dbStats = this.store.getStats();
      const collectorStats = this.getCollectorStats?.() ?? { collected: 0, deduplicated: 0, invalid: 0 };
      const aggStats = this.aggregator?.getStats();

      const uptimeMs = Date.now() - this.startTime;
      const uptimeSec = uptimeMs / 1000;
      const tps = uptimeSec > 0 ? collectorStats.collected / uptimeSec : 0;

      res.json(ok({
        totalCells: dbStats.total_cells,
        totalBatches: dbStats.total_batches,
        totalAnchored: dbStats.total_anchored,
        uniquePlayers: dbStats.unique_players,
        tps: Math.round(tps * 100) / 100,
        cellsCollected: collectorStats.collected,
        cellsDeduplicated: collectorStats.deduplicated,
        cellsInvalid: collectorStats.invalid,
        currentBatchSize: aggStats?.currentBatchSize ?? 0,
        currentBatchAgeMs: aggStats?.currentBatchAgeMs ?? 0,
        uptime_ms: uptimeMs,
        engineAddress: this.getEngineAddress?.() ?? null,
      }));
    });

    // Recent cells (paginated)
    app.get('/api/cells', (req, res) => {
      const limit = Math.min(parseInt(req.query.limit as string) || 50, 100);
      const offset = parseInt(req.query.offset as string) || 0;
      const cells = this.store.getRecentCells(limit, offset);

      res.json(ok({
        cells: cells.map(c => ({
          cellId: c.cellId,
          semanticPath: c.semanticPath,
          sourceAddr: c.sourceAddr,
          receivedAt: c.receivedAt,
          linearity: c.linearity,
          contentHash: c.contentHash.toString('hex'),
          size: c.cellBytes.length,
        })),
        total: this.store.getCellCount(),
        limit,
        offset,
      }));
    });

    // Single cell detail
    app.get('/api/cells/:cellId', (req, res) => {
      const cell = this.store.getCell(req.params.cellId);
      if (!cell) {
        return res.status(404).json(err('Cell not found', 404));
      }
      res.json(ok({
        cellId: cell.cellId,
        semanticPath: cell.semanticPath,
        sourceAddr: cell.sourceAddr,
        receivedAt: cell.receivedAt,
        linearity: cell.linearity,
        contentHash: cell.contentHash.toString('hex'),
        size: cell.cellBytes.length,
        cellBytesHex: Buffer.from(cell.cellBytes).toString('hex'),
      }));
    });

    // Batch list (paginated)
    app.get('/api/batches', (req, res) => {
      const limit = Math.min(parseInt(req.query.limit as string) || 20, 100);
      const offset = parseInt(req.query.offset as string) || 0;
      const batches = this.store.getRecentBatches(limit, offset);

      res.json(ok({
        batches: batches.map(b => ({
          batchId: b.batch_id,
          cellCount: b.cell_count,
          openedAt: b.opened_at,
          closedAt: b.closed_at,
          merkleRoot: b.merkle_root ? Buffer.from(b.merkle_root).toString('hex') : null,
          status: b.status,
        })),
        limit,
        offset,
      }));
    });

    // Batch detail
    app.get('/api/batches/:batchId', (req, res) => {
      const batch = this.store.getBatchWithMeta(req.params.batchId);
      if (!batch) {
        return res.status(404).json(err('Batch not found', 404));
      }
      const anchor = this.store.getAnchor(req.params.batchId);

      res.json(ok({
        batchId: batch.batch_id,
        cellCount: batch.cell_count,
        openedAt: batch.opened_at,
        closedAt: batch.closed_at,
        merkleRoot: batch.merkle_root ? Buffer.from(batch.merkle_root).toString('hex') : null,
        status: batch.status,
        anchor: anchor ? {
          txid: anchor.txid,
          status: anchor.status,
          submittedAt: anchor.submitted_at,
          confirmedAt: anchor.confirmed_at,
        } : null,
      }));
    });

    // Cells in a batch
    app.get('/api/batches/:batchId/cells', (req, res) => {
      const cells = this.store.getCellsByBatch(req.params.batchId);
      res.json(ok({
        batchId: req.params.batchId,
        cells: cells.map(c => ({
          cellId: c.cellId,
          semanticPath: c.semanticPath,
          sourceAddr: c.sourceAddr,
          receivedAt: c.receivedAt,
          linearity: c.linearity,
          contentHash: c.contentHash.toString('hex'),
        })),
        count: cells.length,
      }));
    });

    // Merkle proofs for a batch
    app.get('/api/batches/:batchId/proofs', (req, res) => {
      const proofs = this.store.getMerkleProofsByBatch(req.params.batchId);
      res.json(ok({
        batchId: req.params.batchId,
        proofs: proofs.map(p => ({
          cellId: p.cell_id,
          leafIndex: p.leaf_index,
          proofBlobHex: Buffer.from(p.proof_blob).toString('hex'),
        })),
        count: proofs.length,
      }));
    });

    // Anchor list (paginated)
    app.get('/api/anchors', (req, res) => {
      const limit = Math.min(parseInt(req.query.limit as string) || 20, 100);
      const offset = parseInt(req.query.offset as string) || 0;
      const anchors = this.store.getRecentAnchors(limit, offset);

      res.json(ok({
        anchors: anchors.map(a => ({
          batchId: a.batch_id,
          merkleRoot: Buffer.from(a.merkle_root).toString('hex'),
          txid: a.txid,
          status: a.status,
          submittedAt: a.submitted_at,
          confirmedAt: a.confirmed_at,
          error: a.error,
        })),
        limit,
        offset,
      }));
    });

    // Anchor detail by batchId
    app.get('/api/anchors/:batchId', (req, res) => {
      const anchor = this.store.getAnchor(req.params.batchId);
      if (!anchor) {
        return res.status(404).json(err('Anchor not found', 404));
      }
      res.json(ok({
        batchId: anchor.batch_id,
        merkleRoot: Buffer.from(anchor.merkle_root).toString('hex'),
        txid: anchor.txid,
        status: anchor.status,
        submittedAt: anchor.submitted_at,
        confirmedAt: anchor.confirmed_at,
        payload: anchor.anchor_payload,
        error: anchor.error,
      }));
    });

    // Admin: force-flush current batch
    app.post('/api/admin/flush', (_req, res) => {
      if (!this.aggregator) {
        return res.status(503).json(err('Aggregator not available', 503));
      }
      const batch = this.aggregator.flushBatch();
      if (!batch) {
        return res.json(ok({ message: 'No cells to flush', flushed: false }));
      }
      res.json(ok({
        message: `Batch ${batch.batchId} flushed`,
        flushed: true,
        batchId: batch.batchId,
        cellCount: batch.cells.length,
      }));
    });
  }
}

```
