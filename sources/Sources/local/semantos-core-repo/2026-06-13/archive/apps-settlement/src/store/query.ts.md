---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-settlement/src/store/query.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.710728+00:00
---

# archive/apps-settlement/src/store/query.ts

```ts
/**
 * Query surface — game-facing read-only queries that span more than
 * one Paskian table.
 *
 * Lives in its own module because cross-table SQL doesn't fit
 * cleanly inside any single per-concern store. Mirrors the
 * `context-builder.ts` role in `apps/poker-agent/src/game-state-db/`.
 *
 * Pure read functions — never mutates. Mutations belong to the
 * per-concern stores; this module composes their underlying tables
 * for game-side consumption.
 */

import type { EmergingThread, PaskianEdge, PaskianNode, StableThread } from '../types';

import type { DatabaseHandle } from './db-types';
import { mapEdgeRow, mapNodeRow } from './row-mappers';
import type { EdgeRow, NodeRow } from './row-types';

export interface ReputationScore {
  score: number;
  totalReviews: number;
  histogram: number[];
}

export class QuerySurface {
  constructor(private readonly db: DatabaseHandle) {}

  /**
   * Stable threads — nodes that have settled and persist. These are
   * the learned structures, the world's memory.
   */
  stableThreads(): StableThread[] {
    const rows = this.db
      .prepare(
        `SELECT n.*,
                COALESCE(SUM(e.constraint_weight), 0) as total_weight
         FROM paskian_nodes n
         LEFT JOIN paskian_edges e ON e.to_cell = n.cell_id
         WHERE n.is_stable = 1 AND n.is_pruned = 0
         GROUP BY n.cell_id
         ORDER BY n.h_state DESC`,
      )
      .all() as (NodeRow & { total_weight: number })[];

    return rows.map((r) => ({
      ...mapNodeRow(r),
      totalConstraintStrength: r.total_weight,
    }));
  }

  /**
   * Emerging threads — nodes with positive momentum that haven't
   * stabilised yet. Narrative threads gaining traction.
   */
  emergingThreads(windowMs: number): EmergingThread[] {
    const since = Date.now() - windowMs;
    const rows = this.db
      .prepare(
        `SELECT n.*, AVG(d.delta) as momentum
         FROM paskian_nodes n
         JOIN paskian_edges e ON e.to_cell = n.cell_id
         JOIN constraint_deltas d ON d.edge_id = e.edge_id
         WHERE d.timestamp > ?
           AND n.is_stable = 0
           AND n.is_pruned = 0
         GROUP BY n.cell_id
         HAVING momentum > 0
         ORDER BY momentum DESC`,
      )
      .all(since) as (NodeRow & { momentum: number })[];

    return rows.map((r) => ({
      ...mapNodeRow(r),
      momentum: r.momentum,
    }));
  }

  /** Full graph snapshot — nodes + edges, including pruned. */
  snapshot(): { nodes: PaskianNode[]; edges: PaskianEdge[] } {
    const nodes = (this.db.prepare('SELECT * FROM paskian_nodes').all() as NodeRow[])
      .map(mapNodeRow);
    const edges = (this.db.prepare('SELECT * FROM paskian_edges').all() as EdgeRow[])
      .map(mapEdgeRow);
    return { nodes, edges };
  }

  /**
   * Aggregate reputation score for a provider (ORGANIZATION).
   *
   * Queries all `commerce.review.*` edges where the provider is the
   * primary cell. Applies time-decay weighting: ratings in the last
   * 30 days count 2×, older ratings decay by `(1 - days/365)`. Score
   * is clamped to `[1.0, 5.0]`.
   */
  getReputationScore(providerCellId: string): ReputationScore {
    const now = Date.now();
    const thirtyDaysAgo = now - 30 * 24 * 60 * 60 * 1000;

    const edges = this.db
      .prepare(
        `SELECT e.edge_id, e.from_cell, e.to_cell, e.constraint_weight, e.last_updated,
                n.h_state, n.type_path, n.created_at
         FROM paskian_edges e
         JOIN paskian_nodes n ON n.cell_id = e.from_cell
         WHERE e.from_cell = ? AND n.type_path LIKE 'commerce.review.%'`,
      )
      .all(providerCellId) as Array<{
        edge_id: string;
        from_cell: string;
        to_cell: string;
        constraint_weight: number;
        last_updated: number;
        h_state: number;
        type_path: string;
        created_at: number;
      }>;

    if (edges.length === 0) {
      return { score: 0, totalReviews: 0, histogram: [0, 0, 0, 0, 0] };
    }

    let weightedSum = 0;
    let totalWeight = 0;
    const histogram = [0, 0, 0, 0, 0]; // 1-5 stars

    for (const e of edges) {
      // h_state range is roughly -1..+1 → rating 1..5
      const rating = Math.round(e.h_state * 2 + 3);
      const clampedRating = Math.max(1, Math.min(5, rating));
      histogram[clampedRating - 1]++;

      const daysSinceCreation = (now - e.created_at) / (24 * 60 * 60 * 1000);
      const isRecent = e.created_at > thirtyDaysAgo;
      const decayWeight = isRecent ? 2.0 : Math.max(0, 1 - daysSinceCreation / 365);

      weightedSum += clampedRating * decayWeight;
      totalWeight += decayWeight;
    }

    const rawScore = totalWeight > 0 ? weightedSum / totalWeight : 0;
    const score = Math.max(1.0, Math.min(5.0, rawScore));

    return {
      score,
      totalReviews: edges.length,
      histogram,
    };
  }
}

```
