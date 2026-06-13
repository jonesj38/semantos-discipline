---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-settlement/src/store/__tests__/stability.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.717606+00:00
---

# archive/apps-settlement/src/store/__tests__/stability.test.ts

```ts
/**
 * Per-concern unit tests for `StabilityTracker`.
 *
 * The tracker is append-only — there's no read API on the class
 * itself, so the tests reach into the underlying `stability_log`
 * table to verify the appended shapes.
 */

import { Database } from 'bun:sqlite';
import { describe, expect, test } from 'bun:test';

import { NodeStore } from '../node-index';
import { applyPaskianSchema } from '../paskian-schema';
import { StabilityTracker } from '../stability';

interface RawStabilityRow {
  cell_id: string;
  delta_h: number;
  is_stable: number;
}

describe('StabilityTracker', () => {
  test('recordStability appends rows with the right shape', () => {
    const db = new Database(':memory:');
    applyPaskianSchema(db);
    const nodes = new NodeStore(db);
    const stability = new StabilityTracker(db);

    nodes.upsertNode({ cellId: 'c', typePath: 't' });
    stability.recordStability('c', 0.001, true);
    stability.recordStability('c', 0.5, false);

    const rows = db
      .prepare('SELECT cell_id, delta_h, is_stable FROM stability_log ORDER BY id')
      .all() as RawStabilityRow[];
    expect(rows).toEqual([
      { cell_id: 'c', delta_h: 0.001, is_stable: 1 },
      { cell_id: 'c', delta_h: 0.5, is_stable: 0 },
    ]);
    db.close();
  });
});

```
