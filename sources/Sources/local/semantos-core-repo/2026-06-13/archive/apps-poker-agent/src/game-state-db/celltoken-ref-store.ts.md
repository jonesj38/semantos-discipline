---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/game-state-db/celltoken-ref-store.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.776122+00:00
---

# archive/apps-poker-agent/src/game-state-db/celltoken-ref-store.ts

```ts
/**
 * On-chain CellToken-reference store — owns `celltoken_refs`.
 */

import type { DatabaseHandle } from './db-types';

import { mapCellTokenRefRow } from './row-mappers';
import type { SeqCounter } from './seq-counter';
import type { CellTokenRefRow } from './types';

export interface CellTokenRefInsert {
  agentName: string;
  txid: string;
  /** 'chip-stack' | 'bet' | 'pot-claim' | 'state-transition' */
  cellType: string;
  description: string;
}

export class CellTokenRefStore {
  constructor(
    private readonly db: DatabaseHandle,
    private readonly seq: SeqCounter,
  ) {}

  recordCellToken(handId: number, ref: CellTokenRefInsert): number {
    const seq = this.seq.next();
    this.db
      .prepare(
        `INSERT INTO celltoken_refs (seq, hand_id, agent_name, txid, cell_type, description, timestamp)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
      )
      .run(seq, handId, ref.agentName, ref.txid, ref.cellType, ref.description, Date.now());
    return seq;
  }

  getCellTokens(handId: number): CellTokenRefRow[] {
    const rows = this.db
      .prepare('SELECT * FROM celltoken_refs WHERE hand_id = ? ORDER BY seq')
      .all(handId) as unknown[];
    return rows.map(mapCellTokenRefRow);
  }
}

```
