---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/game-state-db/seq-counter.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.775270+00:00
---

# archive/apps-poker-agent/src/game-state-db/seq-counter.ts

```ts
/**
 * Monotonic sequence counter shared across actions, snapshots,
 * and celltoken refs. Loads its starting value from the highest
 * existing seq across those three tables so re-opening a DB
 * resumes numbering correctly.
 */

import type { DatabaseHandle } from './db-types';

export interface SeqCounter {
  next(): number;
  current(): number;
}

/** Build a fresh counter, seeded from the persisted maxima. */
export function makeSeqCounter(db: DatabaseHandle): SeqCounter {
  let value = loadInitialSeq(db);
  return {
    next: () => ++value,
    current: () => value,
  };
}

/** Read the highest seq across actions/snapshots/celltoken_refs. */
function loadInitialSeq(db: DatabaseHandle): number {
  const a = db.prepare('SELECT MAX(seq) as m FROM actions').get() as { m: number | null } | null;
  const s = db.prepare('SELECT MAX(seq) as m FROM state_snapshots').get() as { m: number | null } | null;
  const t = db.prepare('SELECT MAX(seq) as m FROM celltoken_refs').get() as { m: number | null } | null;
  return Math.max(a?.m ?? 0, s?.m ?? 0, t?.m ?? 0);
}

```
