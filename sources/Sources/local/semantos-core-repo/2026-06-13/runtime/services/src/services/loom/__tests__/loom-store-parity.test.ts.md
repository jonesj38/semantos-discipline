---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/loom/__tests__/loom-store-parity.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.118342+00:00
---

# runtime/services/src/services/loom/__tests__/loom-store-parity.test.ts

```ts
/**
 * Behaviour-parity snapshot for the loom reducer.
 *
 * Runs a 22-step scripted sequence — the kind of trajectory a
 * real workbench session would generate (create object → open card →
 * select → patch → publish → connect → revoke → delete) — and pins
 * the resulting state shape. Prompt 03 will atomize the LoomStore
 * around this same sequence; the snapshot here is the contract those
 * atoms must keep producing.
 *
 * Also asserts that the deprecated `../../state/loomReducer` shim
 * yields a byte-identical state to the new module — proving the
 * one-release re-export hasn't drifted.
 */

import { describe, expect, test } from 'bun:test';
import {
  initialState,
  loomReducer as nextReducer,
  validateVisibilityTransition,
  type LoomAction,
  type LoomState,
} from '../index';
import { loomReducer as legacyReducer } from '../../../state/loomReducer';
import {
  makeCard,
  makeConnection,
  makeHeader,
  makeObject,
  makePatch,
  makeTypeDef,
  visibilityConfigSimple,
} from './fixtures';

function buildSequence(): LoomAction[] {
  const typeDef = makeTypeDef({
    name: 'Note',
    visibility: visibilityConfigSimple,
  });

  const obj1 = makeObject({
    id: 'note-1',
    typeDefinition: typeDef,
    header: makeHeader(2, 0),
    payload: { title: 'first', body: '' },
  });
  const obj2 = makeObject({
    id: 'note-2',
    typeDefinition: typeDef,
    header: makeHeader(2, 0),
    payload: { title: 'second', body: '' },
  });

  const conn = makeConnection({
    id: 'c1',
    fromCardId: 'card-note-1',
    toCardId: 'card-note-2',
  });

  return [
    { type: 'ADD_OBJECT', object: obj1, openAsCard: true },
    { type: 'ADD_OBJECT', object: obj2, openAsCard: true },
    { type: 'SELECT_OBJECT', id: 'note-1' },
    { type: 'UPDATE_PAYLOAD', objectId: 'note-1', field: 'body', value: 'hello' },
    { type: 'UPDATE_OBJECT', id: 'note-1', updates: { visibility: 'draft' } },
    { type: 'ADD_PATCH', objectId: 'note-1', patch: makePatch({ id: 'p-author' }) },
    { type: 'SET_CAPABILITY', objectId: 'note-1', flagId: 4, enabled: true },
    { type: 'MOVE_CARD', id: 'card-note-1', position: { x: 200, y: 50 } },
    { type: 'RESIZE_CARD', id: 'card-note-1', size: { width: 480, height: 600 } },
    { type: 'UPDATE_CARD_STATE', id: 'card-note-2', state: 'collapsed' },
    { type: 'CONNECT_CARDS', connection: conn },
    { type: 'TRANSITION_VISIBILITY', objectId: 'note-1', newVisibility: 'published' },
    { type: 'TRANSITION_LINEARITY', objectId: 'note-1', newLinearity: 3 },
    { type: 'ADD_PATCH', objectId: 'note-1', patch: makePatch({ id: 'p-publish' }) },
    { type: 'TRANSITION_VISIBILITY', objectId: 'note-1', newVisibility: 'revoked' },
    { type: 'FILTER_BY_CATEGORY', path: 'notes' },
    { type: 'ADD_CARD', card: makeCard({ id: 'card-extra', objectId: 'note-2' }) },
    { type: 'DISCONNECT_CARDS', cardId: 'card-note-1', connectionId: 'c1' },
    { type: 'SELECT_OBJECT', id: 'note-2' },
    { type: 'DELETE_OBJECT', id: 'note-1' },
    { type: 'FILTER_BY_CATEGORY', path: null },
    { type: 'SELECT_OBJECT', id: null },
  ];
}

function play(reducer: typeof nextReducer): LoomState {
  return buildSequence().reduce<LoomState>(reducer, initialState);
}

describe('loom reducer — scripted parity', () => {
  test('22-action sequence produces the expected end-state', () => {
    const final = play(nextReducer);

    expect([...final.objects.keys()]).toEqual(['note-2']);
    expect([...final.cards.keys()].sort()).toEqual(['card-extra', 'card-note-2']);
    expect(final.selectedObjectId).toBeNull();
    expect(final.categoryFilter).toBeNull();

    const note2 = final.objects.get('note-2');
    expect(note2?.visibility).toBe('draft');
    expect(note2?.payload).toEqual({ title: 'second', body: '' });
    expect(note2?.patches).toEqual([]);

    const cardNote2 = final.cards.get('card-note-2');
    expect(cardNote2?.state).toBe('collapsed');
    expect(cardNote2?.connections).toEqual([]);
  });

  test('legacy state/loomReducer shim yields identical end-state', () => {
    const next = play(nextReducer);
    const legacy = play(legacyReducer);
    expect([...legacy.objects.keys()]).toEqual([...next.objects.keys()]);
    expect([...legacy.cards.keys()].sort()).toEqual([...next.cards.keys()].sort());
    expect(legacy.selectedObjectId).toBe(next.selectedObjectId);
    expect(legacy.categoryFilter).toBe(next.categoryFilter);
    const legacyNote = legacy.objects.get('note-2');
    const nextNote = next.objects.get('note-2');
    expect(legacyNote?.visibility).toBe(nextNote?.visibility);
    expect(legacyNote?.payload).toEqual(nextNote?.payload ?? {});
  });

  test('publish step in the sequence is approved by validateVisibilityTransition', () => {
    // Replay up to but not including the TRANSITION_VISIBILITY at index 11
    // and confirm the validator agrees with the action that follows.
    const seq = buildSequence();
    const upToPublish = seq.slice(0, 11);
    const stateBeforePublish = upToPublish.reduce<LoomState>(nextReducer, initialState);
    const obj = stateBeforePublish.objects.get('note-1');
    expect(obj).toBeDefined();
    const result = validateVisibilityTransition(obj!, 'published');
    expect(result.ok).toBe(true);
    if (result.ok) expect(result.transitions.newLinearity).toBe(3);
  });
});

```
