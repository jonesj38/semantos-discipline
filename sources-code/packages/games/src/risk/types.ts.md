---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/risk/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.408024+00:00
---

# packages/games/src/risk/types.ts

```ts
/**
 * Risk Types
 *
 * Classic Risk modeled with semantic cells.
 * Territories are RELEVANT cells (persist, referenced by armies).
 * Armies are LINEAR cells (consumed in combat).
 * Cards are LINEAR cells (turned in for reinforcements, then consumed).
 */

import type { GameEntity } from '../../../game-sdk/src/types';

// ── Players ─────────────────────────────────────────────────────

export type PlayerId = number; // 0-5

export interface Player {
  id: PlayerId;
  name: string;
  color: string;
  eliminated: boolean;
  cardCount: number;
}

export const PLAYER_COLORS = ['red', 'blue', 'green', 'yellow', 'purple', 'orange'] as const;

// ── Territories ─────────────────────────────────────────────────

export type TerritoryId = number; // 0-41

export interface TerritoryState {
  owner: PlayerId;
  armies: number;
}

// ── Cards ───────────────────────────────────────────────────────

export type CardType = 'infantry' | 'cavalry' | 'artillery' | 'wild';

export interface RiskCard {
  entity: GameEntity;
  territory: TerritoryId | null; // null for wild cards
  cardType: CardType;
}

// ── Combat ──────────────────────────────────────────────────────

export interface CombatResult {
  attackerLosses: number;
  defenderLosses: number;
  attackerDice: number[];
  defenderDice: number[];
  territoryConquered: boolean;
}

// ── Turn Phases ─────────────────────────────────────────────────

export type TurnPhase = 'reinforce' | 'attack' | 'fortify' | 'gameover';

// ── Board State ─────────────────────────────────────────────────

export interface RiskBoard {
  cellId: string;
  territories: TerritoryState[];
  currentPlayer: PlayerId;
  phase: TurnPhase;
  turnNumber: number;
  previousBoardCellId: string | null;
}

// ── Game Status ─────────────────────────────────────────────────

export type RiskGameStatus = 'setup' | 'playing' | 'gameover';

// ── Move Results ────────────────────────────────────────────────

export interface ReinforceResult {
  territory: TerritoryId;
  armiesPlaced: number;
  armiesRemaining: number;
}

export interface AttackResult {
  from: TerritoryId;
  to: TerritoryId;
  combat: CombatResult;
  board: RiskBoard;
}

export interface FortifyResult {
  from: TerritoryId;
  to: TerritoryId;
  armies: number;
  board: RiskBoard;
}

```
