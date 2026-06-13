---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-mud/src/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.834558+00:00
---

# archive/apps-mud/src/types.ts

```ts
/**
 * MUD Types -- core type definitions for the multiplayer dungeon.
 *
 * Extends the single-player dungeon types with multiplayer concepts:
 * room actors, player sessions, cross-room operations, and wire protocol.
 */

import type { GameEntity } from '../../../packages/game-sdk/src/types';
import type { StorageAdapter } from '../../../core/protocol-types/src/storage';
import type {
  DungeonItem,
  Monster,
  MonsterType,
  Tile,
  Direction,
  Position,
  ItemCategory,
} from '../../../packages/games/src/dungeon/types';

// Re-export StorageAdapter for consumers
export type { StorageAdapter };

// Re-export dungeon types used by MUD
export type {
  DungeonItem,
  Monster,
  MonsterType,
  Tile,
  Direction,
  Position,
  ItemCategory,
};

// ── Player ─────────────────────────────────────────────────────

export type PlayerId = string;

export interface MUDPlayer {
  id: PlayerId;
  entity: GameEntity;
  name: string;
  position: Position;
  hp: number;
  maxHp: number;
  attack: number;
  defense: number;
  level: number;
  xp: number;
  xpToLevel: number;
  gold: number;
  inventory: DungeonItem[];
  equippedWeapon: DungeonItem | null;
  equippedArmor: DungeonItem | null;
  roomId: string;
}

// ── Room ───────────────────────────────────────────────────────

export type RoomId = string;

export interface RoomExit {
  direction: Direction;
  targetRoomId: RoomId;
  locked: boolean;
  keyId?: string;
}

export interface RoomState {
  cellId: string;
  roomId: RoomId;
  name: string;
  description: string;
  width: number;
  height: number;
  tiles: number[][];        // Tile enum values, [y][x]
  occupants: PlayerId[];    // Players currently in this room
  monsters: Monster[];
  items: DungeonItem[];
  exits: RoomExit[];
  doorLocks: Map<string, string>;
  turnNumber: number;
  previousCellId: string | null;
}

// ── Actions (from players to room actor) ───────────────────────

export type ActionType =
  | 'move'
  | 'attack'
  | 'pickup'
  | 'use'
  | 'open'
  | 'drop'
  | 'say'
  | 'look'
  | 'exit-room';

export interface PlayerAction {
  type: ActionType;
  playerId: PlayerId;
  direction?: Direction;
  itemIndex?: number;
  text?: string;            // for 'say'
  targetPlayerId?: PlayerId; // for PvP
}

// ── Action Results (from room actor to players) ─────────────────

export interface ActionResult {
  success: boolean;
  message: string;
  playerId: PlayerId;
}

// ── Room Events (broadcast to all occupants) ────────────────────

export type RoomEventType =
  | 'player-entered'
  | 'player-left'
  | 'player-attacked'
  | 'monster-killed'
  | 'item-dropped'
  | 'item-picked-up'
  | 'door-opened'
  | 'player-said'
  | 'player-died'
  | 'combat';

export interface RoomEvent {
  type: RoomEventType;
  roomId: RoomId;
  playerId: PlayerId;
  message: string;
  data?: Record<string, unknown>;
}

// ── World Configuration ─────────────────────────────────────────

export interface WorldConfig {
  name: string;
  seed?: number;
  roomCount: number;
  maxPlayersPerRoom: number;
  pvpEnabled: boolean;
  startRoomId: RoomId;
  /** Explicit StorageAdapter — bypasses createAdapter() auto-detection. */
  storage?: StorageAdapter;
}

export const DEFAULT_WORLD_CONFIG: WorldConfig = {
  name: 'The Abyss',
  roomCount: 20,
  maxPlayersPerRoom: 20,
  pvpEnabled: false,
  startRoomId: 'tavern',
};

// ── Session ─────────────────────────────────────────────────────

export type SessionId = string;

export interface PlayerSession {
  sessionId: SessionId;
  playerId: PlayerId;
  playerName: string;
  currentRoomId: RoomId;
  connectedAt: number;
}

// ── Wire Protocol Messages ──────────────────────────────────────

export type ClientMessageType = 'action' | 'auth';
export type ServerMessageType =
  | 'room-state'
  | 'action-result'
  | 'room-event'
  | 'error'
  | 'welcome';

export interface ClientMessage {
  type: ClientMessageType;
  action?: PlayerAction;
  auth?: { name: string };
}

export interface ServerMessage {
  type: ServerMessageType;
  message?: string;
  event?: RoomEvent;
  result?: ActionResult;
  roomState?: {
    roomId: RoomId;
    name: string;
    description: string;
    occupants: { id: PlayerId; name: string; position: Position }[];
    visibleMonsters: { name: string; hp: number; position: Position }[];
    visibleItems: { name: string; category: ItemCategory; position: Position }[];
    exits: { direction: Direction; locked: boolean }[];
  };
  player?: {
    hp: number;
    maxHp: number;
    level: number;
    gold: number;
    inventoryCount: number;
  };
}

// ── Constants ───────────────────────────────────────────────────

export const XP_PER_LEVEL = 50;
export const INVENTORY_MAX = 10;
export const FOV_RADIUS = 8;

```
