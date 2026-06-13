---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/adapters/multicast/__tests__/peer-manager.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.071693+00:00
---

# runtime/session-protocol/src/adapters/multicast/__tests__/peer-manager.test.ts

```ts
/**
 * peer-manager unit tests — add / lookup / eviction / clear.
 */

import { describe, expect, test } from "bun:test";
import {
  clearPeers,
  createPeerStore,
  evictStalePeers,
  getPeerByAddress,
  getPeerByBca,
  listPeers,
  peerCount,
  upsertPeer,
} from "../peer-manager";
import type { MulticastPeerInfo } from "../types";

const peer = (overrides: Partial<MulticastPeerInfo> = {}): MulticastPeerInfo => ({
  nodeIdShort: 0x0001,
  bca: "fe80::1",
  address: "fe80::1",
  lastSeen: 1000,
  uptime: 100,
  ...overrides,
});

describe("peer-manager", () => {
  test("upsertPeer + getPeerByBca round-trip", () => {
    const store = createPeerStore();
    upsertPeer(store, peer());
    expect(getPeerByBca(store, "fe80::1")?.bca).toBe("fe80::1");
    expect(getPeerByBca(store, "fe80::99")).toBeUndefined();
  });

  test("upsertPeer overwrites the existing record for the same BCA", () => {
    const store = createPeerStore();
    upsertPeer(store, peer({ uptime: 100 }));
    upsertPeer(store, peer({ uptime: 250 }));
    expect(peerCount(store)).toBe(1);
    expect(getPeerByBca(store, "fe80::1")?.uptime).toBe(250);
  });

  test("getPeerByAddress finds by RemoteInfo address", () => {
    const store = createPeerStore();
    upsertPeer(store, peer({ bca: "fe80::a", address: "fe80::a" }));
    upsertPeer(store, peer({ bca: "fe80::b", address: "fe80::b" }));
    expect(getPeerByAddress(store, "fe80::a")?.bca).toBe("fe80::a");
    expect(getPeerByAddress(store, "fe80::b")?.bca).toBe("fe80::b");
  });

  test("evictStalePeers drops only stale records and returns them", () => {
    const store = createPeerStore();
    upsertPeer(store, peer({ bca: "fresh", lastSeen: 9_000 }));
    upsertPeer(store, peer({ bca: "stale", lastSeen: 1_000 }));
    const evicted = evictStalePeers(store, /*now*/ 10_000, /*timeout*/ 5_000);
    expect(evicted.map((p) => p.bca)).toEqual(["stale"]);
    expect(peerCount(store)).toBe(1);
    expect(getPeerByBca(store, "fresh")).toBeDefined();
    expect(getPeerByBca(store, "stale")).toBeUndefined();
  });

  test("listPeers + peerCount snapshot the registry", () => {
    const store = createPeerStore();
    upsertPeer(store, peer({ bca: "a" }));
    upsertPeer(store, peer({ bca: "b" }));
    upsertPeer(store, peer({ bca: "c" }));
    expect(peerCount(store)).toBe(3);
    expect(listPeers(store).map((p) => p.bca).sort()).toEqual(["a", "b", "c"]);
  });

  test("clearPeers wipes the store", () => {
    const store = createPeerStore();
    upsertPeer(store, peer({ bca: "a" }));
    clearPeers(store);
    expect(peerCount(store)).toBe(0);
  });
});

```
