---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/game-state-db/row-mappers.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.775834+00:00
---

# archive/apps-poker-agent/src/game-state-db/row-mappers.ts

```ts
/**
 * Row mappers — pure functions converting raw SQLite rows into
 * typed `*Row` shapes. Exported standalone so tests can fixture
 * a row object and assert on the mapped shape without spinning up
 * a database.
 *
 * The mappers exist because the legacy code did inline `as ActionRow`
 * casts everywhere; a named mapper makes the row→type contract
 * explicit and gives us one place to add validation later.
 */

import type {
  ActionRow,
  AgentMemoryRow,
  CellTokenRefRow,
  GameSessionRow,
  HandRow,
  PlayerRow,
  StateSnapshotRow,
} from './types';

export function mapSessionRow(raw: unknown): GameSessionRow {
  const r = raw as GameSessionRow;
  return {
    game_id: String(r.game_id),
    small_blind: Number(r.small_blind),
    big_blind: Number(r.big_blind),
    starting_chips: Number(r.starting_chips),
    created_at: Number(r.created_at),
    status: r.status,
  };
}

export function mapPlayerRow(raw: unknown): PlayerRow {
  const r = raw as PlayerRow;
  return {
    game_id: String(r.game_id),
    player_id: String(r.player_id),
    agent_name: String(r.agent_name),
    cert_id: String(r.cert_id),
    wallet_pub_key: String(r.wallet_pub_key),
    seat: Number(r.seat),
    starting_chips: Number(r.starting_chips),
  };
}

export function mapHandRow(raw: unknown): HandRow {
  const r = raw as HandRow;
  return {
    hand_id: Number(r.hand_id),
    game_id: String(r.game_id),
    hand_number: Number(r.hand_number),
    dealer_seat: Number(r.dealer_seat),
    started_at: Number(r.started_at),
    ended_at: r.ended_at === null ? null : Number(r.ended_at),
    winner_id: r.winner_id === null ? null : String(r.winner_id),
    pot_total: Number(r.pot_total),
  };
}

export function mapActionRow(raw: unknown): ActionRow {
  const r = raw as ActionRow;
  return {
    seq: Number(r.seq),
    hand_id: Number(r.hand_id),
    player_id: String(r.player_id),
    action_type: String(r.action_type),
    amount: Number(r.amount),
    phase: String(r.phase),
    chips_after: Number(r.chips_after),
    pot_after: Number(r.pot_after),
    timestamp: Number(r.timestamp),
  };
}

export function mapStateSnapshotRow(raw: unknown): StateSnapshotRow {
  const r = raw as StateSnapshotRow;
  return {
    seq: Number(r.seq),
    hand_id: Number(r.hand_id),
    phase: String(r.phase),
    pot: Number(r.pot),
    community_cards: String(r.community_cards),
    active_players: Number(r.active_players),
    current_bet: Number(r.current_bet),
    timestamp: Number(r.timestamp),
  };
}

export function mapCellTokenRefRow(raw: unknown): CellTokenRefRow {
  const r = raw as CellTokenRefRow;
  return {
    seq: Number(r.seq),
    hand_id: Number(r.hand_id),
    agent_name: String(r.agent_name),
    txid: String(r.txid),
    cell_type: String(r.cell_type),
    description: String(r.description),
    timestamp: Number(r.timestamp),
  };
}

export function mapAgentMemoryRow(raw: unknown): AgentMemoryRow {
  const r = raw as AgentMemoryRow;
  return {
    agent_name: String(r.agent_name),
    key: String(r.key),
    value: String(r.value),
    updated_at: Number(r.updated_at),
  };
}

/** Parse the JSON-encoded community_cards column into an array. */
export function parseCommunityCards(snapshot: StateSnapshotRow): string[] {
  try {
    const v = JSON.parse(snapshot.community_cards) as unknown;
    return Array.isArray(v) ? v.map(String) : [];
  } catch {
    return [];
  }
}

```
