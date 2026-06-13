---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-mud/src/room-actor/__tests__/movement-system.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.847507+00:00
---

# archive/apps-mud/src/room-actor/__tests__/movement-system.test.ts

```ts
/**
 * Movement system tests — handleMove, treasure auto-pickup, look/say.
 */

import { describe, expect, test } from 'bun:test';

import { acceptAllMovePolicy, type PolicyEvaluator } from '../policy-engine';
import {
  buildLookMessage,
  handleMove,
  handleSay,
} from '../movement-system';

import type { DungeonItem, Monster } from '../../../../../packages/games/src/dungeon/types';
import type { MUDPlayer, RoomState } from '../../types';

const ROOM_ID = 'r1';

function makePlayer(overrides: Partial<MUDPlayer> = {}): MUDPlayer {
  return {
    id: 'p',
    entity: { id: 'pe' } as MUDPlayer['entity'],
    name: 'Tester',
    position: { x: 1, y: 1 },
    hp: 10,
    maxHp: 10,
    attack: 1,
    defense: 0,
    level: 1,
    xp: 0,
    xpToLevel: 50,
    gold: 0,
    inventory: [],
    equippedWeapon: null,
    equippedArmor: null,
    roomId: ROOM_ID,
    ...overrides,
  };
}

function makeState(): RoomState {
  return {
    cellId: 'c0',
    roomId: ROOM_ID,
    name: 'Cave',
    description: 'A dark cave.',
    width: 5,
    height: 5,
    tiles: Array(5).fill(0).map(() => Array(5).fill(1)),
    occupants: [],
    monsters: [],
    items: [],
    exits: [],
    doorLocks: new Map(),
    turnNumber: 0,
    previousCellId: null,
  };
}

const rejectAll: PolicyEvaluator = {
  evaluateMove() {
    return {
      ok: false,
      result: { ok: false, gas: 0, hostCalls: [], rejectionCode: 'VERIFY_FAILED' },
    };
  },
  lastResult: () => undefined,
};

describe('handleMove', () => {
  test('successful move updates player position', () => {
    const player = makePlayer({ position: { x: 1, y: 1 } });
    const state = makeState();

    const out = handleMove({
      state,
      player,
      action: { type: 'move', playerId: player.id, direction: 'e' },
      otherPlayers: [],
      policy: acceptAllMovePolicy,
    });

    expect(out.kind).toBe('moved');
    expect(player.position).toEqual({ x: 2, y: 1 });
  });

  test('blocked move when policy rejects', () => {
    const player = makePlayer();
    const state = makeState();
    const out = handleMove({
      state,
      player,
      action: { type: 'move', playerId: player.id, direction: 'e' },
      otherPlayers: [],
      policy: rejectAll,
    });

    expect(out.kind).toBe('blocked');
    expect(player.position).toEqual({ x: 1, y: 1 });
  });

  test('blocked when other player is at target tile', () => {
    const player = makePlayer({ position: { x: 1, y: 1 } });
    const other = makePlayer({ id: 'p2', position: { x: 2, y: 1 } });
    const state = makeState();

    const out = handleMove({
      state,
      player,
      action: { type: 'move', playerId: player.id, direction: 'e' },
      otherPlayers: [other],
      policy: acceptAllMovePolicy,
    });

    expect(out.kind).toBe('blocked');
    if (out.kind === 'blocked') {
      expect(out.message).toContain('Tester'); // other.name = 'Tester' from default
    }
  });

  test('combat detected when monster on target tile', () => {
    const player = makePlayer({ position: { x: 1, y: 1 } });
    const monster: Monster = {
      entity: { id: 'm1' } as Monster['entity'],
      type: { name: 'rat', char: 'r', hp: 3, attack: 1, defense: 0, xpReward: 5 },
      hp: 3,
      position: { x: 2, y: 1 },
    };
    const state = makeState();
    state.monsters = [monster];

    const out = handleMove({
      state,
      player,
      action: { type: 'move', playerId: player.id, direction: 'e' },
      otherPlayers: [],
      policy: acceptAllMovePolicy,
    });

    expect(out.kind).toBe('combat');
    if (out.kind === 'combat') expect(out.monster).toBe(monster);
  });

  test('treasure on destination tile is auto-picked up', () => {
    const player = makePlayer({ position: { x: 1, y: 1 }, gold: 0 });
    const treasure: DungeonItem = {
      entity: { id: 't1' } as DungeonItem['entity'],
      name: 'Gold Pile',
      category: 'treasure',
      position: { x: 2, y: 1 },
      value: 50,
    };
    const state = makeState();
    state.items = [treasure];

    const out = handleMove({
      state,
      player,
      action: { type: 'move', playerId: player.id, direction: 'e' },
      otherPlayers: [],
      policy: acceptAllMovePolicy,
    });

    expect(out.kind).toBe('moved');
    if (out.kind === 'moved') expect(out.consumedCellIds).toContain('t1');
    expect(player.gold).toBe(50);
    expect(state.items).toHaveLength(0);
  });
});

describe('handleSay', () => {
  test('emits player-said and self echo', () => {
    const player = makePlayer({ name: 'Alice' });
    const out = handleSay({
      roomId: ROOM_ID,
      player,
      action: { type: 'say', playerId: player.id, text: 'hello' },
    });

    expect(out.selfMessage).toBe('You say: "hello"');
    expect(out.broadcastEvents).toHaveLength(1);
    expect(out.broadcastEvents[0].type).toBe('player-said');
  });

  test('empty text → no-op', () => {
    const player = makePlayer();
    const out = handleSay({
      roomId: ROOM_ID,
      player,
      action: { type: 'say', playerId: player.id, text: '' },
    });
    expect(out.selfMessage).toBe('');
    expect(out.broadcastEvents).toHaveLength(0);
  });
});

describe('buildLookMessage', () => {
  test('includes name and description', () => {
    const player = makePlayer();
    const state = makeState();
    const msg = buildLookMessage({ state, player, otherPlayers: [] });
    expect(msg).toContain('[Cave]');
    expect(msg).toContain('A dark cave.');
  });

  test('lists other players', () => {
    const player = makePlayer({ id: 'p' });
    const other = makePlayer({ id: 'p2', name: 'Bob' });
    const state = makeState();
    const msg = buildLookMessage({ state, player, otherPlayers: [other] });
    expect(msg).toContain('Bob is here');
  });
});

```
