---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/loom/__tests__/loom-atoms.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.117082+00:00
---

# runtime/services/src/services/loom/__tests__/loom-atoms.test.ts

```ts
/**
 * loom-atoms tests — covers the singleton state atom + dispatch +
 * derived selectors.
 *
 * Acceptance criterion: three new tests that read state via
 * `get(loomStateAtom)` instead of `loomStore.getState()` and a panel-
 * style subscription test showing a consumer sees updates on dispatch.
 */

import { describe, expect, test } from 'bun:test';
import { atom, get, set, subscribe } from '@semantos/state';

import {
  __resetDerivedCachesForTests,
  channelsByStatusAtom,
  dispatch as dispatchSingleton,
  dispatchTo,
  freshInitialState,
  loomStateAtom,
  objectsByHatAtom,
  patchQueueAtom,
  selectedObjectAtom,
  type LoomState,
} from '../loom-atoms';
import { makeObject, makePatch, makeTypeDef } from './fixtures';

function resetSingleton(): void {
  set(loomStateAtom, freshInitialState());
  __resetDerivedCachesForTests();
}

describe('loomStateAtom + dispatch (singleton)', () => {
  test('1. dispatch through singleton is visible via get(loomStateAtom)', () => {
    resetSingleton();
    const obj = makeObject({ id: 'singleton-1' });
    dispatchSingleton({ type: 'ADD_OBJECT', object: obj });
    expect(get(loomStateAtom).objects.get('singleton-1')).toBe(obj);
    resetSingleton();
  });

  test('2. dispatchTo on an isolated atom does not leak to the singleton', () => {
    resetSingleton();
    const local = atom<LoomState>(freshInitialState());
    dispatchTo(local, { type: 'ADD_OBJECT', object: makeObject({ id: 'local-1' }) });
    expect(get(local).objects.has('local-1')).toBe(true);
    expect(get(loomStateAtom).objects.has('local-1')).toBe(false);
    resetSingleton();
  });

  test('3. panel-style consumer subscribed to the atom sees updates on dispatch', () => {
    resetSingleton();
    const seen: string[] = [];
    const dispose = subscribe(loomStateAtom, (s) => {
      const ids = [...s.objects.keys()];
      if (ids.length > 0) seen.push(ids[ids.length - 1]!);
    });
    dispatchSingleton({ type: 'ADD_OBJECT', object: makeObject({ id: 'p1' }) });
    dispatchSingleton({ type: 'ADD_OBJECT', object: makeObject({ id: 'p2' }) });
    dispose();
    dispatchSingleton({ type: 'ADD_OBJECT', object: makeObject({ id: 'p3' }) });
    expect(seen).toEqual(['p1', 'p2']);
    resetSingleton();
  });
});

describe('selectedObjectAtom', () => {
  test('4. is null when nothing is selected', () => {
    resetSingleton();
    expect(get(selectedObjectAtom)).toBeNull();
    resetSingleton();
  });

  test('5. resolves to the object referenced by selectedObjectId', () => {
    resetSingleton();
    const obj = makeObject({ id: 's-1' });
    dispatchSingleton({ type: 'ADD_OBJECT', object: obj });
    dispatchSingleton({ type: 'SELECT_OBJECT', id: 's-1' });
    expect(get(selectedObjectAtom)?.id).toBe('s-1');
    resetSingleton();
  });
});

describe('patchQueueAtom', () => {
  test('6. flattens patches across all objects in insertion order', () => {
    resetSingleton();
    const a = makeObject({
      id: 'a',
      patches: [makePatch({ id: 'a1' }), makePatch({ id: 'a2' })],
    });
    const b = makeObject({ id: 'b', patches: [makePatch({ id: 'b1' })] });
    dispatchSingleton({ type: 'ADD_OBJECT', object: a });
    dispatchSingleton({ type: 'ADD_OBJECT', object: b });
    const queue = get(patchQueueAtom);
    expect(queue.map((p) => p.id)).toEqual(['a1', 'a2', 'b1']);
    resetSingleton();
  });
});

describe('objectsByHatAtom', () => {
  test('7. selects objects whose latest patch was authored by hatId', () => {
    resetSingleton();
    const obj = makeObject({
      id: 'o-by-hat',
      patches: [makePatch({ id: 'p1', hatId: 'hat-A' })],
    });
    dispatchSingleton({ type: 'ADD_OBJECT', object: obj });
    expect(get(objectsByHatAtom('hat-A')).map((o) => o.id)).toEqual(['o-by-hat']);
    expect(get(objectsByHatAtom('hat-B'))).toEqual([]);
    resetSingleton();
  });

  test('8. caches per-hat atoms so identity is stable across reads', () => {
    resetSingleton();
    const a1 = objectsByHatAtom('stable-hat');
    const a2 = objectsByHatAtom('stable-hat');
    expect(a1).toBe(a2);
    resetSingleton();
  });
});

describe('channelsByStatusAtom', () => {
  test('9. selects channel objects in a given payload.status', () => {
    resetSingleton();
    const channel = makeObject({
      id: 'ch-1',
      typeDefinition: makeTypeDef({ name: 'Channel', category: 'metering.channel.payment' }),
      payload: { status: 'metered' },
    });
    const note = makeObject({
      id: 'n-1',
      typeDefinition: makeTypeDef({ name: 'Note', category: 'governance.dispute' }),
      payload: { status: 'metered' },
    });
    dispatchSingleton({ type: 'ADD_OBJECT', object: channel });
    dispatchSingleton({ type: 'ADD_OBJECT', object: note });
    expect(get(channelsByStatusAtom('metered')).map((o) => o.id)).toEqual(['ch-1']);
    expect(get(channelsByStatusAtom('settled'))).toEqual([]);
    resetSingleton();
  });
});

```
