---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/state/src/__tests__/port.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.016845+00:00
---

# core/state/src/__tests__/port.test.ts

```ts
import { describe, test, expect, mock } from "bun:test";
import { port, PortUnboundError } from "../index.js";

interface Clock {
  now(): number;
}

describe("port", () => {
  test("unbound get throws PortUnboundError with portName", () => {
    const clockPort = port<Clock>("Clock");
    let err: unknown;
    try {
      clockPort.get();
    } catch (e) {
      err = e;
    }
    expect(err).toBeInstanceOf(PortUnboundError);
    expect((err as PortUnboundError).portName).toBe("Clock");
    expect((err as Error).message).toContain("Clock");
  });

  test("bind then get returns the impl", () => {
    const clockPort = port<Clock>("Clock");
    const impl: Clock = { now: () => 42 };
    clockPort.bind(impl);
    expect(clockPort.get()).toBe(impl);
    expect(clockPort.get().now()).toBe(42);
  });

  test("unbind resets the port", () => {
    const p = port<Clock>("Clock");
    p.bind({ now: () => 0 });
    expect(p.isBound()).toBe(true);
    p.unbind();
    expect(p.isBound()).toBe(false);
    expect(() => p.get()).toThrow(PortUnboundError);
  });

  test("re-binding warns but replaces the impl", () => {
    const warn = mock(() => {});
    const original = console.warn;
    console.warn = warn;
    try {
      const p = port<Clock>("Clock");
      const a: Clock = { now: () => 1 };
      const b: Clock = { now: () => 2 };
      p.bind(a);
      p.bind(b);
      expect(p.get()).toBe(b);
      expect(warn).toHaveBeenCalledTimes(1);
    } finally {
      console.warn = original;
    }
  });

  test("isBound reflects state across bind/unbind cycles", () => {
    const p = port<Clock>("Clock");
    expect(p.isBound()).toBe(false);
    p.bind({ now: () => 0 });
    expect(p.isBound()).toBe(true);
    p.unbind();
    expect(p.isBound()).toBe(false);
    p.bind({ now: () => 1 });
    expect(p.isBound()).toBe(true);
  });
});

```
