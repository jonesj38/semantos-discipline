---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/game-sdk/src/engine/inventory-ops.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.525687+00:00
---

# packages/game-sdk/src/engine/inventory-ops.ts

```ts
/**
 * Inventory operations — extracted from `GameCellEngine`.
 *
 * Linearity rules (rejection cases) live here so the cell-engine
 * facade stays focused on lifecycle. The legacy semantics:
 *   - LINEAR  → cannot remove without destination
 *   - AFFINE  → can destroy
 *   - RELEVANT → cannot remove
 *   - DEBUG/FUNGIBLE → free
 */

import { LINEARITY } from '../../../../core/cell-ops/src/typeHashRegistry';
import type { StorageAdapter } from '../../../../core/protocol-types/src/storage';
import { LinearityError, type GameEntity, type Inventory } from '../types';

import { hexEncode, rewriteOwnerId, uint8Eq } from './engine-utils';
import { getEntity } from './entity-ops';

export function createInventory(ownerId: Uint8Array): Inventory {
  return { ownerId, slots: new Map() };
}

export function addToInventory(
  storage: StorageAdapter,
  inventory: Inventory,
  slot: string,
  entity: GameEntity,
): Inventory {
  if (inventory.slots.has(slot)) {
    throw new LinearityError(`Slot '${slot}' is already occupied`);
  }
  if (!uint8Eq(entity.ownerId, inventory.ownerId)) {
    throw new LinearityError('Entity ownerId does not match inventory ownerId');
  }
  const cellCopy = new Uint8Array(entity.cell);
  const newSlots = new Map(inventory.slots);
  newSlots.set(slot, cellCopy);
  storage.write(
    `inventories/${hexEncode(inventory.ownerId)}/${slot}.cell`,
    cellCopy,
  );
  return { ownerId: inventory.ownerId, slots: newSlots };
}

export function removeFromInventory(
  storage: StorageAdapter,
  inventory: Inventory,
  slot: string,
): { inventory: Inventory; removed: Uint8Array } {
  const cell = inventory.slots.get(slot);
  if (!cell) throw new LinearityError(`Slot '${slot}' is empty`);
  const entity = getEntity(cell);
  if (entity.linearity === LINEARITY.LINEAR) {
    throw new LinearityError(
      'Cannot remove LINEAR entity without destination — use transferBetweenInventories',
    );
  }
  if (entity.linearity === LINEARITY.RELEVANT) {
    throw new LinearityError('Cannot remove RELEVANT entity from inventory');
  }
  const newSlots = new Map(inventory.slots);
  newSlots.delete(slot);
  storage.delete(`inventories/${hexEncode(inventory.ownerId)}/${slot}.cell`);
  return {
    inventory: { ownerId: inventory.ownerId, slots: newSlots },
    removed: cell,
  };
}

export function transferBetweenInventories(
  storage: StorageAdapter,
  from: Inventory,
  to: Inventory,
  sourceSlot: string,
  destSlot: string,
): { from: Inventory; to: Inventory } {
  const cell = from.slots.get(sourceSlot);
  if (!cell) throw new LinearityError(`Source slot '${sourceSlot}' is empty`);
  if (to.slots.has(destSlot)) {
    throw new LinearityError(`Destination slot '${destSlot}' is already occupied`);
  }
  const entity = getEntity(cell);
  if (entity.linearity === LINEARITY.RELEVANT) {
    throw new LinearityError('Cannot transfer RELEVANT entity');
  }
  const newCell = rewriteOwnerId(cell, to.ownerId);
  const fromSlots = new Map(from.slots);
  fromSlots.delete(sourceSlot);
  const toSlots = new Map(to.slots);
  toSlots.set(destSlot, newCell);
  const fromHex = hexEncode(from.ownerId);
  const toHex = hexEncode(to.ownerId);
  storage.delete(`inventories/${fromHex}/${sourceSlot}.cell`);
  storage.write(`inventories/${toHex}/${destSlot}.cell`, newCell);
  return {
    from: { ownerId: from.ownerId, slots: fromSlots },
    to: { ownerId: to.ownerId, slots: toSlots },
  };
}

export async function loadInventory(
  storage: StorageAdapter,
  ownerId: Uint8Array,
): Promise<Inventory> {
  const ownerHex = hexEncode(ownerId);
  const keys = await storage.list(`inventories/${ownerHex}`);
  const slots = new Map<string, Uint8Array>();
  for (const key of keys) {
    if (key.endsWith('.cell')) {
      const slot = key.slice(0, -5);
      const data = await storage.read(`inventories/${ownerHex}/${key}`);
      if (data) slots.set(slot, data);
    }
  }
  return { ownerId, slots };
}

```
