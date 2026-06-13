---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-mud/src/room-actor/door-system.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.843043+00:00
---

# archive/apps-mud/src/room-actor/door-system.ts

```ts
/**
 * Door system — open + locked-door key consumption.
 *
 * Pure handler over `(state, player, action)` returning a structured
 * `DoorOutcome` the facade fans out as RoomEvents and ActionResults.
 * Locked doors consume the matching key (LINEAR destruction) — the
 * key's cell id flows out via `consumedCellIds` for the persister.
 */

import {
  DIRECTION_OFFSETS,
  Tile,
} from '../../../../packages/games/src/dungeon/types';

import type { MUDPlayer, PlayerAction, RoomEvent, RoomId, RoomState } from '../types';

export interface DoorOutcome {
  success: boolean;
  message: string;
  consumedCellIds: string[];
  broadcastEvents: RoomEvent[];
  stateChanged: boolean;
}

const NOOP: DoorOutcome = {
  success: false,
  message: '',
  consumedCellIds: [],
  broadcastEvents: [],
  stateChanged: false,
};

export interface OpenDoorArgs {
  roomId: RoomId;
  state: RoomState;
  player: MUDPlayer;
  action: PlayerAction;
}

export function handleOpenDoor(args: OpenDoorArgs): DoorOutcome {
  const { roomId, state, player, action } = args;
  if (!action.direction) return NOOP;

  const [dx, dy] = DIRECTION_OFFSETS[action.direction];
  const tx = player.position.x + dx;
  const ty = player.position.y + dy;

  const tile = state.tiles[ty]?.[tx];
  if (tile !== Tile.DOOR_CLOSED && tile !== Tile.DOOR_LOCKED) {
    return { ...NOOP, message: 'No door to open there.' };
  }

  const consumed: string[] = [];
  if (tile === Tile.DOOR_LOCKED) {
    const keyId = state.doorLocks.get(`${tx},${ty}`);
    const keyIdx = player.inventory.findIndex(
      (i) => i.category === 'key' && i.keyId === keyId,
    );
    if (keyIdx < 0) {
      return {
        ...NOOP,
        message: 'The door is locked. You need the right key.',
      };
    }
    // Consume key (LINEAR destruction)
    consumed.push(player.inventory[keyIdx].entity.id);
    player.inventory.splice(keyIdx, 1);
    state.doorLocks.delete(`${tx},${ty}`);
  }

  state.tiles[ty][tx] = Tile.DOOR_OPEN;

  return {
    success: true,
    message: 'You open the door.',
    consumedCellIds: consumed,
    broadcastEvents: [
      {
        type: 'door-opened',
        roomId,
        playerId: player.id,
        message: `${player.name} opens a door.`,
      },
    ],
    stateChanged: true,
  };
}

export interface ExitRoomArgs {
  roomId: RoomId;
  state: RoomState;
  player: MUDPlayer;
  action: PlayerAction;
}

export function handleExitRoom(args: ExitRoomArgs): DoorOutcome {
  const { roomId, state, player, action } = args;
  if (!action.direction) return NOOP;
  const exit = state.exits.find((e) => e.direction === action.direction);
  if (!exit) {
    return { ...NOOP, message: `No exit ${action.direction}.` };
  }

  const consumed: string[] = [];
  if (exit.locked) {
    const keyIdx = player.inventory.findIndex(
      (i) => i.category === 'key' && i.keyId === exit.keyId,
    );
    if (keyIdx < 0) {
      return { ...NOOP, message: 'That exit is locked.' };
    }
    consumed.push(player.inventory[keyIdx].entity.id);
    player.inventory.splice(keyIdx, 1);
    exit.locked = false;
  }

  return {
    success: true,
    message: `You head ${action.direction} toward ${exit.targetRoomId}.`,
    consumedCellIds: consumed,
    broadcastEvents: [
      {
        type: 'player-left',
        roomId,
        playerId: player.id,
        message: `${player.name} heads ${action.direction}.`,
        data: { targetRoomId: exit.targetRoomId, direction: action.direction },
      },
    ],
    // exit-room is signal-only; world server does the cross-room transfer
    stateChanged: false,
  };
}

```
