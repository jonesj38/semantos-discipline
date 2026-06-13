---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/loom/__tests__/handlers/object-lifecycle.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.120969+00:00
---

# runtime/services/src/services/loom/__tests__/handlers/object-lifecycle.test.ts

```ts
/**
 * object-lifecycle handler tests — exercise createObjectFromType,
 * openAsCard, consumeObject, transitionVisibility, getSelectedObject
 * against an isolated state atom (so the singleton stays untouched).
 */

import { describe, expect, test } from 'bun:test';
import { atom, get, type Atom } from '@semantos/state';

import {
  consumeObject,
  createObjectFromType,
  getSelectedObject,
  makeCardCounter,
  openAsCard,
  transitionVisibility,
} from '../../handlers/object-lifecycle';
import type { LoomState } from '../../loom-types';
import { freshInitialState } from '../../loom-atoms';
import {
  makeHeader,
  makeTypeDef,
  visibilityConfigSimple,
} from '../fixtures';

function freshAtom(): Atom<LoomState> {
  return atom<LoomState>(freshInitialState());
}

describe('createObjectFromType', () => {
  test('1. adds the object to state and returns its id', () => {
    const a = freshAtom();
    const typeDef = makeTypeDef({ name: 'Note' });
    const id = createObjectFromType(a, typeDef, undefined, undefined, undefined, false);
    expect(get(a).objects.has(id)).toBe(true);
  });

  test('2. with openAsCard=true creates a card and selects the object', () => {
    const a = freshAtom();
    const typeDef = makeTypeDef({ name: 'Note' });
    const id = createObjectFromType(a, typeDef, undefined, 'hat-1', [1], true);
    const state = get(a);
    expect(state.selectedObjectId).toBe(id);
    expect(state.cards.size).toBe(1);
  });

  test('3. attaches a creation patch when hatId is provided', () => {
    const a = freshAtom();
    const typeDef = makeTypeDef({ name: 'Thing' });
    const id = createObjectFromType(a, typeDef, undefined, 'hat-7', [3, 5], false);
    const obj = get(a).objects.get(id);
    expect(obj?.patches).toHaveLength(1);
    expect(obj?.patches[0]?.kind).toBe('action');
    expect(obj?.patches[0]?.delta.action).toBe('created');
    expect(obj?.patches[0]?.hatId).toBe('hat-7');
    expect(obj?.patches[0]?.hatCapabilities).toEqual([3, 5]);
  });

  test('4. without hatId leaves patches empty', () => {
    const a = freshAtom();
    const id = createObjectFromType(a, makeTypeDef(), undefined, undefined, undefined, false);
    expect(get(a).objects.get(id)?.patches).toEqual([]);
  });
});

describe('openAsCard', () => {
  test('5. dedupes — a second openAsCard for the same object selects without adding a card', () => {
    const a = freshAtom();
    const counter = makeCardCounter();
    const id = createObjectFromType(a, makeTypeDef(), undefined, undefined, undefined, false);
    openAsCard(a, counter, id);
    const cardsAfter1 = get(a).cards.size;
    openAsCard(a, counter, id);
    expect(get(a).cards.size).toBe(cardsAfter1);
    expect(get(a).selectedObjectId).toBe(id);
  });

  test('6. positions cards by counter index', () => {
    const a = freshAtom();
    const counter = makeCardCounter();
    const id1 = createObjectFromType(a, makeTypeDef(), undefined, undefined, undefined, false);
    const id2 = createObjectFromType(a, makeTypeDef({ name: 'X' }), undefined, undefined, undefined, false);
    openAsCard(a, counter, id1);
    openAsCard(a, counter, id2);
    const cards = [...get(a).cards.values()];
    expect(cards).toHaveLength(2);
    expect(cards[0]!.position).toEqual({ x: 100 + 40, y: 100 + 40 });
    expect(cards[1]!.position).toEqual({ x: 100 + 80, y: 100 + 80 });
  });
});

describe('consumeObject', () => {
  test('7. throws when object is missing', () => {
    const a = freshAtom();
    expect(() => consumeObject(a, 'missing', 'hat-1')).toThrow(/Object not found/);
  });

  test('8. rejects non-LINEAR / non-DEBUG objects', () => {
    const a = freshAtom();
    const id = createObjectFromType(
      a,
      makeTypeDef({ linearity: 'AFFINE' }),
      undefined,
      undefined,
      undefined,
      false,
    );
    expect(() => consumeObject(a, id, 'hat-1')).toThrow(/Only LINEAR objects can be consumed/);
  });

  test('9. on a LINEAR object: appends consume patch and bumps linearity to 4', () => {
    const a = freshAtom();
    const id = createObjectFromType(
      a,
      makeTypeDef({ linearity: 'LINEAR' }),
      undefined,
      undefined,
      undefined,
      false,
    );
    consumeObject(a, id, 'hat-1', [9]);
    const obj = get(a).objects.get(id);
    const last = obj?.patches[obj.patches.length - 1];
    expect(last?.delta.action).toBe('consumed');
    expect(last?.hatId).toBe('hat-1');
    expect(obj?.header.linearity).toBe(4);
  });

  test('10. ALREADY_CONSUMED on second attempt', () => {
    const a = freshAtom();
    const id = createObjectFromType(
      a,
      makeTypeDef({ linearity: 'LINEAR' }),
      undefined,
      undefined,
      undefined,
      false,
    );
    consumeObject(a, id, 'hat-1');
    expect(() => consumeObject(a, id, 'hat-2')).toThrow(/ALREADY_CONSUMED/);
  });
});

describe('transitionVisibility', () => {
  test('11. publishes an AFFINE draft and bumps linearity AFFINE→RELEVANT', () => {
    const a = freshAtom();
    const id = createObjectFromType(
      a,
      makeTypeDef({ linearity: 'AFFINE', visibility: visibilityConfigSimple }),
      undefined,
      undefined,
      undefined,
      false,
    );
    // baseline header sanity
    const before = get(a).objects.get(id)!;
    expect(before.header.linearity).toBe(2);
    transitionVisibility(a, id, 'published');
    const after = get(a).objects.get(id)!;
    expect(after.visibility).toBe('published');
    expect(after.header.linearity).toBe(3);
  });

  test('12. throws when the validator rejects the transition', () => {
    const a = freshAtom();
    const id = createObjectFromType(
      a,
      makeTypeDef({ linearity: 'LINEAR', visibility: visibilityConfigSimple, defaultCapabilities: [] }),
      undefined,
      undefined,
      undefined,
      false,
    );
    // override to LINEAR: makeTypeDef defaults linearity field; createObject reads it
    const obj = get(a).objects.get(id)!;
    obj.header = makeHeader(1);
    expect(() => transitionVisibility(a, id, 'published')).toThrow(/LINEAR objects cannot be published/);
  });

  test('13. throws when object id is unknown', () => {
    const a = freshAtom();
    expect(() => transitionVisibility(a, 'missing', 'published')).toThrow(/Object not found/);
  });
});

describe('getSelectedObject', () => {
  test('14. returns null when nothing is selected', () => {
    const a = freshAtom();
    expect(getSelectedObject(a)).toBeNull();
  });

  test('15. returns the object referenced by selectedObjectId', () => {
    const a = freshAtom();
    const id = createObjectFromType(a, makeTypeDef(), undefined, undefined, undefined, true);
    const obj = getSelectedObject(a);
    expect(obj?.id).toBe(id);
  });
});

```
