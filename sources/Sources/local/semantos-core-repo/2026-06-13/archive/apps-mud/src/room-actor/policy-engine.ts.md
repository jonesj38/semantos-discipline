---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-mud/src/room-actor/policy-engine.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.842771+00:00
---

# archive/apps-mud/src/room-actor/policy-engine.ts

```ts
/**
 * Policy engine — single place where MUD action policies are evaluated.
 *
 * The legacy actor inlined `evaluateMovePolicy` next to the move
 * handler. The split centralizes policy here so every system module
 * routes through the same `evaluate` surface and the same
 * `_lastPolicyResult` audit field.
 *
 * Implementation is still the `GameCellEngine` + `HostFunctionRegistry`
 * pair (Lisp scripts compiled via `policies.ts`). The thin adapter
 * shape lets tests inject a stub evaluator without spinning up a WASM
 * kernel.
 */

import type { GameCellEngine } from '../../../../packages/game-sdk/src/engine';
import type { HostFunctionRegistry } from '../../../../core/cell-engine/bindings/host-functions';
import type { PolicyResult } from '../../../../packages/policy-runtime/src/types';
import { Tile } from '../../../../packages/games/src/dungeon/types';

import type { CompiledMUDPolicies } from '../policies';
import type { MUDPlayer, RoomState } from '../types';
import { INVENTORY_MAX } from '../types';

export interface MovePolicyInput {
  state: RoomState;
  player: MUDPlayer;
  targetX: number;
  targetY: number;
}

export interface PolicyEvaluator {
  /** Evaluate the compiled `move` policy. Returns ok + audit result. */
  evaluateMove(input: MovePolicyInput): { ok: boolean; result: PolicyResult };
  /** Last evaluation result, for audit trail inspection. */
  lastResult(): PolicyResult | undefined;
}

export interface MakePolicyEvaluatorArgs {
  cellEngine: GameCellEngine;
  registry: HostFunctionRegistry;
  policies: CompiledMUDPolicies;
}

/**
 * Build the production move-policy evaluator backed by the WASM kernel
 * and host-function registry. Pure factory — no atoms or shared state
 * beyond the captured cell engine.
 */
export function makePolicyEvaluator(
  args: MakePolicyEvaluatorArgs,
): PolicyEvaluator {
  let last: PolicyResult | undefined;

  return {
    evaluateMove(input) {
      const fields = buildMoveFields(input);
      args.registry.setContext(fields);
      const ok = args.cellEngine.evaluatePolicy(args.policies.move.scriptBytes);
      args.registry.clearContext();
      const result: PolicyResult = {
        ok,
        gas: 0,
        hostCalls: [],
        rejectionCode: ok ? undefined : 'VERIFY_FAILED',
        rejectionDetail: ok
          ? undefined
          : `Move policy rejected (${input.targetX},${input.targetY})`,
      };
      last = result;
      return { ok, result };
    },
    lastResult: () => last,
  };
}

function buildMoveFields(input: MovePolicyInput): Record<string, unknown> {
  const { state, player, targetX, targetY } = input;
  const inBounds =
    targetY >= 0 &&
    targetY < state.height &&
    targetX >= 0 &&
    targetX < state.width;
  const targetTile = inBounds ? state.tiles[targetY][targetX] : Tile.WALL;

  return {
    action: 'move',
    playerX: player.position.x,
    playerY: player.position.y,
    targetX,
    targetY,
    mapWidth: state.width,
    mapHeight: state.height,
    targetTile,
    hasWeapon: player.equippedWeapon !== null,
    targetIsMonster: false,
    inventoryCount: player.inventory.length,
    inventoryMax: INVENTORY_MAX,
    doorLocked: targetTile === Tile.DOOR_LOCKED,
    hasMatchingKey: false,
  };
}

/** Convenience evaluator that always accepts — used by tests. */
export const acceptAllMovePolicy: PolicyEvaluator = {
  evaluateMove() {
    const result: PolicyResult = { ok: true, gas: 0, hostCalls: [] };
    return { ok: true, result };
  },
  lastResult: () => undefined,
};

```
