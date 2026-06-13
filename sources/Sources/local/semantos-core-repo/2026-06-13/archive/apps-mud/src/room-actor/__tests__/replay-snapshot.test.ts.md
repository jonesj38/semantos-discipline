---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-mud/src/room-actor/__tests__/replay-snapshot.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.846921+00:00
---

# archive/apps-mud/src/room-actor/__tests__/replay-snapshot.test.ts

```ts
/**
 * 100-action golden-snapshot replay test (per spec for prompt 23).
 *
 * Drives the action processor + outcome applier directly with a fake
 * atom bundle, fake cell engine, and fake persister. After every 10th
 * action the deterministic projection of room state is compared
 * against a frozen golden snapshot.
 *
 * The replay uses a tiny seeded LCG so the action stream is fully
 * deterministic. If anyone changes combat math, inventory rules, or
 * door logic, the snapshot drifts and the test fails — exactly the
 * regression net the spec calls for.
 */

import { describe, expect, test } from 'bun:test';
import { atom, eventBus, get, set } from '@semantos/state';

import { applyHandlerOutcome } from '../outcome-applier';
import { acceptAllMovePolicy } from '../policy-engine';
import { makeRoomActionProcessor } from '../default-handlers';

import type { RoomAtoms } from '../atoms';
import type { PersisterHandle } from '../room-state-persister';
import type { GameCellEngine } from '../../../../../packages/game-sdk/src/engine';

import type {
  Direction,
  DungeonItem,
  Monster,
  MonsterType,
} from '../../../../../packages/games/src/dungeon/types';
import type {
  ActionType,
  MUDPlayer,
  PlayerAction,
  PlayerId,
  RoomEvent,
  RoomState,
} from '../../types';

const ROOM_ID = 'replay-room';
const DIRECTIONS: Direction[] = ['n', 's', 'e', 'w'];
const ACTION_TYPES: ActionType[] = ['move', 'attack', 'pickup', 'use', 'drop', 'say', 'look'];

// Seeded LCG for deterministic action stream
function lcg(seed: number): () => number {
  let s = seed >>> 0;
  return () => {
    s = (s * 1664525 + 1013904223) >>> 0;
    return s / 0x100000000;
  };
}

function makeRat(id: string, x: number, y: number, hp = 4): Monster {
  const type: MonsterType = {
    name: 'Rat',
    char: 'r',
    hp: 3,
    attack: 1,
    defense: 0,
    xpReward: 5,
  };
  return {
    entity: { id } as Monster['entity'],
    type,
    hp,
    position: { x, y },
  };
}

function makeItem(id: string, x: number, y: number): DungeonItem {
  return {
    entity: { id } as DungeonItem['entity'],
    name: 'Gold Pile',
    category: 'treasure',
    position: { x, y },
    value: 5,
  };
}

function makePotion(id: string, x: number, y: number): DungeonItem {
  return {
    entity: { id } as DungeonItem['entity'],
    name: 'Potion',
    category: 'potion',
    position: { x, y },
    healAmount: 5,
  };
}

function makePlayer(): MUDPlayer {
  return {
    id: 'p1',
    entity: { id: 'pe1' } as MUDPlayer['entity'],
    name: 'Hero',
    position: { x: 5, y: 5 },
    hp: 30,
    maxHp: 30,
    attack: 5,
    defense: 1,
    level: 1,
    xp: 0,
    xpToLevel: 50,
    gold: 0,
    inventory: [],
    equippedWeapon: null,
    equippedArmor: null,
    roomId: ROOM_ID,
  };
}

function makeInitialState(): RoomState {
  const tiles = Array(20).fill(0).map(() => Array(20).fill(1));
  const monsters: Monster[] = [];
  for (let i = 0; i < 6; i++) {
    monsters.push(makeRat(`m${i}`, 6 + i, 5, 4));
  }
  const items: DungeonItem[] = [];
  for (let i = 0; i < 4; i++) {
    items.push(makeItem(`gold${i}`, 5, 6 + i));
  }
  for (let i = 0; i < 3; i++) {
    items.push(makePotion(`pot${i}`, 4 + i, 4));
  }
  return {
    cellId: 'state-0',
    roomId: ROOM_ID,
    name: 'Replay Room',
    description: 'Replay test room',
    width: 20,
    height: 20,
    tiles,
    occupants: ['p1'],
    monsters,
    items,
    exits: [],
    doorLocks: new Map(),
    turnNumber: 0,
    previousCellId: null,
  };
}

// Fake cell engine — produces deterministic incrementing cell ids.
function fakeCellEngine(): GameCellEngine {
  let counter = 0;
  return {
    createEntity() {
      counter++;
      return {
        id: `cell-${counter}`,
        cell: new Uint8Array([counter]),
      } as ReturnType<GameCellEngine['createEntity']>;
    },
  } as unknown as GameCellEngine;
}

function noopPersister(): PersisterHandle {
  return {
    enqueue: () => {},
    flush: () => Promise.resolve(),
    dispose: () => {},
    tickAtom: atom(0),
  } as PersisterHandle;
}

function makeAtoms(initialState: RoomState, player: MUDPlayer): RoomAtoms {
  const atoms: RoomAtoms = {
    roomId: ROOM_ID,
    roomStateAtom: atom(initialState),
    playersAtom: atom(new Map<PlayerId, MUDPlayer>([[player.id, player]])),
    consumedCellsAtom: atom(new Set<string>()),
    dagHistoryAtom: atom([initialState.cellId]),
    lastCellBytesAtom: atom<Uint8Array | null>(new Uint8Array([0])),
    eventsBus: eventBus<RoomEvent>(),
  };
  return atoms;
}

interface Snapshot {
  turn: number;
  hp: number;
  gold: number;
  inv: number;
  consumed: number;
  alive: number;
  items: number;
  history: number;
}

function projectSnapshot(atoms: RoomAtoms): Snapshot {
  const state = get(atoms.roomStateAtom);
  const players = get(atoms.playersAtom);
  const player = players.get('p1')!;
  return {
    turn: state.turnNumber,
    hp: player.hp,
    gold: player.gold,
    inv: player.inventory.length,
    consumed: get(atoms.consumedCellsAtom).size,
    alive: state.monsters.filter((m) => m.hp > 0).length,
    items: state.items.length,
    history: get(atoms.dagHistoryAtom).length,
  };
}

function buildAction(playerId: PlayerId, rng: () => number): PlayerAction {
  const type = ACTION_TYPES[Math.floor(rng() * ACTION_TYPES.length)];
  const direction = DIRECTIONS[Math.floor(rng() * DIRECTIONS.length)];
  if (type === 'use' || type === 'drop') {
    return { type, playerId, itemIndex: 0 };
  }
  if (type === 'say') {
    return { type, playerId, text: 'hi' };
  }
  if (type === 'look' || type === 'pickup') {
    return { type, playerId };
  }
  return { type, playerId, direction };
}

describe('Room-actor 100-action golden-snapshot replay', () => {
  test('every 10th action matches the golden snapshot', () => {
    const player = makePlayer();
    const initial = makeInitialState();
    const atoms = makeAtoms(initial, player);
    const cellEngine = fakeCellEngine();
    const persister = noopPersister();
    const processor = makeRoomActionProcessor();

    // Override movement so the player wanders deterministically without
    // walking off the map.
    const policy = acceptAllMovePolicy;
    const rng = lcg(1234);
    const observed: Snapshot[] = [];

    for (let i = 1; i <= 100; i++) {
      const action = buildAction(player.id, rng);
      const livePlayer = get(atoms.playersAtom).get(player.id)!;
      if (livePlayer.hp <= 0) {
        // dead-player path mirrors facade behavior
        atoms.eventsBus.emit({
          type: 'combat',
          roomId: ROOM_ID,
          playerId: livePlayer.id,
          message: 'You are dead. You cannot act.',
        });
      } else {
        const otherPlayers: MUDPlayer[] = [];
        const ctx = {
          roomId: ROOM_ID,
          state: get(atoms.roomStateAtom),
          player: livePlayer,
          action,
          otherPlayers,
          policy,
          pvpEnabled: false,
        };
        const outcome = processor.dispatch(ctx);
        applyHandlerOutcome({
          atoms,
          cellEngine,
          persister,
          player: livePlayer,
          action,
          outcome,
        });
      }
      if (i % 10 === 0) observed.push(projectSnapshot(atoms));
    }

    // Golden snapshots — frozen reference for the seeded action stream.
    // Any change to combat/inventory/movement math must be reflected
    // here intentionally.
    expect(observed).toMatchSnapshot();
  });
});

```
