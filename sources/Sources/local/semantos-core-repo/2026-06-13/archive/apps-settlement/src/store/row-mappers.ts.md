---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-settlement/src/store/row-mappers.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.712416+00:00
---

# archive/apps-settlement/src/store/row-mappers.ts

```ts
/**
 * Pure row→domain mappers for the Paskian store.
 *
 * Exported standalone so tests can fixture a row object and assert on
 * the mapped shape without spinning up a database. The legacy
 * `PaskianStore` defined `rowToNode` / `rowToEdge` as private methods;
 * the prompt-44 split lifts them out of the class so each per-concern
 * store can map its own rows without re-importing the class.
 */

import type { PaskianEdge, PaskianNode } from '../types';

import type { EdgeRow, NodeRow, PruningRow, StabilityRow } from './row-types';

export function mapNodeRow(row: NodeRow): PaskianNode {
  return {
    cellId: row.cell_id,
    typePath: row.type_path,
    hState: row.h_state,
    stability: row.stability,
    interactionCount: row.interaction_count,
    isStable: row.is_stable === 1,
    isPruned: row.is_pruned === 1,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

export function mapEdgeRow(row: EdgeRow): PaskianEdge {
  return {
    edgeId: row.edge_id,
    fromCell: row.from_cell,
    toCell: row.to_cell,
    constraintWeight: row.constraint_weight,
    deltaTrend: row.delta_trend,
    interactionCount: row.interaction_count,
    lastUpdated: row.last_updated,
  };
}

export function mapStabilityRow(row: StabilityRow): {
  cellId: string;
  deltaH: number;
  isStable: boolean;
  recordedAt: number;
} {
  return {
    cellId: row.cell_id,
    deltaH: row.delta_h,
    isStable: row.is_stable === 1,
    recordedAt: row.recorded_at,
  };
}

export function mapPruningRow(row: PruningRow): {
  cellId: string;
  typePath: string;
  reason: string;
  finalHState: number;
  prunedAt: number;
  anchorTxid: string | null;
} {
  return {
    cellId: row.cell_id,
    typePath: row.type_path,
    reason: row.reason,
    finalHState: row.final_h_state,
    prunedAt: row.pruned_at,
    anchorTxid: row.anchor_txid,
  };
}

```
