---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-mud/src/world-server/world-boot-flow.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.838606+00:00
---

# archive/apps-mud/src/world-server/world-boot-flow.ts

```ts
/**
 * World-boot-flow — generate rooms, spin up RoomActors, persist topology,
 * start the pool.
 *
 * Refactor 24 / split of `world-server.ts`. Extracted so the facade
 * does not carry a multi-step boot sequence inline; this keeps
 * `WorldServer.create()` as a thin async constructor.
 *
 * Steps:
 *   1. `generateWorldRooms()` — produce per-room `RoomState` + cell bytes.
 *   2. Spin up a `RoomActor` per room and `register()` into the pool.
 *   3. `wireRoomExits()` — second pass once all rooms exist.
 *   4. `persistTopology()` — JSON snapshot of the exit graph.
 *   5. `pool.startAll()` — fire each actor's async loop.
 */

import type { CellStore } from '../../../../core/protocol-types/src/cell-store';
import type { GameCellEngine } from '../../../../packages/game-sdk/src/engine';
import type { PolicyRuntime } from '../../../../packages/policy-runtime/src/runtime';
import type { AnchorEmitter } from '../../../../packages/policy-runtime/src/anchor-emitter';
import { HostFunctionRegistry } from '@semantos/cell-engine/bindings/host-functions';
import type { CompiledMUDPolicies } from '../policies';
import { RoomActor } from '../room-actor';
import type { WorldConfig } from '../types';

import type { RoomActorPool } from './room-actor-pool';
import {
  generateWorldRooms,
  wireRoomExits,
} from './world-generator';
import {
  persistTopology,
  type TopologySnapshot,
} from './world-persistence';

export interface BootFlowDeps {
  cellEngine: GameCellEngine;
  registry: HostFunctionRegistry;
  policies: CompiledMUDPolicies;
  cellStore: CellStore;
  config: WorldConfig;
  pool: RoomActorPool;
  runtime?: PolicyRuntime;
  anchorEmitter?: AnchorEmitter;
}

/**
 * Run the full boot flow on `deps`. Mutates `deps.pool` (registers all
 * actors and starts them).
 */
export async function bootWorld(deps: BootFlowDeps): Promise<void> {
  // 1. Generate room states + cell bytes
  const generated = generateWorldRooms(deps.cellEngine, deps.config);

  // 2. Spin up per-room actors
  for (const { roomId, state, cellBytes } of generated) {
    const actor = new RoomActor(
      roomId,
      state,
      deps.cellEngine,
      deps.registry,
      deps.policies,
      cellBytes,
      deps.cellStore,
      deps.config.pvpEnabled,
      deps.runtime,
      deps.anchorEmitter,
    );
    deps.pool.register(roomId, actor);
  }

  // 3. Wire exits between rooms (second pass)
  wireRoomExits(generated);

  // 4. Persist topology snapshot
  const topology: TopologySnapshot = {};
  for (const [roomId, actor] of deps.pool.entries()) {
    const s = actor.getState();
    topology[roomId] = {
      name: s.name,
      description: s.description,
      exits: s.exits,
    };
  }
  await persistTopology(deps.cellStore, topology);

  // 5. Start the pool — each actor runs its own async loop
  deps.pool.startAll();
}

```
