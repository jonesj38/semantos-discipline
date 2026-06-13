---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/loom/loom-atoms.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.104231+00:00
---

# runtime/services/src/services/loom/loom-atoms.ts

```ts
/**
 * Loom atoms — the singleton state surface for renderer-agnostic consumers.
 *
 * `loomStateAtom` holds the same `LoomState` the LoomStore facade has
 * always managed; `dispatch` is the convenience wrapper that runs an
 * action through the pure reducer and writes the next state.
 *
 * Derived atoms expose ready-made selectors that panels (and the
 * patch-recorder effect) consume without re-deriving state by hand.
 *
 * Note on isolation: shell sessions that need their own state can still
 * `new LoomStore(atom(freshInitialState()))` and pass an independent
 * atom; the `loomStateAtom` exported here is the well-known singleton
 * for in-process loom-react / loom-svelte consumers.
 */

import {
  atom,
  derived,
  get,
  set,
  type Atom,
  type Getter,
} from '@semantos/state';

import { loomReducer } from './loom-reducer';
import {
  initialState,
  type LoomAction,
  type LoomState,
} from './loom-types';
import type { LoomObject, ObjectPatch } from '../../types/loom';

// Re-exports so consumers can `import { LoomState, LoomAction } from
// '.../loom/loom-atoms'` alongside the atom symbols themselves.
export type { LoomAction, LoomState };

/** Build a fresh empty `LoomState` (independent Maps from `initialState`). */
export function freshInitialState(): LoomState {
  return {
    objects: new Map(),
    cards: new Map(),
    selectedObjectId: null,
    selectedCardId: null,
    categoryFilter: null,
  };
}

/** Singleton state atom. Module-level; one per process. */
export const loomStateAtom: Atom<LoomState> = atom<LoomState>(initialState);

/**
 * Dispatch an action against the singleton state atom.
 *
 * For a panel that wants to dispatch into a non-singleton LoomStore,
 * use {@link dispatchTo} with the store's atom instead.
 */
export function dispatch(action: LoomAction): void {
  set(loomStateAtom, loomReducer(get(loomStateAtom), action));
}

/** Variant that targets any caller-provided state atom. */
export function dispatchTo(stateAtom: Atom<LoomState>, action: LoomAction): void {
  set(stateAtom, loomReducer(get(stateAtom), action));
}

// ── Derived selectors ──

/** The object referenced by `selectedObjectId`, or null. */
export const selectedObjectAtom: Atom<LoomObject | null> = derived((read) => {
  const state = read(loomStateAtom);
  if (!state.selectedObjectId) return null;
  return state.objects.get(state.selectedObjectId) ?? null;
});

/**
 * Flat queue of every patch attached to every object, in the order the
 * objects + their patch arrays produce. Recomputes lazily when the
 * objects map changes.
 *
 * Consumers (e.g. the patch-recorder effect) subscribe and watch for
 * additions; they are expected to dedupe by `patch.id`.
 */
export const patchQueueAtom: Atom<ObjectPatch[]> = derived((read) => {
  const objects = read(loomStateAtom).objects;
  const queue: ObjectPatch[] = [];
  for (const obj of objects.values()) {
    for (const patch of obj.patches) queue.push(patch);
  }
  return queue;
});

/**
 * Select objects whose evidence chain attributes them (or their last
 * patch) to a given `hatId`.
 *
 * Builds a fresh derived atom per call and memoizes by id — caller
 * should keep a stable hatId reference for stable identity.
 */
const objectsByHatCache = new Map<string, Atom<LoomObject[]>>();
export function objectsByHatAtom(hatId: string): Atom<LoomObject[]> {
  const cached = objectsByHatCache.get(hatId);
  if (cached) return cached;
  const a: Atom<LoomObject[]> = derived((read: Getter) => {
    const objs = read(loomStateAtom).objects;
    const out: LoomObject[] = [];
    for (const obj of objs.values()) {
      const last = obj.patches[obj.patches.length - 1];
      if (last?.hatId === hatId) out.push(obj);
    }
    return out;
  });
  objectsByHatCache.set(hatId, a);
  return a;
}

/**
 * Select payment-channel objects (typeDefinition.category starting with
 * `metering.channel`) currently in a particular `payload.status`.
 */
const channelsByStatusCache = new Map<string, Atom<LoomObject[]>>();
export function channelsByStatusAtom(status: string): Atom<LoomObject[]> {
  const cached = channelsByStatusCache.get(status);
  if (cached) return cached;
  const a: Atom<LoomObject[]> = derived((read: Getter) => {
    const objs = read(loomStateAtom).objects;
    const out: LoomObject[] = [];
    for (const obj of objs.values()) {
      const cat = obj.typeDefinition.category ?? '';
      if (!cat.startsWith('metering.channel')) continue;
      if ((obj.payload.status as string | undefined) === status) out.push(obj);
    }
    return out;
  });
  channelsByStatusCache.set(status, a);
  return a;
}

/** Test-only: clear the derived caches between cases. */
export function __resetDerivedCachesForTests(): void {
  objectsByHatCache.clear();
  channelsByStatusCache.clear();
}

```
