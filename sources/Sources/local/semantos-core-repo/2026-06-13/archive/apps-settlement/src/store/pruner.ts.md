---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-settlement/src/store/pruner.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.709041+00:00
---

# archive/apps-settlement/src/store/pruner.ts

```ts
/**
 * Pruner — owns the `pruning_log` table and the candidate query that
 * picks weak nodes for pruning.
 *
 * Note that flipping `is_pruned = 1` on `paskian_nodes` belongs to
 * the node store; this concern just keeps the durable history of
 * pruning events and surfaces the trend-based candidates query.
 */

import type { PaskianNode, PruningRecord } from '../types';

import type { DatabaseHandle } from './db-types';
import { mapNodeRow } from './row-mappers';
import type { NodeRow } from './row-types';

export class Pruner {
  constructor(private readonly db: DatabaseHandle) {}

  /** Append a pruning record. The caller is responsible for marking
   *  the node pruned via the node store. */
  recordPruning(record: PruningRecord): void {
    this.db
      .prepare(
        `INSERT INTO pruning_log
           (cell_id, type_path, reason, final_h_state, pruned_at, anchor_txid)
         VALUES (?, ?, ?, ?, ?, ?)`,
      )
      .run(
        record.cellId,
        record.typePath,
        record.reason,
        record.finalHState,
        record.prunedAt,
        record.anchorTxid,
      );
  }

  /**
   * Pruning candidates: active nodes whose average inbound delta
   * trend has dropped below the threshold.
   *
   * The query joins nodes against their inbound edges and groups by
   * cell — it's the cross-table read that decides the prune set.
   */
  pruningCandidates(threshold: number): PaskianNode[] {
    const rows = this.db
      .prepare(
        `SELECT n.*
         FROM paskian_nodes n
         JOIN paskian_edges e ON e.to_cell = n.cell_id
         WHERE n.is_pruned = 0
         GROUP BY n.cell_id
         HAVING AVG(e.delta_trend) < ?`,
      )
      .all(threshold) as NodeRow[];
    return rows.map(mapNodeRow);
  }
}

```
