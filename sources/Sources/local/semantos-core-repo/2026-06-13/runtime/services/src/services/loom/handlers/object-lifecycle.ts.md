---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/loom/handlers/object-lifecycle.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.116250+00:00
---

# runtime/services/src/services/loom/handlers/object-lifecycle.ts

```ts
/**
 * Object-lifecycle handlers — pure(-ish) state transitions for
 * createObjectFromType, openAsCard, consumeObject, and
 * transitionVisibility. Each operates against a caller-supplied state
 * atom so the same code serves the singleton (loomStateAtom) and any
 * isolated LoomStore instance (e.g. shell sessions).
 *
 * No service calls; the only "side effect" is `set(stateAtom, …)`
 * which the dispatch helper performs.
 */

import { get, type Atom } from '@semantos/state';

import { createObject } from '../../../state/objectFactory';
import type { ObjectTypeDefinition } from '../../../config/extensionConfig';
import type { LoomCard, LoomObject, ObjectPatch } from '../../../types/loom';
import { dispatchTo } from '../loom-atoms';
import type { LoomState } from '../loom-types';
import { validateVisibilityTransition } from '../visibility-rules';

/** Per-store card counter (so multiple LoomStore instances don't collide). */
export interface CardCounter {
  next(): number;
}

export function makeCardCounter(): CardCounter {
  let n = 0;
  return { next: () => ++n };
}

/**
 * Create a fresh object from a type definition, dispatch it into the
 * given store, and return its id. When `openAsCard` is true the reducer
 * also creates a card and selects the object.
 */
export function createObjectFromType(
  stateAtom: Atom<LoomState>,
  typeDef: ObjectTypeDefinition,
  ownerIdBytes?: Uint8Array,
  hatId?: string,
  hatCapabilities?: number[],
  openAsCard = true,
): string {
  const obj = createObject(typeDef, ownerIdBytes);

  if (hatId) {
    const creationPatch: ObjectPatch = {
      id: `patch-${Date.now()}-creation`,
      kind: 'action',
      timestamp: Date.now(),
      delta: { action: 'created', typeName: typeDef.name },
      hatId,
      ...(hatCapabilities !== undefined ? { hatCapabilities } : {}),
    };
    obj.patches.push(creationPatch);
  }

  dispatchTo(stateAtom, { type: 'ADD_OBJECT', object: obj, openAsCard });
  return obj.id;
}

/**
 * Open an existing object as a card, deduplicating against any existing
 * card for the same object.
 */
export function openAsCard(
  stateAtom: Atom<LoomState>,
  counter: CardCounter,
  objectId: string,
): void {
  const state = get(stateAtom);
  for (const card of state.cards.values()) {
    if (card.objectId === objectId) {
      dispatchTo(stateAtom, { type: 'SELECT_OBJECT', id: objectId });
      return;
    }
  }
  const n = counter.next();
  const card: LoomCard = {
    id: `card-${n}`,
    type: 'object',
    objectId,
    position: { x: 100 + (n % 5) * 40, y: 100 + (n % 5) * 40 },
    size: { width: 320, height: 400 },
    state: 'expanded',
    connections: [],
  };
  dispatchTo(stateAtom, { type: 'ADD_CARD', card });
  dispatchTo(stateAtom, { type: 'SELECT_OBJECT', id: objectId });
}

/**
 * Consume a LINEAR object — appends a `consumed` action patch and, if
 * the object was LINEAR (linearity=1), bumps it to DEBUG (4) to mark it
 * as spent. Throws on missing object, wrong linearity, or prior
 * consumption.
 */
export function consumeObject(
  stateAtom: Atom<LoomState>,
  objectId: string,
  hatId: string,
  hatCapabilities?: number[],
): void {
  const state = get(stateAtom);
  const obj = state.objects.get(objectId);
  if (!obj) throw new Error(`Object not found: ${objectId}`);

  if (obj.header.linearity !== 1 && obj.header.linearity !== 4) {
    throw new Error(
      `Only LINEAR objects can be consumed (current linearity: ${obj.header.linearity})`,
    );
  }

  const priorConsume = obj.patches.find(
    (p) => p.kind === 'action' && p.delta.action === 'consumed',
  );
  if (priorConsume) {
    const ts = new Date(priorConsume.timestamp).toISOString();
    throw new Error(
      `ALREADY_CONSUMED: object was consumed at ${ts} by hat ${priorConsume.hatId}`,
    );
  }

  const consumePatch: ObjectPatch = {
    id: `patch-${Date.now()}-consume`,
    kind: 'action',
    timestamp: Date.now(),
    delta: {
      action: 'consumed',
      consumedBy: hatId,
      consumedAt: Date.now(),
    },
    hatId,
    ...(hatCapabilities !== undefined ? { hatCapabilities } : {}),
  };
  dispatchTo(stateAtom, { type: 'ADD_PATCH', objectId, patch: consumePatch });

  if (obj.header.linearity === 1) {
    dispatchTo(stateAtom, { type: 'TRANSITION_LINEARITY', objectId, newLinearity: 4 });
  }
}

/**
 * Transition an object's visibility, deferring rule decisions to
 * {@link validateVisibilityTransition}. On a publish that bumps
 * linearity, both actions are dispatched in order.
 */
export function transitionVisibility(
  stateAtom: Atom<LoomState>,
  objectId: string,
  newVisibility: 'draft' | 'published' | 'revoked',
  hatCapabilities?: number[],
): void {
  const obj = get(stateAtom).objects.get(objectId);
  if (!obj) throw new Error(`Object not found: ${objectId}`);

  const result = validateVisibilityTransition(obj, newVisibility, hatCapabilities);
  if (!result.ok) throw new Error(result.reason);

  dispatchTo(stateAtom, { type: 'TRANSITION_VISIBILITY', objectId, newVisibility });
  if (result.transitions.newLinearity !== undefined) {
    dispatchTo(stateAtom, {
      type: 'TRANSITION_LINEARITY',
      objectId,
      newLinearity: result.transitions.newLinearity,
    });
  }
}

/** Convenience: read the currently-selected object from a state atom. */
export function getSelectedObject(stateAtom: Atom<LoomState>): LoomObject | null {
  const state = get(stateAtom);
  if (!state.selectedObjectId) return null;
  return state.objects.get(state.selectedObjectId) ?? null;
}

```
