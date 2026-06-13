---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/game-state-db/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.772208+00:00
---

# archive/apps-poker-agent/src/game-state-db/types.ts

```ts
/**
 * Public types for the game-state-db split.
 *
 * Pinned identical to the legacy `game-state-db.ts` exports so
 * downstream consumers (game-loop, p2p-agent-runner, agent-runtime)
 * keep compiling unchanged.
 */

export interface GameSessionRow {
  game_id: string;
  small_blind: number;
  big_blind: number;
  starting_chips: number;
  created_at: number;
  status: 'active' | 'complete';
}

export interface PlayerRow {
  game_id: string;
  player_id: string;
  agent_name: string;
  cert_id: string;
  wallet_pub_key: string;
  seat: number;
  starting_chips: number;
}

export interface HandRow {
  hand_id: number;
  game_id: string;
  hand_number: number;
  dealer_seat: number;
  started_at: number;
  ended_at: number | null;
  winner_id: string | null;
  pot_total: number;
}

export interface ActionRow {
  seq: number;
  hand_id: number;
  player_id: string;
  action_type: string;
  amount: number;
  phase: string;
  chips_after: number;
  pot_after: number;
  timestamp: number;
}

export interface StateSnapshotRow {
  seq: number;
  hand_id: number;
  phase: string;
  pot: number;
  community_cards: string; // JSON-encoded card-label array
  active_players: number;
  current_bet: number;
  timestamp: number;
}

export interface CellTokenRefRow {
  seq: number;
  hand_id: number;
  agent_name: string;
  txid: string;
  cell_type: string; // 'chip-stack' | 'bet' | 'pot-claim' | 'state-transition'
  description: string;
  timestamp: number;
}

export interface AgentMemoryRow {
  agent_name: string;
  key: string;
  value: string;
  updated_at: number;
}

// ── Context shapes for Claude API ─────────────────────────────────

export interface HandContext {
  handNumber: number;
  dealerSeat: number;
  myCards: string[];
  communityCards: string[];
  phase: string;
  pot: number;
  myChips: number;
  opponentChips: number;
  actions: ActionSummary[];
  legalActions: string[];
}

export interface ActionSummary {
  seq: number;
  player: string;
  action: string;
  amount: number;
  phase: string;
}

export interface GameHistory {
  handsPlayed: number;
  myWins: number;
  opponentWins: number;
  myChipDelta: number;
  recentHands: HandSummary[];
}

export interface HandSummary {
  handNumber: number;
  winner: string;
  potSize: number;
  showdown: boolean;
  /** dominant action (fold/call/raise) */
  myAction: string;
}

```
