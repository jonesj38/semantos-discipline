---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-mud/src/room-actor/default-handlers.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.841647+00:00
---

# archive/apps-mud/src/room-actor/default-handlers.ts

```ts
/**
 * Default action handler registry — wires every standard MUD action
 * type to its system module. Pulled out of `action-processor.ts` to
 * keep that file focused on the dispatcher contract.
 */

import {
  DIRECTION_OFFSETS,
  posEq,
  type Monster,
} from '../../../../packages/games/src/dungeon/types';

import {
  resolveCombatWithMonster,
  resolvePvP,
} from './combat-system';
import { handleExitRoom, handleOpenDoor } from './door-system';
import {
  handleDrop,
  handlePickup,
  handleUseItem,
} from './inventory-system';
import {
  buildLookMessage,
  handleMove,
  handleSay,
} from './movement-system';

import {
  makeActionProcessor,
  type ActionHandler,
  type ActionProcessor,
  type HandlerContext,
} from './action-processor';
import type { MUDPlayer } from '../types';

type AttackTarget =
  | { kind: 'monster'; monster: Monster }
  | { kind: 'player'; player: MUDPlayer }
  | { kind: 'none' };

/** Register every default action handler against the processor. */
export function registerDefaultHandlers(proc: ActionProcessor): void {
  proc.on('move', moveHandler);
  proc.on('attack', attackHandler);
  proc.on('pickup', pickupHandler);
  proc.on('drop', dropHandler);
  proc.on('use', useHandler);
  proc.on('open', openHandler);
  proc.on('exit-room', exitHandler);
  proc.on('say', sayHandler);
  proc.on('look', lookHandler);
}

/** Convenience: build a processor with every default handler wired in. */
export function makeRoomActionProcessor(): ActionProcessor {
  const proc = makeActionProcessor();
  registerDefaultHandlers(proc);
  return proc;
}

const moveHandler: ActionHandler = (ctx) => ({
  kind: 'move',
  outcome: handleMove({
    state: ctx.state,
    player: ctx.player,
    action: ctx.action,
    otherPlayers: ctx.otherPlayers,
    policy: ctx.policy,
  }),
});

const attackHandler: ActionHandler = (ctx) => {
  if (!ctx.action.direction) {
    return { kind: 'reject', message: 'Nothing to attack there.' };
  }
  const target = findAttackTarget(ctx);
  if (target.kind === 'monster') {
    if (!ctx.player.equippedWeapon) {
      return { kind: 'reject', message: 'You have no weapon equipped!' };
    }
    return {
      kind: 'monster-combat',
      outcome: resolveCombatWithMonster({
        roomId: ctx.roomId,
        player: ctx.player,
        monster: target.monster,
      }),
    };
  }
  if (target.kind === 'player' && ctx.pvpEnabled) {
    return {
      kind: 'pvp',
      outcome: resolvePvP({
        roomId: ctx.roomId,
        attacker: ctx.player,
        defender: target.player,
      }),
      defenderId: target.player.id,
    };
  }
  return { kind: 'reject', message: 'Nothing to attack there.' };
};

const pickupHandler: ActionHandler = (ctx) => ({
  kind: 'inventory',
  outcome: handlePickup({
    roomId: ctx.roomId,
    state: ctx.state,
    player: ctx.player,
  }),
});

const dropHandler: ActionHandler = (ctx) => ({
  kind: 'inventory',
  outcome: handleDrop({
    roomId: ctx.roomId,
    state: ctx.state,
    player: ctx.player,
    action: ctx.action,
  }),
});

const useHandler: ActionHandler = (ctx) => ({
  kind: 'inventory',
  outcome: handleUseItem({ player: ctx.player, action: ctx.action }),
});

const openHandler: ActionHandler = (ctx) => ({
  kind: 'door',
  outcome: handleOpenDoor({
    roomId: ctx.roomId,
    state: ctx.state,
    player: ctx.player,
    action: ctx.action,
  }),
});

const exitHandler: ActionHandler = (ctx) => ({
  kind: 'exit-room',
  outcome: handleExitRoom({
    roomId: ctx.roomId,
    state: ctx.state,
    player: ctx.player,
    action: ctx.action,
  }),
});

const sayHandler: ActionHandler = (ctx) => ({
  kind: 'say',
  outcome: handleSay({
    roomId: ctx.roomId,
    player: ctx.player,
    action: ctx.action,
  }),
});

const lookHandler: ActionHandler = (ctx) => ({
  kind: 'look',
  message: buildLookMessage({
    state: ctx.state,
    player: ctx.player,
    otherPlayers: ctx.otherPlayers,
  }),
});

function findAttackTarget(ctx: HandlerContext): AttackTarget {
  const dir = ctx.action.direction;
  if (!dir) return { kind: 'none' };

  const [dx, dy] = DIRECTION_OFFSETS[dir];
  const tx = ctx.player.position.x + dx;
  const ty = ctx.player.position.y + dy;

  const monster = ctx.state.monsters.find(
    (m) => m.hp > 0 && m.position.x === tx && m.position.y === ty,
  );
  if (monster) return { kind: 'monster', monster };

  for (const other of ctx.otherPlayers) {
    if (posEq(other.position, { x: tx, y: ty })) {
      return { kind: 'player', player: other };
    }
  }
  return { kind: 'none' };
}

```
