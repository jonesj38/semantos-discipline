---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-settlement/src/store/stability.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.711864+00:00
---

# archive/apps-settlement/src/store/stability.ts

```ts
/**
 * Stability tracker — owns the `stability_log` table.
 *
 * The legacy store kept `recordStability` next to the node update
 * helpers; the prompt-44 split puts stability history in its own
 * concern because it's append-only and consumed by the adapter's
 * stability-check loop, not by the per-row node CRUD.
 */

import type { DatabaseHandle } from './db-types';

export class StabilityTracker {
  constructor(private readonly db: DatabaseHandle) {}

  /** Record one ΔH observation for a cell. Append-only. */
  recordStability(cellId: string, deltaH: number, isStable: boolean): void {
    this.db
      .prepare(
        `INSERT INTO stability_log (cell_id, delta_h, is_stable, recorded_at)
         VALUES (?, ?, ?, ?)`,
      )
      .run(cellId, deltaH, isStable ? 1 : 0, Date.now());
  }
}

```
