---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/loom/__tests__/loom-reducer.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.117398+00:00
---

# runtime/services/src/services/loom/__tests__/loom-reducer.test.ts

```ts
/**
 * Reducer transition tests — one or more cases per action type plus
 * structural-sharing invariants. These are the snapshot-style cases the
 * acceptance criteria asks for: ≥30 transitions covering every action.
 */

import { describe, expect, test } from 'bun:test';
import { initialState, loomReducer, type LoomState } from '../index';
import {
  makeCard,
  makeConnection,
  makeHeader,
  makeObject,
  makePatch,
  makeTypeDef,
} from './fixtures';

function withObject(state: LoomState, id: string): LoomState {
  return loomReducer(state, { type: 'ADD_OBJECT', object: makeObject({ id }) });
}

function withCard(state: LoomState, id: string, objectId = 'obj-1'): LoomState {
  return loomReducer(state, { type: 'ADD_CARD', card: makeCard({ id, objectId }) });
}

describe('loomReducer — initialState', () => {
  test('1. starts with empty maps and no selection', () => {
    expect(initialState.objects.size).toBe(0);
    expect(initialState.cards.size).toBe(0);
    expect(initialState.selectedObjectId).toBeNull();
    expect(initialState.selectedCardId).toBeNull();
    expect(initialState.categoryFilter).toBeNull();
  });

  test('2. unknown action type leaves state untouched', () => {
    const next = loomReducer(initialState, { type: 'UNKNOWN' } as never);
    expect(next).toBe(initialState);
  });
});

describe('loomReducer — ADD_OBJECT', () => {
  test('3. adds the object without opening a card by default', () => {
    const obj = makeObject({ id: 'a' });
    const next = loomReducer(initialState, { type: 'ADD_OBJECT', object: obj });
    expect(next.objects.get('a')).toBe(obj);
    expect(next.cards.size).toBe(0);
    expect(next.selectedObjectId).toBeNull();
  });

  test('4. with openAsCard creates a card and selects the object', () => {
    const obj = makeObject({ id: 'a' });
    const next = loomReducer(initialState, { type: 'ADD_OBJECT', object: obj, openAsCard: true });
    expect(next.cards.size).toBe(1);
    const card = next.cards.get('card-a');
    expect(card?.objectId).toBe('a');
    expect(card?.type).toBe('object');
    expect(next.selectedObjectId).toBe('a');
  });

  test('5. structural sharing: previous state map is not mutated', () => {
    const obj = makeObject({ id: 'a' });
    const before = initialState;
    const next = loomReducer(before, { type: 'ADD_OBJECT', object: obj });
    expect(before.objects.size).toBe(0);
    expect(next.objects).not.toBe(before.objects);
  });
});

describe('loomReducer — UPDATE_OBJECT', () => {
  test('6. patches the object and bumps updatedAt', () => {
    const start = withObject(initialState, 'a');
    const next = loomReducer(start, { type: 'UPDATE_OBJECT', id: 'a', updates: { visibility: 'published' } });
    expect(next.objects.get('a')?.visibility).toBe('published');
    expect(next.objects.get('a')?.updatedAt).not.toBe(start.objects.get('a')?.updatedAt);
  });

  test('7. unknown id is a no-op', () => {
    const start = withObject(initialState, 'a');
    const next = loomReducer(start, { type: 'UPDATE_OBJECT', id: 'missing', updates: { visibility: 'revoked' } });
    expect(next).toBe(start);
  });
});

describe('loomReducer — DELETE_OBJECT', () => {
  test('8. removes object and any cards pointing at it', () => {
    let s: LoomState = withObject(initialState, 'a');
    s = withCard(s, 'card-a', 'a');
    s = withCard(s, 'card-other', 'b');
    const next = loomReducer(s, { type: 'DELETE_OBJECT', id: 'a' });
    expect(next.objects.has('a')).toBe(false);
    expect(next.cards.has('card-a')).toBe(false);
    expect(next.cards.has('card-other')).toBe(true);
  });

  test('9. clears selectedObjectId when the deleted object was selected', () => {
    let s: LoomState = withObject(initialState, 'a');
    s = loomReducer(s, { type: 'SELECT_OBJECT', id: 'a' });
    const next = loomReducer(s, { type: 'DELETE_OBJECT', id: 'a' });
    expect(next.selectedObjectId).toBeNull();
  });

  test('10. preserves selectedObjectId when a different object is deleted', () => {
    let s: LoomState = withObject(initialState, 'a');
    s = withObject(s, 'b');
    s = loomReducer(s, { type: 'SELECT_OBJECT', id: 'b' });
    const next = loomReducer(s, { type: 'DELETE_OBJECT', id: 'a' });
    expect(next.selectedObjectId).toBe('b');
  });
});

describe('loomReducer — SELECT_OBJECT', () => {
  test('11. sets the selected id', () => {
    const next = loomReducer(initialState, { type: 'SELECT_OBJECT', id: 'a' });
    expect(next.selectedObjectId).toBe('a');
  });

  test('12. accepts null to deselect', () => {
    const start = loomReducer(initialState, { type: 'SELECT_OBJECT', id: 'a' });
    const next = loomReducer(start, { type: 'SELECT_OBJECT', id: null });
    expect(next.selectedObjectId).toBeNull();
  });
});

describe('loomReducer — ADD_CARD', () => {
  test('13. adds a free-standing card', () => {
    const card = makeCard({ id: 'card-x' });
    const next = loomReducer(initialState, { type: 'ADD_CARD', card });
    expect(next.cards.get('card-x')).toBe(card);
  });
});

describe('loomReducer — MOVE_CARD', () => {
  test('14. moves an existing card', () => {
    const start = withCard(initialState, 'card-1');
    const next = loomReducer(start, { type: 'MOVE_CARD', id: 'card-1', position: { x: 50, y: 60 } });
    expect(next.cards.get('card-1')?.position).toEqual({ x: 50, y: 60 });
  });

  test('15. unknown card id is a no-op', () => {
    const start = withCard(initialState, 'card-1');
    const next = loomReducer(start, { type: 'MOVE_CARD', id: 'missing', position: { x: 1, y: 1 } });
    expect(next).toBe(start);
  });
});

describe('loomReducer — RESIZE_CARD', () => {
  test('16. resizes an existing card', () => {
    const start = withCard(initialState, 'card-1');
    const next = loomReducer(start, { type: 'RESIZE_CARD', id: 'card-1', size: { width: 999, height: 111 } });
    expect(next.cards.get('card-1')?.size).toEqual({ width: 999, height: 111 });
  });

  test('17. unknown card id is a no-op', () => {
    const start = withCard(initialState, 'card-1');
    const next = loomReducer(start, { type: 'RESIZE_CARD', id: 'missing', size: { width: 1, height: 1 } });
    expect(next).toBe(start);
  });
});

describe('loomReducer — CONNECT_CARDS / DISCONNECT_CARDS', () => {
  test('18. CONNECT_CARDS appends a connection on the from-card', () => {
    let s: LoomState = withCard(initialState, 'card-1');
    s = withCard(s, 'card-2', 'obj-2');
    const conn = makeConnection({ id: 'c1', fromCardId: 'card-1', toCardId: 'card-2' });
    const next = loomReducer(s, { type: 'CONNECT_CARDS', connection: conn });
    expect(next.cards.get('card-1')?.connections).toEqual([conn]);
    expect(next.cards.get('card-2')?.connections).toEqual([]);
  });

  test('19. CONNECT_CARDS unknown source is a no-op', () => {
    const start = withCard(initialState, 'card-1');
    const conn = makeConnection({ fromCardId: 'missing' });
    const next = loomReducer(start, { type: 'CONNECT_CARDS', connection: conn });
    expect(next).toBe(start);
  });

  test('20. DISCONNECT_CARDS removes the named connection', () => {
    let s: LoomState = withCard(initialState, 'card-1');
    s = withCard(s, 'card-2', 'obj-2');
    s = loomReducer(s, {
      type: 'CONNECT_CARDS',
      connection: makeConnection({ id: 'c1', fromCardId: 'card-1', toCardId: 'card-2' }),
    });
    const next = loomReducer(s, { type: 'DISCONNECT_CARDS', cardId: 'card-1', connectionId: 'c1' });
    expect(next.cards.get('card-1')?.connections).toEqual([]);
  });

  test('21. DISCONNECT_CARDS unknown card is a no-op', () => {
    const start = withCard(initialState, 'card-1');
    const next = loomReducer(start, { type: 'DISCONNECT_CARDS', cardId: 'missing', connectionId: 'c1' });
    expect(next).toBe(start);
  });
});

describe('loomReducer — UPDATE_CARD_STATE', () => {
  test('22. updates the card visual state', () => {
    const start = withCard(initialState, 'card-1');
    const next = loomReducer(start, { type: 'UPDATE_CARD_STATE', id: 'card-1', state: 'collapsed' });
    expect(next.cards.get('card-1')?.state).toBe('collapsed');
  });

  test('23. unknown card is a no-op', () => {
    const start = withCard(initialState, 'card-1');
    const next = loomReducer(start, { type: 'UPDATE_CARD_STATE', id: 'missing', state: 'maximized' });
    expect(next).toBe(start);
  });
});

describe('loomReducer — SET_CAPABILITY', () => {
  test('24. enabling a capability sets the bit', () => {
    const obj = makeObject({ id: 'a', header: makeHeader(2, 0) });
    const start = loomReducer(initialState, { type: 'ADD_OBJECT', object: obj });
    const next = loomReducer(start, { type: 'SET_CAPABILITY', objectId: 'a', flagId: 3, enabled: true });
    expect(next.objects.get('a')?.header.flags).toBe(1 << 3);
  });

  test('25. disabling a capability clears the bit', () => {
    const obj = makeObject({ id: 'a', header: makeHeader(2, 0b1010) });
    const start = loomReducer(initialState, { type: 'ADD_OBJECT', object: obj });
    const next = loomReducer(start, { type: 'SET_CAPABILITY', objectId: 'a', flagId: 1, enabled: false });
    expect(next.objects.get('a')?.header.flags).toBe(0b1000);
  });

  test('26. unknown object id is a no-op', () => {
    const next = loomReducer(initialState, { type: 'SET_CAPABILITY', objectId: 'missing', flagId: 0, enabled: true });
    expect(next).toBe(initialState);
  });
});

describe('loomReducer — TRANSITION_LINEARITY', () => {
  test('27. updates the linearity field on the header', () => {
    const start = withObject(initialState, 'a');
    const next = loomReducer(start, { type: 'TRANSITION_LINEARITY', objectId: 'a', newLinearity: 3 });
    expect(next.objects.get('a')?.header.linearity).toBe(3);
  });

  test('28. unknown object id is a no-op', () => {
    const next = loomReducer(initialState, { type: 'TRANSITION_LINEARITY', objectId: 'missing', newLinearity: 3 });
    expect(next).toBe(initialState);
  });
});

describe('loomReducer — ADD_PATCH', () => {
  test('29. appends a patch to the object', () => {
    const start = withObject(initialState, 'a');
    const patch = makePatch({ id: 'p1' });
    const next = loomReducer(start, { type: 'ADD_PATCH', objectId: 'a', patch });
    expect(next.objects.get('a')?.patches).toEqual([patch]);
  });

  test('30. unknown object id is a no-op', () => {
    const next = loomReducer(initialState, { type: 'ADD_PATCH', objectId: 'missing', patch: makePatch() });
    expect(next).toBe(initialState);
  });
});

describe('loomReducer — FILTER_BY_CATEGORY', () => {
  test('31. sets the category filter', () => {
    const next = loomReducer(initialState, { type: 'FILTER_BY_CATEGORY', path: 'governance' });
    expect(next.categoryFilter).toBe('governance');
  });

  test('32. accepts null to clear the filter', () => {
    const start = loomReducer(initialState, { type: 'FILTER_BY_CATEGORY', path: 'governance' });
    const next = loomReducer(start, { type: 'FILTER_BY_CATEGORY', path: null });
    expect(next.categoryFilter).toBeNull();
  });
});

describe('loomReducer — UPDATE_PAYLOAD', () => {
  test('33. updates a single payload field, leaving others alone', () => {
    const obj = makeObject({ id: 'a', payload: { title: 'old', count: 1 } });
    const start = loomReducer(initialState, { type: 'ADD_OBJECT', object: obj });
    const next = loomReducer(start, { type: 'UPDATE_PAYLOAD', objectId: 'a', field: 'title', value: 'new' });
    expect(next.objects.get('a')?.payload).toEqual({ title: 'new', count: 1 });
  });

  test('34. unknown object id is a no-op', () => {
    const next = loomReducer(initialState, { type: 'UPDATE_PAYLOAD', objectId: 'missing', field: 'x', value: 1 });
    expect(next).toBe(initialState);
  });
});

describe('loomReducer — TRANSITION_VISIBILITY', () => {
  test('35. updates the visibility field on the object', () => {
    const start = withObject(initialState, 'a');
    const next = loomReducer(start, { type: 'TRANSITION_VISIBILITY', objectId: 'a', newVisibility: 'published' });
    expect(next.objects.get('a')?.visibility).toBe('published');
  });

  test('36. unknown object id is a no-op', () => {
    const next = loomReducer(initialState, { type: 'TRANSITION_VISIBILITY', objectId: 'missing', newVisibility: 'revoked' });
    expect(next).toBe(initialState);
  });
});

describe('loomReducer — purity invariants', () => {
  test('37. reducer never mutates the input state', () => {
    const obj = makeObject({ id: 'a' });
    const before = withObject(initialState, 'a');
    const beforeKeys = [...before.objects.keys()];
    loomReducer(before, { type: 'UPDATE_OBJECT', id: 'a', updates: { visibility: 'published' } });
    loomReducer(before, { type: 'DELETE_OBJECT', id: 'a' });
    loomReducer(before, { type: 'ADD_PATCH', objectId: 'a', patch: makePatch() });
    expect([...before.objects.keys()]).toEqual(beforeKeys);
    expect(before.objects.get('a')?.visibility).toBe('draft');
  });

  test('38. reducer is referentially transparent for fixed inputs', () => {
    const obj = makeObject({ id: 'a', typeDefinition: makeTypeDef({ name: 'X' }) });
    const a = loomReducer(initialState, { type: 'ADD_OBJECT', object: obj });
    const b = loomReducer(initialState, { type: 'ADD_OBJECT', object: obj });
    expect(a.objects.get('a')).toBe(b.objects.get('a'));
  });
});

```
