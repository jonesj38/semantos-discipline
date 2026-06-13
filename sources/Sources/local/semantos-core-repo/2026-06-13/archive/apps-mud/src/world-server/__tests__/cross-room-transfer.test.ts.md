---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-mud/src/world-server/__tests__/cross-room-transfer.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.844826+00:00
---

# archive/apps-mud/src/world-server/__tests__/cross-room-transfer.test.ts

```ts
/**
 * Tests for `cross-room-transfer.ts`.
 *
 * Stub RoomActor surface: `getState`, `addPlayer`, `removePlayer`. Only
 * what `transferPlayer` calls into.
 */

import { describe, test, expect } from 'bun:test';

import { Tile } from '../../../../../packages/games/src/dungeon/types';
import type { RoomActor } from '../../room-actor';
import type { MUDPlayer, RoomState } from '../../types';
import { transferPlayer } from '../cross-room-transfer';
import { PlayerSessionStore } from '../player-session-store';
import { RoomActorPool } from '../room-actor-pool';

function makeRoomState(roomId: string): RoomState {
  const tiles: number[][] = [];
  for (let y = 0; y < 5; y++) {
    const row: number[] = [];
    for (let x = 0; x < 5; x++) row.push(Tile.FLOOR);
    tiles.push(row);
  }
  return {
    cellId: roomId,
    roomId,
    name: roomId,
    description: roomId,
    width: 5,
    height: 5,
    tiles,
    occupants: [],
    monsters: [],
    items: [],
    exits: [],
    doorLocks: new Map(),
    turnNumber: 0,
    previousCellId: null,
  };
}

interface StubActor {
  added: MUDPlayer[];
  removed: string[];
  players: Map<string, MUDPlayer>;
  getState(): RoomState;
  addPlayer(p: MUDPlayer): void;
  removePlayer(playerId: string): MUDPlayer | null;
  start(): Promise<void>;
  stop(): void;
}

interface StubBundle {
  stub: StubActor;
  actor: RoomActor;
}

function makeStubActor(roomId: string): StubBundle {
  const state = makeRoomState(roomId);
  const players = new Map<string, MUDPlayer>();
  const stub: StubActor = {
    added: [],
    removed: [],
    players,
    getState() { return state; },
    addPlayer(p: MUDPlayer) {
      players.set(p.id, p);
      this.added.push(p);
    },
    removePlayer(playerId: string) {
      const p = players.get(playerId);
      if (!p) {
        this.removed.push(playerId);
        return null;
      }
      players.delete(playerId);
      this.removed.push(playerId);
      return p;
    },
    async start() {},
    stop() {},
  };
  return { stub, actor: stub as unknown as RoomActor };
}

function makePlayer(id: string, roomId: string): MUDPlayer {
  return {
    id,
    entity: { id: `entity-${id}` } as never,
    name: id,
    position: { x: 1, y: 1 },
    hp: 30,
    maxHp: 30,
    attack: 2,
    defense: 0,
    level: 1,
    xp: 0,
    xpToLevel: 50,
    gold: 0,
    inventory: [],
    equippedWeapon: null,
    equippedArmor: null,
    roomId,
  };
}

describe('transferPlayer', () => {
  test('moves the player from source to target and re-binds the session', () => {
    const pool = new RoomActorPool();
    const sessions = new PlayerSessionStore();

    const r1 = makeStubActor('r1');
    const r2 = makeStubActor('r2');
    pool.register('r1', r1.actor);
    pool.register('r2', r2.actor);

    const player = makePlayer('p1', 'r1');
    r1.stub.addPlayer(player);
    sessions.bind({
      sessionId: 's1',
      playerId: 'p1',
      playerName: 'p',
      currentRoomId: 'r1',
      connectedAt: 0,
    });

    const ok = transferPlayer(pool, sessions, 'p1', 'r2');
    expect(ok).toBe(true);
    expect(r1.stub.players.has('p1')).toBe(false);
    expect(r2.stub.players.has('p1')).toBe(true);
    expect(sessions.getPlayerRoom('p1')).toBe('r2');
    expect(sessions.getSession('s1')?.currentRoomId).toBe('r2');

    const moved = r2.stub.players.get('p1')!;
    expect(moved.roomId).toBe('r2');
  });

  test('returns false when the player is not bound to any room', () => {
    const pool = new RoomActorPool();
    const sessions = new PlayerSessionStore();
    pool.register('r1', makeStubActor('r1').actor);
    expect(transferPlayer(pool, sessions, 'unknown', 'r1')).toBe(false);
  });

  test('returns false when the target room is missing from the pool', () => {
    const pool = new RoomActorPool();
    const sessions = new PlayerSessionStore();

    const r1 = makeStubActor('r1');
    pool.register('r1', r1.actor);
    r1.stub.addPlayer(makePlayer('p1', 'r1'));
    sessions.bind({
      sessionId: 's1',
      playerId: 'p1',
      playerName: 'p',
      currentRoomId: 'r1',
      connectedAt: 0,
    });

    expect(transferPlayer(pool, sessions, 'p1', 'no-such-room')).toBe(false);
    // Player must remain in r1.
    expect(r1.stub.players.has('p1')).toBe(true);
    expect(sessions.getPlayerRoom('p1')).toBe('r1');
  });

  test('same-room transfer is a no-op success', () => {
    const pool = new RoomActorPool();
    const sessions = new PlayerSessionStore();

    const r1 = makeStubActor('r1');
    pool.register('r1', r1.actor);
    r1.stub.addPlayer(makePlayer('p1', 'r1'));
    sessions.bind({
      sessionId: 's1',
      playerId: 'p1',
      playerName: 'p',
      currentRoomId: 'r1',
      connectedAt: 0,
    });

    expect(transferPlayer(pool, sessions, 'p1', 'r1')).toBe(true);
    // Player should not have been removed/re-added.
    expect(r1.stub.removed).toEqual([]);
    expect(r1.stub.added).toHaveLength(1); // only the initial add
  });
});

```
