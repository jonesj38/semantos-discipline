---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/dungeon/movement-validator.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.405932+00:00
---

# packages/games/src/dungeon/movement-validator.ts

```ts
/**
 * Movement / action validator — central place where dungeon actions
 * route through the WASM policy kernel.
 *
 * The legacy engine inlined `evaluatePolicy` next to every action
 * handler. The split centralizes policy here so each action calls a
 * single `evaluate()` surface and the same `_lastPolicyResult` audit
 * field is updated.
 *
 * Implementation is the `GameCellEngine` + `HostFunctionRegistry`
 * pair (Lisp scripts compiled via `policies.ts`). Tests can construct
 * a `DungeonPolicyEvaluator` with stubs to bypass WASM entirely.
 *
 * The shape mirrors `apps/mud/src/room-actor/policy-engine.ts`.
 */

import type { GameCellEngine } from '../../../game-sdk/src/engine';
import type { HostFunctionRegistry } from '@semantos/cell-engine';
import type { PolicyResult } from '../../../policy-runtime/src/types';
import type { PolicyRuntime } from '../../../policy-runtime/src/runtime';

import type { CompiledDungeonPolicies } from './policies';
import {
  Tile,
  type ActionType,
  type DungeonBoard,
  type DungeonFloor,
  type DungeonPlayer,
  INVENTORY_MAX,
} from './types';

export interface PolicyContextExtras {
  hasItem?: boolean;
  itemUsable?: boolean;
}

export interface EvaluatePolicyArgs {
  action: ActionType;
  targetX: number;
  targetY: number;
  board: DungeonBoard;
  extras?: PolicyContextExtras;
}

export interface DungeonPolicyEvaluator {
  /** Evaluate a compiled dungeon policy. Returns ok + writes audit. */
  evaluate(args: EvaluatePolicyArgs): boolean;
  /** Last evaluation result, for audit-trail inspection. */
  lastResult(): PolicyResult | undefined;
}

export interface MakePolicyEvaluatorArgs {
  cellEngine: GameCellEngine;
  registry: HostFunctionRegistry;
  policies: CompiledDungeonPolicies;
  /** Phase 29.5 PolicyRuntime — when bound, results are recorded. */
  runtime?: PolicyRuntime;
}

/**
 * Build the dungeon policy evaluator backed by the WASM kernel and
 * host-function registry. Pure factory — no atoms beyond the captured
 * cell engine and the rolling `lastResult`.
 */
export function makePolicyEvaluator(
  args: MakePolicyEvaluatorArgs,
): DungeonPolicyEvaluator {
  let last: PolicyResult | undefined;

  return {
    evaluate(input) {
      const fields = buildContextFields(input);
      const policyKey = mapActionToPolicyKey(input.action);
      const policyBytes = args.policies[policyKey].scriptBytes;

      args.registry.setContext(fields);
      const ok = args.cellEngine.evaluatePolicy(policyBytes);
      args.registry.clearContext();

      // Phase 29.5: record structured result for audit
      last = {
        ok,
        gas: 0,
        hostCalls: [],
        rejectionCode: ok ? undefined : 'VERIFY_FAILED',
        rejectionDetail: ok
          ? undefined
          : `Policy '${policyKey}' rejected action '${input.action}'`,
      };
      return ok;
    },
    lastResult: () => last,
  };
}

/** Map the public action type onto the compiled-policy key. */
function mapActionToPolicyKey(
  action: ActionType,
): keyof CompiledDungeonPolicies {
  if (action === 'use') return 'useItem';
  if (action === 'open') return 'openDoor';
  return action;
}

/**
 * Build the frozen evaluation context the WASM engine reads via
 * `OP_CALLHOST`. Keeps the field surface in one place so changes
 * stay co-located with the predicate registry in `host-functions.ts`.
 */
function buildContextFields(args: EvaluatePolicyArgs): Record<string, unknown> {
  const { action, targetX, targetY, board, extras } = args;
  const floor: DungeonFloor = board.floors[board.floor];
  const player: DungeonPlayer = board.player;

  const targetTile =
    targetY >= 0 &&
    targetY < floor.height &&
    targetX >= 0 &&
    targetX < floor.width
      ? floor.tiles[targetY][targetX]
      : Tile.WALL;

  return {
    action,
    playerX: player.position.x,
    playerY: player.position.y,
    targetX,
    targetY,
    mapWidth: floor.width,
    mapHeight: floor.height,
    targetTile,
    hasWeapon: player.equippedWeapon !== null,
    targetIsMonster: floor.monsters.some(
      (m) => m.hp > 0 && m.position.x === targetX && m.position.y === targetY,
    ),
    inventoryCount: player.inventory.length,
    inventoryMax: INVENTORY_MAX,
    doorLocked: targetTile === Tile.DOOR_LOCKED,
    hasMatchingKey: hasMatchingKeyForDoor(board, targetX, targetY),
    ...(extras ?? {}),
  };
}

/** Inventory-side check: does the player carry the matching key? */
export function hasMatchingKeyForDoor(
  board: DungeonBoard,
  x: number,
  y: number,
): boolean {
  const floor = board.floors[board.floor];
  const requiredKeyId = floor.doorLocks.get(`${x},${y}`);
  if (!requiredKeyId) return false;
  return board.player.inventory.some(
    (i) => i.category === 'key' && i.keyId === requiredKeyId,
  );
}

```
