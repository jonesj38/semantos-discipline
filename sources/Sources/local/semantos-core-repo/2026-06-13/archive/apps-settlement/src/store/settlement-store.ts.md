---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-settlement/src/store/settlement-store.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.712690+00:00
---

# archive/apps-settlement/src/store/settlement-store.ts

```ts
/**
 * `PaskianStore` facade — composes the per-concern modules and
 * preserves the legacy public API exactly.
 *
 * The legacy 501-LOC `apps/settlement/src/store.ts` mixed schema DDL,
 * node CRUD, edge CRUD, the constraint-delta log, stability tracking,
 * pruning, and game-facing cross-table queries in a single class.
 * The prompt-44 split factors each concern into its own module under
 * `apps/settlement/src/store/` while keeping `PaskianStore` itself a
 * thin facade so existing consumers (`adapter.ts`, `index.ts`,
 * `extensions/navigation/src/paskian-bridge.ts`) keep compiling
 * unchanged.
 *
 * Cross-references:
 *   apps/poker-agent/src/game-state-db/game-state-db-facade.ts  — same pattern (prompt 21)
 *   apps/settlement/src/store/provenance-store.ts               — sibling concern in the same folder
 */

import { Database } from 'bun:sqlite';

import type {
  EmergingThread,
  PaskianEdge,
  PaskianNode,
  PruningRecord,
  StableThread,
} from '../types';

import type { DatabaseHandle } from './db-types';
import { DeltaLog } from './delta-log';
import { EdgeStore } from './edge-index';
import { NodeStore } from './node-index';
import { applyPaskianSchema } from './paskian-schema';
import { Pruner } from './pruner';
import { QuerySurface, type ReputationScore } from './query';
import { StabilityTracker } from './stability';

export class PaskianStore {
  private readonly db: DatabaseHandle;
  private readonly nodes: NodeStore;
  private readonly edges: EdgeStore;
  private readonly deltas: DeltaLog;
  private readonly stability: StabilityTracker;
  private readonly pruner: Pruner;
  private readonly queries: QuerySurface;

  constructor(dbPath?: string) {
    this.db = new Database(dbPath ?? ':memory:');
    this.db.exec('PRAGMA journal_mode=WAL');
    applyPaskianSchema(this.db);
    this.nodes = new NodeStore(this.db);
    this.edges = new EdgeStore(this.db);
    this.deltas = new DeltaLog(this.db);
    this.stability = new StabilityTracker(this.db);
    this.pruner = new Pruner(this.db);
    this.queries = new QuerySurface(this.db);
  }

  // ── Node operations ────────────────────────────────────────────────

  upsertNode(node: Pick<PaskianNode, 'cellId' | 'typePath'>): void {
    this.nodes.upsertNode(node);
  }

  getNode(cellId: string): PaskianNode | null {
    return this.nodes.getNode(cellId);
  }

  updateNodeState(cellId: string, deltaH: number): void {
    this.nodes.updateNodeState(cellId, deltaH);
  }

  markStable(cellId: string, isStable: boolean): void {
    this.nodes.markStable(cellId, isStable);
  }

  markPruned(cellId: string): void {
    this.nodes.markPruned(cellId);
  }

  activeNodes(): PaskianNode[] {
    return this.nodes.activeNodes();
  }

  // ── Edge operations ────────────────────────────────────────────────

  upsertEdge(fromCell: string, toCell: string): string {
    return this.edges.upsertEdge(fromCell, toCell);
  }

  getEdge(edgeId: string): PaskianEdge | null {
    return this.edges.getEdge(edgeId);
  }

  neighbours(cellId: string): PaskianEdge[] {
    return this.edges.neighbours(cellId);
  }

  allEdges(cellId: string): PaskianEdge[] {
    return this.edges.allEdges(cellId);
  }

  updateEdgeWeight(edgeId: string, delta: number): void {
    this.edges.updateEdgeWeight(edgeId, delta);
  }

  updateEdgeTrend(edgeId: string, trend: number): void {
    this.edges.updateEdgeTrend(edgeId, trend);
  }

  // ── Constraint delta log ───────────────────────────────────────────

  recordDelta(
    edgeId: string,
    delta: number,
    interaction: string,
    cellVersion?: number,
    prevStateHash?: string,
  ): void {
    this.deltas.recordDelta(edgeId, delta, interaction, cellVersion, prevStateHash);
  }

  avgDelta(edgeId: string, windowMs: number): number {
    return this.deltas.avgDelta(edgeId, windowMs);
  }

  inboundTrend(cellId: string): number {
    return this.deltas.inboundTrend(cellId);
  }

  // ── Stability log ──────────────────────────────────────────────────

  recordStability(cellId: string, deltaH: number, isStable: boolean): void {
    this.stability.recordStability(cellId, deltaH, isStable);
  }

  // ── Pruning log ────────────────────────────────────────────────────

  recordPruning(record: PruningRecord): void {
    this.pruner.recordPruning(record);
  }

  pruningCandidates(threshold: number): PaskianNode[] {
    return this.pruner.pruningCandidates(threshold);
  }

  // ── Query surface ──────────────────────────────────────────────────

  stableThreads(): StableThread[] {
    return this.queries.stableThreads();
  }

  emergingThreads(windowMs: number): EmergingThread[] {
    return this.queries.emergingThreads(windowMs);
  }

  snapshot(): { nodes: PaskianNode[]; edges: PaskianEdge[] } {
    return this.queries.snapshot();
  }

  getReputationScore(providerCellId: string): ReputationScore {
    return this.queries.getReputationScore(providerCellId);
  }

  // ── Lifecycle ──────────────────────────────────────────────────────

  close(): void {
    this.db.close();
  }
}

```
