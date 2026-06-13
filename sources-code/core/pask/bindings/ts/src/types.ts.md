---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/pask/bindings/ts/src/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.934225+00:00
---

# core/pask/bindings/ts/src/types.ts

```ts
/**
 * Public Pask types — mirror friend-semantos/packages/paskian/src/types.ts
 * so callers can swap implementations transparently. Internally these
 * are projections of the WASM extern structs (Node, Edge, StableThread).
 */

export interface PaskianNode {
  cellId: string;
  typePath: string;
  hState: number;
  stability: number;
  interactionCount: number;
  isStable: boolean;
  isPruned: boolean;
  createdAt: number;
  updatedAt: number;
}

export interface PaskianEdge {
  edgeId: string;
  fromCell: string;
  toCell: string;
  constraintWeight: number;
  deltaTrend: number;
  interactionCount: number;
  lastUpdated: number;
}

export interface PaskianInteraction {
  cellId: string;
  kind: string;
  /** Pre-multiplied by contextWeight (matches adapter.ts:effectiveStrength). */
  strength: number;
  relatedCells?: string[];
  /** Optional caller-supplied clock (epoch ms). Defaults to Date.now(). */
  nowMs?: number;
}

export interface StableThread extends PaskianNode {
  totalConstraintStrength: number;
}

export interface PaskConfig {
  pruneThreshold: number;
  stabilityEpsilon: number;
  minInteractions: number;
  propagationDepth: number;
  learningRate: number;
  stabilityWindowMs: number;
  stabilityCheckEvery: number;
  pruneEvery: number;
}

export const DEFAULT_PASK_CONFIG: PaskConfig = {
  pruneThreshold: -0.3,
  stabilityEpsilon: 0.01,
  minInteractions: 5,
  propagationDepth: 3,
  learningRate: 0.1,
  stabilityWindowMs: 60_000,
  stabilityCheckEvery: 1,
  pruneEvery: 1,
};

```
