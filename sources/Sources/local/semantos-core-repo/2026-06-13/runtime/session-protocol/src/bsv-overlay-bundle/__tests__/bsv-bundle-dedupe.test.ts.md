---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/bsv-overlay-bundle/__tests__/bsv-bundle-dedupe.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.072724+00:00
---

# runtime/session-protocol/src/bsv-overlay-bundle/__tests__/bsv-bundle-dedupe.test.ts

```ts
/**
 * Unit tests for the observable bundle dedupe set.
 */

import { describe, test, expect } from "bun:test";
import { createBundleDedupe } from "../bsv-bundle-dedupe.js";

describe("createBundleDedupe", () => {
  test("first markSeen returns true and bumps size", () => {
    const d = createBundleDedupe();
    expect(d.size).toBe(0);
    expect(d.markSeen("tx1.0")).toBe(true);
    expect(d.size).toBe(1);
  });

  test("second markSeen of the same outpoint returns false and does not bump size", () => {
    const d = createBundleDedupe();
    d.markSeen("tx1.0");
    expect(d.markSeen("tx1.0")).toBe(false);
    expect(d.size).toBe(1);
  });

  test("snapshot returns all seen outpoints", () => {
    const d = createBundleDedupe();
    d.markSeen("tx1.0");
    d.markSeen("tx2.1");
    d.markSeen("tx3.0");
    expect(d.snapshot().slice().sort()).toEqual(["tx1.0", "tx2.1", "tx3.0"]);
  });

  test("clear empties the set", () => {
    const d = createBundleDedupe();
    d.markSeen("a");
    d.markSeen("b");
    d.clear();
    expect(d.size).toBe(0);
    expect(d.snapshot()).toEqual([]);
    // After clear, an outpoint can be re-added.
    expect(d.markSeen("a")).toBe(true);
  });

  test("subscribe fires once per new outpoint", () => {
    const d = createBundleDedupe();
    const events: string[] = [];
    d.subscribe((e) => events.push(`${e.outpoint}:${e.size}`));
    d.markSeen("a");
    d.markSeen("a"); // duplicate — no event
    d.markSeen("b");
    expect(events).toEqual(["a:1", "b:2"]);
  });

  test("unsubscribe stops events", () => {
    const d = createBundleDedupe();
    let count = 0;
    const off = d.subscribe(() => {
      count++;
    });
    d.markSeen("a");
    off();
    d.markSeen("b");
    expect(count).toBe(1);
  });

  test("a throwing listener does not corrupt dedupe state or block other listeners", () => {
    const d = createBundleDedupe();
    const seen: string[] = [];
    d.subscribe(() => {
      throw new Error("boom");
    });
    d.subscribe((e) => seen.push(e.outpoint));
    d.markSeen("x");
    expect(d.size).toBe(1);
    expect(seen).toEqual(["x"]);
  });
});

```
