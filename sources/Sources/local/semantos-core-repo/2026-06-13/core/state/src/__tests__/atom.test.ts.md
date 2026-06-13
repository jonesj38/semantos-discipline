---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/state/src/__tests__/atom.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.015431+00:00
---

# core/state/src/__tests__/atom.test.ts

```ts
import { describe, test, expect } from "bun:test";
import { atom, get, set, subscribe } from "../index.js";

describe("atom", () => {
  test("initializes with the given value", () => {
    const a = atom(42);
    expect(get(a)).toBe(42);
  });

  test("set updates the stored value", () => {
    const a = atom("a");
    set(a, "b");
    expect(get(a)).toBe("b");
  });

  test("subscribers see each new value", () => {
    const a = atom(0);
    const seen: number[] = [];
    subscribe(a, (v) => seen.push(v));
    set(a, 1);
    set(a, 2);
    set(a, 3);
    expect(seen).toEqual([1, 2, 3]);
  });

  test("setting to the same value via Object.is does not notify", () => {
    const a = atom(1);
    let calls = 0;
    subscribe(a, () => calls++);
    set(a, 1);
    expect(calls).toBe(0);
    set(a, 2);
    expect(calls).toBe(1);
  });

  test("dispose returned by subscribe removes the listener", () => {
    const a = atom(0);
    let calls = 0;
    const dispose = subscribe(a, () => calls++);
    set(a, 1);
    dispose();
    set(a, 2);
    set(a, 3);
    expect(calls).toBe(1);
  });

  test("reference equality: same object reference does not notify", () => {
    const obj = { x: 1 };
    const a = atom(obj);
    let calls = 0;
    subscribe(a, () => calls++);
    set(a, obj);
    expect(calls).toBe(0);
  });
});

```
