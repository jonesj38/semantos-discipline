---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/state/src/__tests__/slice.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.015990+00:00
---

# core/state/src/__tests__/slice.test.ts

```ts
import { describe, test, expect } from "bun:test";
import { derived, effect, get, slice, subscribe } from "../index.js";

type CounterAction = { type: "inc" } | { type: "dec" } | { type: "set"; value: number };

function counterReducer(state: number, action: CounterAction): number {
  switch (action.type) {
    case "inc":
      return state + 1;
    case "dec":
      return state - 1;
    case "set":
      return action.value;
  }
}

describe("slice", () => {
  test("stateAtom holds the initial value", () => {
    const s = slice({ reducer: counterReducer, initial: 0 });
    expect(get(s.stateAtom)).toBe(0);
  });

  test("dispatch updates stateAtom via the reducer", () => {
    const s = slice({ reducer: counterReducer, initial: 0 });
    s.dispatch({ type: "inc" });
    s.dispatch({ type: "inc" });
    s.dispatch({ type: "inc" });
    s.dispatch({ type: "dec" });
    expect(get(s.stateAtom)).toBe(2);
  });

  test("subscribers on the state atom see each transition", () => {
    const s = slice({ reducer: counterReducer, initial: 5 });
    const seen: number[] = [];
    subscribe(s.stateAtom, (v) => seen.push(v));
    s.dispatch({ type: "set", value: 10 });
    s.dispatch({ type: "dec" });
    expect(seen).toEqual([10, 9]);
  });

  test("reducer is pure: same input yields same output, state is not mutated in place", () => {
    type S = { count: number };
    type A = { type: "inc" };
    const reducer = (state: S, _action: A): S => ({ count: state.count + 1 });
    const s = slice<S, A>({ reducer, initial: { count: 0 } });
    const before = get(s.stateAtom);
    s.dispatch({ type: "inc" });
    const after = get(s.stateAtom);
    expect(before).not.toBe(after);
    expect(before.count).toBe(0);
    expect(after.count).toBe(1);
  });

  test("state atom is composable with derived", () => {
    const s = slice({ reducer: counterReducer, initial: 0 });
    const doubled = derived((r) => r(s.stateAtom) * 2);
    expect(get(doubled)).toBe(0);
    s.dispatch({ type: "inc" });
    s.dispatch({ type: "inc" });
    expect(get(doubled)).toBe(4);
  });

  test("state atom is composable with effect", () => {
    const s = slice({ reducer: counterReducer, initial: 0 });
    const seen: number[] = [];
    const dispose = effect((r) => {
      seen.push(r(s.stateAtom));
    });
    s.dispatch({ type: "inc" });
    s.dispatch({ type: "inc" });
    dispose();
    s.dispatch({ type: "inc" });
    expect(seen).toEqual([0, 1, 2]);
  });
});

```
