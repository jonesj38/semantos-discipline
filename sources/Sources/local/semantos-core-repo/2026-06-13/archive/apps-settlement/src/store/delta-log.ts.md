---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-settlement/src/store/delta-log.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.710451+00:00
---

# archive/apps-settlement/src/store/delta-log.ts

```ts
/**
 * Delta log — owns the `constraint_deltas` table plus the rolling
 * aggregates derived from it (per-edge avgDelta, per-node inboundTrend).
 *
 * The legacy `PaskianStore` mixed `recordDelta` / `avgDelta` /
 * `inboundTrend` next to the edge CRUD; the prompt-44 split factors
 * the delta log out as its own concern because stability detection
 * and pruning both consume from it without otherwise touching edges.
 *
 * `inboundTrend` reads `delta_trend` off `paskian_edges` — that's an
 * aggregate over the most recent EMA per inbound edge, so it lives
 * here with the other delta-derived aggregates rather than in the
 * pure edge store.
 */

import type { DatabaseHandle } from './db-types';

export class DeltaLog {
  constructor(private readonly db: DatabaseHandle) {}

  /** Append a constraint-delta record. */
  recordDelta(
    edgeId: string,
    delta: number,
    interaction: string,
    cellVersion?: number,
    prevStateHash?: string,
  ): void {
    this.db
      .prepare(
        `INSERT INTO constraint_deltas
           (edge_id, delta, interaction, cell_version, prev_state_hash, timestamp)
         VALUES (?, ?, ?, ?, ?, ?)`,
      )
      .run(
        edgeId,
        delta,
        interaction,
        cellVersion ?? 0,
        prevStateHash ?? '',
        Date.now(),
      );
  }

  /**
   * Average absolute delta for an edge over a time window (ms).
   * Used for stability detection: if this → 0, the edge is stable.
   */
  avgDelta(edgeId: string, windowMs: number): number {
    const since = Date.now() - windowMs;
    const row = this.db
      .prepare(
        `SELECT AVG(ABS(delta)) as avg_delta
         FROM constraint_deltas
         WHERE edge_id = ? AND timestamp > ?`,
      )
      .get(edgeId, since) as { avg_delta: number | null } | null;
    return row?.avg_delta ?? 0;
  }

  /**
   * Average delta trend across all edges pointing to a node.
   * Used for pruning: if trend < threshold the node is weakening.
   *
   * Reads `delta_trend` off `paskian_edges` — the EMA there is the
   * latest summary of this edge's recent deltas.
   */
  inboundTrend(cellId: string): number {
    const row = this.db
      .prepare(
        `SELECT AVG(delta_trend) as avg_trend
         FROM paskian_edges
         WHERE to_cell = ?`,
      )
      .get(cellId) as { avg_trend: number | null } | null;
    return row?.avg_trend ?? 0;
  }
}

```
