---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-settlement/src/store/__tests__/row-mappers.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.717289+00:00
---

# archive/apps-settlement/src/store/__tests__/row-mappers.test.ts

```ts
/**
 * Pure-fn unit tests for the row mappers — no database required.
 * The mappers were lifted out of `PaskianStore` private methods so
 * they can be tested in isolation; this file is the assertion that
 * the row→domain shape is preserved across the split.
 */

import { describe, expect, test } from 'bun:test';

import {
  mapEdgeRow,
  mapNodeRow,
  mapPruningRow,
  mapStabilityRow,
} from '../row-mappers';
import type {
  EdgeRow,
  NodeRow,
  PruningRow,
  StabilityRow,
} from '../row-types';

describe('row-mappers', () => {
  test('mapNodeRow converts SQLite row → PaskianNode camelCase + bools', () => {
    const row: NodeRow = {
      cell_id: 'cell-1',
      type_path: 'paskian.story.thread',
      h_state: 0.42,
      stability: 0.1,
      interaction_count: 7,
      is_stable: 1,
      is_pruned: 0,
      created_at: 1000,
      updated_at: 2000,
    };

    expect(mapNodeRow(row)).toEqual({
      cellId: 'cell-1',
      typePath: 'paskian.story.thread',
      hState: 0.42,
      stability: 0.1,
      interactionCount: 7,
      isStable: true,
      isPruned: false,
      createdAt: 1000,
      updatedAt: 2000,
    });
  });

  test('mapNodeRow treats is_pruned=1 as boolean true', () => {
    const row: NodeRow = {
      cell_id: 'x',
      type_path: 't',
      h_state: 0,
      stability: 0,
      interaction_count: 0,
      is_stable: 0,
      is_pruned: 1,
      created_at: 0,
      updated_at: 0,
    };
    expect(mapNodeRow(row).isPruned).toBe(true);
    expect(mapNodeRow(row).isStable).toBe(false);
  });

  test('mapEdgeRow converts SQLite row → PaskianEdge camelCase', () => {
    const row: EdgeRow = {
      edge_id: 'a-b',
      from_cell: 'a',
      to_cell: 'b',
      constraint_weight: 1.5,
      delta_trend: 0.2,
      interaction_count: 3,
      last_updated: 9999,
    };

    expect(mapEdgeRow(row)).toEqual({
      edgeId: 'a-b',
      fromCell: 'a',
      toCell: 'b',
      constraintWeight: 1.5,
      deltaTrend: 0.2,
      interactionCount: 3,
      lastUpdated: 9999,
    });
  });

  test('mapStabilityRow converts is_stable int → boolean', () => {
    const row: StabilityRow = {
      cell_id: 'c',
      delta_h: 0.001,
      is_stable: 1,
      recorded_at: 42,
    };

    expect(mapStabilityRow(row)).toEqual({
      cellId: 'c',
      deltaH: 0.001,
      isStable: true,
      recordedAt: 42,
    });
  });

  test('mapPruningRow converts SQLite row → PruningRecord shape', () => {
    const row: PruningRow = {
      cell_id: 'cell-x',
      type_path: 'paskian.story.thread',
      reason: 'weak_constraint',
      final_h_state: -0.5,
      pruned_at: 12345,
      anchor_txid: null,
    };

    expect(mapPruningRow(row)).toEqual({
      cellId: 'cell-x',
      typePath: 'paskian.story.thread',
      reason: 'weak_constraint',
      finalHState: -0.5,
      prunedAt: 12345,
      anchorTxid: null,
    });
  });
});

```
