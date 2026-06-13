---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/adapters/multicast/__tests__/subscription-store.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.069589+00:00
---

# runtime/session-protocol/src/adapters/multicast/__tests__/subscription-store.test.ts

```ts
/**
 * subscription-store unit tests — add / remove / notify / first-empty.
 */

import { describe, expect, test } from "bun:test";
import {
  addSubscriber,
  clearSubscribers,
  createSubscriptionStore,
  notify,
  removeSubscriber,
  topicsWithSubscribers,
} from "../subscription-store";
import type { NetworkEvent } from "@semantos/protocol-types/network";

const ev: NetworkEvent = {
  type: "object_published",
  result: {} as never,
  timestamp: 1,
};

describe("subscription-store", () => {
  test("first subscriber for a topic is flagged", () => {
    const store = createSubscriptionStore();
    expect(addSubscriber(store, "t", () => {}).firstForTopic).toBe(true);
    expect(addSubscriber(store, "t", () => {}).firstForTopic).toBe(false);
  });

  test("notify fans out to all subscribers; survives one throwing", () => {
    const store = createSubscriptionStore();
    const seen: string[] = [];
    addSubscriber(store, "t", () => seen.push("a"));
    addSubscriber(store, "t", () => {
      throw new Error("boom");
    });
    addSubscriber(store, "t", () => seen.push("c"));
    notify(store, "t", ev);
    expect(seen).toEqual(["a", "c"]);
  });

  test("removeSubscriber returns topicEmpty when last subscriber leaves", () => {
    const store = createSubscriptionStore();
    const cb = () => {};
    addSubscriber(store, "t", cb);
    expect(removeSubscriber(store, "t", cb).topicEmpty).toBe(true);
    expect(Array.from(topicsWithSubscribers(store))).toEqual([]);
  });

  test("removeSubscriber leaves topic intact when others remain", () => {
    const store = createSubscriptionStore();
    const a = () => {};
    const b = () => {};
    addSubscriber(store, "t", a);
    addSubscriber(store, "t", b);
    expect(removeSubscriber(store, "t", a).topicEmpty).toBe(false);
    expect(Array.from(topicsWithSubscribers(store))).toEqual(["t"]);
  });

  test("clearSubscribers wipes all topics", () => {
    const store = createSubscriptionStore();
    addSubscriber(store, "x", () => {});
    addSubscriber(store, "y", () => {});
    clearSubscribers(store);
    expect(Array.from(topicsWithSubscribers(store))).toEqual([]);
  });
});

```
