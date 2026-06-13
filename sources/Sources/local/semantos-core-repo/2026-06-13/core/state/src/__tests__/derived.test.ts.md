---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/state/src/__tests__/derived.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.016572+00:00
---

# core/state/src/__tests__/derived.test.ts

```ts
import { describe, test, expect } from "bun:test";
import { atom, derived, get, set, subscribe } from "../index.js";

describe("derived", () => {
  test("computes initial value from its dependencies", () => {
    const a = atom(2);
    const squared = derived((read) => read(a) * read(a));
    expect(get(squared)).toBe(4);
  });

  test("re-computes when a dependency changes", () => {
    const a = atom(1);
    const b = atom(10);
    const sum = derived((read) => read(a) + read(b));
    expect(get(sum)).toBe(11);
    set(a, 5);
    expect(get(sum)).toBe(15);
    set(b, 20);
    expect(get(sum)).toBe(25);
  });

  test("memoizes: only notifies subscribers when computed value actually changes", () => {
    const a = atom(2);
    const isEven = derived((read) => read(a) % 2 === 0);
    let calls = 0;
    subscribe(isEven, () => calls++);
    set(a, 4);
    set(a, 6);
    expect(calls).toBe(0);
    set(a, 7);
    expect(calls).toBe(1);
  });

  test("cascading derives: chained derived atoms re-fire in order", () => {
    const a = atom(1);
    const b = derived((r) => r(a) + 1);
    const c = derived((r) => r(b) * 10);
    expect(get(c)).toBe(20);
    set(a, 4);
    expect(get(b)).toBe(5);
    expect(get(c)).toBe(50);
  });

  test("dependency tracking is dynamic: re-reads only what the latest run touched", () => {
    const flag = atom(true);
    const left = atom(1);
    const right = atom(100);
    const pick = derived((r) => (r(flag) ? r(left) : r(right)));
    expect(get(pick)).toBe(1);
    set(right, 999);
    expect(get(pick)).toBe(1);
    set(flag, false);
    expect(get(pick)).toBe(999);
    set(left, 42);
    expect(get(pick)).toBe(999);
  });

  test("cycle: derived that writes to one of its own deps throws", () => {
    const a = atom(0);
    expect(() =>
      derived((r) => {
        const v = r(a);
        set(a, v + 1);
        return v;
      }),
    ).toThrow(/Cycle detected/);
  });
});

```
