---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/ws-node-adapter/src/adapter/lifecycle.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.334776+00:00
---

# runtime/ws-node-adapter/src/adapter/lifecycle.ts

```ts
/**
 * adapter/lifecycle.ts — server start / stop and per-listener wiring.
 *
 * Owns the `WsServer` returned by the transport. Doesn't own the
 * connection map (registry.ts does), the codec (codec.ts /
 * envelope-codec.ts), or the well-known builder (well-known.ts).
 *
 * Acceptance criterion (prompt 39): "WebSocket lifecycle testable
 * without a real socket (use a test-double transport)" — start/stop
 * flow only talks to the `WsTransport` seam, so an in-memory double
 * (see `transport.ts`) makes the lifecycle a pure exchange of bytes.
 */

import type { Verifier } from "@semantos/session-protocol";

import {
  WsPeerConnection,
  type LocalIdentity,
} from "../ws-peer-connection.js";
import { FRAME_KIND, type SessionEnvelopeFrame } from "../types.js";
import type {
  WsListenConfig,
  WsServer,
  WsTransport,
} from "./transport.js";

// ---------------------------------------------------------------------------
// Args
// ---------------------------------------------------------------------------

export interface StartListenerArgs {
  transport: WsTransport;
  listen: WsListenConfig;
  localIdentity: LocalIdentity;
  verifier: Verifier;
  deriveBcaFromPubkey: (pubkey: Uint8Array) => Promise<string>;
  isAcceptableIssuer?: (issuerPubkey: Uint8Array) => boolean;
  handshakeTimeoutMs?: number;
  log?: (tag: string, msg: string) => void;
  /** Called whenever a peer authenticates. */
  onAuthenticated: (conn: WsPeerConnection) => void;
  /** Called for every post-auth frame from a listener-side peer. */
  onFrame: (
    conn: WsPeerConnection,
    frame: SessionEnvelopeFrame | { kind: typeof FRAME_KIND.HEARTBEAT },
  ) => void;
  /** Called when a listener-side peer disconnects (any reason). */
  onClose: (conn: WsPeerConnection, reason?: string) => void;
  /** Caller-supplied JSON for `/.well-known/semantos-node`. */
  buildWellKnown: () => Promise<Record<string, unknown>>;
}

// ---------------------------------------------------------------------------
// Start a listener
// ---------------------------------------------------------------------------

/**
 * Start listening on the configured port + host. Each accepted socket
 * gets a fresh `WsPeerConnection` in `listener` mode wired into the
 * caller's hooks. Returns the underlying `WsServer` handle.
 */
export function startListener(args: StartListenerArgs): WsServer {
  return args.transport.listen(args.listen, {
    onWellKnown: args.buildWellKnown,
    onAccept: (socket) => {
      const conn = new WsPeerConnection({
        role: "listener",
        localIdentity: args.localIdentity,
        verifier: args.verifier,
        deriveBcaFromPubkey: args.deriveBcaFromPubkey,
        isAcceptableIssuer: args.isAcceptableIssuer,
        sendBytes: (b) => socket.send(b),
        closeSocket: (code, reason) => socket.close(code, reason),
        onAuthenticated: (c) => args.onAuthenticated(c),
        onFrame: (c, f) => args.onFrame(c, f),
        onClose: (c, reason) => args.onClose(c, reason),
        handshakeTimeoutMs: args.handshakeTimeoutMs,
        log: args.log,
      });
      // Fire and forget — Bun's `open` handler is synchronous. start()
      // sends our handshake. Errors are logged through the connection's
      // own logger.
      conn.start().catch((e) => {
        args.log?.("listener", `start failed: ${(e as Error).message}`);
      });
      return {
        onMessage: (bytes) => {
          conn.handleBytes(bytes).catch((e) => {
            args.log?.(
              "listener",
              `handleBytes failed: ${(e as Error).message}`,
            );
          });
        },
        onClose: (reason) => {
          conn.handleSocketClose(reason);
        },
      };
    },
  });
}

```
