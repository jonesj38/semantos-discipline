---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/game-state-db/snapshot-store.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.773489+00:00
---

# archive/apps-poker-agent/src/game-state-db/snapshot-store.ts

```ts
/**
 * Phase-snapshot store — owns the `state_snapshots` table.
 */

import type { DatabaseHandle } from './db-types';

import { mapStateSnapshotRow } from './row-mappers';
import type { SeqCounter } from './seq-counter';
import type { StateSnapshotRow } from './types';

export interface SnapshotInsert {
  phase: string;
  pot: number;
  communityCards: string[];
  activePlayers: number;
  currentBet: number;
}

export class SnapshotStore {
  constructor(
    private readonly db: DatabaseHandle,
    private readonly seq: SeqCounter,
  ) {}

  recordSnapshot(handId: number, snapshot: SnapshotInsert): number {
    const seq = this.seq.next();
    this.db
      .prepare(
        `INSERT INTO state_snapshots (seq, hand_id, phase, pot, community_cards, active_players, current_bet, timestamp)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      )
      .run(
        seq,
        handId,
        snapshot.phase,
        snapshot.pot,
        JSON.stringify(snapshot.communityCards),
        snapshot.activePlayers,
        snapshot.currentBet,
        Date.now(),
      );
    return seq;
  }

  getSnapshotsSince(sinceSeq: number): StateSnapshotRow[] {
    const rows = this.db
      .prepare('SELECT * FROM state_snapshots WHERE seq > ? ORDER BY seq')
      .all(sinceSeq) as unknown[];
    return rows.map(mapStateSnapshotRow);
  }
}

```
