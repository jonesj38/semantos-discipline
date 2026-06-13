---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/game-sdk/src/engine/__tests__/action-dispatcher.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.532224+00:00
---

# packages/game-sdk/src/engine/__tests__/action-dispatcher.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import { makeActionDispatcher } from '../action-dispatcher';
import { makeEngineSlice, type Reducer } from '../reducer-base';

type Action = { type: 'inc' } | { type: 'reset' };
const reducer: Reducer<{ value: number }, Action> = (s, a) =>
  a.type === 'inc' ? { value: s.value + 1 } : { value: 0 };

describe('makeActionDispatcher', () => {
  test('1. dispatch runs the reducer + typed handlers', async () => {
    const slice = makeEngineSlice(reducer, { value: 0 });
    const d = makeActionDispatcher(slice);
    const seen: string[] = [];
    d.on('inc', ({ next }) => {
      seen.push(`inc:${next.value}`);
    });
    await d.dispatch({ type: 'inc' });
    expect(seen).toEqual(['inc:1']);
    expect(d.state()).toEqual({ value: 1 });
  });

  test('2. onAny fires for every action', async () => {
    const slice = makeEngineSlice(reducer, { value: 0 });
    const d = makeActionDispatcher(slice);
    const types: string[] = [];
    d.onAny(({ action }) => {
      types.push(action.type);
    });
    await d.dispatch({ type: 'inc' });
    await d.dispatch({ type: 'reset' });
    expect(types).toEqual(['inc', 'reset']);
  });

  test('3. dispose stops a typed handler', async () => {
    const slice = makeEngineSlice(reducer, { value: 0 });
    const d = makeActionDispatcher(slice);
    let count = 0;
    const dispose = d.on('inc', () => count++);
    await d.dispatch({ type: 'inc' });
    dispose();
    await d.dispatch({ type: 'inc' });
    expect(count).toBe(1);
  });

  test('4. handlers fire after the reducer (next reflects new state)', async () => {
    const slice = makeEngineSlice(reducer, { value: 0 });
    const d = makeActionDispatcher(slice);
    let observed = -1;
    d.on('inc', ({ next, prev }) => {
      observed = next.value;
      expect(prev.value).toBe(0);
    });
    await d.dispatch({ type: 'inc' });
    expect(observed).toBe(1);
  });
});

```
