---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-mud/src/room-actor/movement-system.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.840899+00:00
---

# archive/apps-mud/src/room-actor/movement-system.ts

```ts
/**
 * Movement system — `handleMove`, treasure auto-pickup, position update.
 *
 * Returns one of three outcomes via `MoveOutcome.kind`:
 *   - `combat`   — target tile occupied by a live monster, route to combat
 *   - `blocked`  — policy rejected, or another player standing there
 *   - `moved`    — position updated, treasure auto-picked up
 *
 * Also exposes `handleLook` and `handleSay` since they were sibling
 * read-only/chat handlers in the legacy actor and don't justify their
 * own modules.
 */

import {
  DIRECTION_OFFSETS,
  posEq,
  type Monster,
} from '../../../../packages/games/src/dungeon/types';

import type { PolicyEvaluator } from './policy-engine';
import type { MUDPlayer, PlayerAction, RoomEvent, RoomId, RoomState } from '../types';

export type MoveOutcome =
  | { kind: 'combat'; monster: Monster }
  | { kind: 'blocked'; message: string }
  | {
      kind: 'moved';
      message: string;
      consumedCellIds: string[];
      stateChanged: true;
    };

export interface HandleMoveArgs {
  state: RoomState;
  player: MUDPlayer;
  action: PlayerAction;
  /** Other players in the same room — checked for blocking and PvP. */
  otherPlayers: MUDPlayer[];
  policy: PolicyEvaluator;
}

export function handleMove(args: HandleMoveArgs): MoveOutcome {
  const { state, player, action, otherPlayers, policy } = args;
  if (!action.direction) {
    return { kind: 'blocked', message: '' };
  }
  const [dx, dy] = DIRECTION_OFFSETS[action.direction];
  const tx = player.position.x + dx;
  const ty = player.position.y + dy;

  // Check for monster at target — auto-attack
  const monster = state.monsters.find(
    (m) => m.hp > 0 && m.position.x === tx && m.position.y === ty,
  );
  if (monster) {
    return { kind: 'combat', monster };
  }

  // Check for other player at target — blocked
  for (const other of otherPlayers) {
    if (posEq(other.position, { x: tx, y: ty })) {
      return { kind: 'blocked', message: `${other.name} is standing there.` };
    }
  }

  const decision = policy.evaluateMove({
    state,
    player,
    targetX: tx,
    targetY: ty,
  });
  if (!decision.ok) {
    return {
      kind: 'blocked',
      message: `Can't move ${action.direction} -- blocked.`,
    };
  }

  // Commit move
  player.position = { x: tx, y: ty };

  // Auto-pickup treasure on the new tile
  let msg = `Moved ${action.direction}.`;
  const consumed: string[] = [];
  const treasureIdx = state.items.findIndex(
    (i) => i.category === 'treasure' && posEq(i.position, player.position),
  );
  if (treasureIdx >= 0) {
    const treasure = state.items[treasureIdx];
    player.gold += treasure.value ?? 0;
    consumed.push(treasure.entity.id);
    state.items.splice(treasureIdx, 1);
    msg += ` Picked up ${treasure.name} (+${treasure.value}g).`;
  }

  return {
    kind: 'moved',
    message: msg,
    consumedCellIds: consumed,
    stateChanged: true,
  };
}

// ── Look / Say (read-only / chat) ─────────────────────────────────

export interface HandleLookArgs {
  state: RoomState;
  player: MUDPlayer;
  otherPlayers: MUDPlayer[];
}

export function buildLookMessage(args: HandleLookArgs): string {
  const { state, player, otherPlayers } = args;
  const parts: string[] = [];
  parts.push(`[${state.name}] ${state.description}`);

  for (const other of otherPlayers) {
    parts.push(`  ${other.name} is here.`);
  }

  for (const m of state.monsters.filter((mm) => mm.hp > 0)) {
    parts.push(`  ${m.type.name} (${m.hp} HP) lurks nearby.`);
  }

  for (const item of state.items) {
    if (posEq(item.position, player.position)) {
      parts.push(`  On the ground: ${item.name}`);
    }
  }

  parts.push(
    `Exits: ${state.exits
      .map((e) => `${e.direction}${e.locked ? ' (locked)' : ''} -> ${e.targetRoomId}`)
      .join(', ')}`,
  );

  return parts.join('\n');
}

export interface HandleSayArgs {
  roomId: RoomId;
  player: MUDPlayer;
  action: PlayerAction;
}

export interface SayOutcome {
  /** Message to echo back to the speaker. Empty means no-op (no text). */
  selfMessage: string;
  broadcastEvents: RoomEvent[];
}

export function handleSay(args: HandleSayArgs): SayOutcome {
  const { roomId, player, action } = args;
  const text = action.text ?? '';
  if (!text) return { selfMessage: '', broadcastEvents: [] };
  return {
    selfMessage: `You say: "${text}"`,
    broadcastEvents: [
      {
        type: 'player-said',
        roomId,
        playerId: player.id,
        message: `${player.name} says: "${text}"`,
        data: { text },
      },
    ],
  };
}

```
