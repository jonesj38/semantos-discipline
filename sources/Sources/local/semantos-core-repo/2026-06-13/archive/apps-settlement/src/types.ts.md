---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-settlement/src/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.706685+00:00
---

# archive/apps-settlement/src/types.ts

```ts
/**
 * Paskian Learning Layer — Core Types
 *
 * These types model the paper's formulation:
 *   G = (V, E)         → PaskianGraph
 *   h_i                → PaskianNode.hState
 *   C_ij(h_i, h_j)     → PaskianEdge.constraintWeight
 *   ΔH ≈ 0             → PaskianNode.isStable
 *   Prune if weak       → PruningRecord
 *
 * All types are pure data — no methods. The PaskianStore class
 * (store.ts) owns the SQLite persistence. The PaskianAdapter
 * (adapter.ts) owns the learning dynamics.
 */

// ── Graph primitives ───────────────────────────────────────────────────

export interface PaskianNode {
  /** Semantos cell ID backing this node. */
  cellId: string;
  /** Type path (e.g. 'paskian.story.thread.romance'). */
  typePath: string;
  /** Current node state value — h_i in the paper. */
  hState: number;
  /** Running average of |ΔH| — used for stability detection. */
  stability: number;
  /** Total interactions this node has participated in. */
  interactionCount: number;
  /** Whether ΔH < ε for enough interactions. */
  isStable: boolean;
  /** Whether this node has been pruned (AFFINE consumed). */
  isPruned: boolean;
  /** Creation timestamp (epoch ms). */
  createdAt: number;
  /** Last update timestamp (epoch ms). */
  updatedAt: number;
}

export interface PaskianEdge {
  /** Unique edge identifier (fromCell-toCell). */
  edgeId: string;
  /** Source cell ID. */
  fromCell: string;
  /** Target cell ID. */
  toCell: string;
  /** Current constraint weight — C_ij strength. */
  constraintWeight: number;
  /** Trend of recent deltas (positive = strengthening). */
  deltaTrend: number;
  /** Number of interactions affecting this edge. */
  interactionCount: number;
  /** Last update timestamp (epoch ms). */
  lastUpdated: number;
  /** Phase 2: Which conversation context generated this edge (SELF, INDIVIDUAL, GROUP, AI_AGENT). */
  conversationContext?: string;
  /** Phase 2: Context weight for dimension scoring (1.0 = self, 0.3 = AI). */
  contextWeight?: number;
}

export interface ConstraintDelta {
  /** Auto-increment ID. */
  id: number;
  /** Which edge was affected. */
  edgeId: string;
  /** The delta applied this interaction. */
  delta: number;
  /** Description of what caused the delta. */
  interaction: string;
  /** Cell version at the time of delta. */
  cellVersion: number;
  /** Links to cell DAG (hex). */
  prevStateHash: string;
  /** Timestamp (epoch ms). */
  timestamp: number;
}

export interface StabilityRecord {
  cellId: string;
  deltaH: number;
  isStable: boolean;
  recordedAt: number;
}

export interface PruningRecord {
  cellId: string;
  typePath: string;
  reason: 'weak_constraint' | 'inconsistent' | 'manual';
  finalHState: number;
  prunedAt: number;
  /** BSV anchor txid for the consumption event (hex, or null if not yet anchored). */
  anchorTxid: string | null;
}

// ── Interaction event ──────────────────────────────────────────────────

/**
 * An interaction event that modifies the Paskian graph.
 * This is the I in: G ← Φ(G, I)
 */
export interface PaskianInteraction {
  /** Which cell was directly affected. */
  cellId: string;
  /** Human-readable label for the interaction type. */
  kind: string;
  /** Signed strength of the interaction (positive = reinforcing). */
  strength: number;
  /** Optional: other cells to create edges to. */
  relatedCells?: string[];
  /** Optional: metadata for the constraint delta log. */
  metadata?: Record<string, unknown>;
  /** Phase 2: Conversation context type (SELF, INDIVIDUAL, GROUP, AI_AGENT). */
  conversationContext?: string;
  /** Phase 2: Context weight for dimension scoring modulation. */
  contextWeight?: number;
}

// ── Query results ──────────────────────────────────────────────────────

export interface StableThread extends PaskianNode {
  /** Computed from edge weights pointing to this node. */
  totalConstraintStrength: number;
}

export interface EmergingThread extends PaskianNode {
  /** Average delta momentum over the stability window. */
  momentum: number;
}

// ── Adapter event callbacks ────────────────────────────────────────────

export interface PaskianEvents {
  /** Fired when a node is declared stable. */
  onStabilised?(node: PaskianNode): void;
  /** Fired when a node or edge is pruned. */
  onPruned?(record: PruningRecord): void;
  /** Fired when a new edge is created. */
  onEdgeCreated?(edge: PaskianEdge): void;
  /** Fired when constraint propagation completes a pass. */
  onPropagationComplete?(affectedCount: number): void;
}

```
