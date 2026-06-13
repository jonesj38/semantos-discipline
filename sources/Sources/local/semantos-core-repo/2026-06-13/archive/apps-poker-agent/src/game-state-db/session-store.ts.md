---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/game-state-db/session-store.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.774979+00:00
---

# archive/apps-poker-agent/src/game-state-db/session-store.ts

```ts
/**
 * Sessions + players store. Owns the `game_sessions` and `players`
 * tables; no other module writes to them.
 */

import type { DatabaseHandle } from './db-types';

export interface SessionConfig {
  smallBlind: number;
  bigBlind: number;
  startingChips: number;
}

export interface PlayerInsert {
  playerId: string;
  agentName: string;
  certId: string;
  walletPubKey: string;
  seat: number;
  startingChips: number;
}

export class SessionStore {
  constructor(private readonly db: DatabaseHandle) {}

  createSession(gameId: string, config: SessionConfig): void {
    this.db
      .prepare(
        `INSERT INTO game_sessions (game_id, small_blind, big_blind, starting_chips, created_at, status)
         VALUES (?, ?, ?, ?, ?, 'active')`,
      )
      .run(gameId, config.smallBlind, config.bigBlind, config.startingChips, Date.now());
  }

  addPlayer(gameId: string, player: PlayerInsert): void {
    this.db
      .prepare(
        `INSERT INTO players (game_id, player_id, agent_name, cert_id, wallet_pub_key, seat, starting_chips)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
      )
      .run(
        gameId,
        player.playerId,
        player.agentName,
        player.certId,
        player.walletPubKey,
        player.seat,
        player.startingChips,
      );
  }
}

```
