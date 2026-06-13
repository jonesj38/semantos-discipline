---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/game-sdk/src/ecs/systems/trade-system.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.533908+00:00
---

# packages/game-sdk/src/ecs/systems/trade-system.ts

```ts
/**
 * Trade System — the worked tier-crossing example.
 *
 * This is the canonical pattern for a system that crosses the tier-1 /
 * tier-2 boundary:
 *
 *   1. Query the hot loop for `TradeIntent` components with status=pending.
 *      This is cache-friendly bitECS stuff, runs in microseconds.
 *
 *   2. For each intent: look up both parties in the sidecar (they must be
 *      CellBacked), look up their inventories from the engine, build a
 *      TradeProposal, and hand it to `engine.executeTrade`.
 *
 *   3. On success: write the result back into the sidecar so the next
 *      syncFromCell pass observes the new owners. Mark both entities dirty
 *      so the bridge re-syncs them. Set intent.status = 1 (accepted).
 *
 *   4. On failure: set intent.status = 2 (rejected). The intent component
 *      stays on the entity so UI/logging systems can observe the rejection.
 *
 * Notice what this system does NOT do:
 *
 *   - It doesn't touch cells directly. The tier-2 layer owns all cell
 *     manipulation.
 *   - It doesn't mutate inventories in-place. The engine returns fresh
 *     inventory objects and we rebind them.
 *   - It doesn't know about storage or linearity. Those are the engine's
 *     concern.
 *
 * The system is a 30-line adapter between two models of state — which is
 * exactly what a tier-crossing system should be.
 */

import { query, hasComponent, addComponent } from 'bitecs';

import type { GameCellEngine } from '../../engine';
import type { Inventory, TradeProposal } from '../../types';

import {
  CellBacked,
  TradeIntent,
  Dirty,
} from '../components';

import {
  type GameWorld,
  getCellBackedEntity,
  loadTradeOffer,
  clearTradeOffer,
  markDirty,
} from '../world';

// ── Trade status codes ─────────────────────────────────────────────────────

export const TRADE_PENDING = 0;
export const TRADE_ACCEPTED = 1;
export const TRADE_REJECTED = 2;

// ── System signature ──────────────────────────────────────────────────────

/**
 * A system is just a function. The trade-system takes the world, the engine,
 * and (optionally) a map of ownerHex → Inventory that the caller already
 * loaded. If the inventory map is omitted, we call `engine.loadInventory`
 * for each party — which is async and blocks the hot loop, so don't do that
 * every frame.
 *
 * Returns the number of intents resolved (accepted or rejected) this pass.
 */
export async function tradeSystem(
  world: GameWorld,
  engine: GameCellEngine,
  inventories?: Map<string, Inventory>,
): Promise<number> {
  // Tier-1 query: all entities with a pending trade intent. Microseconds.
  const candidates = query(world.ecs, [TradeIntent]);

  let resolved = 0;

  for (const intentEid of candidates) {
    if (TradeIntent.status[intentEid] !== TRADE_PENDING) continue;

    const aEid = TradeIntent.partyA[intentEid];
    const bEid = TradeIntent.partyB[intentEid];
    const offerKey = TradeIntent.offerKey[intentEid];

    // Tier-1 validation: both parties must be CellBacked to have cells to
    // trade at all. Cheap bitmask check.
    if (
      !hasComponent(world.ecs, aEid, CellBacked) ||
      !hasComponent(world.ecs, bEid, CellBacked)
    ) {
      TradeIntent.status[intentEid] = TRADE_REJECTED;
      resolved++;
      continue;
    }

    const aEntity = getCellBackedEntity(world, aEid);
    const bEntity = getCellBackedEntity(world, bEid);
    if (!aEntity || !bEntity) {
      TradeIntent.status[intentEid] = TRADE_REJECTED;
      resolved++;
      continue;
    }

    const offerSlots = loadTradeOffer(world, offerKey);
    if (!offerSlots) {
      TradeIntent.status[intentEid] = TRADE_REJECTED;
      resolved++;
      continue;
    }

    // Convention: the `offerSlots` list is partyA's offer. For a two-sided
    // trade the caller stashes two offers back-to-back and we pick the next
    // key for partyB. A real game would have a richer intent struct; this
    // keeps the example small.
    const offerSlotsB = loadTradeOffer(world, offerKey + 1) ?? [];

    // Resolve both inventories — caller-supplied or fetched from storage.
    const aHex = hex(aEntity.ownerId);
    const bHex = hex(bEntity.ownerId);
    const aInv =
      inventories?.get(aHex) ?? (await engine.loadInventory(aEntity.ownerId));
    const bInv =
      inventories?.get(bHex) ?? (await engine.loadInventory(bEntity.ownerId));

    // Build the proposal and delegate to tier-2. The engine enforces
    // linearity, persists the swap, and returns fresh inventory objects.
    const proposal: TradeProposal = {
      partyA: { inventory: aInv, offer: { slots: offerSlots } },
      partyB: { inventory: bInv, offer: { slots: offerSlotsB } },
    };
    const result = engine.executeTrade(proposal);

    if (!result.success) {
      TradeIntent.status[intentEid] = TRADE_REJECTED;
      clearTradeOffer(world, offerKey);
      if (offerSlotsB.length > 0) clearTradeOffer(world, offerKey + 1);
      resolved++;
      continue;
    }

    // Rebind inventories if the caller is holding them.
    if (inventories) {
      inventories.set(aHex, result.updatedA!);
      inventories.set(bHex, result.updatedB!);
    }

    // Mark both parties dirty so the bridge re-syncs cell state on the
    // next syncToCell pass. This is essential — their owned entities just
    // got their ownerIds rewritten.
    if (!hasComponent(world.ecs, aEid, Dirty)) {
      addComponent(world.ecs, aEid, Dirty);
    }
    if (!hasComponent(world.ecs, bEid, Dirty)) {
      addComponent(world.ecs, bEid, Dirty);
    }
    markDirty(world, aEid);
    markDirty(world, bEid);

    TradeIntent.status[intentEid] = TRADE_ACCEPTED;
    clearTradeOffer(world, offerKey);
    if (offerSlotsB.length > 0) clearTradeOffer(world, offerKey + 1);
    resolved++;
  }

  return resolved;
}

// ── Helpers ────────────────────────────────────────────────────────────────

function hex(bytes: Uint8Array): string {
  let out = '';
  for (let i = 0; i < bytes.length; i++) {
    out += bytes[i].toString(16).padStart(2, '0');
  }
  return out;
}

```
