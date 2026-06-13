---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/transfer-rendezvous.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.053307+00:00
---

# runtime/session-protocol/src/swarm/transfer-rendezvous.ts

```ts
/**
 * transfer-rendezvous — the on-chain reference IS the rendezvous.
 *
 * Derives a deterministic IPv6 multicast group from a 32-byte reference (the
 * manifest's anchor txid, or — before anchoring — the infohash itself), reusing
 * the shard-proxy's BRC-12 group derivation (ShardFrame). This unifies discovery
 * and transport: a peer that knows the content reference can compute the exact
 * IPv6 group to join, with no tracker round-trip — the "type-path = multicast
 * group" idea, made concrete and IPv6-native.
 *
 * Scope note: the multi-torrent SwarmClient multiplexes all torrents over ONE
 * shared socket/group and self-filters by infohash, so per-content groups are
 * an OPT-IN for dedicated single-stream transfers (e.g. brain-to-brain sync) or
 * chosen at transport-construction time by the daemon. This module is the pure
 * derivation; binding a socket to the group is the caller's choice.
 */

import { fromHex, ShardFrame, MULTICAST_SCOPE, type MulticastScope } from '@semantos/protocol-types';

export interface RendezvousOptions {
  /** Group space = 2^shardBits. Default 8 (256 switch-friendly groups). 1–24. */
  shardBits?: number;
  /** Multicast scope. Default 'link' (ff02::/16, LAN). */
  scope?: MulticastScope;
  /** 10-byte base for the IPv6 group middle bytes. Default zeros. */
  base?: Uint8Array;
}

export interface Rendezvous {
  /** IPv6 multicast group string, e.g. "ff02:0:0:0:0:0:0:6e". */
  group: string;
  /** The shard group index the reference maps to. */
  shardIndex: number;
}

function formatIPv6(addr: Uint8Array): string {
  const groups: string[] = [];
  for (let i = 0; i < 16; i += 2) groups.push(((addr[i] << 8) | addr[i + 1]).toString(16));
  return groups.join(':');
}

/** Derive an IPv6 multicast group from any 32-byte reference (txid or infohash). */
export function multicastGroupForRef(ref32: Uint8Array, opts: RendezvousOptions = {}): Rendezvous {
  if (ref32.length < 4) throw new Error(`reference must be ≥4 bytes, got ${ref32.length}`);
  const shardBits = opts.shardBits ?? 8;
  const scope = MULTICAST_SCOPE[opts.scope ?? 'link'];
  const shardIndex = ShardFrame.shardIndex(ref32, shardBits);
  const addr = ShardFrame.multicastAddr(shardIndex, scope, opts.base ?? new Uint8Array(10));
  return { group: formatIPv6(addr), shardIndex };
}

/** Group for an infohash (known immediately, pre-anchor). */
export function multicastGroupForInfohash(infohashHex: string, opts?: RendezvousOptions): Rendezvous {
  return multicastGroupForRef(fromHex(infohashHex), opts);
}

/**
 * Group for an anchor txid. Display-order txid is reversed vs the internal byte
 * order ShardFrame expects, so we reverse before deriving — matching the shard
 * proxy's on-the-wire txid handling.
 */
export function multicastGroupForTxid(txidHex: string, opts?: RendezvousOptions): Rendezvous {
  return multicastGroupForRef(fromHex(txidHex).reverse(), opts);
}

```
