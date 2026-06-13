---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-settlement/src/services/batch-aggregator.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.713724+00:00
---

# archive/apps-settlement/src/services/batch-aggregator.ts

```ts
/**
 * BatchAggregator — Time-windowed cell batching for the Border Router.
 *
 * Accumulates validated cells into batches. Every N milliseconds (default 30s),
 * closes the current batch and emits it for Merkle root computation and anchoring.
 * Skips empty batches. Flushes partial batch on shutdown.
 *
 * Cross-references:
 *   packages/protocol-types/src/anchor-scheduler.ts — batch timing logic pattern
 */

import { randomUUID } from 'node:crypto';

import type { ProvenanceStore } from '../store/provenance-store';
import type { CollectedCell, CellBatch, BorderRouterConfig } from './border-router-types';
import { TypedBorderRouterEmitter } from './border-router-types';

// ── BatchAggregator ──────────────────────────────────────────────────

export class BatchAggregator extends TypedBorderRouterEmitter {
  private store: ProvenanceStore;
  private windowMs: number;
  private timer: ReturnType<typeof setInterval> | null = null;
  private running = false;

  // Current batch accumulator
  private currentBatchId: string;
  private currentCells: CollectedCell[] = [];
  private currentOpenedAt: number;

  // Stats
  private totalBatchesClosed = 0;
  private totalCellsBatched = 0;

  constructor(store: ProvenanceStore, config: BorderRouterConfig) {
    super();
    this.store = store;
    this.windowMs = config.batchIntervalMs;

    // Initialize first batch
    this.currentBatchId = randomUUID();
    this.currentOpenedAt = Date.now();
    this.store.createBatch(this.currentBatchId, this.currentOpenedAt);
  }

  start(): void {
    if (this.running) return;
    this.running = true;

    this.timer = setInterval(() => {
      this.closeBatchWindow();
    }, this.windowMs);

    console.log(`[BatchAggregator] Started with ${this.windowMs}ms batch window`);
  }

  stop(): void {
    if (!this.running) return;
    this.running = false;

    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }

    // Flush any partial batch
    if (this.currentCells.length > 0) {
      this.closeBatchWindow();
    }

    console.log('[BatchAggregator] Stopped');
  }

  addCell(cell: CollectedCell): void {
    this.currentCells.push(cell);
    // Assign cell to current batch in store
    this.store.assignCellsToBatch([cell.cellId], this.currentBatchId);
  }

  getCurrentBatchSize(): number {
    return this.currentCells.length;
  }

  getCurrentBatchId(): string {
    return this.currentBatchId;
  }

  getCurrentBatchAgeMs(): number {
    return Date.now() - this.currentOpenedAt;
  }

  getStats() {
    return {
      totalBatchesClosed: this.totalBatchesClosed,
      totalCellsBatched: this.totalCellsBatched,
      currentBatchSize: this.currentCells.length,
      currentBatchAgeMs: this.getCurrentBatchAgeMs(),
    };
  }

  /**
   * Force-close the current batch immediately (admin operation).
   */
  flushBatch(): CellBatch | null {
    if (this.currentCells.length === 0) return null;
    return this.closeBatchWindow();
  }

  // ── Private ────────────────────────────────────────────────────────

  private closeBatchWindow(): CellBatch | null {
    const cells = this.currentCells;
    const batchId = this.currentBatchId;
    const openedAt = this.currentOpenedAt;
    const closedAt = Date.now();

    // Skip empty batches
    if (cells.length === 0) {
      this.emit('batch:empty');
      return null;
    }

    // Close this batch in the store
    this.store.closeBatch(batchId, closedAt, cells.length);

    const batch: CellBatch = {
      batchId,
      cells,
      openedAt,
      closedAt,
    };

    this.totalBatchesClosed++;
    this.totalCellsBatched += cells.length;

    // Start new batch
    this.currentBatchId = randomUUID();
    this.currentOpenedAt = Date.now();
    this.currentCells = [];
    this.store.createBatch(this.currentBatchId, this.currentOpenedAt);

    // Emit batch ready
    this.emit('batch:closed', batch);

    console.log(
      `[BatchAggregator] Batch ${batchId.slice(0, 8)} closed: ${cells.length} cells`,
    );

    return batch;
  }
}

```
