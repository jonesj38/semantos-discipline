---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/adapters/multicast/outbound-queue.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.066950+00:00
---

# runtime/session-protocol/src/adapters/multicast/outbound-queue.ts

```ts
/**
 * outbound-queue — buffers outbound packets and applies a tiny
 * retry policy on transport errors.
 *
 * Per the prompt-38 spec: "outbound queue + retry policy; driven by
 * an effect atom." We don't pull in `@semantos/state` for this single
 * adapter — the "effect atom" semantics here are an internal
 * promise-chained drain triggered by enqueue and reactivated by
 * transport-error backoff.
 *
 * Default retry policy:
 *   - up to 3 attempts per packet
 *   - 25ms / 50ms backoff between tries
 *   - on terminal failure, optional `onDrop` observer fires
 *
 * The orchestrator passes `send(packet, port, address)` as a callback,
 * so this module never needs to know about UDP or multicast addressing.
 *
 * Cross-references:
 *   docs/prd/refactor-monoliths/38-multicast-adapter-split.md
 */

export interface OutboundPacket {
  packet: Uint8Array;
  port: number;
  address: string;
  /** When set, retries on this packet are not attempted (heartbeats). */
  bestEffort?: boolean;
}

export interface RetryPolicy {
  /** Max send attempts (1 = no retry). Default: 3. */
  maxAttempts: number;
  /** Backoff sequence in ms; index clamped to length-1. Default: [25,50]. */
  backoffMs: number[];
}

export interface OutboundQueueConfig {
  send: (
    packet: Uint8Array,
    port: number,
    address: string,
  ) => Promise<void>;
  retryPolicy?: RetryPolicy;
  onDrop?: (item: OutboundPacket, lastError: unknown) => void;
}

const DEFAULT_RETRY: RetryPolicy = {
  maxAttempts: 3,
  backoffMs: [25, 50],
};

export interface OutboundQueue {
  /** Enqueue a packet for delivery. Resolves once it has been sent (or dropped). */
  enqueue(item: OutboundPacket): Promise<void>;
  /** Number of pending items not yet attempted. */
  size(): number;
  /** Drain in flight + queued items. */
  drain(): Promise<void>;
}

export function createOutboundQueue(
  config: OutboundQueueConfig,
): OutboundQueue {
  const policy = config.retryPolicy ?? DEFAULT_RETRY;
  const queue: Array<{
    item: OutboundPacket;
    resolve: () => void;
  }> = [];
  let draining: Promise<void> | null = null;

  async function attemptSend(item: OutboundPacket): Promise<void> {
    let lastErr: unknown = undefined;
    const attempts = item.bestEffort ? 1 : policy.maxAttempts;
    for (let i = 0; i < attempts; i++) {
      try {
        await config.send(item.packet, item.port, item.address);
        return;
      } catch (err) {
        lastErr = err;
        if (i + 1 < attempts) {
          const idx = Math.min(i, policy.backoffMs.length - 1);
          const ms = policy.backoffMs[idx] ?? 0;
          await sleep(ms);
        }
      }
    }
    config.onDrop?.(item, lastErr);
  }

  async function drainLoop(): Promise<void> {
    while (queue.length > 0) {
      const next = queue.shift()!;
      await attemptSend(next.item);
      next.resolve();
    }
    draining = null;
  }

  return {
    enqueue(item: OutboundPacket): Promise<void> {
      return new Promise<void>((resolve) => {
        queue.push({ item, resolve });
        if (!draining) {
          draining = drainLoop();
        }
      });
    },
    size(): number {
      return queue.length;
    },
    async drain(): Promise<void> {
      if (draining) await draining;
    },
  };
}

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve) => {
    if (ms <= 0) {
      queueMicrotask(resolve);
      return;
    }
    setTimeout(resolve, ms);
  });
}

```
