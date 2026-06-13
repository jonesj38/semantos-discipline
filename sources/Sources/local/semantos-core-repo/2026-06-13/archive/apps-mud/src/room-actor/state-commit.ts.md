---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-mud/src/room-actor/state-commit.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.840623+00:00
---

# archive/apps-mud/src/room-actor/state-commit.ts

```ts
/**
 * State commit — produces the next room-state cell on the DAG and
 * fans out to the persister + anchor emitter.
 *
 * Pulled out of `outcome-applier.ts` to keep the applier under the
 * 220-LOC ceiling. Pure-ish: mutates the supplied atoms via the
 * functional `@semantos/state` API and reads the cell engine.
 */

import { get, set } from '@semantos/state';

import type { GameCellEngine } from '../../../../packages/game-sdk/src/engine';
import { GameEntityType } from '../../../../packages/game-sdk/src/types';
import type { AnchorEmitter } from '../../../../packages/policy-runtime/src/anchor-emitter';

import type { Monster } from '../../../../packages/games/src/dungeon/types';

import type { RoomAtoms } from './atoms';
import type { PersisterHandle } from './room-state-persister';
import type { RoomState } from '../types';

const RELEVANT = 3;
const ROOM_OWNER = new Uint8Array(16);
ROOM_OWNER[0] = 0x50;

export interface CommitStateArgs {
  atoms: RoomAtoms;
  cellEngine: GameCellEngine;
  anchorEmitter?: AnchorEmitter;
  persister: PersisterHandle;
}

/** Mint a new RELEVANT room-state cell and persist it asynchronously. */
export function commitRoomState(args: CommitStateArgs): void {
  const { atoms, cellEngine, anchorEmitter, persister } = args;
  const state = get(atoms.roomStateAtom);
  const lastBytes = get(atoms.lastCellBytesAtom);

  const boardEntity = cellEngine.createEntity({
    entityType: GameEntityType.STRUCTURE,
    ownerId: ROOM_OWNER,
    linearity: RELEVANT,
    metadata: {
      domain: 'mud-room',
      roomId: state.roomId,
      turn: state.turnNumber,
      occupants: state.occupants.length,
      monsters: state.monsters.filter((m: Monster) => m.hp > 0).length,
      items: state.items.length,
      prev: state.cellId,
    },
    state: 'active',
    prevCell: lastBytes ?? undefined,
  });

  const nextState: RoomState = {
    ...state,
    cellId: boardEntity.id,
    previousCellId: state.cellId,
  };
  set(atoms.roomStateAtom, nextState);
  set(atoms.lastCellBytesAtom, boardEntity.cell);
  set(atoms.dagHistoryAtom, [...get(atoms.dagHistoryAtom), boardEntity.id]);

  // Non-blocking persistence via effect-backed queue
  persister.enqueue({
    cellId: boardEntity.id,
    roomId: state.roomId,
    turn: state.turnNumber,
    occupants: state.occupants,
    aliveMonsters: state.monsters.filter((m: Monster) => m.hp > 0).length,
    itemCount: state.items.length,
    previousCellId: state.cellId,
  });

  // Anchor emission for terminal events (player deaths)
  const players = get(atoms.playersAtom);
  const hasDeadPlayer = [...players.values()].some((p) => p.hp <= 0);
  if (anchorEmitter && hasDeadPlayer) {
    anchorEmitter.emit(boardEntity.cell, {
      linearity: 'RELEVANT',
      anchorPolicy: 'terminal-only',
      idempotencyKey: `mud-${state.roomId}-${boardEntity.id}-death`,
    });
  }
}

```
