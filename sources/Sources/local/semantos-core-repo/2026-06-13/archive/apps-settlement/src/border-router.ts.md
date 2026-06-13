---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-settlement/src/border-router.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.707534+00:00
---

# archive/apps-settlement/src/border-router.ts

```ts
/**
 * BorderRouter — Main orchestrator for the H3 settlement layer.
 *
 * Wires together all subsystems:
 *   CellCollector → BatchAggregator → MerkleBatcher → BsvAnchorPipeline
 *   ProvenanceStore (SQLite persistence)
 *   RestServer + WebSocket (external APIs)
 *
 * Event flow:
 *   1. CellCollector receives UDP multicast datagrams
 *   2. Validated cells are forwarded to BatchAggregator
 *   3. Every 30s, BatchAggregator closes a batch
 *   4. MerkleBatcher computes Merkle root + proofs
 *   5. BsvAnchorPipeline writes OP_RETURN to BSV
 *   6. All events are broadcast via WebSocket
 *   7. REST API serves the provenance DAG
 *
 * Cross-references:
 *   docs/prd/hackathon/PHASE-H3-BORDER-ROUTER-AGGREGATOR.md — PRD
 */

import { mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

import { loadConfig, type BorderRouterConfig, type LiveStats } from './services/border-router-types';
import { ProvenanceStore } from './store/provenance-store';
import { CellCollector } from './services/cell-collector';
import { BatchAggregator } from './services/batch-aggregator';
import { MerkleBatcher } from './services/merkle-batcher';
import { BsvAnchorPipeline } from './services/bsv-anchor-pipeline';
import { RestServer } from './api/rest-server';
import { BorderRouterWebSocket } from './api/websocket-server';

// ── BorderRouter ─────────────────────────────────────────────────────

export class BorderRouter {
  readonly config: BorderRouterConfig;
  readonly store: ProvenanceStore;
  readonly collector: CellCollector;
  readonly aggregator: BatchAggregator;
  readonly merkleBatcher: MerkleBatcher;
  readonly anchorPipeline: BsvAnchorPipeline;
  readonly restServer: RestServer;
  readonly wsServer: BorderRouterWebSocket;

  private startTime: number = 0;
  private statsInterval: ReturnType<typeof setInterval> | null = null;
  private dedupPruneInterval: ReturnType<typeof setInterval> | null = null;

  constructor(config?: Partial<BorderRouterConfig>) {
    this.config = { ...loadConfig(), ...config };

    // Ensure DB directory exists
    if (this.config.dbPath !== ':memory:') {
      try {
        mkdirSync(dirname(this.config.dbPath), { recursive: true });
      } catch {
        // May already exist
      }
    }

    // Initialize subsystems
    this.store = new ProvenanceStore(this.config.dbPath);
    this.collector = new CellCollector(this.store, this.config);
    this.aggregator = new BatchAggregator(this.store, this.config);
    this.merkleBatcher = new MerkleBatcher(this.store);
    this.anchorPipeline = new BsvAnchorPipeline(this.store, this.config);
    this.restServer = new RestServer(this.config.restPort, this.store, {
      aggregator: this.aggregator,
      getEngineAddress: () => this.anchorPipeline.getEngineAddress(),
      getCollectorStats: () => this.collector.getStats(),
    });
    this.wsServer = new BorderRouterWebSocket(this.config.wsPort);

    this.wireEvents();
  }

  async start(): Promise<void> {
    this.startTime = Date.now();

    console.log('═══════════════════════════════════════════════════════════');
    console.log('  Semantos Border Router — H3 Settlement Layer');
    console.log('═══════════════════════════════════════════════════════════');
    console.log(`  Multicast: [${this.config.multicastGroup}]:${this.config.multicastPort}`);
    console.log(`  Batch window: ${this.config.batchIntervalMs}ms`);
    console.log(`  REST API: http://0.0.0.0:${this.config.restPort}`);
    console.log(`  WebSocket: ws://0.0.0.0:${this.config.wsPort}`);
    console.log(`  BSV network: ${this.config.bsvNetwork}`);
    console.log(`  Dry-run: ${this.config.dryRun}`);
    console.log(`  DB: ${this.config.dbPath}`);
    console.log('═══════════════════════════════════════════════════════════');

    // Initialize anchor pipeline (funding, pre-split)
    await this.anchorPipeline.initialize();

    // Start API servers
    await this.restServer.start();
    await this.wsServer.start();

    // Start processing pipeline
    this.aggregator.start();
    await this.collector.start();

    // Periodic stats broadcast via WebSocket (every 10s)
    this.statsInterval = setInterval(() => {
      this.broadcastStats();
    }, 10_000);

    // Periodic dedup log pruning (every 5 minutes)
    this.dedupPruneInterval = setInterval(() => {
      const pruned = this.store.pruneDedup(this.config.dedupWindowMs);
      if (pruned > 0) {
        console.log(`[BorderRouter] Pruned ${pruned} stale dedup entries`);
      }
    }, 5 * 60_000);

    console.log('[BorderRouter] All systems started');
  }

  async stop(): Promise<void> {
    console.log('[BorderRouter] Shutting down...');

    // Stop accepting new cells
    await this.collector.stop();

    // Flush current batch
    this.aggregator.stop();

    // Clear timers
    if (this.statsInterval) {
      clearInterval(this.statsInterval);
      this.statsInterval = null;
    }
    if (this.dedupPruneInterval) {
      clearInterval(this.dedupPruneInterval);
      this.dedupPruneInterval = null;
    }

    // Stop API servers
    await this.wsServer.stop();
    await this.restServer.stop();

    // Close store
    this.store.close();

    console.log('[BorderRouter] Shutdown complete');
  }

  getStats(): LiveStats {
    const collectorStats = this.collector.getStats();
    const aggStats = this.aggregator.getStats();
    const dbStats = this.store.getStats();
    const uptimeMs = Date.now() - this.startTime;
    const uptimeSec = uptimeMs / 1000;

    return {
      cellsPerSecond: uptimeSec > 0 ? Math.round((collectorStats.collected / uptimeSec) * 100) / 100 : 0,
      totalCellsCollected: collectorStats.collected,
      totalCellsAnchored: dbStats.total_anchored,
      totalBatches: dbStats.total_batches,
      totalAnchors: dbStats.total_anchored,
      currentBatchSize: aggStats.currentBatchSize,
      currentBatchAgeMs: aggStats.currentBatchAgeMs,
      uniquePlayers: dbStats.unique_players,
      uptimeMs,
    };
  }

  // ── Event Wiring ───────────────────────────────────────────────────

  private wireEvents(): void {
    // Cell → Aggregator + WebSocket
    this.collector.on('cell:received', (cell) => {
      this.aggregator.addCell(cell);
      this.wsServer.broadcastCell(cell);
    });

    // Batch → Merkle + WebSocket
    this.aggregator.on('batch:closed', (batch) => {
      const anchor = this.merkleBatcher.processBatch(batch);
      this.wsServer.broadcastBatch(batch, anchor.merkleRoot);

      // Anchor to BSV
      this.anchorPipeline.anchor(anchor).catch((err) => {
        console.error('[BorderRouter] Anchor error:', (err as Error).message);
      });
    });

    // Anchor events → WebSocket
    this.anchorPipeline.on('anchor:submitted', (anchor) => {
      this.wsServer.broadcastAnchor(anchor);
    });

    this.anchorPipeline.on('anchor:failed', (anchor, error) => {
      this.wsServer.broadcastAnchorFailed(anchor, error);
    });
  }

  private broadcastStats(): void {
    const stats = this.getStats();
    this.wsServer.broadcastStats(stats);
  }
}

// ── Main entry point ─────────────────────────────────────────────────

async function main(): Promise<void> {
  const router = new BorderRouter();

  // Graceful shutdown
  const shutdown = async () => {
    await router.stop();
    process.exit(0);
  };

  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);

  await router.start();
}

// Run if this is the entry point
if (import.meta.url === `file://${process.argv[1]}` || process.argv[1]?.endsWith('border-router.ts')) {
  main().catch((err) => {
    console.error('[BorderRouter] Fatal:', err);
    process.exit(1);
  });
}

```
