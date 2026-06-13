---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/adapters/multicast/effect-applier.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.069189+00:00
---

# runtime/session-protocol/src/adapters/multicast/effect-applier.ts

```ts
/**
 * effect-applier — folds `HandlerEffect[]` from the message-handler
 * back into peer / subscription / observer state.
 *
 * Splitting this out keeps the orchestrator's `onIncoming` loop a
 * one-liner and makes the side-effect surface easy to test in
 * isolation: synthesise an effect array, call `applyEffect`, assert
 * against the stores.
 *
 * Cross-references:
 *   docs/prd/refactor-monoliths/38-multicast-adapter-split.md
 *   ./message-handler.ts — producer of `HandlerEffect[]`
 *   ./multicast-adapter.ts — caller binding state to this applier
 */

import type {
  NetworkEvent,
  NetworkResult,
} from "@semantos/protocol-types/network";
import type { RemoteInfo } from "@semantos/protocol-types/adapters/udp-transport";

import type { HeartbeatSink } from "../../types.js";
import type { HandlerEffect } from "./message-handler.js";
import {
  upsertPeer,
  type PeerStore,
} from "./peer-manager.js";
import {
  notify,
  type SubscriptionStore,
} from "./subscription-store.js";
import {
  recordObject,
  type ObjectStore,
} from "./object-store.js";
import type { ObserverList } from "./observers.js";
import type {
  ControlMessage,
  DuplicatePathEvent,
  MulticastPeerInfo,
} from "./types.js";

export interface EffectApplyCtx {
  peers: PeerStore;
  subscribers: SubscriptionStore;
  objects: ObjectStore;
  cellObservers: ObserverList<NetworkEvent>;
  controlObservers: ObserverList<{ msg: ControlMessage; rinfo: RemoteInfo }>;
  duplicatePathObservers: ObserverList<DuplicatePathEvent>;
  heartbeatSink?: HeartbeatSink;
}

/**
 * Dispatch an entire array of effects produced by `handleIncoming`. The
 * orchestrator typically calls this rather than `applyEffect` so the
 * iteration lives here too.
 */
export function applyEffects(
  ctx: EffectApplyCtx,
  effects: readonly HandlerEffect[],
  rinfo: RemoteInfo,
): void {
  for (const eff of effects) applyEffect(ctx, eff, rinfo);
}

export function applyEffect(
  ctx: EffectApplyCtx,
  eff: HandlerEffect,
  rinfo: RemoteInfo,
): void {
  switch (eff.kind) {
    case "peer-heartbeat": {
      const peer = upsertPeer(ctx.peers, eff.peer);
      ctx.heartbeatSink?.onPeerHeartbeatReceived?.({
        bca: peer.bca,
        firstSeen: peer.lastSeen,
        lastSeen: peer.lastSeen,
        metadata: peer.metadata,
      });
      return;
    }
    case "cell-received":
      applyRecord(ctx, eff.result, eff.event.timestamp ?? Date.now());
      notify(ctx.subscribers, eff.topic, eff.event);
      ctx.cellObservers.fire(eff.event);
      return;
    case "control-received":
      ctx.controlObservers.fire({ msg: eff.msg, rinfo });
      return;
    case "drop":
      return;
  }
}

function applyRecord(
  ctx: EffectApplyCtx,
  result: NetworkResult,
  now: number,
): void {
  const conflict = recordObject(ctx.objects, result, now);
  if (conflict) ctx.duplicatePathObservers.fire(conflict);
}


```
