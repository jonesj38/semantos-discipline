---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-mud/src/renderer.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.835925+00:00
---

# archive/apps-mud/src/renderer.ts

```ts
/**
 * MUD renderer -- ASCII rendering for multiplayer rooms.
 *
 * Extends the single-player dungeon renderer with multi-player display:
 * other players shown as numbered symbols, player names in status.
 */

import {
  Tile,
  ITEM_CHARS,
  posKey,
} from '../../../packages/games/src/dungeon/types';
import type { RoomState, MUDPlayer, PlayerId } from './types';

// ── Tile Characters ────────────────────────────────────────────

const TILE_CHARS: Record<number, string> = {
  [Tile.WALL]: '#',
  [Tile.FLOOR]: '.',
  [Tile.DOOR_CLOSED]: '+',
  [Tile.DOOR_OPEN]: '/',
  [Tile.DOOR_LOCKED]: 'X',
  [Tile.STAIRS_DOWN]: '>',
  [Tile.STAIRS_UP]: '<',
};

// ── Render Room Map ────────────────────────────────────────────

export function renderRoom(
  state: RoomState,
  players: MUDPlayer[],
  viewerId: PlayerId,
): string {
  const { width, height, tiles, monsters, items } = state;

  // Build entity maps
  const monsterMap = new Map<string, string>();
  for (const m of monsters) {
    if (m.hp > 0) monsterMap.set(posKey(m.position), m.type.char);
  }

  const itemMap = new Map<string, string>();
  for (const item of items) {
    itemMap.set(posKey(item.position), ITEM_CHARS[item.category]);
  }

  // Player map: viewer = @, others = 1-9
  const playerMap = new Map<string, string>();
  let otherIdx = 1;
  for (const p of players) {
    if (p.id === viewerId) {
      playerMap.set(posKey(p.position), '@');
    } else {
      playerMap.set(posKey(p.position), String(Math.min(otherIdx++, 9)));
    }
  }

  // Render
  const lines: string[] = [];
  for (let y = 0; y < height; y++) {
    let line = '';
    for (let x = 0; x < width; x++) {
      const key = `${x},${y}`;
      if (playerMap.has(key)) {
        line += playerMap.get(key)!;
      } else if (monsterMap.has(key)) {
        line += monsterMap.get(key)!;
      } else if (itemMap.has(key)) {
        line += itemMap.get(key)!;
      } else {
        line += TILE_CHARS[tiles[y][x]] ?? ' ';
      }
    }
    lines.push(line);
  }

  return lines.join('\n');
}

// ── Player Status ──────────────────────────────────────────────

export function renderPlayerStatus(player: MUDPlayer): string {
  const weapon = player.equippedWeapon
    ? `${player.equippedWeapon.name}(${player.equippedWeapon.durability ?? '~'})`
    : 'fists';
  const armor = player.equippedArmor
    ? `${player.equippedArmor.name}(${player.equippedArmor.durability ?? '~'})`
    : 'none';
  return [
    `${player.name} | Level ${player.level}`,
    `HP: ${player.hp}/${player.maxHp} | ATK: ${player.attack} | DEF: ${player.defense}`,
    `Weapon: ${weapon} | Armor: ${armor}`,
    `XP: ${player.xp}/${player.xpToLevel} | Gold: ${player.gold}`,
    `Inventory: ${player.inventory.length}/10`,
  ].join('\n');
}

// ── Room Description ───────────────────────────────────────────

export function renderRoomDescription(
  state: RoomState,
  players: MUDPlayer[],
  viewerId: PlayerId,
): string {
  const parts: string[] = [];
  parts.push(`[${state.name}] ${state.description}`);

  // Other players
  for (const p of players) {
    if (p.id !== viewerId) {
      parts.push(`  ${p.name} is here. (Level ${p.level})`);
    }
  }

  // Monsters
  const alive = state.monsters.filter(m => m.hp > 0);
  if (alive.length > 0) {
    parts.push(`  Monsters: ${alive.map(m => `${m.type.name}(${m.hp}hp)`).join(', ')}`);
  }

  // Items on ground
  if (state.items.length > 0) {
    parts.push(`  Items: ${state.items.map(i => i.name).join(', ')}`);
  }

  // Exits
  parts.push(`  Exits: ${state.exits.map(e =>
    `${e.direction}${e.locked ? '(locked)' : ''} -> ${e.targetRoomId}`
  ).join(', ')}`);

  return parts.join('\n');
}

// ── Inventory ──────────────────────────────────────────────────

export function renderMUDInventory(player: MUDPlayer): string {
  if (player.inventory.length === 0) return 'Inventory is empty.';

  const lines: string[] = ['Inventory:'];
  for (let i = 0; i < player.inventory.length; i++) {
    const item = player.inventory[i];
    let detail = `  [${i}] ${ITEM_CHARS[item.category]} ${item.name}`;
    if (item.damage !== undefined) detail += ` (dmg:${item.damage})`;
    if (item.defense !== undefined) detail += ` (def:${item.defense})`;
    if (item.healAmount !== undefined) detail += ` (heal:${item.healAmount})`;
    if (item.durability !== undefined) detail += ` (dur:${item.durability})`;
    if (item.value !== undefined) detail += ` (${item.value}g)`;
    if (item === player.equippedWeapon) detail += ' [EQUIPPED]';
    if (item === player.equippedArmor) detail += ' [EQUIPPED]';
    lines.push(detail);
  }
  return lines.join('\n');
}

```
