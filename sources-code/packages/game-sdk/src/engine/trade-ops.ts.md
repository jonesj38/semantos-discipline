---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/game-sdk/src/engine/trade-ops.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.525397+00:00
---

# packages/game-sdk/src/engine/trade-ops.ts

```ts
/**
 * Atomic two-party trade — extracted from `GameCellEngine`.
 *
 * Snapshot-and-swap semantics: validate everything first, then
 * commit both halves. RELEVANT entities cannot be traded.
 */

import { LINEARITY } from '../../../../core/cell-ops/src/typeHashRegistry';
import type { StorageAdapter } from '../../../../core/protocol-types/src/storage';
import type { TradeProposal, TradeResult } from '../types';

import { hexEncode, rewriteOwnerId } from './engine-utils';
import { getEntity } from './entity-ops';

export function executeTrade(
  storage: StorageAdapter,
  proposal: TradeProposal,
): TradeResult {
  const { partyA, partyB } = proposal;

  const aCheck = validateOffer(partyA);
  if (!aCheck.ok) return { success: false, error: aCheck.error };
  const bCheck = validateOffer(partyB);
  if (!bCheck.ok) return { success: false, error: bCheck.error };

  // Snapshot-and-swap: clone both Maps so a mid-trade error doesn't
  // leak partial mutation onto either party.
  const aSlots = new Map(partyA.inventory.slots);
  const bSlots = new Map(partyB.inventory.slots);
  const aHex = hexEncode(partyA.inventory.ownerId);
  const bHex = hexEncode(partyB.inventory.ownerId);

  for (const slot of partyA.offer.slots) {
    const cell = aSlots.get(slot)!;
    const newCell = rewriteOwnerId(cell, partyB.inventory.ownerId);
    aSlots.delete(slot);
    bSlots.set(slot, newCell);
    storage.delete(`inventories/${aHex}/${slot}.cell`);
    storage.write(`inventories/${bHex}/${slot}.cell`, newCell);
  }
  for (const slot of partyB.offer.slots) {
    const cell = bSlots.get(slot)!;
    const newCell = rewriteOwnerId(cell, partyA.inventory.ownerId);
    bSlots.delete(slot);
    aSlots.set(slot, newCell);
    storage.delete(`inventories/${bHex}/${slot}.cell`);
    storage.write(`inventories/${aHex}/${slot}.cell`, newCell);
  }

  return {
    success: true,
    updatedA: { ownerId: partyA.inventory.ownerId, slots: aSlots },
    updatedB: { ownerId: partyB.inventory.ownerId, slots: bSlots },
  };
}

function validateOffer(party: TradeProposal['partyA']):
  | { ok: true }
  | { ok: false; error: string } {
  for (const slot of party.offer.slots) {
    if (!party.inventory.slots.has(slot)) {
      return { ok: false, error: `Party does not own slot '${slot}'` };
    }
  }
  for (const slot of party.offer.slots) {
    const entity = getEntity(party.inventory.slots.get(slot)!);
    if (entity.linearity === LINEARITY.RELEVANT) {
      return { ok: false, error: `Cannot trade RELEVANT entity in slot '${slot}'` };
    }
  }
  return { ok: true };
}

```
