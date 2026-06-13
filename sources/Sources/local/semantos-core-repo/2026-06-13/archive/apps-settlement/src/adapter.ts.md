---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-settlement/src/adapter.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.707107+00:00
---

# archive/apps-settlement/src/adapter.ts

```ts
/**
 * PaskianAdapter — the learning dynamics engine.
 *
 * This is the operational core of the Paskian learning system. It
 * implements the paper's main loop:
 *
 *   RECEIVE interaction I
 *   G ← APPLY_INTERACTION(G, I)
 *   A ← IDENTIFY_AFFECTED_NODES(G, I)
 *   REPEAT k times:
 *     FOR each node i in A:
 *       h_i ← LOCAL_UPDATE(i, G)
 *     A ← EXPAND_LOCAL_REGION(A)
 *   G ← PRUNE(G)
 *
 * The adapter sits between the game layer (bitECS / GameCellEngine)
 * and the SQLite store. It translates cell transitions into Paskian
 * graph dynamics.
 *
 * The learning isn't a separate system — it's a view over the cell
 * transition history. The SQLite store is the materialised projection.
 *
 * Cross-references:
 *   store.ts        — SQLite persistence
 *   grammar.ts      — type paths and tuning
 *   types.ts        — PaskianInteraction, PaskianEvents
 *   game-sdk/engine  — GameCellEngine (cell transitions)
 */

import type { StorageAdapter } from '../../protocol-types/src/storage';

import { PaskianStore } from './store';
import type { PaskianConfig } from './grammar';
import { DEFAULT_PASKIAN_CONFIG } from './grammar';
import type {
  PaskianInteraction,
  PaskianEvents,
  PaskianNode,
  PaskianEdge,
  StableThread,
  EmergingThread,
  PruningRecord,
} from './types';

// ── Adapter ────────────────────────────────────────────────────────────

export interface PaskianAdapterOptions {
  /** SQLite database path (default: ':memory:'). */
  dbPath?: string;
  /** Override default tuning parameters. */
  config?: Partial<PaskianConfig>;
  /** Event callbacks for stability, pruning, etc. */
  events?: PaskianEvents;
  /** StorageAdapter for writing compliance events (BSV anchor triggers). */
  storage?: StorageAdapter;
}

export class PaskianAdapter {
  readonly store: PaskianStore;
  readonly config: PaskianConfig;
  private events: PaskianEvents;
  private storage: StorageAdapter | null;

  constructor(options?: PaskianAdapterOptions) {
    this.store = new PaskianStore(options?.dbPath);
    this.config = { ...DEFAULT_PASKIAN_CONFIG, ...options?.config };
    this.events = options?.events ?? {};
    this.storage = options?.storage ?? null;
  }

  // ── Main entry point ─────────────────────────────────────────────

  /**
   * Process an interaction event through the full Paskian loop.
   *
   * This is the function the game layer calls after a cell transition.
   * It corresponds to one pass through the paper's main loop.
   *
   * Returns the set of nodes that were affected (for logging/UI).
   */
  async interact(interaction: PaskianInteraction): Promise<Set<string>> {
    const { cellId, kind, strength, relatedCells, conversationContext, contextWeight } = interaction;

    // Phase 2: Apply context weight to interaction strength
    const effectiveStrength = contextWeight != null ? strength * contextWeight : strength;

    // ── Step 1: APPLY_INTERACTION — ensure nodes and edges exist
    this.store.upsertNode({ cellId, typePath: kind });

    if (relatedCells) {
      for (const related of relatedCells) {
        this.store.upsertNode({ cellId: related, typePath: kind });
        const edgeId = this.store.upsertEdge(cellId, related);
        const edge = this.store.getEdge(edgeId)!;
        // Phase 2: Tag edge with conversation context
        if (conversationContext && edge) {
          edge.conversationContext = conversationContext;
          edge.contextWeight = contextWeight;
        }
        this.events.onEdgeCreated?.(edge);
      }
    }

    // ── Step 2: IDENTIFY_AFFECTED_NODES
    const affected = new Set<string>([cellId]);
    if (relatedCells) {
      for (const r of relatedCells) affected.add(r);
    }

    // ── Step 3: Update the directly-interacted node
    this.store.updateNodeState(cellId, effectiveStrength);

    // Update edge weights for all related cells
    if (relatedCells) {
      for (const related of relatedCells) {
        const edgeId = `${cellId}-${related}`;
        this.store.updateEdgeWeight(edgeId, effectiveStrength * this.config.learningRate);
        this.store.recordDelta(edgeId, effectiveStrength * this.config.learningRate, kind);
      }
    }

    // ── Step 4: LOCAL PROPAGATION — k iterations
    let region = new Set(affected);

    for (let k = 0; k < this.config.propagationDepth; k++) {
      for (const nodeId of region) {
        await this.localUpdate(nodeId, kind);
      }
      region = this.expandRegion(region);
    }

    // Merge expanded region into affected set
    for (const nodeId of region) affected.add(nodeId);

    this.events.onPropagationComplete?.(affected.size);

    // ── Step 5: STABILITY CHECK — for all affected nodes
    for (const nodeId of affected) {
      await this.checkStability(nodeId);
    }

    // ── Step 6: PRUNE — check for weak nodes
    await this.prune();

    return affected;
  }

  // ── The paper's LOCAL_UPDATE function ─────────────────────────────

  /**
   * h_i ← f(h_i, {h_j : j ∈ N(i)})
   *
   * Each node updates based on constraint effects from its neighbours.
   */
  private async localUpdate(cellId: string, interaction: string): Promise<void> {
    const edges = this.store.neighbours(cellId);
    if (edges.length === 0) return;

    let totalEffect = 0;

    for (const edge of edges) {
      const effect = this.constraintEffect(cellId, edge);
      totalEffect += effect;

      // Record the propagation delta
      this.store.recordDelta(edge.edgeId, effect, `propagation:${interaction}`);

      // Update edge trend (exponential moving average)
      const newTrend = edge.deltaTrend * 0.9 + effect * 0.1;
      this.store.updateEdgeTrend(edge.edgeId, newTrend);
    }

    // Apply accumulated effect to the node
    if (totalEffect !== 0) {
      this.store.updateNodeState(cellId, totalEffect);
    }
  }

  // ── The paper's CONSTRAINT_EFFECT function ────────────────────────

  /**
   * CONSTRAINT_EFFECT(h_i, h_j) → gradient or adjustment based on C_ij
   *
   * The effect is proportional to the constraint weight and the
   * difference between connected node states. This drives nodes
   * toward coherent configurations.
   */
  private constraintEffect(cellId: string, edge: PaskianEdge): number {
    const source = this.store.getNode(cellId);
    const target = this.store.getNode(edge.toCell);
    if (!source || !target) return 0;

    // The constraint pulls the node toward coherence with its neighbour.
    // Positive weight = agreement, negative = tension.
    const stateDiff = target.hState - source.hState;
    return stateDiff * edge.constraintWeight * this.config.learningRate;
  }

  // ── Region expansion ──────────────────────────────────────────────

  /**
   * EXPAND_LOCAL_REGION — grow the affected region by one hop.
   * This is how constraint effects ripple through the graph.
   */
  private expandRegion(current: Set<string>): Set<string> {
    const expanded = new Set(current);
    for (const cellId of current) {
      const edges = this.store.neighbours(cellId);
      for (const edge of edges) {
        expanded.add(edge.toCell);
      }
      // Also check inbound edges
      const allEdges = this.store.allEdges(cellId);
      for (const edge of allEdges) {
        expanded.add(edge.fromCell);
        expanded.add(edge.toCell);
      }
    }
    return expanded;
  }

  // ── Stability detection: ΔH ≈ 0 ──────────────────────────────────

  /**
   * A node is stable when its average absolute delta over the
   * stability window drops below epsilon, and it has had enough
   * interactions to be meaningful.
   */
  private async checkStability(cellId: string): Promise<void> {
    const node = this.store.getNode(cellId);
    if (!node || node.isPruned) return;

    // Not enough interactions to judge
    if (node.interactionCount < this.config.minInteractions) return;

    // Compute average |ΔH| from all edges touching this node
    const edges = this.store.allEdges(cellId);
    if (edges.length === 0) return;

    let totalAvgDelta = 0;
    for (const edge of edges) {
      totalAvgDelta += this.store.avgDelta(edge.edgeId, this.config.stabilityWindow);
    }
    const avgDeltaH = totalAvgDelta / edges.length;

    const isStable = avgDeltaH < this.config.stabilityEpsilon;
    const wasStable = node.isStable;

    // Update node and log
    this.store.markStable(cellId, isStable);
    this.store.recordStability(cellId, avgDeltaH, isStable);

    // Fire event on transition to stable
    if (isStable && !wasStable) {
      this.events.onStabilised?.(this.store.getNode(cellId)!);

      // Write compliance event for BSV anchoring
      if (this.storage) {
        const payload = new TextEncoder().encode(
          JSON.stringify({ cellId, stabilisedAt: Date.now(), avgDeltaH }),
        );
        await this.storage.write(`paskian/stable/${cellId}`, payload);
      }
    }
  }

  // ── Pruning: remove weak/inconsistent nodes ───────────────────────

  /**
   * PRUNE(G) — remove nodes whose inbound constraint trend has
   * dropped below the prune threshold.
   *
   * Pruning corresponds to AFFINE cell consumption in Semantos.
   */
  private async prune(): Promise<void> {
    const candidates = this.store.pruningCandidates(this.config.pruneThreshold);

    for (const candidate of candidates) {
      // Record the pruning
      const record: PruningRecord = {
        cellId: candidate.cellId,
        typePath: candidate.typePath,
        reason: 'weak_constraint',
        finalHState: candidate.hState,
        prunedAt: Date.now(),
        anchorTxid: null, // filled in by the anchor layer
      };

      this.store.markPruned(candidate.cellId);
      this.store.recordPruning(record);

      this.events.onPruned?.(record);

      // Write compliance event for BSV anchoring
      if (this.storage) {
        const payload = new TextEncoder().encode(
          JSON.stringify(record),
        );
        await this.storage.write(`paskian/pruned/${candidate.cellId}`, payload);
      }
    }
  }

  // ── Query interface (game-facing) ──────────────────────────────────

  /**
   * Stable threads — learned structures that persist.
   * The world's memory.
   */
  stableThreads(): StableThread[] {
    return this.store.stableThreads();
  }

  /**
   * Emerging threads — narrative threads gaining traction.
   * The world's attention.
   */
  emergingThreads(): EmergingThread[] {
    return this.store.emergingThreads(this.config.stabilityWindow);
  }

  /**
   * Full graph snapshot for debugging or serialisation.
   */
  snapshot(): { nodes: PaskianNode[]; edges: PaskianEdge[] } {
    return this.store.snapshot();
  }

  /**
   * Get a single node by cell ID.
   */
  getNode(cellId: string): PaskianNode | null {
    return this.store.getNode(cellId);
  }

  // ── Phase 3: Commerce Review & Reputation ────────────────────────

  /**
   * Log a review interaction for reputation scoring.
   * Normalizes 1-5 star rating to strength -1.0..+1.0 and feeds
   * into the standard interact() loop as a commerce.review node.
   */
  async logReview(params: {
    providerCellId: string;
    reviewerCellId: string;
    rating: number;
    orderId: string;
  }): Promise<Set<string>> {
    // Normalize rating: 1 → -1.0, 3 → 0.0, 5 → +1.0
    const normalizedStrength = (params.rating - 3) / 2;

    return this.interact({
      cellId: params.providerCellId,
      kind: `commerce.review.${params.orderId}`,
      strength: normalizedStrength,
      relatedCells: [params.reviewerCellId],
      conversationContext: 'INDIVIDUAL',
      contextWeight: 0.7, // INDIVIDUAL context weight
      metadata: {
        rating: params.rating,
        orderId: params.orderId,
        reviewerCellId: params.reviewerCellId,
      },
    });
  }

  /**
   * Get the reputation score for a provider (ORGANIZATION).
   * Aggregates all commerce.review.* nodes linked to this provider.
   */
  getReputationScore(providerCellId: string): {
    score: number;
    totalReviews: number;
    histogram: number[];
  } {
    return this.store.getReputationScore(providerCellId);
  }

  // ── Lifecycle ──────────────────────────────────────────────────────

  close(): void {
    this.store.close();
  }
}

```
