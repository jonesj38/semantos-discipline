---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/overlay-bundle-transport.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.035450+00:00
---

# runtime/session-protocol/src/overlay-bundle-transport.ts

```ts
/**
 * OverlayBundleTransport — BundleTransport backed by an overlay-
 * network client (BRC-22 topic manager + BRC-24 lookup service).
 *
 * Slice 5d shipped the BundleTransport interface + InMemoryTransport
 * reference. 5e wraps an overlay-network client into the same
 * interface: signed + trusted + addressed + policy-gated bundles
 * ride the BSV overlay instead of an in-process network.
 *
 * The module separates two concerns:
 *
 *   1. `OverlayBundleClient` — a minimal interface for publish +
 *      recipient-scoped subscribe. One production implementation
 *      wraps `TopicManagerClient` + `LookupServiceClient` from
 *      `@semantos/protocol-types/overlay/*` (BRC-22 SHIP broadcast
 *      + BRC-24 SLAP resolve). A loopback test double ships here
 *      for gate tests + dev loops.
 *
 *   2. `createOverlayBundleTransport(client, localCertId)` — adapts
 *      the client into a `BundleTransport`. Routes `send()` through
 *      the client's `publishBundle`; wires `onReceive()` through
 *      the client's recipient-scoped subscription.
 *
 * BRC-87 topic name: `tm_semantos_bundles`.
 *
 * Rationale — why a client abstraction instead of hardcoding to
 * TopicManagerClient? Two real benefits:
 *
 *   - Testability: LoopbackOverlayBundleClient lets gates run
 *     end-to-end without a real BSV connection or funded wallet
 *   - Portability: an overlay backend could be swapped (Plexus,
 *     libp2p, matrix-style relay) without changing the transport.
 *     The BRC primitives are the first implementation target, not
 *     the only one.
 *
 * Verification + trust + policy stay above the transport — same as
 * Slice 5d. The overlay is the wire; it never decides who to trust.
 */

import type { SignedBundle } from "./bundle-envelope.js";
import type {
  BundleTransport,
  ReceiveHandler,
  Unsubscribe,
} from "./bundle-transport.js";
import { TransportError } from "./bundle-transport.js";

// ── OverlayBundleClient interface ──────────────────────────────

/**
 * The minimum overlay-network surface a bundle transport needs.
 *
 * A production implementation (BsvOverlayBundleClient, follow-up
 * slice) wraps BRC-22 SHIP broadcast + BRC-24 SLAP lookup polling.
 * The ships-here `LoopbackOverlayBundleClient` is the in-memory
 * double used by gate tests.
 */
export interface OverlayBundleClient {
  /**
   * Publish a signed bundle to the overlay. The overlay is
   * responsible for making the bundle discoverable by the
   * recipient certId encoded in the envelope. Returns a stable id
   * from the overlay (txid for BSV, generated id for loopback).
   *
   * The client does NOT verify the bundle — verification is the
   * receiver's job. This API is just the wire.
   */
  publishBundle<T>(bundle: SignedBundle<T>): Promise<PublishReceipt>;

  /**
   * Subscribe to bundles addressed to a specific recipient certId.
   * Real implementations poll BRC-24 lookup services; loopback
   * dispatches synchronously. Returns an unsubscribe function.
   *
   * Handlers must not throw — if processing fails they're the
   * transport's responsibility, and the handler's pipeline (verify
   * + policy + import) handles its own errors downstream.
   */
  subscribeBundlesForRecipient<T = unknown>(
    recipientCertId: string,
    handler: (bundle: SignedBundle<T>) => void | Promise<void>,
  ): Unsubscribe;
}

export interface PublishReceipt {
  /** The overlay's stable id for the published bundle (BSV txid, or a synthetic id). */
  id: string;
  /** Human-readable overlay backend tag — 'bsv-overlay', 'loopback', etc. */
  backend: string;
  /** Wall-clock ms when the overlay accepted the bundle. */
  publishedAt: number;
}

/**
 * BRC-87 compliant topic name for Semantos signed-bundle federation.
 * Used by the production BSV-overlay implementation and documented
 * here so the name is stable across consumers even before that
 * implementation lands.
 */
export const SEMANTOS_BUNDLES_TOPIC = "tm_semantos_bundles";

/**
 * BRC-87 compliant lookup service name for resolving bundles by
 * recipient. Documented here for the same stability reason.
 */
export const SEMANTOS_BUNDLES_LOOKUP = "ls_semantos_bundles_by_recipient";

// ── Loopback overlay client (for tests / in-process dev) ──────

/**
 * In-memory OverlayBundleClient — simulates an overlay by
 * maintaining a set of subscribers keyed by recipient certId. No
 * BSV wallet, no network I/O.
 *
 * Deterministic ordering: each `publishBundle` awaits every matching
 * subscriber before returning. Tests know exactly when delivery
 * completes.
 *
 * Differs from Slice 5d's `InMemoryTransportNetwork` in one
 * important way: that one routes at the *transport* layer (one
 * transport per party, network dispatches); this one models the
 * *overlay* layer (the overlay accepts publishes regardless of
 * sender, and multiple recipients could subscribe to the same
 * certId — a bundle broadcasts to all matching subscribers).
 */
export function createLoopbackOverlayBundleClient(): OverlayBundleClient & {
  /** For gate-test introspection — how many subscribers are on this recipient cert. */
  subscriberCount(recipientCertId: string): number;
  /** Count of successful publishes since creation. */
  publishCount(): number;
  /** Snapshot the recipient certIds with at least one active subscriber. */
  activeRecipients(): string[];
} {
  const subscribers = new Map<
    string,
    Set<(bundle: SignedBundle<unknown>) => void | Promise<void>>
  >();
  let publishes = 0;
  let publishSeq = 0;

  return {
    async publishBundle<T>(bundle: SignedBundle<T>): Promise<PublishReceipt> {
      const recipient = bundle.recipient?.certId;
      if (!recipient) {
        throw new TransportError(
          "unaddressed_bundle",
          "loopback overlay client: bundle has no recipient.certId",
        );
      }
      publishes += 1;
      const publishedAt = Date.now();
      const id = `loopback-pub-${++publishSeq}`;

      const set = subscribers.get(recipient);
      if (set) {
        // Fan out to every active subscriber. Await each so the
        // publisher gate knows when delivery is complete.
        for (const handler of set) {
          await handler(bundle as SignedBundle<unknown>);
        }
      }

      return { id, backend: "loopback", publishedAt };
    },

    subscribeBundlesForRecipient<T = unknown>(
      recipientCertId: string,
      handler: (bundle: SignedBundle<T>) => void | Promise<void>,
    ): Unsubscribe {
      let set = subscribers.get(recipientCertId);
      if (!set) {
        set = new Set();
        subscribers.set(recipientCertId, set);
      }
      const wrapped = handler as (
        b: SignedBundle<unknown>,
      ) => void | Promise<void>;
      set.add(wrapped);
      return () => {
        const current = subscribers.get(recipientCertId);
        if (!current) return;
        current.delete(wrapped);
        if (current.size === 0) subscribers.delete(recipientCertId);
      };
    },

    subscriberCount(recipientCertId: string): number {
      return subscribers.get(recipientCertId)?.size ?? 0;
    },

    publishCount(): number {
      return publishes;
    },

    activeRecipients(): string[] {
      return Array.from(subscribers.keys()).sort();
    },
  };
}

// ── Transport factory ─────────────────────────────────────────

/**
 * Wrap an OverlayBundleClient into a BundleTransport.
 *
 * On `send(bundle)`:
 *   - reject unaddressed bundles before touching the client
 *   - reject self-send (sender == recipient)
 *   - delegate to client.publishBundle
 *
 * On `onReceive(handler)`:
 *   - subscribe the handler to bundles addressed to this
 *     transport's localCertId via the client
 *
 * The transport is intentionally thin — all non-wire concerns
 * (verify, trust, policy) live above it, so replacing the overlay
 * with a different backend doesn't require any changes to the
 * receiver pipeline.
 */
export function createOverlayBundleTransport(
  client: OverlayBundleClient,
  localCertId: string,
): BundleTransport {
  return {
    localCertId,

    async send<T>(bundle: SignedBundle<T>): Promise<void> {
      if (!bundle.recipient?.certId) {
        throw new TransportError(
          "unaddressed_bundle",
          "overlay transport: send requires addressed bundle (bundle.recipient.certId)",
        );
      }
      if (bundle.recipient.certId === localCertId) {
        throw new TransportError(
          "self_send",
          `overlay transport: ${localCertId} tried to send to itself`,
        );
      }
      await client.publishBundle(bundle);
    },

    onReceive<T = unknown>(handler: ReceiveHandler<T>): Unsubscribe {
      return client.subscribeBundlesForRecipient(localCertId, handler);
    },
  };
}

```
