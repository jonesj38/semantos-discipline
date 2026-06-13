---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-settlement/src/store/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.709771+00:00
---

# archive/apps-settlement/src/store/index.ts

```ts
/**
 * Settlement-store barrel — public surface for both the Paskian
 * constraint-graph store (prompt 44) and the Border-Router
 * provenance store (phase H3).
 *
 * The Paskian split (prompt 44) factors the legacy 501-LOC
 * `apps/settlement/src/store.ts` into per-concern modules:
 *
 *   schema             — DDL + applyPaskianSchema
 *   row-types          — SQLite row shapes
 *   row-mappers        — pure row→domain converters
 *   node-store         — paskian_nodes CRUD
 *   edge-store         — paskian_edges CRUD
 *   delta-log          — constraint_deltas append + aggregates
 *   stability-tracker  — stability_log append
 *   pruner             — pruning_log append + pruningCandidates
 *   query-surface      — game-facing cross-table reads
 *   paskian-store-facade — composes everything; preserves legacy API
 */

// Paskian split
export { PaskianStore } from './settlement-store';
export {
  PASKIAN_SCHEMA_SQL,
  PASKIAN_SCHEMA_VERSION,
  applyPaskianSchema,
} from './paskian-schema';
export type { DatabaseHandle, PreparedStatement } from './db-types';
export type {
  EdgeRow,
  NodeRow,
  DeltaRow,
  StabilityRow,
  PruningRow,
} from './row-types';
export {
  mapEdgeRow,
  mapNodeRow,
  mapPruningRow,
  mapStabilityRow,
} from './row-mappers';
export { NodeStore } from './node-index';
export { EdgeStore, makeEdgeId } from './edge-index';
export { DeltaLog } from './delta-log';
export { StabilityTracker } from './stability';
export { Pruner } from './pruner';
export { QuerySurface, type ReputationScore } from './query';

// Border-Router provenance store (phase H3, sibling concern)
export { ProvenanceStore } from './provenance-store';

```
