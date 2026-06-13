---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-mud/src/room-actor/__tests__/action-processor.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.846634+00:00
---

# archive/apps-mud/src/room-actor/__tests__/action-processor.test.ts

```ts
/**
 * Action processor tests — registry-based dispatch.
 *
 * Verifies that registering a handler routes the matching action,
 * the empty-processor branch returns a `reject`, and that the
 * default-handler set covers every action type.
 */

import { describe, expect, test } from 'bun:test';

import { makeActionProcessor, type ActionProcessor, type HandlerContext } from '../action-processor';
import { makeRoomActionProcessor, registerDefaultHandlers } from '../default-handlers';
import { acceptAllMovePolicy } from '../policy-engine';

import type { ActionType, MUDPlayer, RoomState } from '../../types';

function dummyCtx(actionType: ActionType): HandlerContext {
  const player: MUDPlayer = {
    id: 'p',
    entity: { id: 'pe' } as MUDPlayer['entity'],
    name: 'X',
    position: { x: 0, y: 0 },
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
    roomId: 'r',
  };
  const state: RoomState = {
    cellId: 'c',
    roomId: 'r',
    name: 'r',
    description: '',
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
  return {
    roomId: 'r',
    state,
    player,
    action: { type: actionType, playerId: player.id, direction: 'e' },
    otherPlayers: [],
    policy: acceptAllMovePolicy,
    pvpEnabled: false,
  };
}

describe('makeActionProcessor', () => {
  test('empty processor rejects every action', () => {
    const proc = makeActionProcessor();
    const out = proc.dispatch(dummyCtx('move'));
    expect(out.kind).toBe('reject');
  });

  test('registered handler is dispatched', () => {
    const proc = makeActionProcessor();
    proc.on('look', () => ({ kind: 'look', message: 'custom look' }));
    const out = proc.dispatch(dummyCtx('look'));
    expect(out.kind).toBe('look');
    if (out.kind === 'look') expect(out.message).toBe('custom look');
  });

  test('disposing handler removes it', () => {
    const proc = makeActionProcessor();
    const dispose = proc.on('look', () => ({ kind: 'look', message: 'x' }));
    dispose();
    const out = proc.dispatch(dummyCtx('look'));
    expect(out.kind).toBe('reject');
  });
});

describe('makeRoomActionProcessor', () => {
  test('every standard action type has a handler', () => {
    const proc = makeRoomActionProcessor();
    const types: ActionType[] = [
      'move', 'attack', 'pickup', 'use', 'open', 'drop', 'say', 'look', 'exit-room',
    ];
    for (const t of types) {
      expect(proc.handlers.has(t)).toBe(true);
    }
  });

  test('registerDefaultHandlers attaches to an empty processor', () => {
    const proc: ActionProcessor = makeActionProcessor();
    expect(proc.handlers.size).toBe(0);
    registerDefaultHandlers(proc);
    expect(proc.handlers.size).toBeGreaterThan(0);
  });
});

```
