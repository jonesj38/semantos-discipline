---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/http-transport.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.037945+00:00
---

# runtime/session-protocol/src/http-transport.ts

```ts
/**
 * HttpBundleTransport — BundleTransport over plain HTTP POST.
 *
 * First real transport implementation. Peers addressed by certId;
 * a static `peerRegistry: Map<certId, baseUrl>` tells this transport
 * where to POST bundles addressed to a given cert.
 *
 * Wire format: `JSON.stringify(signedBundle)`. Same wire the in-memory
 * transport simulates — nothing fancy.
 *
 * The transport does NOT verify signatures, consult cert stores, or
 * enforce handoff policy. Those decisions live above the transport,
 * in the `onReceive` handler. Transport's only concerns:
 *   - route bundles to registered peers by recipient.certId
 *   - deliver inbound POSTs to the local onReceive handler
 *   - enforce self_send + recipient_not_registered + unaddressed_bundle
 *
 * Uses Bun.serve for inbound listening (matches apps/loom-react/server
 * pattern). Port conflicts throw synchronously at construction.
 *
 * Interface parity with InMemoryTransport: every gate that passes
 * against createInMemoryTransport must also pass against
 * createHttpTransport between two localhost ports.
 */
// Bun.Server type referenced via globalThis.Bun to avoid the generic
// WebSocketData parameter that `import type { Server } from "bun"` forces.
type BunServer = ReturnType<typeof Bun.serve>;
import type { SignedBundle } from "./bundle-envelope.js";
import {
  type BundleTransport,
  type ReceiveHandler,
  type Unsubscribe,
  TransportError,
} from "./bundle-transport.js";

// ── Options ────────────────────────────────────────────────────

export interface HttpBundleTransportOptions {
  /** certId of this transport's owner — used for self_send detection. */
  ownCertId: string;

  /** Port to bind the inbound Bun.serve listener on. */
  listenPort: number;

  /** Hostname to bind to. Default `0.0.0.0`. */
  listenHost?: string;

  /** Map of peer certId → base URL (e.g. `http://10.0.0.5:8080`). Static. */
  peerRegistry: Map<string, string>;

  /** HTTP request timeout for outbound sends (ms). Default 10000. */
  requestTimeoutMs?: number;

  /** Path prefix for federation endpoints. Default `/federation`. */
  pathPrefix?: string;
}

/**
 * Shared transport-level error code added by HTTP transport.
 *
 * The core `TransportErrorCode` union uses `unaddressed_bundle`,
 * `recipient_not_registered`, `network_closed`, `self_send`. HTTP
 * adds `transport_error` for network-level failures (timeout,
 * unreachable, non-2xx). We reuse `network_closed` for post-close
 * sends; `transport_error` is a TransportError with a string detail
 * as the message.
 */

// ── Factory ────────────────────────────────────────────────────

export function createHttpTransport(
  opts: HttpBundleTransportOptions,
): BundleTransport & { close: () => Promise<void> } {
  const handlers = new Set<
    (bundle: SignedBundle<unknown>) => void | Promise<void>
  >();
  const inFlight = new Set<Promise<void>>();
  let closed = false;
  const pathPrefix = opts.pathPrefix ?? "/federation";
  const expectedPath = `${pathPrefix}/bundle`;
  const requestTimeoutMs = opts.requestTimeoutMs ?? 10_000;

  // Bind Bun.serve synchronously — port conflicts throw here.
  let server: BunServer;
  try {
    server = Bun.serve({
      port: opts.listenPort,
      hostname: opts.listenHost ?? "0.0.0.0",
      async fetch(req) {
        if (closed) return new Response("closed", { status: 503 });
        const url = new URL(req.url);
        if (url.pathname !== expectedPath || req.method !== "POST") {
          return new Response("not found", { status: 404 });
        }
        let bundle: SignedBundle<unknown>;
        try {
          bundle = (await req.json()) as SignedBundle<unknown>;
        } catch (e) {
          return new Response(`bad json: ${String(e)}`, { status: 400 });
        }
        if (handlers.size === 0) {
          return new Response("no handler", { status: 503 });
        }
        // Run handlers; track for graceful shutdown.
        const task = (async () => {
          for (const h of handlers) {
            await h(bundle);
          }
        })();
        inFlight.add(task);
        try {
          await task;
        } finally {
          inFlight.delete(task);
        }
        return new Response("ok", { status: 200 });
      },
      error(err) {
        return new Response(`error: ${String(err)}`, { status: 500 });
      },
    });
  } catch (err) {
    // Bun.serve throws synchronously on port conflict.
    throw new TransportError(
      "network_closed",
      `HttpBundleTransport failed to bind to ${opts.listenHost ?? "0.0.0.0"}:${opts.listenPort}: ${String(err)}`,
    );
  }

  const transport: BundleTransport & { close: () => Promise<void> } = {
    get localCertId() {
      return opts.ownCertId;
    },

    async send<T>(bundle: SignedBundle<T>): Promise<void> {
      if (closed) {
        throw new TransportError(
          "network_closed",
          `HttpBundleTransport ${opts.ownCertId} is closed`,
        );
      }
      const recipientCertId = bundle.recipient?.certId;
      if (!recipientCertId) {
        throw new TransportError(
          "unaddressed_bundle",
          "send() requires an addressed bundle (bundle.recipient.certId)",
        );
      }
      if (recipientCertId === opts.ownCertId) {
        throw new TransportError(
          "self_send",
          `transport ${opts.ownCertId} tried to send to itself`,
        );
      }
      const baseUrl = opts.peerRegistry.get(recipientCertId);
      if (!baseUrl) {
        throw new TransportError(
          "recipient_not_registered",
          `no peer URL registered for certId ${recipientCertId}`,
        );
      }
      const endpoint = `${baseUrl.replace(/\/$/, "")}${expectedPath}`;
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), requestTimeoutMs);
      try {
        const res = await fetch(endpoint, {
          method: "POST",
          headers: {
            "content-type": "application/json",
            "x-semantos-recipient-cert": recipientCertId,
            "x-semantos-sender-cert": opts.ownCertId,
          },
          body: JSON.stringify(bundle),
          signal: controller.signal,
        });
        if (!res.ok) {
          throw new TransportError(
            "network_closed",
            `peer ${recipientCertId} returned HTTP ${res.status}`,
          );
        }
      } catch (err) {
        if (err instanceof TransportError) throw err;
        throw new TransportError(
          "network_closed",
          `send to ${recipientCertId} at ${endpoint} failed: ${String(err)}`,
        );
      } finally {
        clearTimeout(timeoutId);
      }
    },

    onReceive<T = unknown>(handler: ReceiveHandler<T>): Unsubscribe {
      const wrapped = handler as (
        bundle: SignedBundle<unknown>,
      ) => void | Promise<void>;
      handlers.add(wrapped);
      return () => {
        handlers.delete(wrapped);
      };
    },

    async close(): Promise<void> {
      if (closed) return;
      closed = true;
      // Wait up to 5s for in-flight inbound handlers to complete.
      const deadline = Date.now() + 5_000;
      while (inFlight.size > 0 && Date.now() < deadline) {
        await Promise.race([
          Promise.allSettled([...inFlight]),
          new Promise((r) => setTimeout(r, 100)),
        ]);
      }
      server.stop(true);
    },
  };

  return transport;
}

```
