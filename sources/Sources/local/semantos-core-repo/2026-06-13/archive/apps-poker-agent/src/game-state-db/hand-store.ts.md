---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/game-state-db/hand-store.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.774172+00:00
---

# archive/apps-poker-agent/src/game-state-db/hand-store.ts

```ts
/**
 * Hand lifecycle store — owns the `hands` table.
 */

import type { DatabaseHandle } from './db-types';

export class HandStore {
  constructor(private readonly db: DatabaseHandle) {}

  /** Insert a fresh hand and return the AUTOINCREMENT hand_id. */
  startHand(gameId: string, handNumber: number, dealerSeat: number): number {
    const result = this.db
      .prepare(
        `INSERT INTO hands (game_id, hand_number, dealer_seat, started_at)
         VALUES (?, ?, ?, ?)`,
      )
      .run(gameId, handNumber, dealerSeat, Date.now());
    return Number(result.lastInsertRowid);
  }

  /** Mark an existing hand as ended and credit the winner. */
  endHand(handId: number, winnerId: string, potTotal: number): void {
    this.db
      .prepare(`UPDATE hands SET ended_at = ?, winner_id = ?, pot_total = ? WHERE hand_id = ?`)
      .run(Date.now(), winnerId, potTotal, handId);
  }
}

```
