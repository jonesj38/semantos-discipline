---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/broadcast.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.038236+00:00
---

# runtime/session-protocol/src/broadcast.ts

```ts
/**
 * Session broadcast — thin helpers for session-peer event delivery.
 *
 * This file is DELIBERATELY minimal. The hackathon `DirectBroadcastEngine`
 * (1672 lines) conflated two concerns:
 *   1. Deliver an event to other session peers   (this file)
 *   2. Anchor a cell on BSV chain via ARC/MAPI   (packages/chain-broadcast)
 *
 * Those live in different tiers now. Keeping (1) small and transport-agnostic
 * means a new NetworkAdapter (WSS, WebRTC, 6LoWPAN) can host a session with
 * zero changes here.
 *
 * `SessionRuntime` uses `adapter.publish` directly for its own envelopes;
 * the helpers below are for consumers that want to fan out custom
 * side-channel payloads (control messages, out-of-band hints, stats) on the
 * same topic or a sibling topic.
 */

import type {
  NetworkAdapter,
  NetworkEvent,
  PublishableObject,
  PublishResult,
} from "@semantos/protocol-types/network";

/**
 * Publish an opaque cell to a session topic. Returns the adapter's
 * PublishResult so callers can log the txid / publishedAt.
 */
export async function broadcastToSession(
  adapter: NetworkAdapter,
  topic: string,
  cell: PublishableObject,
): Promise<PublishResult> {
  return adapter.publish(cell, { topic });
}

/**
 * Subscribe to a session topic, decoding events through a caller-supplied
 * decoder. Returns an unsubscribe function.
 */
export function subscribeToSession<Decoded>(
  adapter: NetworkAdapter,
  topic: string,
  decode: (ev: NetworkEvent) => Decoded | null,
  onMessage: (msg: Decoded) => void,
): () => void {
  return adapter.subscribe(topic, (ev) => {
    try {
      const decoded = decode(ev);
      if (decoded !== null) onMessage(decoded);
    } catch {
      /* swallow malformed events — session runtime handles its own envelope */
    }
  });
}

```
