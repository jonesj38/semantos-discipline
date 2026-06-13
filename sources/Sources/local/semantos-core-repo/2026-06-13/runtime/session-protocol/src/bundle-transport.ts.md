---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/bundle-transport.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.036854+00:00
---

# runtime/session-protocol/src/bundle-transport.ts

```ts
/**
 * BundleTransport — transport-agnostic channel for signed bundles.
 *
 * Closes the Slice-5 story: 5a signs bundles, 5b gates on signer
 * trust, 5c addresses them and gates on per-object policy. 5d is
 * the wire those bundles ride on. Gates up to 5c used
 * `JSON.stringify/parse` as the wire stand-in. This module gives
 * that wire a real interface so real transports (WebRTC, overlay,
 * signed HTTP, shared filesystem, Plexus edge) plug in cleanly
 * without touching the layers above.
 *
 * The interface is deliberately minimal — transports just move
 * bundles between parties identified by cert id. All verification +
 * trust + policy decisions happen above the transport, using the
 * bundle's own signer/recipient fields.
 *
 * Ships one reference implementation: `InMemoryTransportNetwork` +
 * `createInMemoryTransport(network, myCertId)`. Useful for tests
 * and in-process dev that want the full federation stack without
 * spinning up real networking. Real transports (extensions-supplied)
 * implement `BundleTransport` and drop into the same call sites.
 */

import type { SignedBundle } from "./bundle-envelope.js";

// ── Interface ──────────────────────────────────────────────────

export type ReceiveHandler<T = unknown> = (
  bundle: SignedBundle<T>,
) => void | Promise<void>;

/** Call-site unsubscribe — returned by `onReceive`. */
export type Unsubscribe = () => void;

export interface BundleTransport {
  /**
   * Send a signed bundle. The transport uses `bundle.recipient` to
   * route — bundles without a recipient are rejected with
   * `TransportError('unaddressed_bundle', ...)` since Slice 5c
   * addressed-bundle semantics are the production posture.
   *
   * Does not verify the signature — that's the receiver's job.
   * Transport is the wire; trust decisions live above it.
   */
  send<T>(bundle: SignedBundle<T>): Promise<void>;

  /**
   * Subscribe to incoming bundles addressed to this transport's
   * cert id. Returns an unsubscribe function.
   *
   * The handler receives the bundle as-is — verification is the
   * handler's responsibility.
   */
  onReceive<T = unknown>(handler: ReceiveHandler<T>): Unsubscribe;

  /** This transport's bound cert id. Informational. */
  readonly localCertId: string;
}

export class TransportError extends Error {
  constructor(
    public readonly code: TransportErrorCode,
    message: string,
  ) {
    super(message);
    this.name = "TransportError";
  }
}

export type TransportErrorCode =
  | "unaddressed_bundle"
  | "recipient_not_registered"
  | "network_closed"
  | "self_send";

// ── In-memory reference implementation ─────────────────────────

/**
 * A shared in-process network — transports register with their cert
 * id, the network routes bundles between them. One process,
 * deterministic timing, no real networking. Useful for unit tests
 * and the federation gate.
 */
export class InMemoryTransportNetwork {
  private readonly subscribers = new Map<
    string,
    Set<(bundle: SignedBundle<unknown>) => void | Promise<void>>
  >();
  private closed = false;

  /** Register a transport's subscriber for the given cert id. */
  register(
    certId: string,
    handler: (bundle: SignedBundle<unknown>) => void | Promise<void>,
  ): Unsubscribe {
    if (this.closed) {
      throw new TransportError(
        "network_closed",
        "InMemoryTransportNetwork is closed",
      );
    }
    let set = this.subscribers.get(certId);
    if (!set) {
      set = new Set();
      this.subscribers.set(certId, set);
    }
    set.add(handler);
    return () => {
      const current = this.subscribers.get(certId);
      if (!current) return;
      current.delete(handler);
      if (current.size === 0) this.subscribers.delete(certId);
    };
  }

  /**
   * Deliver a bundle to the recipient cert id. All subscribers for
   * that cert id receive the bundle. Awaits every handler so the
   * caller knows when the delivery round completes — makes
   * deterministic-order gate tests easy to write.
   */
  async deliver<T>(bundle: SignedBundle<T>): Promise<void> {
    if (this.closed) {
      throw new TransportError(
        "network_closed",
        "InMemoryTransportNetwork is closed",
      );
    }
    if (!bundle.recipient?.certId) {
      throw new TransportError(
        "unaddressed_bundle",
        "bundle has no recipient.certId; addressed bundles only",
      );
    }
    const handlers = this.subscribers.get(bundle.recipient.certId);
    if (!handlers || handlers.size === 0) {
      throw new TransportError(
        "recipient_not_registered",
        `no transport registered for certId ${bundle.recipient.certId}`,
      );
    }
    for (const handler of handlers) {
      await handler(bundle as SignedBundle<unknown>);
    }
  }

  /** Snapshot of all registered recipient cert ids. */
  registeredCertIds(): string[] {
    return Array.from(this.subscribers.keys()).sort();
  }

  /** Close the network — subsequent register/deliver calls throw. */
  close(): void {
    this.closed = true;
    this.subscribers.clear();
  }
}

/**
 * Create a BundleTransport bound to a local cert id on a shared
 * InMemoryTransportNetwork. Multiple transports can run on one
 * network, one per party.
 */
export function createInMemoryTransport(
  network: InMemoryTransportNetwork,
  localCertId: string,
): BundleTransport {
  const handlers = new Set<
    (bundle: SignedBundle<unknown>) => void | Promise<void>
  >();

  // One network-side subscription that fans out to local handlers.
  // Using a single network-level subscription means registering
  // multiple transport handlers on one transport doesn't register
  // them multiple times with the network.
  let networkUnsub: Unsubscribe | null = null;
  const ensureSubscribed = () => {
    if (networkUnsub) return;
    networkUnsub = network.register(localCertId, async (bundle) => {
      for (const h of handlers) {
        await h(bundle);
      }
    });
  };

  return {
    localCertId,

    async send<T>(bundle: SignedBundle<T>): Promise<void> {
      if (!bundle.recipient?.certId) {
        throw new TransportError(
          "unaddressed_bundle",
          "send() requires an addressed bundle (bundle.recipient.certId)",
        );
      }
      if (bundle.recipient.certId === localCertId) {
        // Self-send is almost always a bug — let the caller see it
        // explicitly rather than silently loopback.
        throw new TransportError(
          "self_send",
          `transport ${localCertId} tried to send to itself`,
        );
      }
      await network.deliver(bundle);
    },

    onReceive<T = unknown>(handler: ReceiveHandler<T>): Unsubscribe {
      ensureSubscribed();
      const wrapped = handler as (
        bundle: SignedBundle<unknown>,
      ) => void | Promise<void>;
      handlers.add(wrapped);
      return () => {
        handlers.delete(wrapped);
        if (handlers.size === 0 && networkUnsub) {
          networkUnsub();
          networkUnsub = null;
        }
      };
    },
  };
}

```
