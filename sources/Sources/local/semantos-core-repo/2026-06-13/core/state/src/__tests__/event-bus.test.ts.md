---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/state/src/__tests__/event-bus.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.014851+00:00
---

# core/state/src/__tests__/event-bus.test.ts

```ts
import { describe, test, expect } from "bun:test";
import { eventBus } from "../index.js";

describe("eventBus", () => {
  test("emit before any subscriber: event is not received", () => {
    const bus = eventBus<number>();
    bus.emit(1);
    const seen: number[] = [];
    bus.on((e) => seen.push(e));
    expect(seen).toEqual([]);
  });

  test("subscribers receive events emitted after subscription", () => {
    const bus = eventBus<string>();
    const seen: string[] = [];
    bus.on((e) => seen.push(e));
    bus.emit("hello");
    bus.emit("world");
    expect(seen).toEqual(["hello", "world"]);
  });

  test("dispose from on() stops the subscriber", () => {
    const bus = eventBus<number>();
    const seen: number[] = [];
    const dispose = bus.on((e) => seen.push(e));
    bus.emit(1);
    dispose();
    bus.emit(2);
    expect(seen).toEqual([1]);
  });

  test("once fires exactly once", () => {
    const bus = eventBus<number>();
    const seen: number[] = [];
    bus.once((e) => seen.push(e));
    bus.emit(10);
    bus.emit(20);
    bus.emit(30);
    expect(seen).toEqual([10]);
  });

  test("once dispose removes the listener before it fires", () => {
    const bus = eventBus<number>();
    const seen: number[] = [];
    const dispose = bus.once((e) => seen.push(e));
    dispose();
    bus.emit(1);
    expect(seen).toEqual([]);
  });

  test("multiple independent subscribers each receive events", () => {
    const bus = eventBus<number>();
    const a: number[] = [];
    const b: number[] = [];
    bus.on((e) => a.push(e));
    bus.on((e) => b.push(e));
    bus.emit(1);
    bus.emit(2);
    expect(a).toEqual([1, 2]);
    expect(b).toEqual([1, 2]);
  });
});

```
