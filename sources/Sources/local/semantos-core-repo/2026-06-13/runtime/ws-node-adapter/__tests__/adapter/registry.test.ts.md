---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/ws-node-adapter/__tests__/adapter/registry.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.338485+00:00
---

# runtime/ws-node-adapter/__tests__/adapter/registry.test.ts

```ts
/**
 * adapter/registry.ts — peer + subscriber map unit tests.
 *
 * Pure data structures; no socket, no codec. Covers the bookkeeping
 * the facade relies on.
 */

import { describe, expect, test } from "bun:test";
import {
  PeerRegistry,
  SubscriberRegistry,
} from "../../src/adapter/registry";
import type { WsPeerConnection } from "../../src/ws-peer-connection";

// Minimal stub that satisfies the type — registry never inspects the value.
function fakeConn(label: string): WsPeerConnection {
  return { _label: label } as unknown as WsPeerConnection;
}

describe("PeerRegistry", () => {
  test("set/get/delete round-trip", () => {
    const r = new PeerRegistry();
    const c = fakeConn("alice");
    r.set("bca:alice", c);
    expect(r.get("bca:alice")).toBe(c);
    r.delete("bca:alice");
    expect(r.get("bca:alice")).toBeUndefined();
  });

  test("keys returns inserted bcas", () => {
    const r = new PeerRegistry();
    r.set("bca:alice", fakeConn("alice"));
    r.set("bca:bob", fakeConn("bob"));
    expect(r.keys().sort()).toEqual(["bca:alice", "bca:bob"]);
  });

  test("forEach iterates all values", () => {
    const r = new PeerRegistry();
    r.set("a", fakeConn("a"));
    r.set("b", fakeConn("b"));
    const seen: WsPeerConnection[] = [];
    r.forEach((c) => seen.push(c));
    expect(seen).toHaveLength(2);
  });

  test("size + clear", () => {
    const r = new PeerRegistry();
    r.set("a", fakeConn("a"));
    r.set("b", fakeConn("b"));
    expect(r.size()).toBe(2);
    r.clear();
    expect(r.size()).toBe(0);
    expect(r.keys()).toEqual([]);
  });
});

describe("SubscriberRegistry", () => {
  test("add returns unsubscribe fn that removes the callback", () => {
    const r = new SubscriberRegistry();
    let calls = 0;
    const unsub = r.add("topic-x", () => {
      calls++;
    });
    for (const cb of r.snapshot("topic-x")) cb({} as never);
    expect(calls).toBe(1);
    unsub();
    for (const cb of r.snapshot("topic-x")) cb({} as never);
    expect(calls).toBe(1);
  });

  test("multiple subscribers on the same topic all fire", () => {
    const r = new SubscriberRegistry();
    let a = 0;
    let b = 0;
    r.add("t", () => a++);
    r.add("t", () => b++);
    for (const cb of r.snapshot("t")) cb({} as never);
    expect(a).toBe(1);
    expect(b).toBe(1);
  });

  test("snapshot is safe to mutate during iteration (unsubscribe-during-deliver)", () => {
    const r = new SubscriberRegistry();
    let unsubBHits = 0;
    let unsubB!: () => void;
    r.add("t", () => {
      unsubB();
    });
    unsubB = r.add("t", () => {
      unsubBHits++;
    });
    for (const cb of r.snapshot("t")) cb({} as never);
    // Both fired in this iteration (snapshot semantics) — second
    // iteration would see only the first remaining.
    expect(unsubBHits).toBe(1);
    expect(r.snapshot("t").length).toBe(1);
  });

  test("snapshot returns empty array when no subscribers", () => {
    const r = new SubscriberRegistry();
    expect(r.snapshot("nothing")).toEqual([]);
  });
});

```
