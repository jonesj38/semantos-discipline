---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/bsv-overlay-bundle/bsv-bundle-client-facade.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.049295+00:00
---

# runtime/session-protocol/src/bsv-overlay-bundle/bsv-bundle-client-facade.ts

```ts
/**
 * Bundle-client facade — composes publisher + subscriber + poller +
 * dedupe into the public `OverlayBundleClient` shape.
 *
 * Replaces the original 481-LOC monolith with a thin assembly layer
 * over the per-concern modules. Each piece is independently
 * testable; the facade just wires them together.
 */

import type { PublicKey } from "@bsv/sdk";

import type { SignedBundle } from "../bundle-envelope.js";
import type { Unsubscribe } from "../bundle-transport.js";
import type {
  OverlayBundleClient,
  PublishReceipt,
} from "../overlay-bundle-transport.js";
import {
  publishOne,
  senderPubkeyHexFrom,
} from "./bsv-bundle-publisher.js";
import { startBundlePoller } from "./bsv-bundle-poller.js";
import type { SubscriberLogger } from "./bsv-bundle-subscriber.js";
import type { BundleLookupPoller, BundleTxSender } from "./bsv-bundle-ports.js";

export interface BsvOverlayBundleClientConfig {
  /** Tx-sending port — production adapter wraps wallet + SHIP. */
  sender: BundleTxSender;
  /** Lookup port — production adapter wraps BRC-24 SLAP resolver. */
  poller: BundleLookupPoller;
  /**
   * Sender's public key — embedded as the P2PK lock in the
   * PushDrop output. Required at client-creation time because every
   * publish from this client is locked to the same sender identity.
   */
  senderPubKey: PublicKey;
  /**
   * Poll interval for the lookup loop. Default 5s. Callers
   * prioritising latency over SLAP load can drop to 1s; batch
   * workloads can raise to 30s+.
   */
  pollIntervalMs?: number;
  /** Injectable clock for deterministic tests. Default: Date.now. */
  now?: () => number;
  /**
   * Optional logger. When a poll errors we log-and-continue rather
   * than tearing down the subscription. Default: console.warn.
   */
  logger?: SubscriberLogger;
}

/**
 * Construct a real BSV-backed `OverlayBundleClient`.
 *
 * Both ports are injected — pass the production adapters
 * (`createWalletClientBundleTxSender` /
 * `createLookupServiceBundlePoller`) to wire to a live wallet +
 * overlay, or pass fakes in a gate test. The returned client
 * satisfies the same interface as `createLoopbackOverlayBundleClient`
 * from Slice 5e.
 */
export function createBsvOverlayBundleClient(
  config: BsvOverlayBundleClientConfig,
): OverlayBundleClient {
  const {
    sender,
    poller,
    senderPubKey,
    pollIntervalMs = 5_000,
    now = () => Date.now(),
    logger = (message, err) =>
      // Match Slice 5d's convention — surface errors without crashing
      // the node.
      // eslint-disable-next-line no-console
      console.warn(`[bsv-overlay-bundle-client] ${message}`, err),
  } = config;

  const senderPubkeyHex = senderPubkeyHexFrom(senderPubKey);
  const publisherDeps = { sender, senderPubKey, senderPubkeyHex, now };

  return {
    publishBundle<T>(bundle: SignedBundle<T>): Promise<PublishReceipt> {
      return publishOne(publisherDeps, bundle);
    },

    subscribeBundlesForRecipient<T = unknown>(
      recipientCertId: string,
      handler: (bundle: SignedBundle<T>) => void | Promise<void>,
    ): Unsubscribe {
      const handle = startBundlePoller<T>({
        poller,
        handler,
        recipientCertId,
        pollIntervalMs,
        logger,
      });
      return () => handle.stop();
    },
  };
}

```
