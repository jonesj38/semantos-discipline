---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/game-sdk/src/ecs/bridge.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.529520+00:00
---

# packages/game-sdk/src/ecs/bridge.ts

```ts
/**
 * Tier-1 ↔ Tier-2 Bridge.
 *
 * The game-sdk has a two-tier architecture:
 *
 *   Tier-1 (bitECS): hot-loop working set — per-frame reads and writes,
 *     cache-friendly SoA arrays, cheap queries. Not durable, not
 *     authoritative, not auditable.
 *
 *   Tier-2 (cell-engine): authority layer — 1024-byte cells, linearity
 *     enforcement, snapshot-and-swap trades, prev-state-hash chains. Durable,
 *     auditable, expensive per-update.
 *
 * The bridge is the only place those two tiers touch:
 *
 *   syncFromCell  :  authoritative cell → bitECS components (demotion)
 *   syncToCell    :  bitECS components → authoritative cell (promotion)
 *
 * Game code never pokes at cells directly. It mutates bitECS components, sets
 * the Dirty tag, and lets syncToCell handle the tier boundary.
 *
 * ## Metadata shape
 *
 * syncFromCell reads numeric gameplay fields out of the cell's metadata JSON
 * under well-known keys. The convention:
 *
 *   metadata.position  = { x, y, z }        // optional
 *   metadata.velocity  = { dx, dy, dz }     // optional
 *   metadata.health    = { current, max }   // optional
 *
 * If a key is absent, the corresponding bitECS component is not added. This
 * means you can have "render-only" entities (Position + cell) or "stat-only"
 * entities (Health + cell) without paying for unused components.
 *
 * syncToCell is symmetric: it reads the components that are present on the
 * eid and writes them back into metadata under the same keys before calling
 * `engine.updateEntity`.
 */

import { addEntity, addComponent, hasComponent, removeComponent } from 'bitecs';

import type { GameEntity } from '../types';
import type { GameCellEngine } from '../engine';

import {
  CellBacked,
  Dirty,
  Position,
  Velocity,
  Health,
  Owner,
  StateTag,
  hashStateTag,
  shortOwnerId,
} from './components';

import {
  type GameWorld,
  registerCellBacked,
  getCellBackedEntity,
  setCellBackedEntity,
  drainDirty,
} from './world';

// ── Promotion path: tier-2 → tier-1 ────────────────────────────────────────

/**
 * Spawn a fresh bitECS entity from an authoritative GameEntity.
 *
 * - Adds `CellBacked` (handle + entityType + linearity + timestamp).
 * - Adds `Owner` (truncated ownerId).
 * - Adds `StateTag` (u16 hash of entity.state).
 * - Adds `Position` / `Velocity` / `Health` if the corresponding metadata
 *   keys are present.
 *
 * Returns the newly created eid. The caller gets a handle to use with any
 * bitECS APIs and can freely add more components.
 */
export function syncFromCell(world: GameWorld, entity: GameEntity): number {
  const eid = addEntity(world.ecs);

  const handle = registerCellBacked(world, eid, entity);

  // CellBacked bridge tag
  addComponent(world.ecs, eid, CellBacked);
  CellBacked.handle[eid] = handle;
  CellBacked.entityType[eid] = entity.entityType;
  CellBacked.linearity[eid] = entity.linearity;
  // u32 truncation of the ms timestamp — wraps every ~49 days, but the
  // authoritative value lives on the GameEntity so it's fine as an index.
  CellBacked.timestamp[eid] = Number(entity.timestamp & 0xffffffffn);

  // Owner (truncated shortId)
  addComponent(world.ecs, eid, Owner);
  Owner.shortId[eid] = shortOwnerId(entity.ownerId);

  // StateTag (u16 hash of state string)
  addComponent(world.ecs, eid, StateTag);
  StateTag.hash[eid] = hashStateTag(entity.state);

  // Optional hot components — only if metadata mentions them
  const pos = entity.metadata.position as
    | { x?: number; y?: number; z?: number }
    | undefined;
  if (pos && typeof pos === 'object') {
    addComponent(world.ecs, eid, Position);
    Position.x[eid] = Number(pos.x ?? 0);
    Position.y[eid] = Number(pos.y ?? 0);
    Position.z[eid] = Number(pos.z ?? 0);
  }

  const vel = entity.metadata.velocity as
    | { dx?: number; dy?: number; dz?: number }
    | undefined;
  if (vel && typeof vel === 'object') {
    addComponent(world.ecs, eid, Velocity);
    Velocity.dx[eid] = Number(vel.dx ?? 0);
    Velocity.dy[eid] = Number(vel.dy ?? 0);
    Velocity.dz[eid] = Number(vel.dz ?? 0);
  }

  const hp = entity.metadata.health as
    | { current?: number; max?: number }
    | undefined;
  if (hp && typeof hp === 'object') {
    addComponent(world.ecs, eid, Health);
    Health.current[eid] = Number(hp.current ?? 0);
    Health.max[eid] = Number(hp.max ?? 0);
  }

  return eid;
}

// ── Promotion path: tier-1 → tier-2 ────────────────────────────────────────

/**
 * Collect the metadata updates that a bitECS entity would write back to its
 * cell. Pure function, no side effects.
 *
 * Only emits keys for components that are actually present on the eid.
 */
function collectMetadataUpdates(
  world: GameWorld,
  eid: number,
): { metadata: Record<string, unknown>; state?: string } {
  const metadata: Record<string, unknown> = {};

  if (hasComponent(world.ecs, eid, Position)) {
    metadata.position = {
      x: Position.x[eid],
      y: Position.y[eid],
      z: Position.z[eid],
    };
  }

  if (hasComponent(world.ecs, eid, Velocity)) {
    metadata.velocity = {
      dx: Velocity.dx[eid],
      dy: Velocity.dy[eid],
      dz: Velocity.dz[eid],
    };
  }

  if (hasComponent(world.ecs, eid, Health)) {
    metadata.health = {
      current: Health.current[eid],
      max: Health.max[eid],
    };
  }

  // StateTag is a hash; we can't recover the string from it. The state
  // string is authoritative on the tier-2 GameEntity, so we don't touch
  // `state` here unless a dedicated state-transition system has already
  // updated the sidecar entity (handled by the trade-system example).
  return { metadata };
}

/**
 * Promote every dirty entity back to its cell. This is the tier-boundary
 * crossing — it calls `engine.updateEntity` for each dirty eid, which
 * allocates a new cell with an updated prevStateHash chain.
 *
 * The function drains the dirty queue, but it does NOT remove the `Dirty`
 * component — that's the caller's responsibility after they've decided the
 * promotion was successful.
 *
 * Returns a summary of what was promoted (useful for logging and tests).
 */
export function syncToCell(
  world: GameWorld,
  engine: GameCellEngine,
): { promoted: number; skipped: number; failed: number } {
  let promoted = 0;
  let skipped = 0;
  let failed = 0;

  const eids = drainDirty(world);

  for (const eid of eids) {
    const current = getCellBackedEntity(world, eid);
    if (!current) {
      // Not cell-backed — nothing to promote. Hot-loop-only entity.
      skipped++;
      continue;
    }

    try {
      const updates = collectMetadataUpdates(world, eid);
      const next = engine.updateEntity(current, updates);
      setCellBackedEntity(world, eid, next);

      // Refresh CellBacked.timestamp to match the new cell
      CellBacked.timestamp[eid] = Number(next.timestamp & 0xffffffffn);

      // Clear the Dirty tag now that we've committed
      if (hasComponent(world.ecs, eid, Dirty)) {
        removeComponent(world.ecs, eid, Dirty);
      }

      promoted++;
    } catch {
      failed++;
    }
  }

  return { promoted, skipped, failed };
}

```
