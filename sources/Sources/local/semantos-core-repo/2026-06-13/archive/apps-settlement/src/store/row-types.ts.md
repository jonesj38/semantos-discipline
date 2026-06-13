---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-settlement/src/store/row-types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.709464+00:00
---

# archive/apps-settlement/src/store/row-types.ts

```ts
/**
 * SQLite row shapes for the Paskian store. These mirror the columns
 * of each table 1:1 and are kept separate from the domain types in
 * `../types.ts` (which use camelCase and exclude SQLite booleans).
 *
 * Per-concern stores read these row shapes; the row mappers in
 * `row-mappers.ts` convert them to the domain types.
 */

export interface NodeRow {
  cell_id: string;
  type_path: string;
  h_state: number;
  stability: number;
  interaction_count: number;
  /** SQLite boolean (0/1). */
  is_stable: number;
  /** SQLite boolean (0/1). */
  is_pruned: number;
  created_at: number;
  updated_at: number;
}

export interface EdgeRow {
  edge_id: string;
  from_cell: string;
  to_cell: string;
  constraint_weight: number;
  delta_trend: number;
  interaction_count: number;
  last_updated: number;
}

export interface DeltaRow {
  id: number;
  edge_id: string;
  delta: number;
  interaction: string;
  cell_version: number;
  prev_state_hash: string;
  timestamp: number;
}

export interface StabilityRow {
  cell_id: string;
  delta_h: number;
  /** SQLite boolean (0/1). */
  is_stable: number;
  recorded_at: number;
}

export interface PruningRow {
  cell_id: string;
  type_path: string;
  reason: string;
  final_h_state: number;
  pruned_at: number;
  anchor_txid: string | null;
}

```
