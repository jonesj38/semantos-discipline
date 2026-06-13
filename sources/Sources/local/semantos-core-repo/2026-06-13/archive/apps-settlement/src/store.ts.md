---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-settlement/src/store.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.707941+00:00
---

# archive/apps-settlement/src/store.ts

```ts
/**
 * @deprecated The legacy 501-LOC `apps/settlement/src/store.ts` was
 * split into per-concern modules under `./store/` by prompt 44. Import
 * from the barrel (`./store`) — Bun resolves the directory's
 * `index.ts` first, so existing `from './store'` imports keep working.
 *
 * This file remains as a thin re-export shim for any consumer that
 * resolves the file path (`store.ts`) directly rather than the
 * directory. Remove once all consumers migrate to `./store` or the
 * named per-concern module.
 *
 * The split:
 *
 *   store/db-types.ts          — minimal `DatabaseHandle` interface
 *   store/paskian-schema.ts    — DDL + `applyPaskianSchema`
 *   store/row-types.ts         — SQLite row shapes
 *   store/row-mappers.ts       — pure row→domain converters
 *   store/node-index.ts        — paskian_nodes CRUD
 *   store/edge-index.ts        — paskian_edges CRUD
 *   store/delta-log.ts         — constraint_deltas + avgDelta + inboundTrend
 *   store/stability.ts         — stability_log append
 *   store/pruner.ts            — pruning_log + pruningCandidates
 *   store/query.ts             — game-facing cross-table reads
 *   store/settlement-store.ts  — composes the above; preserves legacy API
 */

export { PaskianStore } from './store/settlement-store';

```
