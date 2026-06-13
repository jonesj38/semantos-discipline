---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/game-sdk/src/engine/cell-engine-facade.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.526891+00:00
---

# packages/game-sdk/src/engine/cell-engine-facade.ts

```ts
/**
 * `GameCellEngine` — thin orchestrator over the prompt-22 ops
 * modules. Public method shape matches the legacy class exactly
 * so all five downstream game extensions compile unchanged.
 */

import type { PlexusKernelWasm } from '../../../../core/cell-ops/src/wasm-interface';
import { createAdapter } from '../../../../core/protocol-types/src/adapters/create-adapter';
import type { StorageAdapter } from '../../../../core/protocol-types/src/storage';
import type {
  AnchorEmitter,
  AnchorOptions,
} from '../../../../packages/policy-runtime/src/anchor-emitter';
import type {
  PolicyContext,
  PolicyResult,
} from '../../../../packages/policy-runtime/src/types';
import type { PolicyRuntime } from '../../../../packages/policy-runtime/src/runtime';

import {
  createEntity,
  deserializeEntity,
  getEntity,
  loadEntity,
  serializeEntity,
  updateEntity,
  type CreateEntityOptions,
  type UpdateEntityChanges,
} from './entity-ops';
import {
  addToInventory,
  createInventory,
  loadInventory,
  removeFromInventory,
  transferBetweenInventories,
} from './inventory-ops';
import { bootKernel, type LoadKernelOptions } from './kernel-loader';
import { evaluatePolicy, transitionEntity } from './transition-ops';
import { executeTrade } from './trade-ops';
import type {
  EntityStateMachine,
  GameEntity,
  Inventory,
  TradeProposal,
  TradeResult,
} from '../types';

export interface CreateOptions extends LoadKernelOptions {
  /** Explicit StorageAdapter — bypasses createAdapter() auto-detection. */
  storage?: StorageAdapter;
  /** Phase 29.5: PolicyRuntime for kernel-enforced policy evaluation. */
  policyRuntime?: PolicyRuntime;
  /** Phase 29.5: AnchorEmitter for terminal-event anchor transactions. */
  anchorEmitter?: AnchorEmitter;
}

export class GameCellEngine {
  private kernel: PlexusKernelWasm;
  readonly storage: StorageAdapter;
  readonly policyRuntime?: PolicyRuntime;
  readonly anchorEmitter?: AnchorEmitter;

  private constructor(
    kernel: PlexusKernelWasm,
    storage: StorageAdapter,
    policyRuntime?: PolicyRuntime,
    anchorEmitter?: AnchorEmitter,
  ) {
    this.kernel = kernel;
    this.storage = storage;
    this.policyRuntime = policyRuntime;
    this.anchorEmitter = anchorEmitter;
  }

  static async create(options?: CreateOptions): Promise<GameCellEngine> {
    const kernel = await bootKernel(options ?? {});
    const storage = options?.storage ?? (await createAdapter());
    return new GameCellEngine(
      kernel,
      storage,
      options?.policyRuntime,
      options?.anchorEmitter,
    );
  }

  // ── Entity CRUD ─────────────────────────────────────────────

  createEntity(opts: CreateEntityOptions): GameEntity {
    return createEntity(this.storage, opts);
  }
  getEntity(cell: Uint8Array): GameEntity {
    return getEntity(cell);
  }
  updateEntity(entity: GameEntity, updates: UpdateEntityChanges): GameEntity {
    return updateEntity(this.storage, entity, updates);
  }
  async loadEntity(id: string): Promise<GameEntity | null> {
    return loadEntity(this.storage, id);
  }
  serialize(entity: GameEntity): Uint8Array {
    return serializeEntity(entity);
  }
  deserialize(cell: Uint8Array): GameEntity {
    return deserializeEntity(cell);
  }

  // ── Inventory ───────────────────────────────────────────────

  createInventory(ownerId: Uint8Array): Inventory {
    return createInventory(ownerId);
  }
  addToInventory(inventory: Inventory, slot: string, entity: GameEntity): Inventory {
    return addToInventory(this.storage, inventory, slot, entity);
  }
  removeFromInventory(
    inventory: Inventory,
    slot: string,
  ): { inventory: Inventory; removed: Uint8Array } {
    return removeFromInventory(this.storage, inventory, slot);
  }
  transferBetweenInventories(
    from: Inventory,
    to: Inventory,
    sourceSlot: string,
    destSlot: string,
  ): { from: Inventory; to: Inventory } {
    return transferBetweenInventories(this.storage, from, to, sourceSlot, destSlot);
  }
  async loadInventory(ownerId: Uint8Array): Promise<Inventory> {
    return loadInventory(this.storage, ownerId);
  }

  // ── Trade ───────────────────────────────────────────────────

  executeTrade(proposal: TradeProposal): TradeResult {
    return executeTrade(this.storage, proposal);
  }

  // ── State machine ───────────────────────────────────────────

  transition(
    entity: GameEntity,
    toState: string,
    machine: EntityStateMachine,
  ): GameEntity {
    return transitionEntity({
      storage: this.storage,
      kernel: this.kernel,
      entity,
      toState,
      machine,
    });
  }

  // ── Policy ──────────────────────────────────────────────────

  evaluatePolicy(scriptBytes: Uint8Array): boolean {
    return evaluatePolicy(this.kernel, scriptBytes);
  }

  async evaluateWithRuntime(
    scriptBytes: Uint8Array,
    ctx: PolicyContext,
  ): Promise<PolicyResult> {
    if (!this.policyRuntime) {
      const ok = this.evaluatePolicy(scriptBytes);
      return {
        ok,
        gas: 0,
        hostCalls: [],
        rejectionCode: ok ? undefined : 'VERIFY_FAILED',
        rejectionDetail: ok
          ? undefined
          : 'Policy evaluation failed (raw kernel, no PolicyRuntime)',
      };
    }
    return this.policyRuntime.evaluate(scriptBytes, ctx);
  }

  async emitAnchor(
    cell: Uint8Array,
    opts: AnchorOptions,
  ): Promise<{ txid: string } | null> {
    if (!this.anchorEmitter) return null;
    const result = await this.anchorEmitter.emit(cell, opts);
    return { txid: result.txid };
  }
}

export type { CreateEntityOptions };

```
