---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/ws-node-adapter/src/adapter/transport.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.336161+00:00
---

# runtime/ws-node-adapter/src/adapter/transport.ts

```ts
/**
 * adapter/transport.ts — transport-port abstraction for the WS lifecycle.
 *
 * Per the prompt-39 acceptance criterion: "WebSocket lifecycle testable
 * without a real socket (use a test-double transport)". The lifecycle
 * module talks to this seam; production binds a Bun.serve / WebSocket
 * implementation, tests bind an in-memory loopback double.
 *
 * Same shape as `apps/poker-agent/src/p2p-agent-runner/transport-port.ts`
 * — a per-session factory rather than a single instance, since each
 * `start()` opens an inbound listener and may dial multiple outbound
 * peers.
 *
 * Dial side: `WsTransport.dial(url, hooks)` opens an outbound socket
 * and wires inbound bytes / close into the supplied hooks. The returned
 * `WsSocket` lets the lifecycle module write bytes / close.
 *
 * Listen side: `WsTransport.listen(port, host, tls, hooks)` starts an
 * inbound listener. The hooks fire per-incoming-connection and per-
 * incoming-byte-frame. The returned `WsServer` exposes the actual port
 * (for serverPort=0) and a `stop()`.
 *
 * Neither side knows anything about license-handshake, codec, or
 * topics — those live one layer up.
 */

import type { Server } from "bun";

// ---------------------------------------------------------------------------
// Outbound (dial) seam
// ---------------------------------------------------------------------------

export interface WsSocketHooks {
  onOpen: () => void;
  onMessage: (bytes: Uint8Array) => void;
  onClose: (reason?: string) => void;
  onError: () => void;
}

export interface WsSocket {
  send(bytes: Uint8Array): void;
  close(code?: number, reason?: string): void;
}

// ---------------------------------------------------------------------------
// Inbound (listen) seam
// ---------------------------------------------------------------------------

/**
 * Per-incoming-connection hooks. The lifecycle layer hands these to the
 * transport when a peer dials in, so it can be notified when bytes arrive
 * and when the socket closes.
 *
 * `bind` is called once per inbound socket; the lifecycle layer returns
 * the peer-frame hooks for that connection.
 */
export interface WsListenerHooks {
  /** Called once per accepted inbound socket; returns this connection's per-socket hooks. */
  onAccept: (socket: WsSocket) => WsAcceptedHooks;
  /** Called for HTTP requests on `/.well-known/semantos-node`. */
  onWellKnown: () => Promise<Record<string, unknown>>;
}

export interface WsAcceptedHooks {
  onMessage: (bytes: Uint8Array) => void;
  onClose: (reason?: string) => void;
}

export interface WsServer {
  /** Actual port the server is listening on (useful for `serverPort=0`). */
  readonly port: number | undefined;
  stop(): void;
}

// ---------------------------------------------------------------------------
// Listen + dial factory
// ---------------------------------------------------------------------------

export interface WsListenConfig {
  port?: number;
  host?: string;
  tls?: { cert: string | Buffer; key: string | Buffer };
}

export interface WsTransport {
  dial(url: string, hooks: WsSocketHooks): WsSocket;
  listen(cfg: WsListenConfig, hooks: WsListenerHooks): WsServer;
}

// ---------------------------------------------------------------------------
// Bun-backed default implementation
// ---------------------------------------------------------------------------

interface BunPeerData {
  hooks?: WsAcceptedHooks;
  socket?: WsSocket;
}

/**
 * Production transport. `listen()` uses `Bun.serve`; `dial()` uses the
 * platform `WebSocket` (Bun ships one). Tests can substitute an in-memory
 * double.
 */
export const bunWsTransport: WsTransport = {
  dial(url, hooks) {
    const ws = new WebSocket(url);
    ws.binaryType = "arraybuffer";

    const socket: WsSocket = {
      send(bytes) {
        ws.send(bytes);
      },
      close(_code, reason) {
        ws.close(1000, reason ?? "");
      },
    };

    ws.addEventListener("open", () => hooks.onOpen());
    ws.addEventListener("message", (ev: MessageEvent) => {
      hooks.onMessage(toUint8(ev.data as ArrayBuffer | Uint8Array | Buffer));
    });
    ws.addEventListener("close", (ev: CloseEvent) => {
      hooks.onClose(ev.reason);
    });
    ws.addEventListener("error", () => hooks.onError());

    return socket;
  },

  listen(cfg, hooks) {
    let server: Server | undefined;
    server = Bun.serve({
      port: cfg.port ?? 0,
      hostname: cfg.host ?? "0.0.0.0",
      tls: cfg.tls,
      fetch: async (req, srv) => {
        const url = new URL(req.url);
        if (url.pathname === "/session") {
          if (srv.upgrade(req, { data: {} as BunPeerData })) return;
          return new Response("upgrade-failed", { status: 400 });
        }
        if (url.pathname === "/.well-known/semantos-node") {
          const body = await hooks.onWellKnown();
          return new Response(JSON.stringify(body), {
            status: 200,
            headers: { "content-type": "application/json" },
          });
        }
        return new Response("not-found", { status: 404 });
      },
      websocket: {
        open(ws) {
          const data = ws.data as BunPeerData;
          const socket: WsSocket = {
            send(bytes) {
              ws.sendBinary(bytes);
            },
            close(code, reason) {
              ws.close(code, reason);
            },
          };
          data.socket = socket;
          data.hooks = hooks.onAccept(socket);
        },
        message(ws, message) {
          const data = ws.data as BunPeerData;
          if (!data.hooks) return;
          data.hooks.onMessage(toUint8(message));
        },
        close(ws, _code, reason) {
          const data = ws.data as BunPeerData;
          data.hooks?.onClose(reason);
        },
      },
    });

    return {
      get port(): number | undefined {
        return server?.port;
      },
      stop() {
        server?.stop(true);
        server = undefined;
      },
    };
  },
};

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

function toUint8(data: ArrayBuffer | Uint8Array | Buffer | string): Uint8Array {
  if (data instanceof ArrayBuffer) return new Uint8Array(data);
  if (data instanceof Uint8Array) {
    return data.constructor === Uint8Array ? data : new Uint8Array(data);
  }
  if (typeof data === "string") return new TextEncoder().encode(data);
  // Bun Buffer (Node-compatible) is also Uint8Array.
  return new Uint8Array(data as ArrayBufferLike);
}

```
