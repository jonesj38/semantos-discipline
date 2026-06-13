---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/ws-node-adapter/src/adapter/registry.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.336704+00:00
---

# runtime/ws-node-adapter/src/adapter/registry.ts

```ts
/**
 * adapter/registry.ts — peer + subscriber registries for the facade.
 *
 * Two related but independent maps live here:
 *
 *   - PeerRegistry: peerBca → WsPeerConnection. Only authenticated
 *     entries live here. The facade adds on `onAuthenticated` and
 *     removes on `onClose`.
 *
 *   - SubscriberRegistry: topic → set of callbacks. Mirrors the
 *     MulticastAdapter's pub/sub bookkeeping.
 *
 * Splitting out the registries from the lifecycle/facade keeps "is
 * this peer connected?" and "who's subscribed to topic X?" decisions
 * pure and trivially testable.
 */

import type { NetworkEvent } from "@semantos/protocol-types/network";
import type { WsPeerConnection } from "../ws-peer-connection.js";

// ---------------------------------------------------------------------------
// PeerRegistry
// ---------------------------------------------------------------------------

export class PeerRegistry {
  private readonly map = new Map<string, WsPeerConnection>();

  set(peerBca: string, conn: WsPeerConnection): void {
    this.map.set(peerBca, conn);
  }

  get(peerBca: string): WsPeerConnection | undefined {
    return this.map.get(peerBca);
  }

  delete(peerBca: string): void {
    this.map.delete(peerBca);
  }

  /** All currently-tracked peer BCAs (caller may want only authenticated ones). */
  keys(): readonly string[] {
    return Array.from(this.map.keys());
  }

  /** All currently-tracked connections. */
  values(): readonly WsPeerConnection[] {
    return Array.from(this.map.values());
  }

  /** Apply a function to each connection. */
  forEach(fn: (conn: WsPeerConnection) => void): void {
    for (const c of this.map.values()) fn(c);
  }

  size(): number {
    return this.map.size;
  }

  clear(): void {
    this.map.clear();
  }
}

// ---------------------------------------------------------------------------
// SubscriberRegistry
// ---------------------------------------------------------------------------

export type Subscriber = (event: NetworkEvent) => void;

export class SubscriberRegistry {
  private readonly map = new Map<string, Set<Subscriber>>();

  /** Subscribe a callback to a topic. Returns the unsubscribe fn. */
  add(topic: string, cb: Subscriber): () => void {
    let subs = this.map.get(topic);
    if (!subs) {
      subs = new Set();
      this.map.set(topic, subs);
    }
    subs.add(cb);
    return () => {
      const s = this.map.get(topic);
      if (!s) return;
      s.delete(cb);
      if (s.size === 0) this.map.delete(topic);
    };
  }

  /** Snapshot of subscribers for a topic; safe to mutate during iteration. */
  snapshot(topic: string): readonly Subscriber[] {
    const s = this.map.get(topic);
    if (!s || s.size === 0) return [];
    return Array.from(s);
  }
}

```
