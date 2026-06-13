---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/game-sdk/src/engine/reducer-base.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.528005+00:00
---

# packages/game-sdk/src/engine/reducer-base.ts

```ts
/**
 * Generic reducer base — the pure-FSM core every downstream game
 * inherits.
 *
 * `makeEngineSlice(reducer, initial)` returns an `EngineSlice` that
 * holds an atom-backed state value, accepts actions through
 * `dispatch(action)`, and notifies subscribers on change. Reducers
 * are pure: `(state, action) → state`. Side-effects belong in the
 * effect layer (see `engine-template.ts`).
 *
 * This is the prompt-15 "channelReducer" shape generalized so
 * dungeon, chess, risk, go, and poker can all share the same core.
 */

import { atom, get, set, subscribe, type Atom } from '@semantos/state';

export type Reducer<S, A> = (state: S, action: A) => S;

export interface EngineSlice<S, A> {
  /** Read the current state synchronously. */
  state(): S;
  /** Push an action through the reducer. */
  dispatch(action: A): S;
  /** Subscribe to state changes; returns a `dispose()`. */
  subscribe(fn: (state: S, prev: S) => void): () => void;
  /** The underlying atom — exposed for advanced consumers (selectors). */
  stateAtom: Atom<S>;
  /** Reset the slice to its initial value. */
  reset(): void;
}

export function makeEngineSlice<S, A>(
  reducer: Reducer<S, A>,
  initial: S,
): EngineSlice<S, A> {
  const stateAtom = atom<S>(initial);
  return {
    state: () => get(stateAtom),
    dispatch: (action) => {
      const prev = get(stateAtom);
      const next = reducer(prev, action);
      if (!Object.is(prev, next)) set(stateAtom, next);
      return next;
    },
    subscribe: (fn) => {
      let prev = get(stateAtom);
      return subscribe(stateAtom, (next) => {
        const before = prev;
        prev = next;
        fn(next, before);
      });
    },
    stateAtom,
    reset: () => set(stateAtom, initial),
  };
}

/**
 * Compose multiple reducers under named keys into a combined
 * reducer. Convenience for downstream games that split their
 * state by concern (board / players / clock / etc.).
 */
export function combineReducers<S extends Record<string, unknown>, A>(
  reducers: { [K in keyof S]: Reducer<S[K], A> },
): Reducer<S, A> {
  const keys = Object.keys(reducers) as (keyof S)[];
  return (state, action) => {
    const next = { ...state } as S;
    let changed = false;
    for (const key of keys) {
      const slice = state[key];
      const updated = reducers[key](slice, action);
      if (!Object.is(slice, updated)) {
        (next as Record<keyof S, unknown>)[key] = updated;
        changed = true;
      }
    }
    return changed ? next : state;
  };
}

```
