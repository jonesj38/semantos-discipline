---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/ws-node-adapter/src/adapter/local-delivery.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.336972+00:00
---

# runtime/ws-node-adapter/src/adapter/local-delivery.ts

```ts
/**
 * adapter/local-delivery.ts — fan envelopes out to local subscribers.
 *
 * Mirrors MulticastAdapter loopback semantics: a node receives its own
 * publishes on the same topic. Centralised here so both the `publish()`
 * path (own publishes) and the `onPeerFrame` path (verified inbound
 * envelopes) take the same shape.
 */

import type {
  NetworkEvent,
  NetworkResult,
} from "@semantos/protocol-types/network";

import type { SessionEnvelopeFrame } from "../types.js";
import type { SubscriberRegistry } from "./registry.js";

export interface DeliverLocallyArgs {
  envelope: SessionEnvelopeFrame;
  /** Wall-clock for the NetworkEvent timestamp. */
  now: number;
  /** Synthetic txid — not derived from anything chain-y in 35B.1. */
  txid: string;
  /** Provenance for the result; the publish path supplies the object's path, the receive path uses "". */
  semanticPath: string;
  parentPath: string | undefined;
}

/**
 * Build a `NetworkEvent` from `envelope` and fan it out to every callback
 * subscribed to `envelope.topic`. Snapshot iteration tolerates
 * unsubscribe-during-delivery.
 */
export function deliverLocally(
  subscribers: SubscriberRegistry,
  args: DeliverLocallyArgs,
): void {
  const subs = subscribers.snapshot(args.envelope.topic);
  if (subs.length === 0) return;

  const result: NetworkResult = {
    txid: args.txid,
    vout: 0,
    cellBytes: args.envelope.payload,
    semanticPath: args.semanticPath,
    contentHash: args.envelope.contentHash,
    ownerCert: args.envelope.ownerCert,
    typeHash: args.envelope.typeHash,
    parentPath: args.parentPath,
    publishedAt: args.now,
    multicastGroup: args.envelope.topic,
  };
  const event: NetworkEvent = {
    type: "object_published",
    result,
    timestamp: args.now,
  };

  for (const cb of subs) cb(event);
}

```
