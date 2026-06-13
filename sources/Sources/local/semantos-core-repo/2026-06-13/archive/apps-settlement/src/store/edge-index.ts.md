---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-settlement/src/store/edge-index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.711290+00:00
---

# archive/apps-settlement/src/store/edge-index.ts

```ts
/**
 * Edge index — owns the `paskian_edges` table (forward + reverse
 * adjacency).
 *
 * Tracks constraint weights and delta-trend EMAs between cells.
 * Pure CRUD; aggregate queries (e.g. inbound trend, cross-table
 * joins) live in `delta-log.ts` and `query.ts`. Per the prompt-44
 * spec this concern has no knowledge of any other concern.
 */

import type { PaskianEdge } from '../types';

import type { DatabaseHandle } from './db-types';
import { mapEdgeRow } from './row-mappers';
import type { EdgeRow } from './row-types';

/** Compute the deterministic edge ID from its endpoints. */
export function makeEdgeId(fromCell: string, toCell: string): string {
  return `${fromCell}-${toCell}`;
}

export class EdgeStore {
  constructor(private readonly db: DatabaseHandle) {}

  /** Upsert an edge between two cells. Returns the deterministic edge_id. */
  upsertEdge(fromCell: string, toCell: string): string {
    const edgeId = makeEdgeId(fromCell, toCell);
    const now = Date.now();
    this.db
      .prepare(
        `INSERT INTO paskian_edges (edge_id, from_cell, to_cell, last_updated)
         VALUES (?, ?, ?, ?)
         ON CONFLICT(edge_id) DO UPDATE SET last_updated = ?`,
      )
      .run(edgeId, fromCell, toCell, now, now);
    return edgeId;
  }

  /** Fetch a single edge by id. */
  getEdge(edgeId: string): PaskianEdge | null {
    const row = this.db
      .prepare('SELECT * FROM paskian_edges WHERE edge_id = ?')
      .get(edgeId) as EdgeRow | null;
    return row ? mapEdgeRow(row) : null;
  }

  /** Outgoing neighbours (edges where from_cell = cellId). */
  neighbours(cellId: string): PaskianEdge[] {
    const rows = this.db
      .prepare('SELECT * FROM paskian_edges WHERE from_cell = ?')
      .all(cellId) as EdgeRow[];
    return rows.map(mapEdgeRow);
  }

  /** All edges touching a node (both directions). */
  allEdges(cellId: string): PaskianEdge[] {
    const rows = this.db
      .prepare('SELECT * FROM paskian_edges WHERE from_cell = ? OR to_cell = ?')
      .all(cellId, cellId) as EdgeRow[];
    return rows.map(mapEdgeRow);
  }

  /** Every edge in the graph — for snapshot/debug. */
  allEdgesGlobal(): PaskianEdge[] {
    const rows = this.db
      .prepare('SELECT * FROM paskian_edges')
      .all() as EdgeRow[];
    return rows.map(mapEdgeRow);
  }

  /** Increment constraint weight + interaction count and stamp last_updated. */
  updateEdgeWeight(edgeId: string, delta: number): void {
    const now = Date.now();
    this.db
      .prepare(
        `UPDATE paskian_edges
         SET constraint_weight = constraint_weight + ?,
             interaction_count = interaction_count + 1,
             last_updated = ?
         WHERE edge_id = ?`,
      )
      .run(delta, now, edgeId);
  }

  /** Set the delta-trend EMA for an edge. */
  updateEdgeTrend(edgeId: string, trend: number): void {
    this.db
      .prepare('UPDATE paskian_edges SET delta_trend = ? WHERE edge_id = ?')
      .run(trend, edgeId);
  }
}

```
