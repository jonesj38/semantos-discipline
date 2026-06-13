---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/game-state-db/schema.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.772897+00:00
---

# archive/apps-poker-agent/src/game-state-db/schema.ts

```ts
/**
 * Schema DDL — all CREATE TABLE / CREATE INDEX statements live here,
 * versioned for forward migration.
 *
 * The legacy `createTables()` was inline in the constructor; this
 * extraction is the single allowed home for SQL DDL per the prompt-
 * 21 acceptance criterion ("Inline SQL strings only in `schema.ts`
 * or the specific store file that owns the table"). Each store
 * file may execute its own table-scoped queries; cross-table joins
 * live in `context-builder.ts`.
 */

import type { DatabaseHandle } from './db-types';

/** Schema version — bumped when DDL changes. */
export const SCHEMA_VERSION = 1;

/** Combined DDL applied at startup. Idempotent (`IF NOT EXISTS`). */
export const SCHEMA_SQL = `
  CREATE TABLE IF NOT EXISTS game_sessions (
    game_id TEXT PRIMARY KEY,
    small_blind INTEGER NOT NULL,
    big_blind INTEGER NOT NULL,
    starting_chips INTEGER NOT NULL,
    created_at INTEGER NOT NULL,
    status TEXT NOT NULL DEFAULT 'active'
  );

  CREATE TABLE IF NOT EXISTS players (
    game_id TEXT NOT NULL,
    player_id TEXT NOT NULL,
    agent_name TEXT NOT NULL,
    cert_id TEXT NOT NULL,
    wallet_pub_key TEXT NOT NULL,
    seat INTEGER NOT NULL,
    starting_chips INTEGER NOT NULL,
    PRIMARY KEY (game_id, player_id)
  );

  CREATE TABLE IF NOT EXISTS hands (
    hand_id INTEGER PRIMARY KEY AUTOINCREMENT,
    game_id TEXT NOT NULL,
    hand_number INTEGER NOT NULL,
    dealer_seat INTEGER NOT NULL,
    started_at INTEGER NOT NULL,
    ended_at INTEGER,
    winner_id TEXT,
    pot_total INTEGER DEFAULT 0
  );

  CREATE TABLE IF NOT EXISTS actions (
    seq INTEGER PRIMARY KEY,
    hand_id INTEGER NOT NULL,
    player_id TEXT NOT NULL,
    action_type TEXT NOT NULL,
    amount INTEGER DEFAULT 0,
    phase TEXT NOT NULL,
    chips_after INTEGER NOT NULL,
    pot_after INTEGER NOT NULL,
    timestamp INTEGER NOT NULL,
    FOREIGN KEY (hand_id) REFERENCES hands(hand_id)
  );

  CREATE TABLE IF NOT EXISTS state_snapshots (
    seq INTEGER PRIMARY KEY,
    hand_id INTEGER NOT NULL,
    phase TEXT NOT NULL,
    pot INTEGER NOT NULL,
    community_cards TEXT NOT NULL DEFAULT '[]',
    active_players INTEGER NOT NULL,
    current_bet INTEGER NOT NULL DEFAULT 0,
    timestamp INTEGER NOT NULL,
    FOREIGN KEY (hand_id) REFERENCES hands(hand_id)
  );

  CREATE TABLE IF NOT EXISTS celltoken_refs (
    seq INTEGER PRIMARY KEY,
    hand_id INTEGER NOT NULL,
    agent_name TEXT NOT NULL,
    txid TEXT NOT NULL,
    cell_type TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    timestamp INTEGER NOT NULL,
    FOREIGN KEY (hand_id) REFERENCES hands(hand_id)
  );

  CREATE TABLE IF NOT EXISTS agent_memory (
    agent_name TEXT NOT NULL,
    key TEXT NOT NULL,
    value TEXT NOT NULL,
    updated_at INTEGER NOT NULL,
    PRIMARY KEY (agent_name, key)
  );

  CREATE INDEX IF NOT EXISTS idx_actions_hand ON actions(hand_id);
  CREATE INDEX IF NOT EXISTS idx_actions_player ON actions(player_id);
  CREATE INDEX IF NOT EXISTS idx_snapshots_hand ON state_snapshots(hand_id);
  CREATE INDEX IF NOT EXISTS idx_celltoken_hand ON celltoken_refs(hand_id);
`;

/**
 * Apply the schema to a fresh or existing database. Safe to run on
 * every boot — every CREATE uses `IF NOT EXISTS`.
 */
export function applySchema(db: DatabaseHandle): void {
  db.exec(SCHEMA_SQL);
}

```
