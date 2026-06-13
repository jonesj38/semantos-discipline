---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/dungeon/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.402059+00:00
---

# packages/games/src/dungeon/types.ts

```ts
/**
 * Dungeon Crawler Types -- all type definitions for the roguelike dungeon game.
 *
 * Linearity mapping:
 *   Player  -> RELEVANT (referenced throughout, never consumed)
 *   Board   -> RELEVANT (DAG-chained via prevStateHash)
 *   Potion  -> LINEAR   (consumed once on use)
 *   Key     -> LINEAR   (consumed when door opened)
 *   Scroll  -> LINEAR   (consumed on use)
 *   Weapon  -> AFFINE   (can break via durability)
 *   Armor   -> AFFINE   (can break via durability)
 *   Monster -> AFFINE   (destroyed in combat)
 */

import type { GameEntity } from '../../../game-sdk/src/types';

// -- Map tiles ---------------------------------------------------------------

export enum Tile {
  WALL = 0,
  FLOOR = 1,
  DOOR_CLOSED = 2,
  DOOR_OPEN = 3,
  DOOR_LOCKED = 4,
  STAIRS_DOWN = 5,
  STAIRS_UP = 6,
}

// -- Direction ---------------------------------------------------------------

export type Direction = 'n' | 's' | 'e' | 'w';

export const DIRECTION_OFFSETS: Record<Direction, [number, number]> = {
  n: [0, -1],
  s: [0, 1],
  e: [1, 0],
  w: [-1, 0],
};

export function isDirection(s: string): s is Direction {
  return s === 'n' || s === 's' || s === 'e' || s === 'w';
}

// -- Position ----------------------------------------------------------------

export interface Position { x: number; y: number; }

export function posKey(p: Position): string { return `${p.x},${p.y}`; }
export function posEq(a: Position, b: Position): boolean { return a.x === b.x && a.y === b.y; }

// -- Action types (for policy evaluation) ------------------------------------

export type ActionType = 'move' | 'attack' | 'pickup' | 'use' | 'open';

// -- Items -------------------------------------------------------------------

export type ItemCategory = 'weapon' | 'armor' | 'potion' | 'key' | 'scroll' | 'treasure';

export interface DungeonItem {
  entity: GameEntity;
  name: string;
  category: ItemCategory;
  position: Position;
  damage?: number;        // weapons
  defense?: number;       // armor
  healAmount?: number;    // potions
  keyId?: string;         // keys -- which lock they open
  durability?: number;    // AFFINE items: breaks when 0
  value?: number;         // treasure gold value
}

// -- Item templates ----------------------------------------------------------

export interface ItemTemplate {
  name: string;
  category: ItemCategory;
  damage?: number;
  defense?: number;
  healAmount?: number;
  durability?: number;
  value?: number;
}

export const ITEM_TEMPLATES: Record<string, ItemTemplate> = {
  // Weapons (AFFINE -- can break)
  dagger:      { name: 'Dagger',       category: 'weapon', damage: 2,  durability: 20 },
  shortSword:  { name: 'Short Sword',  category: 'weapon', damage: 4,  durability: 30 },
  longSword:   { name: 'Long Sword',   category: 'weapon', damage: 6,  durability: 25 },
  battleAxe:   { name: 'Battle Axe',   category: 'weapon', damage: 8,  durability: 15 },
  magicStaff:  { name: 'Magic Staff',  category: 'weapon', damage: 10, durability: 10 },

  // Armor (AFFINE -- can break)
  leather:     { name: 'Leather Armor', category: 'armor', defense: 2, durability: 25 },
  chainMail:   { name: 'Chain Mail',    category: 'armor', defense: 4, durability: 20 },
  plateMail:   { name: 'Plate Mail',    category: 'armor', defense: 6, durability: 15 },

  // Potions (LINEAR -- consumed on use)
  healthSmall: { name: 'Small Health Potion', category: 'potion', healAmount: 10 },
  healthLarge: { name: 'Large Health Potion', category: 'potion', healAmount: 25 },

  // Scrolls (LINEAR -- consumed on use)
  scrollMap:   { name: 'Scroll of Mapping', category: 'scroll' },

  // Treasure (LINEAR -- consumed on pickup, adds gold)
  goldPile:    { name: 'Gold Pile',    category: 'treasure', value: 10 },
  gemstone:    { name: 'Gemstone',     category: 'treasure', value: 25 },
  crown:       { name: 'Golden Crown', category: 'treasure', value: 100 },
};

// -- Monsters ----------------------------------------------------------------

export interface MonsterType {
  name: string;
  char: string;
  hp: number;
  attack: number;
  defense: number;
  xpReward: number;
}

export const MONSTER_TYPES: Record<string, MonsterType> = {
  rat:      { name: 'Rat',      char: 'r', hp: 3,  attack: 1, defense: 0, xpReward: 5 },
  bat:      { name: 'Bat',      char: 'b', hp: 2,  attack: 2, defense: 0, xpReward: 5 },
  goblin:   { name: 'Goblin',   char: 'g', hp: 6,  attack: 3, defense: 1, xpReward: 15 },
  skeleton: { name: 'Skeleton', char: 's', hp: 8,  attack: 4, defense: 2, xpReward: 25 },
  orc:      { name: 'Orc',      char: 'o', hp: 12, attack: 5, defense: 3, xpReward: 40 },
  troll:    { name: 'Troll',    char: 'T', hp: 20, attack: 7, defense: 4, xpReward: 75 },
  dragon:   { name: 'Dragon',   char: 'D', hp: 40, attack: 12, defense: 6, xpReward: 200 },
};

// Floor-specific monster pools (harder monsters deeper)
export const FLOOR_MONSTERS: string[][] = [
  ['rat', 'bat'],
  ['rat', 'goblin', 'bat'],
  ['goblin', 'skeleton'],
  ['skeleton', 'orc'],
  ['orc', 'troll', 'dragon'],
];

// -- Monster instance --------------------------------------------------------

export interface Monster {
  entity: GameEntity;
  type: MonsterType;
  hp: number;
  position: Position;
}

// -- Player ------------------------------------------------------------------

export interface DungeonPlayer {
  entity: GameEntity;
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
}

// -- Dungeon Floor -----------------------------------------------------------

export interface DungeonFloor {
  width: number;
  height: number;
  tiles: Tile[][];         // [y][x]
  monsters: Monster[];
  items: DungeonItem[];
  doorLocks: Map<string, string>;  // "x,y" -> keyId
}

// -- Board state (RELEVANT cell, DAG-chained) --------------------------------

export interface DungeonBoard {
  cellId: string;
  floor: number;
  floors: DungeonFloor[];
  player: DungeonPlayer;
  turnNumber: number;
  previousBoardCellId: string | null;
  messages: string[];      // recent action messages
}

// -- Results -----------------------------------------------------------------

export type DungeonGameStatus = 'playing' | 'dead' | 'victory';

export interface ActionResult {
  board: DungeonBoard;
  message: string;
  status: DungeonGameStatus;
}

// -- Constants ---------------------------------------------------------------

export const MAX_FLOORS = 5;
export const MAP_WIDTH = 60;
export const MAP_HEIGHT = 25;
export const FOV_RADIUS = 8;
export const INVENTORY_MAX = 10;
export const XP_PER_LEVEL = 50;

// -- Item display chars for renderer -----------------------------------------

export const ITEM_CHARS: Record<ItemCategory, string> = {
  weapon: ')',
  armor: '[',
  potion: '!',
  key: '*',
  scroll: '?',
  treasure: '$',
};

```
