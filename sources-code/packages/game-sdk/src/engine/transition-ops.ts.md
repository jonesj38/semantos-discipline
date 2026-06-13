---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/game-sdk/src/engine/transition-ops.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.524767+00:00
---

# packages/game-sdk/src/engine/transition-ops.ts

```ts
/**
 * Entity state-machine transitions + raw policy evaluation.
 *
 * `transitionEntity()` finds the legal transition, evaluates its
 * policy through the WASM kernel, and produces a new entity cell
 * with the updated state. The policy bytes are interpreted by the
 * cell-engine kernel directly — see `policy-runtime` for the
 * higher-level audited evaluation.
 */

import type { PlexusKernelWasm } from '../../../../core/cell-ops/src/wasm-interface';
import type { StorageAdapter } from '../../../../core/protocol-types/src/storage';
import {
  TransitionError,
  type EntityStateMachine,
  type GameEntity,
} from '../types';

import { updateEntity } from './entity-ops';

/** Run compiled policy bytes through the kernel; returns truthiness of TOS. */
export function evaluatePolicy(
  kernel: PlexusKernelWasm,
  scriptBytes: Uint8Array,
): boolean {
  kernel.kernel_reset();
  const wasmMem = new Uint8Array(kernel.memory.buffer);
  const scriptPtr = 1024; // safe offset past initial stack region
  wasmMem.set(scriptBytes, scriptPtr);
  const loadRc = kernel.kernel_load_script(scriptPtr, scriptBytes.length);
  if (loadRc !== 0) return false;
  return kernel.kernel_execute() === 0;
}

/** Apply a state transition; throws TransitionError on illegal moves. */
export function transitionEntity(args: {
  storage: StorageAdapter;
  kernel: PlexusKernelWasm;
  entity: GameEntity;
  toState: string;
  machine: EntityStateMachine;
}): GameEntity {
  const trans = args.machine.transitions.find(
    (t) => t.from === args.entity.state && t.to === args.toState,
  );
  if (!trans) {
    throw new TransitionError(
      `No transition from '${args.entity.state}' to '${args.toState}'`,
    );
  }
  if (trans.policy) {
    const passed = evaluatePolicy(args.kernel, new TextEncoder().encode(trans.policy));
    if (!passed) {
      throw new TransitionError(
        `Policy rejected transition from '${args.entity.state}' to '${args.toState}'`,
      );
    }
  }
  return updateEntity(args.storage, args.entity, { state: args.toState });
}

```
