---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/adapters/multicast/subscription-store.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.067338+00:00
---

# runtime/session-protocol/src/adapters/multicast/subscription-store.ts

```ts
/**
 * subscription-store — pure registry of `{ topic → Subscriber[] }`.
 *
 * Per the prompt-38 spec: "{ sessionId → Subscriber[] }; add/remove/notify."
 * In multicast-land the keying is by `topic` (which `topicToGroup` then
 * maps to a multicast group); the contract is identical.
 *
 * The orchestrator owns side-effecting concerns (group join/leave,
 * `onAnyCell` global callbacks, duplicate-path observers); this module
 * only manages per-topic subscriber sets.
 *
 * Cross-references:
 *   docs/prd/refactor-monoliths/38-multicast-adapter-split.md
 *   ../multicast-adapter.ts (legacy) — the source for these semantics
 */

import type { NetworkEvent } from "@semantos/protocol-types/network";

export type Subscriber = (event: NetworkEvent) => void;

export interface SubscriptionStore {
  byTopic: Map<string, Set<Subscriber>>;
}

export function createSubscriptionStore(): SubscriptionStore {
  return { byTopic: new Map() };
}

/**
 * Add a subscriber for a topic. Returns whether this is the first
 * subscriber on this topic — the orchestrator uses that to decide
 * whether it needs to `addMembership` on the underlying transport.
 */
export function addSubscriber(
  store: SubscriptionStore,
  topic: string,
  cb: Subscriber,
): { firstForTopic: boolean } {
  let set = store.byTopic.get(topic);
  const firstForTopic = !set;
  if (!set) {
    set = new Set();
    store.byTopic.set(topic, set);
  }
  set.add(cb);
  return { firstForTopic };
}

/**
 * Remove a subscriber from a topic. Returns whether the topic has any
 * remaining subscribers — the orchestrator uses that to decide whether
 * it should `dropMembership` on the underlying transport.
 */
export function removeSubscriber(
  store: SubscriptionStore,
  topic: string,
  cb: Subscriber,
): { remainingForTopic: number; topicEmpty: boolean } {
  const set = store.byTopic.get(topic);
  if (!set) return { remainingForTopic: 0, topicEmpty: true };
  set.delete(cb);
  if (set.size === 0) {
    store.byTopic.delete(topic);
    return { remainingForTopic: 0, topicEmpty: true };
  }
  return { remainingForTopic: set.size, topicEmpty: false };
}

/** Snapshot of all topics that currently have subscribers. */
export function topicsWithSubscribers(
  store: SubscriptionStore,
): IterableIterator<string> {
  return store.byTopic.keys();
}

/** Notify every subscriber for a topic. Errors are swallowed per-cb. */
export function notify(
  store: SubscriptionStore,
  topic: string,
  event: NetworkEvent,
): void {
  const set = store.byTopic.get(topic);
  if (!set) return;
  for (const cb of set) {
    try {
      cb(event);
    } catch {
      /* isolate observer errors — one bad subscriber must not stall fan-out */
    }
  }
}

/** Drop every subscriber. Used by `MulticastAdapter.clear()`. */
export function clearSubscribers(store: SubscriptionStore): void {
  store.byTopic.clear();
}

```
