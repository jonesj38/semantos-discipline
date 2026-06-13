---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-settlement/src/store/node-index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.710160+00:00
---

# archive/apps-settlement/src/store/node-index.ts

```ts
/**
 * Node index — owns the `paskian_nodes` table.
 *
 * Pure CRUD for graph nodes (h_state, stability/pruned flags,
 * interaction count). Cross-table reads (e.g. nodes joined with
 * edges) live in `query.ts`. Per the prompt-44 spec this concern
 * has no knowledge of any other concern.
 */

import type { PaskianNode } from '../types';

import type { DatabaseHandle } from './db-types';
import { mapNodeRow } from './row-mappers';
import type { NodeRow } from './row-types';

export class NodeStore {
  constructor(private readonly db: DatabaseHandle) {}

  /** Upsert a node's identity (cell_id + type_path). Idempotent. */
  upsertNode(node: Pick<PaskianNode, 'cellId' | 'typePath'>): void {
    const now = Date.now();
    this.db
      .prepare(
        `INSERT INTO paskian_nodes (cell_id, type_path, created_at, updated_at)
         VALUES (?, ?, ?, ?)
         ON CONFLICT(cell_id) DO UPDATE SET updated_at = ?`,
      )
      .run(node.cellId, node.typePath, now, now, now);
  }

  /** Fetch a single node by cell ID. */
  getNode(cellId: string): PaskianNode | null {
    const row = this.db
      .prepare('SELECT * FROM paskian_nodes WHERE cell_id = ?')
      .get(cellId) as NodeRow | null;
    return row ? mapNodeRow(row) : null;
  }

  /**
   * Apply a delta to the node's h_state, increment interaction
   * count, and stamp updated_at.
   */
  updateNodeState(cellId: string, deltaH: number): void {
    const now = Date.now();
    this.db
      .prepare(
        `UPDATE paskian_nodes
         SET h_state = h_state + ?,
             interaction_count = interaction_count + 1,
             updated_at = ?
         WHERE cell_id = ?`,
      )
      .run(deltaH, now, cellId);
  }

  /** Mark or unmark stability. */
  markStable(cellId: string, isStable: boolean): void {
    this.db
      .prepare('UPDATE paskian_nodes SET is_stable = ? WHERE cell_id = ?')
      .run(isStable ? 1 : 0, cellId);
  }

  /** Mark a node as pruned (AFFINE consumed). One-way. */
  markPruned(cellId: string): void {
    this.db
      .prepare('UPDATE paskian_nodes SET is_pruned = 1 WHERE cell_id = ?')
      .run(cellId);
  }

  /** All active (non-pruned) nodes. */
  activeNodes(): PaskianNode[] {
    const rows = this.db
      .prepare('SELECT * FROM paskian_nodes WHERE is_pruned = 0')
      .all() as NodeRow[];
    return rows.map(mapNodeRow);
  }

  /** Every node, regardless of pruned state — for snapshot/debug. */
  allNodes(): PaskianNode[] {
    const rows = this.db
      .prepare('SELECT * FROM paskian_nodes')
      .all() as NodeRow[];
    return rows.map(mapNodeRow);
  }
}

```
