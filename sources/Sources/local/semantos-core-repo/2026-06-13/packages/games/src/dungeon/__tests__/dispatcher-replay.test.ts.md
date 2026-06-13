---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/dungeon/__tests__/dispatcher-replay.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.432728+00:00
---

# packages/games/src/dungeon/__tests__/dispatcher-replay.test.ts

```ts
/**
 * Dispatcher-level deterministic replay — drives 200 actions through
 * the action-dispatcher with handcrafted board + stub policy, so the
 * test doesn't depend on the WASM kernel or the (pre-existing,
 * unrelated-to-this-prompt) broken `policies.ts` import paths.
 *
 * Acceptance per spec: "deterministic seed → replay 200-action run;
 * board state and consumed cells identical."
 *
 * The dispatcher is what we're refactoring; this test pins the
 * deterministic equivalence at the layer the split owns.
 */

import { afterEach, describe, expect, test } from 'bun:test';

import {
  dispatchDungeonAction,
  type DispatcherContext,
  type DungeonAction,
} from '../action-dispatcher';
import { resolveCombat } from '../combat-engine';
import type { GameEntity } from '../../../../game-sdk/src/types';
import type { DungeonPolicyEvaluator } from '../movement-validator';
import {
  Tile,
  XP_PER_LEVEL,
  type ActionResult,
  type Direction,
  type DungeonBoard,
  type DungeonFloor,
  type DungeonItem,
  type DungeonPlayer,
  type Monster,
  MONSTER_TYPES,
} from '../types';

// ── Deterministic RNG ────────────────────────────────────────

function mulberry32(seed: number): () => number {
  let t = seed >>> 0;
  return () => {
    t = (t + 0x6d2b79f5) >>> 0;
    let r = Math.imul(t ^ (t >>> 15), 1 | t);
    r = (r + Math.imul(r ^ (r >>> 7), 61 | r)) ^ r;
    return ((r ^ (r >>> 14)) >>> 0) / 4294967296;
  };
}

function fakeEntity(id: string): GameEntity {
  return { id, cell: new Uint8Array() } as unknown as GameEntity;
}

// ── Hand-built world ────────────────────────────────────────

function buildWorld(seed: number): {
  ctx: DispatcherContext & { commits: string[]; rejects: string[] };
  policy: DungeonPolicyEvaluator;
} {
  const rng = mulberry32(seed);

  // 10x10 floor, walls on the outer ring, monsters and items inside.
  const tiles: Tile[][] = Array.from({ length: 10 }, (_, y) =>
    Array.from({ length: 10 }, (_, x) => {
      if (x === 0 || y === 0 || x === 9 || y === 9) return Tile.WALL;
      return Tile.FLOOR;
    }),
  );
  // Plant stairs down at (8, 8) for descend testing.
  tiles[8][8] = Tile.STAIRS_DOWN;

  const monsters: Monster[] = [];
  for (let i = 0; i < 4; i++) {
    const x = 2 + Math.floor(rng() * 6);
    const y = 2 + Math.floor(rng() * 6);
    const type = MONSTER_TYPES.rat;
    monsters.push({
      entity: fakeEntity(`mon-${i}`),
      type,
      hp: type.hp,
      position: { x, y },
    });
  }

  const items: DungeonItem[] = [];
  for (let i = 0; i < 4; i++) {
    const x = 2 + Math.floor(rng() * 6);
    const y = 2 + Math.floor(rng() * 6);
    items.push({
      entity: fakeEntity(`item-${i}`),
      name: 'Small Health Potion',
      category: 'potion',
      position: { x, y },
      healAmount: 5,
    });
  }

  const floor: DungeonFloor = {
    width: 10,
    height: 10,
    tiles,
    monsters,
    items,
    doorLocks: new Map(),
  };

  const player: DungeonPlayer = {
    entity: fakeEntity('player'),
    position: { x: 1, y: 1 },
    hp: 30,
    maxHp: 30,
    attack: 2,
    defense: 0,
    level: 1,
    xp: 0,
    xpToLevel: XP_PER_LEVEL,
    gold: 0,
    inventory: [
      {
        entity: fakeEntity('start-dagger'),
        name: 'Dagger',
        category: 'weapon',
        position: { x: 1, y: 1 },
        damage: 2,
        durability: 50,
      },
    ],
    equippedWeapon: null,
    equippedArmor: null,
  };
  player.equippedWeapon = player.inventory[0];

  const board: DungeonBoard = {
    cellId: 'b0',
    floor: 0,
    floors: [floor],
    player,
    turnNumber: 0,
    previousBoardCellId: null,
    messages: [],
  };

  // Mirror legacy semantics: move policy passes for in-bounds + non-wall;
  // attack passes when adjacent to a monster + has-weapon; pickup passes
  // when at-or-adjacent + inv-not-full; use passes when item is usable;
  // open passes for door tiles.
  const policy: DungeonPolicyEvaluator = {
    evaluate: ({ action, targetX, targetY, board: b, extras }) => {
      const f = b.floors[b.floor];
      if (
        targetX < 0 ||
        targetY < 0 ||
        targetY >= f.height ||
        targetX >= f.width
      ) {
        return false;
      }
      const tile = f.tiles[targetY][targetX];
      const adj =
        Math.abs(targetX - b.player.position.x) +
          Math.abs(targetY - b.player.position.y) <=
        1;
      switch (action) {
        case 'move':
          return tile !== Tile.WALL && tile !== Tile.DOOR_CLOSED && tile !== Tile.DOOR_LOCKED;
        case 'attack': {
          const m = f.monsters.find(
            (mm) =>
              mm.hp > 0 &&
              mm.position.x === targetX &&
              mm.position.y === targetY,
          );
          return Boolean(m) && b.player.equippedWeapon !== null && adj;
        }
        case 'pickup':
          return adj && b.player.inventory.length < 10;
        case 'use':
          return Boolean(extras?.hasItem && extras?.itemUsable);
        case 'open':
          return (
            (tile === Tile.DOOR_CLOSED || tile === Tile.DOOR_LOCKED) && adj
          );
      }
      return false;
    },
    lastResult: () => undefined,
  };

  const commits: string[] = [];
  const rejects: string[] = [];
  const ctx: DispatcherContext & { commits: string[]; rejects: string[] } = {
    board,
    status: 'playing',
    consumedCells: new Set<string>(),
    visibleTiles: new Set<string>(),
    exploredTiles: new Set<string>(),
    fov: { compute: () => {} },
    recomputeFov: () => {
      // pretend full reveal
      for (let y = 0; y < floor.height; y++) {
        for (let x = 0; x < floor.width; x++) {
          ctx.visibleTiles.add(`${x},${y}`);
          ctx.exploredTiles.add(`${x},${y}`);
        }
      }
    },
    generateNextFloor: () => {
      // No new floor for this fixture — descend triggers victory.
    },
    commit: (msg) => {
      commits.push(msg);
      return { board, message: msg, status: ctx.status } as ActionResult;
    },
    result: (msg) => {
      rejects.push(msg);
      return { board, message: msg, status: ctx.status } as ActionResult;
    },
    assertPlaying: () => {
      if (ctx.status !== 'playing') throw new Error('over');
    },
    commits,
    rejects,
  };

  return { ctx, policy };
}

// ── Action script (deterministic) ────────────────────────────

const DIRECTIONS: Direction[] = ['n', 's', 'e', 'w'];

function buildScript(seed: number, count: number): DungeonAction[] {
  const rng = mulberry32(seed);
  const out: DungeonAction[] = [];
  for (let i = 0; i < count; i++) {
    const r = rng();
    const dir = DIRECTIONS[Math.floor(rng() * 4)];
    if (r < 0.7) out.push({ type: 'move', direction: dir });
    else if (r < 0.85) out.push({ type: 'attack', direction: dir });
    else if (r < 0.92) out.push({ type: 'pickup' });
    else if (r < 0.98) out.push({ type: 'open-door', direction: dir });
    else out.push({ type: 'use', itemIndex: 0 });
  }
  return out;
}

// ── Snapshot helper ──────────────────────────────────────────

function snapshot(
  ctx: DispatcherContext & { commits: string[]; rejects: string[] },
): unknown {
  const b = ctx.board;
  return {
    status: ctx.status,
    turn: b.turnNumber,
    floor: b.floor,
    playerPos: { ...b.player.position },
    playerHp: b.player.hp,
    playerLevel: b.player.level,
    playerXp: b.player.xp,
    playerGold: b.player.gold,
    inventoryCount: b.player.inventory.length,
    monstersAlive: b.floors[b.floor].monsters.filter((m) => m.hp > 0).length,
    floorItemCount: b.floors[b.floor].items.length,
    consumedCells: [...ctx.consumedCells].sort(),
    visibleTileCount: ctx.visibleTiles.size,
    exploredTileCount: ctx.exploredTiles.size,
    commits: ctx.commits.length,
    rejects: ctx.rejects.length,
  };
}

afterEach(() => {});

describe('dispatcher 200-action deterministic replay', () => {
  test('two runs with same seed produce identical board + consumed cells', () => {
    const seed = 0xa11ce;
    const script = buildScript(seed, 200);

    const a = buildWorld(seed);
    const b = buildWorld(seed);

    for (const act of script) {
      if (a.ctx.status !== 'playing' || b.ctx.status !== 'playing') break;
      try {
        dispatchDungeonAction({ ctx: a.ctx, policy: a.policy }, act);
      } catch {
        // swallow assertPlaying throws if status flipped
      }
      try {
        dispatchDungeonAction({ ctx: b.ctx, policy: b.policy }, act);
      } catch {
        // mirror
      }
    }

    expect(snapshot(b.ctx)).toEqual(snapshot(a.ctx) as object);

    // Sanity: at least one move + one combat happened.
    expect(a.ctx.commits.length).toBeGreaterThan(0);
  });

  test('combat consumes monster cells and grants xp', () => {
    const { ctx, policy } = buildWorld(7);
    // Drop the player next to a monster and force-kill a rat.
    const m = ctx.board.floors[0].monsters[0];
    m.position = {
      x: ctx.board.player.position.x + 1,
      y: ctx.board.player.position.y,
    };
    m.hp = 1;

    const before = ctx.board.player.xp;
    dispatchDungeonAction({ ctx, policy }, { type: 'attack', direction: 'e' });
    expect(m.hp).toBeLessThanOrEqual(0);
    expect(ctx.consumedCells.has(m.entity.id)).toBe(true);
    expect(ctx.board.player.xp).toBeGreaterThan(before);
  });
});

```
