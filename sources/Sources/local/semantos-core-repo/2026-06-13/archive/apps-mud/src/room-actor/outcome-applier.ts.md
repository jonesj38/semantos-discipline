---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-mud/src/room-actor/outcome-applier.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.841928+00:00
---

# archive/apps-mud/src/room-actor/outcome-applier.ts

```ts
/**
 * Outcome applier — translates a `HandlerOutcome` from the action
 * processor into atom mutations, event emissions, and a state commit.
 *
 * The facade owns the actor lifecycle; this module owns the per-action
 * effect fan-out so the facade stays under 220 LOC and the applier
 * itself is unit-testable against a fake atom bundle + event bus.
 */

import { get, set } from '@semantos/state';

import type { GameCellEngine } from '../../../../packages/game-sdk/src/engine';
import type { AnchorEmitter } from '../../../../packages/policy-runtime/src/anchor-emitter';

import type { HandlerOutcome } from './action-processor';
import type { RoomAtoms } from './atoms';
import type { PersisterHandle } from './room-state-persister';
import { resolveCombatWithMonster } from './combat-system';
import { commitRoomState } from './state-commit';

import type {
  MUDPlayer,
  PlayerAction,
  PlayerId,
  RoomEvent,
} from '../types';

export interface ApplyOutcomeArgs {
  atoms: RoomAtoms;
  cellEngine: GameCellEngine;
  anchorEmitter?: AnchorEmitter;
  persister: PersisterHandle;
  player: MUDPlayer;
  action: PlayerAction;
  outcome: HandlerOutcome;
}

export function applyHandlerOutcome(args: ApplyOutcomeArgs): void {
  const { atoms, player, outcome } = args;
  const roomId = atoms.roomId;

  switch (outcome.kind) {
    case 'reject':
      emitResult(atoms, player.id, false, outcome.message);
      return;

    case 'look':
      emitResult(atoms, player.id, true, outcome.message);
      return;

    case 'say':
      for (const ev of outcome.outcome.broadcastEvents) atoms.eventsBus.emit(ev);
      if (outcome.outcome.selfMessage) {
        emitResult(atoms, player.id, true, outcome.outcome.selfMessage);
      }
      return;

    case 'move': {
      const m = outcome.outcome;
      if (m.kind === 'combat') {
        // 'move' onto a live monster forces combat (legacy parity).
        const combat = resolveCombatWithMonster({ roomId, player, monster: m.monster });
        return applyHandlerOutcome({
          ...args,
          outcome: { kind: 'monster-combat', outcome: combat },
        });
      }
      if (m.kind === 'blocked') {
        emitResult(atoms, player.id, false, m.message);
        return;
      }
      bumpTurn(atoms);
      addConsumed(atoms, m.consumedCellIds);
      commit(args);
      emitResult(atoms, player.id, true, m.message);
      return;
    }

    case 'monster-combat': {
      const c = outcome.outcome;
      addConsumed(atoms, c.consumedCellIds);
      for (const ev of c.broadcastEvents) atoms.eventsBus.emit(ev);
      bumpTurn(atoms);
      commit(args);
      emitResult(atoms, player.id, true, c.message);
      return;
    }

    case 'pvp': {
      const p = outcome.outcome;
      if (p.attackerError) {
        emitResult(atoms, player.id, false, p.attackerError);
        return;
      }
      addConsumed(atoms, p.consumedCellIds);
      for (const ev of p.broadcastEvents) atoms.eventsBus.emit(ev);
      if (p.defenderMessage) {
        emitResult(atoms, outcome.defenderId, true, p.defenderMessage);
      }
      bumpTurn(atoms);
      commit(args);
      emitResult(atoms, player.id, true, p.message);
      return;
    }

    case 'inventory':
    case 'door': {
      const o = outcome.outcome;
      if (!o.success && !o.stateChanged) {
        emitResult(atoms, player.id, false, o.message);
        return;
      }
      addConsumed(atoms, o.consumedCellIds);
      for (const ev of o.broadcastEvents) atoms.eventsBus.emit(ev);
      if (o.stateChanged) {
        bumpTurn(atoms);
        commit(args);
      }
      emitResult(atoms, player.id, o.success, o.message);
      return;
    }

    case 'exit-room': {
      const d = outcome.outcome;
      if (!d.success) {
        emitResult(atoms, player.id, false, d.message);
        return;
      }
      addConsumed(atoms, d.consumedCellIds);
      for (const ev of d.broadcastEvents) atoms.eventsBus.emit(ev);
      // No commit — exit-room is a signal; world-server transfers the player.
      emitResult(atoms, player.id, true, d.message);
      return;
    }
  }
}

// ── Internal helpers ──────────────────────────────────────────────

function emitResult(
  atoms: RoomAtoms,
  playerId: PlayerId,
  success: boolean,
  message: string,
): void {
  const event: RoomEvent = {
    type: 'combat',
    roomId: atoms.roomId,
    playerId,
    message,
    data: { success },
  };
  atoms.eventsBus.emit(event);
}

function bumpTurn(atoms: RoomAtoms): void {
  const state = get(atoms.roomStateAtom);
  set(atoms.roomStateAtom, { ...state, turnNumber: state.turnNumber + 1 });
}

function addConsumed(atoms: RoomAtoms, ids: string[]): void {
  if (ids.length === 0) return;
  const next = new Set(get(atoms.consumedCellsAtom));
  for (const id of ids) next.add(id);
  set(atoms.consumedCellsAtom, next);
}

function commit(args: ApplyOutcomeArgs): void {
  commitRoomState({
    atoms: args.atoms,
    cellEngine: args.cellEngine,
    anchorEmitter: args.anchorEmitter,
    persister: args.persister,
  });
}

```
