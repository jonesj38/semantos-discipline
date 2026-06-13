---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/game-sdk/src/ecs/world.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.529237+00:00
---

# packages/game-sdk/src/ecs/world.ts

```ts
/**
 * Game World — bitECS world factory wired up for the game-sdk.
 *
 * The bitECS world is a pure data container. This module wraps it with:
 *
 *   - A sidecar `entityById` Map<handle, GameEntity> that holds the
 *     authoritative tier-2 cell for every CellBacked entity. bitECS can't
 *     store objects in SoA components, so we index into this Map via the
 *     u32 `CellBacked.handle` field.
 *
 *   - A sidecar `tradeOffers` Map<key, string[]> for command components that
 *     need string-list payloads (see TradeIntent in components.ts).
 *
 *   - A handle allocator (`nextHandle`) and an offer-key allocator
 *     (`nextOfferKey`) so components can reference sidecar entries by
 *     numeric key.
 *
 *   - A dirty-promotion queue so hot-loop systems can flag entities for
 *     tier-2 promotion without scanning all components at sync time.
 *     (The Dirty component is still the source of truth; the queue is just
 *     a fast-path enumerator.)
 *
 * The world is deliberately decoupled from `GameCellEngine` — the bridge
 * module takes both as parameters. That way you can mock the tier-2 layer in
 * tests, or drive the same bitECS world against multiple engine instances.
 */

import { createWorld, registerComponents } from 'bitecs';

import type { GameEntity } from '../types';
import {
  CellBacked,
  Dirty,
  Position,
  Velocity,
  Health,
  Owner,
  StateTag,
  TradeIntent,
} from './components';

// ── Types ──────────────────────────────────────────────────────────────────

/**
 * The shape of a game world. This is a bitECS world with sidecar tables
 * attached as plain properties. bitECS treats unknown properties on the
 * world object as opaque and leaves them alone.
 */
export interface GameWorld {
  /** The underlying bitECS world (any of the ECS API calls accept this). */
  readonly ecs: ReturnType<typeof createWorld>;

  /** Sidecar: handle → authoritative cell-backed GameEntity. */
  readonly entityById: Map<number, GameEntity>;

  /** Sidecar: reverse lookup eid → handle, for promotion. */
  readonly handleByEid: Map<number, number>;

  /** Sidecar: offerKey → list of slot names (for TradeIntent). */
  readonly tradeOffers: Map<number, string[]>;

  /** Handle allocator. */
  nextHandle: number;

  /** TradeIntent offer-key allocator. */
  nextOfferKey: number;

  /** Fast-path set of eids flagged as dirty since the last syncToCell. */
  readonly dirtyQueue: Set<number>;
}

// ── Factory ────────────────────────────────────────────────────────────────

/**
 * Create a new game world with all game-sdk components registered.
 *
 * You can add more components post-hoc by calling `registerComponents` with
 * your own component descriptors — bitECS won't notice.
 */
export function createGameWorld(): GameWorld {
  const ecs = createWorld();

  registerComponents(ecs, [
    CellBacked,
    Dirty,
    Position,
    Velocity,
    Health,
    Owner,
    StateTag,
    TradeIntent,
  ]);

  return {
    ecs,
    entityById: new Map(),
    handleByEid: new Map(),
    tradeOffers: new Map(),
    nextHandle: 1, // 0 is reserved for "not yet assigned"
    nextOfferKey: 1,
    dirtyQueue: new Set(),
  };
}

// ── Sidecar helpers ────────────────────────────────────────────────────────

/**
 * Allocate a fresh handle for a new cell-backed entity and record the
 * sidecar mapping. Returns the handle value the caller should write into
 * `CellBacked.handle[eid]`.
 */
export function registerCellBacked(
  world: GameWorld,
  eid: number,
  entity: GameEntity,
): number {
  const handle = world.nextHandle++;
  world.entityById.set(handle, entity);
  world.handleByEid.set(eid, handle);
  return handle;
}

/**
 * Look up the authoritative GameEntity for an eid. Returns undefined if the
 * eid is not cell-backed (has no handle in the sidecar).
 */
export function getCellBackedEntity(
  world: GameWorld,
  eid: number,
): GameEntity | undefined {
  const handle = world.handleByEid.get(eid);
  if (handle === undefined) return undefined;
  return world.entityById.get(handle);
}

/**
 * Replace the authoritative entity for an eid (used by the bridge after a
 * successful tier-2 update).
 */
export function setCellBackedEntity(
  world: GameWorld,
  eid: number,
  entity: GameEntity,
): void {
  const handle = world.handleByEid.get(eid);
  if (handle === undefined) {
    throw new Error(
      `Entity ${eid} is not cell-backed — call registerCellBacked first`,
    );
  }
  world.entityById.set(handle, entity);
}

/** Stash a trade offer (slot-name list) and return its key. */
export function stashTradeOffer(world: GameWorld, slots: string[]): number {
  const key = world.nextOfferKey++;
  world.tradeOffers.set(key, slots);
  return key;
}

/** Retrieve a stashed trade offer by key. */
export function loadTradeOffer(
  world: GameWorld,
  key: number,
): string[] | undefined {
  return world.tradeOffers.get(key);
}

/** Drop a stashed trade offer (call after the trade resolves). */
export function clearTradeOffer(world: GameWorld, key: number): void {
  world.tradeOffers.delete(key);
}

// ── Dirty tracking ─────────────────────────────────────────────────────────

/**
 * Mark an entity dirty. Systems in the hot loop should call this whenever
 * they mutate gameplay state that needs to be persisted to tier-2.
 *
 * This is a two-channel mechanism:
 *   1. The bitECS `Dirty` tag — queryable, used by the bridge to enumerate.
 *   2. The `dirtyQueue` Set — fast-path for sync-time iteration without a
 *      component scan.
 *
 * The caller is responsible for adding the `Dirty` component itself via
 * bitECS's `addComponent`. This function only records the queue entry.
 */
export function markDirty(world: GameWorld, eid: number): void {
  world.dirtyQueue.add(eid);
}

/**
 * Drain the dirty queue and return the list of eids to promote. After this,
 * the queue is empty. The caller is responsible for removing the `Dirty`
 * component from each eid after successful promotion.
 */
export function drainDirty(world: GameWorld): number[] {
  const out = Array.from(world.dirtyQueue);
  world.dirtyQueue.clear();
  return out;
}

```
