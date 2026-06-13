---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/dungeon/__tests__/action-dispatcher.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.433322+00:00
---

# packages/games/src/dungeon/__tests__/action-dispatcher.test.ts

```ts
/**
 * Action-dispatcher tests — drive the dispatcher with a stub policy
 * evaluator + handcrafted board so tests don't need the WASM kernel.
 *
 * Covers the policy gating (rejection branches) and the basic mutation
 * paths. Combat / inventory / open-door deeper behaviour lives in
 * their own per-module tests.
 */

import { describe, expect, test } from 'bun:test';

import {
  dispatchDungeonAction,
  type DispatcherContext,
  type DispatcherDeps,
  type DungeonAction,
} from '../action-dispatcher';
import type { GameEntity } from '../../../../game-sdk/src/types';
import type { DungeonPolicyEvaluator } from '../movement-validator';
import {
  Tile,
  XP_PER_LEVEL,
  type ActionResult,
  type DungeonBoard,
  type DungeonFloor,
  type DungeonItem,
  type DungeonPlayer,
} from '../types';

function fakeEntity(id: string): GameEntity {
  return { id, cell: new Uint8Array() } as unknown as GameEntity;
}

function makeFloor(): DungeonFloor {
  const tiles: Tile[][] = Array.from({ length: 5 }, () =>
    new Array(5).fill(Tile.FLOOR),
  );
  return { width: 5, height: 5, tiles, monsters: [], items: [], doorLocks: new Map() };
}

function makePlayer(): DungeonPlayer {
  return {
    entity: fakeEntity('player'),
    position: { x: 2, y: 2 },
    hp: 30,
    maxHp: 30,
    attack: 2,
    defense: 0,
    level: 1,
    xp: 0,
    xpToLevel: XP_PER_LEVEL,
    gold: 0,
    inventory: [],
    equippedWeapon: null,
    equippedArmor: null,
  };
}

function makeBoard(): DungeonBoard {
  const player = makePlayer();
  return {
    cellId: 'b0',
    floor: 0,
    floors: [makeFloor()],
    player,
    turnNumber: 0,
    previousBoardCellId: null,
    messages: [],
  };
}

function makeCtx(board: DungeonBoard): DispatcherContext & {
  commits: string[];
  rejects: string[];
} {
  const commits: string[] = [];
  const rejects: string[] = [];
  const ctx: DispatcherContext & { commits: string[]; rejects: string[] } = {
    board,
    status: 'playing',
    consumedCells: new Set<string>(),
    visibleTiles: new Set<string>(),
    exploredTiles: new Set<string>(),
    fov: { compute: () => {} },
    recomputeFov: () => {},
    generateNextFloor: () => {},
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
  return ctx;
}

function makePolicy(decide: (a: string) => boolean): DungeonPolicyEvaluator {
  return {
    evaluate: (input) => decide(input.action),
    lastResult: () => undefined,
  };
}

function dispatch(
  ctx: ReturnType<typeof makeCtx>,
  policy: DungeonPolicyEvaluator,
  action: DungeonAction,
): ActionResult {
  const deps: DispatcherDeps = { ctx, policy };
  return dispatchDungeonAction(deps, action);
}

describe('action-dispatcher / move', () => {
  test('move accepted advances player, bumps turn, commits', () => {
    const board = makeBoard();
    const ctx = makeCtx(board);
    const policy = makePolicy(() => true);
    const before = { ...board.player.position };
    dispatch(ctx, policy, { type: 'move', direction: 'e' });
    expect(board.player.position).not.toEqual(before);
    expect(board.turnNumber).toBe(1);
    expect(ctx.commits).toHaveLength(1);
  });

  test('move rejected keeps player still + does not commit', () => {
    const board = makeBoard();
    const ctx = makeCtx(board);
    const policy = makePolicy(() => false);
    const before = { ...board.player.position };
    dispatch(ctx, policy, { type: 'move', direction: 'e' });
    expect(board.player.position).toEqual(before);
    expect(board.turnNumber).toBe(0);
    expect(ctx.rejects).toHaveLength(1);
    expect(ctx.commits).toHaveLength(0);
  });
});

describe('action-dispatcher / pickup', () => {
  test('pickup with no items returns early without policy call', () => {
    const board = makeBoard();
    const ctx = makeCtx(board);
    let invoked = 0;
    const policy: DungeonPolicyEvaluator = {
      evaluate: () => {
        invoked++;
        return true;
      },
      lastResult: () => undefined,
    };
    dispatch(ctx, policy, { type: 'pickup' });
    expect(ctx.rejects[0]).toContain('Nothing');
    expect(invoked).toBe(0);
  });

  test('pickup happy path adds the item to inventory', () => {
    const board = makeBoard();
    const ctx = makeCtx(board);
    const item: DungeonItem = {
      entity: fakeEntity('potion'),
      name: 'Small Health Potion',
      category: 'potion',
      position: { x: 2, y: 2 },
      healAmount: 8,
    };
    board.floors[0].items.push(item);
    const policy = makePolicy(() => true);
    dispatch(ctx, policy, { type: 'pickup' });
    expect(board.player.inventory).toContain(item);
    expect(ctx.commits).toHaveLength(1);
  });
});

describe('action-dispatcher / descend', () => {
  test('not on stairs → no commit', () => {
    const board = makeBoard();
    const ctx = makeCtx(board);
    const policy = makePolicy(() => true);
    dispatch(ctx, policy, { type: 'descend' });
    expect(ctx.rejects[0]).toContain('No stairs');
    expect(ctx.commits).toHaveLength(0);
  });

  test('on stairs at final floor → victory + commit', () => {
    const board = makeBoard();
    board.floor = 4; // MAX_FLOORS - 1
    board.floors[4] = makeFloor();
    board.floors[4].tiles[2][2] = Tile.STAIRS_DOWN;
    const ctx = makeCtx(board);
    const policy = makePolicy(() => true);
    dispatch(ctx, policy, { type: 'descend' });
    expect(ctx.status).toBe('victory');
    expect(ctx.commits).toHaveLength(1);
  });
});

```
