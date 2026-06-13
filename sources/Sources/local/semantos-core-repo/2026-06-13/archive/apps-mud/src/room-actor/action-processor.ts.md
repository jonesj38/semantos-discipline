---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-mud/src/room-actor/action-processor.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.843874+00:00
---

# archive/apps-mud/src/room-actor/action-processor.ts

```ts
/**
 * Action processor — registry-based dispatcher replacing the legacy
 * `processAction` switch.
 *
 * Each action type registers a handler that takes a `HandlerContext`
 * and returns a `HandlerOutcome`. The facade owns the actual side-
 * effects (atom mutation, event emission, persistence) — handlers are
 * pure dispatchers that return what should happen.
 *
 * Default handler bindings live in `default-handlers.ts`; use
 * `makeRoomActionProcessor()` from there to get a fully-wired
 * dispatcher. This file only owns the contract.
 */

import type { CombatOutcome, PvPOutcome } from './combat-system';
import type { DoorOutcome } from './door-system';
import type { InventoryOutcome } from './inventory-system';
import type { MoveOutcome, SayOutcome } from './movement-system';
import type { PolicyEvaluator } from './policy-engine';

import type { ActionType, MUDPlayer, PlayerAction, RoomId, RoomState } from '../types';

export interface HandlerContext {
  roomId: RoomId;
  state: RoomState;
  player: MUDPlayer;
  action: PlayerAction;
  otherPlayers: MUDPlayer[];
  policy: PolicyEvaluator;
  pvpEnabled: boolean;
}

export type HandlerOutcome =
  | { kind: 'move'; outcome: MoveOutcome }
  | { kind: 'monster-combat'; outcome: CombatOutcome }
  | { kind: 'pvp'; outcome: PvPOutcome; defenderId: string }
  | { kind: 'inventory'; outcome: InventoryOutcome }
  | { kind: 'door'; outcome: DoorOutcome }
  | { kind: 'exit-room'; outcome: DoorOutcome }
  | { kind: 'say'; outcome: SayOutcome }
  | { kind: 'look'; message: string }
  | { kind: 'reject'; message: string };

export type ActionHandler = (ctx: HandlerContext) => HandlerOutcome;

export interface ActionProcessor {
  /** Register a handler for a single action type. Returns dispose. */
  on(type: ActionType, handler: ActionHandler): () => void;
  /** Dispatch an action. Returns the outcome from the matching handler. */
  dispatch(ctx: HandlerContext): HandlerOutcome;
  /** Test seam — the live handler registry, keyed by action type. */
  readonly handlers: ReadonlyMap<ActionType, ActionHandler>;
}

/**
 * Build a fresh, empty action processor. Use
 * `makeRoomActionProcessor()` from `default-handlers.ts` for the
 * fully-wired MUD dispatcher.
 */
export function makeActionProcessor(): ActionProcessor {
  const handlers = new Map<ActionType, ActionHandler>();
  return {
    on(type, handler) {
      handlers.set(type, handler);
      return () => {
        if (handlers.get(type) === handler) handlers.delete(type);
      };
    },
    dispatch(ctx) {
      const handler = handlers.get(ctx.action.type);
      if (!handler) {
        return { kind: 'reject', message: `Unknown action: ${ctx.action.type}` };
      }
      return handler(ctx);
    },
    handlers,
  };
}

```
