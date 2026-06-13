---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/adapters/multicast/operations.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.066664+00:00
---

# runtime/session-protocol/src/adapters/multicast/operations.ts

```ts
/**
 * operations — `NetworkAdapter`-method bodies extracted from the
 * `MulticastAdapter` orchestrator.
 *
 * Each function takes the adapter's mutable state by reference (peer
 * store, object store, outbound queue, etc.) and performs the
 * read/write needed for one public method. Pulling these out keeps the
 * orchestrator file under the prompt-38 LOC budget while preserving
 * the single-class public API.
 *
 * Cross-references:
 *   docs/prd/refactor-monoliths/38-multicast-adapter-split.md
 *   ./multicast-adapter.ts — caller binding state to these functions
 */

import type {
  NetworkEvent,
  PublishOptions,
  PublishResult,
  PublishableObject,
} from "@semantos/protocol-types/network";

import type { ResolvedConfig } from "./config.js";
import { DEFAULT_TOPIC } from "./config.js";
import type { GroupMembership } from "./group-membership.js";
import {
  buildLocalResult,
  buildWireBody,
  frameCellPacket,
} from "./publish-flow.js";
import {
  recordObject,
  type ObjectStore,
} from "./object-store.js";
import {
  addSubscriber,
  notify,
  removeSubscriber,
  topicsWithSubscribers,
  type Subscriber,
  type SubscriptionStore,
} from "./subscription-store.js";
import type { OutboundQueue } from "./outbound-queue.js";
import type { ObserverList } from "./observers.js";
import type { ControlMessage, DuplicatePathEvent } from "./types.js";
import { frameControlPacket } from "./control-flow.js";
import {
  MSG_CELL,
  encodeHeader,
  framePacket,
} from "./wire-header.js";

export interface PublishCtx {
  cfg: ResolvedConfig;
  membership: GroupMembership;
  outbound: OutboundQueue;
  objects: ObjectStore;
  subscribers: SubscriptionStore;
  cellObservers: ObserverList<NetworkEvent>;
  duplicatePathObservers: ObserverList<DuplicatePathEvent>;
  /** Snapshot fields that change over the adapter's lifetime. */
  nodeIdShort: number;
  nextMsgId: () => number;
}

export async function publishObject(
  ctx: PublishCtx,
  object: PublishableObject,
  options?: PublishOptions,
): Promise<PublishResult> {
  const txid = await ctx.cfg.txidProvider.mint(object.cellBytes);
  const now = Date.now();
  const topic = options?.topic ?? DEFAULT_TOPIC;
  const group = ctx.cfg.topicToGroup(topic);
  await ctx.membership.ensureMembership(group);

  const result = buildLocalResult(object, txid, topic, now);
  const conflict = recordObject(ctx.objects, result, now);
  if (conflict) ctx.duplicatePathObservers.fire(conflict);

  const packet = frameCellPacket({
    body: buildWireBody(object, topic),
    codec: ctx.cfg.codec,
    msgId: ctx.nextMsgId(),
    nodeIdShort: ctx.nodeIdShort,
    timestamp: now,
    maxPayload: ctx.cfg.maxPayload,
  });
  await ctx.outbound.enqueue({ packet, port: ctx.cfg.port, address: group });

  const event: NetworkEvent = {
    type: "object_published",
    result,
    timestamp: now,
  };
  notify(ctx.subscribers, topic, event);
  ctx.cellObservers.fire(event);

  return { txid, publishedAt: now, multicastGroup: topic };
}

export interface SendUnicastCtx {
  cfg: ResolvedConfig;
  outbound: OutboundQueue;
  nodeIdShort: number;
  nextMsgId: () => number;
}

export async function sendUnicast(
  ctx: SendUnicastCtx,
  address: string,
  message: Uint8Array,
): Promise<void> {
  const header = encodeHeader(
    MSG_CELL,
    ctx.nextMsgId(),
    ctx.nodeIdShort,
    Date.now() >>> 0,
    message.length,
  );
  await ctx.outbound.enqueue({
    packet: framePacket(header, message),
    port: ctx.cfg.port,
    address,
  });
}

export interface SendControlCtx {
  cfg: ResolvedConfig;
  outbound: OutboundQueue;
  nodeIdShort: number;
  nextMsgId: () => number;
}

export async function sendControlMessage(
  ctx: SendControlCtx,
  msg: ControlMessage,
): Promise<void> {
  const packet = frameControlPacket({
    msg,
    codec: ctx.cfg.codec,
    msgId: ctx.nextMsgId(),
    nodeIdShort: ctx.nodeIdShort,
    now: Date.now(),
    maxPayload: ctx.cfg.maxPayload,
  });
  await ctx.outbound.enqueue({
    packet,
    port: ctx.cfg.port,
    address: ctx.cfg.primaryGroup,
  });
}

export interface SubscribeCtx {
  cfg: ResolvedConfig;
  membership: GroupMembership;
  subscribers: SubscriptionStore;
}

/**
 * Add a subscriber for `topic`, ensure the multicast group is joined,
 * and return an unsubscribe function that drops membership when the
 * topic empties.
 */
export function subscribeTopic(
  ctx: SubscribeCtx,
  topic: string,
  callback: Subscriber,
): () => void {
  addSubscriber(ctx.subscribers, topic, callback);
  ctx.membership.ensureMembership(ctx.cfg.topicToGroup(topic)).catch(() => {});
  return () => {
    const { topicEmpty } = removeSubscriber(ctx.subscribers, topic, callback);
    if (topicEmpty) {
      ctx.membership.maybeDropGroup(topic, topicsWithSubscribers(ctx.subscribers));
    }
  };
}

```
