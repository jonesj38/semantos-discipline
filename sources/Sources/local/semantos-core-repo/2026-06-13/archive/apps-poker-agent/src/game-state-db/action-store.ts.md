---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/game-state-db/action-store.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.775546+00:00
---

# archive/apps-poker-agent/src/game-state-db/action-store.ts

```ts
/**
 * Action store — owns the `actions` table. Pulls a fresh seq from
 * the shared `SeqCounter` for every insert.
 */

import type { DatabaseHandle } from './db-types';

import { mapActionRow } from './row-mappers';
import type { SeqCounter } from './seq-counter';
import type { ActionRow } from './types';

export interface ActionInsert {
  playerId: string;
  actionType: string;
  amount: number;
  phase: string;
  chipsAfter: number;
  potAfter: number;
}

export class ActionStore {
  constructor(
    private readonly db: DatabaseHandle,
    private readonly seq: SeqCounter,
  ) {}

  recordAction(handId: number, action: ActionInsert): number {
    const seq = this.seq.next();
    this.db
      .prepare(
        `INSERT INTO actions (seq, hand_id, player_id, action_type, amount, phase, chips_after, pot_after, timestamp)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      )
      .run(
        seq,
        handId,
        action.playerId,
        action.actionType,
        action.amount,
        action.phase,
        action.chipsAfter,
        action.potAfter,
        Date.now(),
      );
    return seq;
  }

  /** Actions strictly after `sinceSeq`; optional `handId` filter. */
  getActionsSince(sinceSeq: number, handId?: number): ActionRow[] {
    const rows =
      handId !== undefined
        ? (this.db
            .prepare('SELECT * FROM actions WHERE seq > ? AND hand_id = ? ORDER BY seq')
            .all(sinceSeq, handId) as unknown[])
        : (this.db
            .prepare('SELECT * FROM actions WHERE seq > ? ORDER BY seq')
            .all(sinceSeq) as unknown[]);
    return rows.map(mapActionRow);
  }
}

```
