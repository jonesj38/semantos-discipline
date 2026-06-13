---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-settlement/src/ecs/paskian-system.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.715618+00:00
---

# archive/apps-settlement/src/ecs/paskian-system.ts

```ts
/**
 * Paskian System — bitECS system that feeds the Paskian learning graph.
 *
 * This is the tier-crossing hook: it sits in the bitECS system pipeline
 * alongside tradeSystem, and fires after every syncToCell pass. Every
 * dirty entity that was promoted back to its cell gets its transition
 * logged as a Paskian interaction.
 *
 * The system follows the same pattern as trade-system.ts:
 *   - Query the hot loop for relevant components
 *   - Cross the tier boundary via the adapter
 *   - Fire-and-forget the learning dynamics
 *
 * Architecture:
 *
 *   bitECS hot loop (per-frame)
 *     ↓ entity mutated, Dirty tag set
 *   syncToCell (tier boundary)
 *     ↓ cell transition committed
 *   paskianSystem (this file)
 *     ↓ interaction logged to PaskianAdapter
 *   PaskianAdapter.interact()
 *     ↓ local propagation, stability check, pruning
 *   PaskianStore (SQLite)
 *     ↓ materialised learning state
 *
 * Cross-references:
 *   game-sdk/ecs/systems/trade-system.ts — same pattern
 *   game-sdk/ecs/bridge.ts               — syncToCell (fires before this)
 *   adapter.ts                           — PaskianAdapter
 */

import { query, hasComponent } from 'bitecs';

import type { GameWorld } from '../../../../packages/game-sdk/src/ecs/world';
import {
  CellBacked,
  StateTag,
  Position,
  Health,
} from '../../../../packages/game-sdk/src/ecs/components';
import { getCellBackedEntity } from '../../../../packages/game-sdk/src/ecs/world';

import type { PaskianAdapter } from '../adapter';
import type { PaskianInteraction } from '../types';

// ── Paskian-aware component (optional, can use existing components) ──

/**
 * Configuration for what kinds of entity changes generate Paskian
 * interactions. This lets the game layer control which state changes
 * are "interesting" to the learning system.
 */
export interface PaskianSystemConfig {
  /**
   * Which entity types (by GameEntityType number) to track.
   * If empty, all entity types are tracked.
   */
  trackedEntityTypes: number[];

  /**
   * Base interaction strength for different kinds of state changes.
   * The system multiplies these by the magnitude of the change.
   */
  strengthWeights: {
    stateChange: number;    // entity changed ECS state
    movement: number;       // entity moved (position changed)
    healthChange: number;   // entity took damage or healed
    creation: number;       // entity was created
    consumption: number;    // entity was consumed
  };
}

export const DEFAULT_PASKIAN_SYSTEM_CONFIG: PaskianSystemConfig = {
  trackedEntityTypes: [],  // track all
  strengthWeights: {
    stateChange: 1.0,
    movement: 0.3,
    healthChange: 0.8,
    creation: 1.5,
    consumption: -1.5,
  },
};

// ── System state (tracks previous frame for delta detection) ─────────

interface EntitySnapshot {
  stateHash: number;
  x: number;
  y: number;
  z: number;
  health: number;
}

const prevSnapshots = new Map<number, EntitySnapshot>();

// ── System function ──────────────────────────────────────────────────

/**
 * The Paskian learning system.
 *
 * Call this once per frame (or once per game tick) AFTER syncToCell.
 * It detects which entities changed and generates PaskianInteraction
 * events for each meaningful change.
 *
 * Returns the number of interactions generated this pass.
 */
export async function paskianSystem(
  world: GameWorld,
  adapter: PaskianAdapter,
  config: PaskianSystemConfig = DEFAULT_PASKIAN_SYSTEM_CONFIG,
): Promise<number> {
  // Query all cell-backed entities
  const candidates = query(world.ecs, [CellBacked]);
  let interactionCount = 0;

  for (const eid of candidates) {
    // Filter by tracked entity types
    if (
      config.trackedEntityTypes.length > 0 &&
      !config.trackedEntityTypes.includes(CellBacked.entityType[eid])
    ) {
      continue;
    }

    const entity = getCellBackedEntity(world, eid);
    if (!entity) continue;

    const cellId = entity.id;
    const prev = prevSnapshots.get(eid);

    // Build current snapshot
    const current: EntitySnapshot = {
      stateHash: hasComponent(world.ecs, eid, StateTag) ? StateTag.hash[eid] : 0,
      x: hasComponent(world.ecs, eid, Position) ? Position.x[eid] : 0,
      y: hasComponent(world.ecs, eid, Position) ? Position.y[eid] : 0,
      z: hasComponent(world.ecs, eid, Position) ? Position.z[eid] : 0,
      health: hasComponent(world.ecs, eid, Health) ? Health.current[eid] : 0,
    };

    if (!prev) {
      // First time seeing this entity — creation event
      const interaction: PaskianInteraction = {
        cellId,
        kind: `paskian.story.entity`,
        strength: config.strengthWeights.creation,
      };
      await adapter.interact(interaction);
      interactionCount++;
      prevSnapshots.set(eid, current);
      continue;
    }

    // Detect changes and generate interactions
    const interactions: PaskianInteraction[] = [];

    // State change
    if (current.stateHash !== prev.stateHash) {
      interactions.push({
        cellId,
        kind: 'paskian.story.moment',
        strength: config.strengthWeights.stateChange,
      });
    }

    // Movement
    const dx = current.x - prev.x;
    const dy = current.y - prev.y;
    const dz = current.z - prev.z;
    const dist = Math.sqrt(dx * dx + dy * dy + dz * dz);
    if (dist > 0.01) {
      interactions.push({
        cellId,
        kind: 'paskian.story.entity',
        strength: config.strengthWeights.movement * Math.min(dist, 10) / 10,
      });
    }

    // Health change
    const healthDelta = current.health - prev.health;
    if (Math.abs(healthDelta) > 0) {
      interactions.push({
        cellId,
        kind: 'paskian.story.entity',
        strength: config.strengthWeights.healthChange * Math.sign(healthDelta),
      });
    }

    // Fire all interactions
    for (const interaction of interactions) {
      await adapter.interact(interaction);
      interactionCount++;
    }

    // Update snapshot
    prevSnapshots.set(eid, current);
  }

  return interactionCount;
}

/**
 * Register an explicit interaction from game code.
 *
 * Use this for events that don't map to ECS component changes:
 * "player talked to NPC", "player explored new area", "player
 * solved puzzle", etc.
 */
export async function paskianInteract(
  adapter: PaskianAdapter,
  cellId: string,
  kind: string,
  strength: number,
  relatedCells?: string[],
): Promise<void> {
  await adapter.interact({
    cellId,
    kind,
    strength,
    relatedCells,
  });
}

/**
 * Clear tracking state for an entity (call on entity removal).
 */
export function paskianForget(eid: number): void {
  prevSnapshots.delete(eid);
}

```
