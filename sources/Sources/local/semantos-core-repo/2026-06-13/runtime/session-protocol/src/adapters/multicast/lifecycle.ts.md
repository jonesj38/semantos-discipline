---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/adapters/multicast/lifecycle.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.063808+00:00
---

# runtime/session-protocol/src/adapters/multicast/lifecycle.ts

```ts
/**
 * lifecycle — heartbeat emit + stale-peer eviction lifecycle helpers.
 *
 * Splitting these out keeps the orchestrator file under the prompt-38
 * LOC budget. The orchestrator still owns the `setInterval` timers
 * (so they live and die with the adapter instance) but the per-tick
 * work is delegated here.
 *
 * Cross-references:
 *   docs/prd/refactor-monoliths/38-multicast-adapter-split.md
 *   ./multicast-adapter.ts — caller that consumes these helpers
 */

import type { ResolvedConfig } from "./config.js";
import {
  buildHeartbeat,
  frameHeartbeatPacket,
} from "./heartbeat-flow.js";
import {
  evictStalePeers,
  peerCount,
  type PeerStore,
} from "./peer-manager.js";
import type { OutboundQueue } from "./outbound-queue.js";
import type { ObserverList } from "./observers.js";
import type { MulticastPeerInfo } from "./types.js";

export interface HeartbeatTickCtx {
  cfg: ResolvedConfig;
  peers: PeerStore;
  outbound: OutboundQueue;
  bca: string;
  nodeIdShort: number;
  startedAt: number;
  running: boolean;
  nextMsgId: () => number;
}

/**
 * One iteration of the heartbeat timer: build + frame the heartbeat,
 * enqueue best-effort, fire the optional `onHeartbeatSent` sink.
 */
export function emitHeartbeatTick(ctx: HeartbeatTickCtx): void {
  if (!ctx.running) return;
  const now = Date.now();
  const packet = frameHeartbeatPacket({
    hb: buildHeartbeat({
      nodeIdShort: ctx.nodeIdShort,
      bca: ctx.bca,
      startedAt: ctx.startedAt,
      peersKnown: peerCount(ctx.peers),
      now,
    }),
    codec: ctx.cfg.codec,
    msgId: ctx.nextMsgId(),
    nodeIdShort: ctx.nodeIdShort,
    now,
    maxPayload: ctx.cfg.maxPayload,
  });
  if (!packet) return;
  ctx.outbound
    .enqueue({
      packet,
      port: ctx.cfg.port,
      address: ctx.cfg.primaryGroup,
      bestEffort: true,
    })
    .catch(() => {});
  ctx.cfg.heartbeatSink?.onHeartbeatSent?.(now);
}

export interface EvictionTickCtx {
  peers: PeerStore;
  staleTimeoutMs: number;
  peerOfflineObservers: ObserverList<MulticastPeerInfo>;
}

/** One iteration of the eviction timer: drop stale peers, fire offline observers. */
export function evictionTick(ctx: EvictionTickCtx): void {
  const evicted = evictStalePeers(ctx.peers, Date.now(), ctx.staleTimeoutMs);
  for (const peer of evicted) ctx.peerOfflineObservers.fire(peer);
}

```
