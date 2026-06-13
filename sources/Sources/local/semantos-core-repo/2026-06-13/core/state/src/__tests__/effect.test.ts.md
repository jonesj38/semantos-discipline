---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/state/src/__tests__/effect.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.015156+00:00
---

# core/state/src/__tests__/effect.test.ts

```ts
import { describe, test, expect } from "bun:test";
import { atom, effect, set } from "../index.js";

describe("effect", () => {
  test("runs synchronously on creation", () => {
    let ran = false;
    effect(() => {
      ran = true;
    });
    expect(ran).toBe(true);
  });

  test("re-runs when a tracked dep changes", () => {
    const a = atom(0);
    const seen: number[] = [];
    effect((r) => {
      seen.push(r(a));
    });
    set(a, 1);
    set(a, 2);
    expect(seen).toEqual([0, 1, 2]);
  });

  test("teardown runs before each re-run", () => {
    const a = atom(0);
    const log: string[] = [];
    effect((r) => {
      const v = r(a);
      log.push(`setup:${v}`);
      return () => log.push(`teardown:${v}`);
    });
    set(a, 1);
    set(a, 2);
    expect(log).toEqual([
      "setup:0",
      "teardown:0",
      "setup:1",
      "teardown:1",
      "setup:2",
    ]);
  });

  test("teardown runs on dispose and effect stops re-running", () => {
    const a = atom(0);
    const log: string[] = [];
    const dispose = effect((r) => {
      const v = r(a);
      log.push(`setup:${v}`);
      return () => log.push(`teardown:${v}`);
    });
    set(a, 1);
    dispose();
    set(a, 2);
    expect(log).toEqual(["setup:0", "teardown:0", "setup:1", "teardown:1"]);
  });

  test("ignores atoms read outside the effect fn (no static deps)", () => {
    const a = atom(0);
    const b = atom(100);
    // Read b before creating the effect so it is not part of the tracked deps.
    const snapshot = b.value;
    const seen: number[] = [];
    effect((r) => {
      seen.push(r(a) + snapshot);
    });
    set(b, 200);
    expect(seen).toEqual([100]);
    set(a, 1);
    expect(seen).toEqual([100, 101]);
  });

  test("dispose is idempotent", () => {
    const a = atom(0);
    let runs = 0;
    const dispose = effect((r) => {
      r(a);
      runs++;
    });
    dispose();
    dispose();
    set(a, 1);
    expect(runs).toBe(1);
  });
});

```
