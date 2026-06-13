---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/dungeon/renderer.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.404830+00:00
---

# packages/games/src/dungeon/renderer.ts

```ts
/**
 * ASCII dungeon renderer with fog-of-war.
 *
 * Visible tiles show full detail. Explored-but-not-visible tiles
 * show in lowercase/dimmed. Unexplored tiles are blank.
 *
 * Legend:
 *   @  Player       #  Wall         .  Floor
 *   +  Door(closed) /  Door(open)   X  Door(locked)
 *   >  Stairs down  <  Stairs up
 *   r  Rat          g  Goblin       s  Skeleton      o  Orc
 *   T  Troll        D  Dragon       b  Bat
 *   !  Potion       )  Weapon       [  Armor
 *   *  Key          ?  Scroll       $  Treasure
 */

import {
  Tile,
  type DungeonBoard,
  type DungeonFloor,
  type DungeonPlayer,
  type Monster,
  type DungeonItem,
  type Position,
  ITEM_CHARS,
  posKey,
} from './types';

// ── Tile Characters ────────────────────────────────────────────

const TILE_CHARS: Record<Tile, string> = {
  [Tile.WALL]: '#',
  [Tile.FLOOR]: '.',
  [Tile.DOOR_CLOSED]: '+',
  [Tile.DOOR_OPEN]: '/',
  [Tile.DOOR_LOCKED]: 'X',
  [Tile.STAIRS_DOWN]: '>',
  [Tile.STAIRS_UP]: '<',
};

// ── Render Map ────────────────────────────────────────────────

export function renderMap(
  board: DungeonBoard,
  visibleTiles: Set<string>,
  exploredTiles: Set<string>,
): string {
  const floor = board.floors[board.floor];
  const { width, height, tiles, monsters, items } = floor;
  const player = board.player;

  // Build entity lookup maps (position -> char)
  const monsterMap = new Map<string, string>();
  for (const m of monsters) {
    if (m.hp > 0) {
      monsterMap.set(posKey(m.position), m.type.char);
    }
  }

  const itemMap = new Map<string, string>();
  for (const item of items) {
    itemMap.set(posKey(item.position), ITEM_CHARS[item.category]);
  }

  const playerKey = posKey(player.position);

  // Render grid
  const lines: string[] = [];
  for (let y = 0; y < height; y++) {
    let line = '';
    for (let x = 0; x < width; x++) {
      const key = `${x},${y}`;

      if (key === playerKey) {
        line += '@';
      } else if (visibleTiles.has(key)) {
        // Fully visible: show entities or tile
        if (monsterMap.has(key)) {
          line += monsterMap.get(key)!;
        } else if (itemMap.has(key)) {
          line += itemMap.get(key)!;
        } else {
          line += TILE_CHARS[tiles[y][x]] ?? ' ';
        }
      } else if (exploredTiles.has(key)) {
        // Explored but not visible: show tile dimmed (no entities)
        const ch = TILE_CHARS[tiles[y][x]] ?? ' ';
        line += ch === '#' ? '#' : ch === '.' ? ',' : ch.toLowerCase();
      } else {
        line += ' ';
      }
    }
    lines.push(line);
  }

  return lines.join('\n');
}

// ── Render Status Bar ─────────────────────────────────────────

export function renderStatus(board: DungeonBoard): string {
  const p = board.player;
  const weapon = p.equippedWeapon ? `${p.equippedWeapon.name}(${p.equippedWeapon.durability ?? '~'})` : 'fists';
  const armor = p.equippedArmor ? `${p.equippedArmor.name}(${p.equippedArmor.durability ?? '~'})` : 'none';
  return [
    `Floor ${board.floor + 1} | Turn ${board.turnNumber}`,
    `HP: ${p.hp}/${p.maxHp} | ATK: ${p.attack} | DEF: ${p.defense}`,
    `Weapon: ${weapon} | Armor: ${armor}`,
    `Level ${p.level} | XP: ${p.xp}/${p.xpToLevel} | Gold: ${p.gold}`,
    `Inventory: ${p.inventory.length}/10`,
  ].join('\n');
}

// ── Render Inventory ──────────────────────────────────────────

export function renderInventory(player: DungeonPlayer): string {
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

// ── Describe Surroundings ─────────────────────────────────────

export function describeSurroundings(
  board: DungeonBoard,
  visibleTiles: Set<string>,
): string {
  const floor = board.floors[board.floor];
  const player = board.player;
  const parts: string[] = [];

  // Items at player position
  const itemsHere = floor.items.filter(i => i.position.x === player.position.x && i.position.y === player.position.y);
  if (itemsHere.length > 0) {
    parts.push(`On the ground: ${itemsHere.map(i => i.name).join(', ')}`);
  }

  // Visible monsters
  const visibleMonsters = floor.monsters.filter(m =>
    m.hp > 0 && visibleTiles.has(posKey(m.position)),
  );
  if (visibleMonsters.length > 0) {
    parts.push(`Visible: ${visibleMonsters.map(m => `${m.type.name} (${m.hp}hp)`).join(', ')}`);
  }

  // Stairs
  const tile = floor.tiles[player.position.y][player.position.x];
  if (tile === Tile.STAIRS_DOWN) parts.push('You see stairs leading down.');
  if (tile === Tile.STAIRS_UP) parts.push('You see stairs leading up.');

  return parts.length > 0 ? parts.join('\n') : 'Nothing of interest nearby.';
}

```
