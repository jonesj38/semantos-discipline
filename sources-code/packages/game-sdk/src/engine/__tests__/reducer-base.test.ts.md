---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/game-sdk/src/engine/__tests__/reducer-base.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.531927+00:00
---

# packages/game-sdk/src/engine/__tests__/reducer-base.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import {
  combineReducers,
  makeEngineSlice,
  type Reducer,
} from '../reducer-base';

interface CounterState {
  value: number;
}

type CounterAction =
  | { type: 'inc' }
  | { type: 'dec' }
  | { type: 'set'; value: number };

const counterReducer: Reducer<CounterState, CounterAction> = (state, action) => {
  switch (action.type) {
    case 'inc':
      return { value: state.value + 1 };
    case 'dec':
      return { value: state.value - 1 };
    case 'set':
      return { value: action.value };
    default:
      return state;
  }
};

describe('makeEngineSlice', () => {
  test('1. holds initial state', () => {
    const slice = makeEngineSlice(counterReducer, { value: 0 });
    expect(slice.state()).toEqual({ value: 0 });
  });

  test('2. dispatch returns next state', () => {
    const slice = makeEngineSlice(counterReducer, { value: 0 });
    expect(slice.dispatch({ type: 'inc' })).toEqual({ value: 1 });
    expect(slice.state()).toEqual({ value: 1 });
  });

  test('3. subscribers fire on change with prev/next', () => {
    const slice = makeEngineSlice(counterReducer, { value: 0 });
    const seen: { next: number; prev: number }[] = [];
    slice.subscribe((next, prev) => seen.push({ next: next.value, prev: prev.value }));
    slice.dispatch({ type: 'inc' });
    slice.dispatch({ type: 'set', value: 42 });
    expect(seen).toEqual([
      { next: 1, prev: 0 },
      { next: 42, prev: 1 },
    ]);
  });

  test('4. dispose stops the subscription', () => {
    const slice = makeEngineSlice(counterReducer, { value: 0 });
    let count = 0;
    const dispose = slice.subscribe(() => count++);
    slice.dispatch({ type: 'inc' });
    dispose();
    slice.dispatch({ type: 'inc' });
    expect(count).toBe(1);
  });

  test('5. reset goes back to initial', () => {
    const slice = makeEngineSlice(counterReducer, { value: 5 });
    slice.dispatch({ type: 'inc' });
    slice.reset();
    expect(slice.state()).toEqual({ value: 5 });
  });
});

describe('combineReducers', () => {
  interface Combined {
    a: CounterState;
    b: CounterState;
  }
  const combined: Reducer<Combined, CounterAction> = combineReducers({
    a: counterReducer,
    b: counterReducer,
  });

  test('6. dispatches an action to every slice', () => {
    const slice = makeEngineSlice(combined, { a: { value: 0 }, b: { value: 0 } });
    slice.dispatch({ type: 'inc' });
    expect(slice.state()).toEqual({ a: { value: 1 }, b: { value: 1 } });
  });

  test('7. preserves identity when no slice changes', () => {
    const initial = { a: { value: 0 }, b: { value: 0 } };
    const slice = makeEngineSlice(combined, initial);
    const before = slice.state();
    slice.dispatch({ type: 'fold' as never });
    expect(slice.state()).toBe(before);
  });
});

```
