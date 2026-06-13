---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/dungeon/map-gen.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.401783+00:00
---

# packages/games/src/dungeon/map-gen.ts

```ts
/**
 * Procedural dungeon generation via rot.js Digger algorithm.
 *
 * Generates a multi-room dungeon with corridors, doors, and stairs.
 * Entity placement (monsters, items, keys) is handled by the engine
 * using the room list returned here.
 */

import ROT from 'rot-js';
import { Tile, MAP_WIDTH, MAP_HEIGHT, type Position } from './types';

// Re-export Room type for the engine
export type { Room } from 'rot-js/lib/map/features';

export interface GeneratedFloor {
  tiles: Tile[][];
  rooms: { center: [number, number]; left: number; right: number; top: number; bottom: number }[];
  stairsDown: Position | null;
  stairsUp: Position | null;
  playerStart: Position;
}

/**
 * Generate a single dungeon floor using rot.js Digger.
 *
 * @param floorIndex  0-based floor number
 * @param totalFloors total number of floors in the dungeon
 */
export function generateFloor(
  floorIndex: number,
  totalFloors: number,
  width = MAP_WIDTH,
  height = MAP_HEIGHT,
): GeneratedFloor {
  // Build tile grid -- start all walls
  const tiles: Tile[][] = Array.from({ length: height }, () =>
    new Array(width).fill(Tile.WALL),
  );

  // Run rot.js Digger
  const digger = new ROT.Map.Digger(width, height, {
    roomWidth: [3, 9],
    roomHeight: [3, 5],
    corridorLength: [2, 8],
    dugPercentage: 0.3,
  });

  digger.create((x, y, value) => {
    // value: 0 = passable (floor), 1 = wall
    if (value === 0) {
      tiles[y][x] = Tile.FLOOR;
    }
  });

  // Extract rooms
  const rotRooms = digger.getRooms();
  const rooms = rotRooms.map(r => ({
    center: r.getCenter() as [number, number],
    left: r.getLeft(),
    right: r.getRight(),
    top: r.getTop(),
    bottom: r.getBottom(),
  }));

  // Place doors at room entrances
  for (const room of rotRooms) {
    room.getDoors((x, y) => {
      if (tiles[y][x] === Tile.FLOOR) {
        tiles[y][x] = Tile.DOOR_CLOSED;
      }
    });
  }

  // Player starts in the center of the first room
  const playerStart: Position = {
    x: rooms[0].center[0],
    y: rooms[0].center[1],
  };

  // Stairs up in the first room (except floor 0)
  let stairsUp: Position | null = null;
  if (floorIndex > 0) {
    stairsUp = { x: rooms[0].center[0] + 1, y: rooms[0].center[1] };
    if (tiles[stairsUp.y][stairsUp.x] === Tile.FLOOR) {
      tiles[stairsUp.y][stairsUp.x] = Tile.STAIRS_UP;
    }
  }

  // Stairs down in the last room (except final floor)
  let stairsDown: Position | null = null;
  if (floorIndex < totalFloors - 1 && rooms.length > 1) {
    const lastRoom = rooms[rooms.length - 1];
    stairsDown = { x: lastRoom.center[0], y: lastRoom.center[1] };
    tiles[stairsDown.y][stairsDown.x] = Tile.STAIRS_DOWN;
  }

  return { tiles, rooms, stairsDown, stairsUp, playerStart };
}

/**
 * Get a random floor position within a room (not on the center or stairs).
 */
export function randomRoomPosition(
  room: { left: number; right: number; top: number; bottom: number },
  tiles: Tile[][],
  avoid: Set<string>,
): Position | null {
  const candidates: Position[] = [];
  for (let y = room.top; y <= room.bottom; y++) {
    for (let x = room.left; x <= room.right; x++) {
      const key = `${x},${y}`;
      if (tiles[y][x] === Tile.FLOOR && !avoid.has(key)) {
        candidates.push({ x, y });
      }
    }
  }
  if (candidates.length === 0) return null;
  return candidates[Math.floor(Math.random() * candidates.length)];
}

```
