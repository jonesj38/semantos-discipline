---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/ws-node-adapter/src/bundle-transport-bridge.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.332412+00:00
---

# runtime/ws-node-adapter/src/bundle-transport-bridge.ts

```ts
/**
 * WsBundleTransport — Slice 5d `BundleTransport` over `WsNodeAdapter`.
 *
 * 35B.1 ships the federation wire (license-handshake, per-peer WSS,
 * publish/subscribe). Slice 5d ships the signed-bundle transport
 * interface that intent federation uses. This bridge plugs the two
 * together: two daemons on the federation channel exchange
 * `SignedBundle<T>` via the exact same addressed-bundle semantics 5d
 * defined, without any overlay/BRC-22/24 plumbing.
 *
 * Wire convention:
 *   - topic = `bundles/${recipient.certId}` — only the addressed peer
 *     subscribes to their own topic, so `WsNodeAdapter`'s fan-out to
 *     all authenticated peers is implicitly filtered by subscription.
 *   - payload = JSON-encoded `SignedBundle<T>` as UTF-8 bytes.
 *
 * The bridge intentionally does not verify signatures or enforce trust
 * — that's the caller's job (via `verifyBundleWithTrust` at the seam
 * above this transport). Matches the in-memory reference transport's
 * posture exactly.
 *
 * For 35B.2 — once wire-sig enforcement lands on `WsNodeAdapter`, the
 * transport's envelope sig will cover these bundle payloads too, so
 * receivers get transport-layer sender auth for free on top of the
 * bundle's own signature.
 */

import type {
  NetworkAdapter,
  NetworkEvent,
  PublishableObject,
} from "@semantos/protocol-types/network";
import type {
  BundleTransport,
  ReceiveHandler,
  SignedBundle,
  Unsubscribe,
} from "@semantos/session-protocol";
import { TransportError } from "@semantos/session-protocol";

// ---------------------------------------------------------------------------
// Topic convention
// ---------------------------------------------------------------------------

/** Topic a transport subscribes to for its own incoming bundles. */
export function bundleTopicForCertId(certId: string): string {
  return `bundles/${certId}`;
}

// ---------------------------------------------------------------------------
// Factory
// ---------------------------------------------------------------------------

export interface WsBundleTransportConfig {
  /** The federation-plane adapter that carries the bundles on the wire. */
  adapter: NetworkAdapter;
  /** This transport's own cert id — the one recipients will address to. */
  localCertId: string;
}

/**
 * Build a `BundleTransport` backed by a `NetworkAdapter` (typically a
 * live `WsNodeAdapter`). Bundles are addressed via `recipient.certId`
 * and routed by topic on the underlying adapter.
 */
export function createWsBundleTransport(
  cfg: WsBundleTransportConfig,
): BundleTransport {
  const { adapter, localCertId } = cfg;

  const encoder = new TextEncoder();
  const decoder = new TextDecoder("utf-8", { fatal: true });

  // Local handler set + lazy network subscription — mirrors the
  // InMemoryTransport pattern: one adapter-level subscribe that
  // fans out to many local receive handlers.
  const handlers = new Set<
    (bundle: SignedBundle<unknown>) => void | Promise<void>
  >();
  let adapterUnsub: (() => void) | null = null;

  const ensureSubscribed = () => {
    if (adapterUnsub) return;
    adapterUnsub = adapter.subscribe(
      bundleTopicForCertId(localCertId),
      async (event: NetworkEvent) => {
        // Only object_published carries new inbound bundles. In 35B.1
        // WsNodeAdapter never emits updated/consumed for this topic,
        // but guarding keeps the bridge future-proof.
        if (event.type !== "object_published") return;

        let json: string;
        try {
          json = decoder.decode(event.result.cellBytes);
        } catch {
          // Malformed bytes — drop rather than surface. Matches
          // production posture for unknown frames.
          return;
        }

        let bundle: SignedBundle<unknown>;
        try {
          bundle = JSON.parse(json) as SignedBundle<unknown>;
        } catch {
          return;
        }

        // Defence in depth: even though the topic is certId-scoped,
        // reject any bundle whose recipient.certId doesn't match us.
        // Prevents a miscofigured sender from leaking bundles to the
        // wrong handler if they get the topic right but the
        // recipient field wrong.
        if (bundle.recipient?.certId !== localCertId) return;

        for (const h of handlers) {
          await h(bundle);
        }
      },
    );
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
        throw new TransportError(
          "self_send",
          `transport ${localCertId} tried to send to itself`,
        );
      }

      const json = JSON.stringify(bundle);
      const cellBytes = encoder.encode(json);

      const obj: PublishableObject = {
        cellBytes,
        semanticPath: `/bundles/${bundle.recipient.certId}`,
        contentHash: bundle.signature, // bundle's own sig is already a content-identifying hex
        ownerCert: localCertId,
        typeHash: "signed-bundle",
      };

      await adapter.publish(obj, {
        topic: bundleTopicForCertId(bundle.recipient.certId),
      });
    },

    onReceive<T = unknown>(handler: ReceiveHandler<T>): Unsubscribe {
      ensureSubscribed();
      const wrapped = handler as (
        bundle: SignedBundle<unknown>,
      ) => void | Promise<void>;
      handlers.add(wrapped);
      return () => {
        handlers.delete(wrapped);
        if (handlers.size === 0 && adapterUnsub) {
          adapterUnsub();
          adapterUnsub = null;
        }
      };
    },
  };
}

```
