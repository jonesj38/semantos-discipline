---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/ws-node-adapter/src/adapter/dial.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.336435+00:00
---

# runtime/ws-node-adapter/src/adapter/dial.ts

```ts
/**
 * adapter/dial.ts — outbound dial + handshake helper.
 *
 * Separated from the listener path because:
 *
 *   1. Dialer-only concerns (resolving an endpoint via locator,
 *      awaiting `open` before sending) shouldn't bloat the lifecycle
 *      module.
 *   2. The dial path is the test-friendliest seam: an in-memory
 *      transport double can emulate the round-trip exactly without
 *      a real socket.
 *
 * The function takes a transport seam, builds a `WsPeerConnection` in
 * `dialer` mode, wires the socket-side hooks into the connection's
 * state machine, and returns a promise that resolves with the
 * authenticated connection (or rejects on close-before-auth / error).
 */

import type { Verifier } from "@semantos/session-protocol";
import type { PeerLocator } from "@semantos/peer-locator";

import {
  WsPeerConnection,
  type LocalIdentity,
} from "../ws-peer-connection.js";
import { FRAME_KIND, type SessionEnvelopeFrame } from "../types.js";
import type { WsTransport } from "./transport.js";

// ---------------------------------------------------------------------------
// Args
// ---------------------------------------------------------------------------

export interface DialArgs {
  peerBca: string;
  locator: PeerLocator;
  transport: WsTransport;
  localIdentity: LocalIdentity;
  verifier: Verifier;
  deriveBcaFromPubkey: (pubkey: Uint8Array) => Promise<string>;
  isAcceptableIssuer?: (issuerPubkey: Uint8Array) => boolean;
  handshakeTimeoutMs?: number;
  log?: (tag: string, msg: string) => void;
  onAuthenticated: (conn: WsPeerConnection) => void;
  onFrame: (
    conn: WsPeerConnection,
    frame: SessionEnvelopeFrame | { kind: typeof FRAME_KIND.HEARTBEAT },
  ) => void;
  onClose: (conn: WsPeerConnection, reason?: string) => void;
}

/**
 * Resolve `peerBca` via the locator, dial the WSS endpoint, and wait
 * for the handshake to complete. Resolves with the authenticated
 * `WsPeerConnection`; rejects on locator-miss / socket-error /
 * close-before-auth.
 */
export async function dialAndAuthenticate(
  args: DialArgs,
): Promise<WsPeerConnection> {
  const endpoint = await args.locator.resolve(args.peerBca);
  if (!endpoint) {
    throw new Error(
      `WsNodeAdapter.connect: no endpoint for ${args.peerBca}`,
    );
  }

  let resolveAuth: (conn: WsPeerConnection) => void = () => {};
  let rejectAuth: (e: Error) => void = () => {};
  const authPromise = new Promise<WsPeerConnection>((resolve, reject) => {
    resolveAuth = resolve;
    rejectAuth = reject;
  });

  let socket = undefined as ReturnType<WsTransport["dial"]> | undefined;

  const conn = new WsPeerConnection({
    role: "dialer",
    localIdentity: args.localIdentity,
    verifier: args.verifier,
    deriveBcaFromPubkey: args.deriveBcaFromPubkey,
    isAcceptableIssuer: args.isAcceptableIssuer,
    sendBytes: (b) => socket?.send(b),
    closeSocket: (_code, reason) => socket?.close(1000, reason ?? ""),
    onAuthenticated: (c) => {
      args.onAuthenticated(c);
      resolveAuth(c);
    },
    onFrame: (c, f) => args.onFrame(c, f),
    onClose: (c, reason) => {
      args.onClose(c, reason);
      rejectAuth(new Error(`connection closed: ${reason ?? "unknown"}`));
    },
    handshakeTimeoutMs: args.handshakeTimeoutMs,
    log: args.log,
  });

  socket = args.transport.dial(endpoint.wssUrl, {
    onOpen: () => {
      conn.start().catch((e) => rejectAuth(e as Error));
    },
    onMessage: (bytes) => {
      conn.handleBytes(bytes).catch(() => {});
    },
    onClose: (reason) => {
      conn.handleSocketClose(reason);
    },
    onError: () => {
      rejectAuth(new Error("websocket error"));
    },
  });

  return authPromise;
}

```
