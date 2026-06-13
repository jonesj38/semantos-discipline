---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/adapters/multicast/peer-manager.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.064663+00:00
---

# runtime/session-protocol/src/adapters/multicast/peer-manager.ts

```ts
/**
 * peer-manager — pure registry of peers observed on the multicast group.
 *
 * Tracks `bca → MulticastPeerInfo` along with the addresses they were
 * heard on. The orchestrator owns the lifecycle (timer-driven eviction,
 * heartbeat-sink fan-out); this module is data + reducers, no I/O.
 *
 * Per the prompt-38 spec: "peer registry; tracks connected peers,
 * addresses, last-seen; pure struct + functions."
 *
 * Cross-references:
 *   docs/prd/refactor-monoliths/38-multicast-adapter-split.md
 *   ./types.ts — `MulticastPeerInfo` definition
 */

import type { MulticastPeerInfo } from "./types.js";

/**
 * Pure registry of peers. Keyed on BCA (the cryptographic identity)
 * because the wire-level `nodeIdShort` collides for ~1-in-2^16 pairs.
 */
export interface PeerStore {
  byBca: Map<string, MulticastPeerInfo>;
}

export function createPeerStore(): PeerStore {
  return { byBca: new Map() };
}

/**
 * Insert or update a peer record. Returns the updated record so callers
 * can chain into observer notifications without re-reading the map.
 */
export function upsertPeer(
  store: PeerStore,
  peer: MulticastPeerInfo,
): MulticastPeerInfo {
  store.byBca.set(peer.bca, peer);
  return peer;
}

/** Lookup by BCA. Returns `undefined` if not seen. */
export function getPeerByBca(
  store: PeerStore,
  bca: string,
): MulticastPeerInfo | undefined {
  return store.byBca.get(bca);
}

/**
 * Lookup by source address (used by `resolveBCA` callers that hold a
 * `RemoteInfo.address` rather than a BCA). Returns the first peer whose
 * `address` matches; `undefined` when no peer registered that address.
 */
export function getPeerByAddress(
  store: PeerStore,
  address: string,
): MulticastPeerInfo | undefined {
  for (const peer of store.byBca.values()) {
    if (peer.address === address) return peer;
  }
  // Hackathon fallback: legacy callers passed the BCA in as `address`.
  return store.byBca.get(address);
}

/** Snapshot of all peers (defensive copy — callers may iterate freely). */
export function listPeers(store: PeerStore): MulticastPeerInfo[] {
  return Array.from(store.byBca.values());
}

/** Total peer count. */
export function peerCount(store: PeerStore): number {
  return store.byBca.size;
}

/**
 * Evict peers whose `lastSeen` is older than `now - staleTimeoutMs`.
 * Returns the evicted records so the caller can fire `onPeerOffline`
 * callbacks without poking back into the store.
 */
export function evictStalePeers(
  store: PeerStore,
  now: number,
  staleTimeoutMs: number,
): MulticastPeerInfo[] {
  const evicted: MulticastPeerInfo[] = [];
  for (const [bca, peer] of store.byBca) {
    if (now - peer.lastSeen > staleTimeoutMs) {
      store.byBca.delete(bca);
      evicted.push(peer);
    }
  }
  return evicted;
}

/** Drop every peer; used by `MulticastAdapter.clear()`. */
export function clearPeers(store: PeerStore): void {
  store.byBca.clear();
}

```
