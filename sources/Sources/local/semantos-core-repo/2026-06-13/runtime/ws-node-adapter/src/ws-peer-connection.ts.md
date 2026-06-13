---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/ws-node-adapter/src/ws-peer-connection.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.332683+00:00
---

# runtime/ws-node-adapter/src/ws-peer-connection.ts

```ts
/**
 * WsPeerConnection — per-peer state machine for one WSS connection.
 *
 * State machine:
 *
 *   authenticating
 *     ├─ received valid handshake → authenticated
 *     ├─ received invalid handshake / unexpected frame → closed (4001)
 *     └─ handshake timeout → closed (4001)
 *   authenticated
 *     ├─ received envelope/heartbeat → onFrame()
 *     ├─ received goodbye → closing → closed
 *     └─ local close() → closing (send goodbye) → closed
 *   closed
 *     └─ terminal
 *
 * Transport-agnostic. The class takes `sendBytes` / `closeSocket` callbacks
 * so callers (Bun.serve listener, browser/Node WebSocket dialer) wire their
 * respective socket APIs. Inbound bytes flow through `handleBytes`;
 * socket-close via `handleSocketClose`.
 *
 * Handshake is symmetric: both sides send their handshake frame immediately
 * on `start()`, then transition to `authenticated` upon verifying the
 * peer's frame. Real replay protection comes from TLS at the transport
 * layer; the challenge in each handshake prevents signature caching.
 */

import type { Signer, Verifier } from "@semantos/session-protocol";
import type { License } from "@semantos/protocol-types/license";
import { decodeFrame, encodeFrame } from "./codec.js";
import {
  buildHandshakeFrame,
  verifyHandshakeFrame,
} from "./license-handshake.js";
import {
  FRAME_KIND,
  type ConnectionState,
  type Frame,
  type HeartbeatFrame,
  type SessionEnvelopeFrame,
} from "./types.js";

// ---------------------------------------------------------------------------
// LocalIdentity — bundle of "what I need to sign a handshake as myself"
// ---------------------------------------------------------------------------

export interface LocalIdentity {
  /** Holder's Signer — signs the handshake payload. */
  signer: Signer;
  /** Decoded License for reference (not sent on the wire — bytes go). */
  license: License;
  /** Pre-encoded license bytes; sent in every outbound handshake. */
  licenseBytes: Uint8Array;
  /** Holder's self-declared BCA; matched by the peer against license.pubkey. */
  bca: string;
}

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

export interface WsPeerConnectionConfig {
  role: "dialer" | "listener";
  localIdentity: LocalIdentity;
  verifier: Verifier;
  /** Called on incoming peer pubkey to derive the expected BCA. */
  deriveBcaFromPubkey: (pubkey: Uint8Array) => Promise<string>;
  /** Optional policy gate — e.g. reject dev-issuer in production. */
  isAcceptableIssuer?: (issuerPubkey: Uint8Array) => boolean;

  /** Injected: write framed bytes to the socket. */
  sendBytes: (bytes: Uint8Array) => void;
  /** Injected: close the socket (graceful if possible). */
  closeSocket: (code?: number, reason?: string) => void;

  onAuthenticated?: (conn: WsPeerConnection) => void;
  onFrame?: (
    conn: WsPeerConnection,
    frame: SessionEnvelopeFrame | HeartbeatFrame,
  ) => void;
  onClose?: (conn: WsPeerConnection, reason?: string) => void;

  /** How long we wait for a valid peer handshake. Defaults to 10s. */
  handshakeTimeoutMs?: number;
  log?: (tag: string, msg: string) => void;
}

// ---------------------------------------------------------------------------
// WsPeerConnection
// ---------------------------------------------------------------------------

export class WsPeerConnection {
  readonly role: "dialer" | "listener";
  private readonly cfg: WsPeerConnectionConfig;
  private state: ConnectionState = "authenticating";
  private peerBcaValue?: string;
  private peerPubkeyValue?: Uint8Array;
  private handshakeTimer?: ReturnType<typeof setTimeout>;

  constructor(cfg: WsPeerConnectionConfig) {
    this.cfg = cfg;
    this.role = cfg.role;
  }

  // ── state accessors ───────────────────────────────────────

  get currentState(): ConnectionState {
    return this.state;
  }

  get peerBca(): string | undefined {
    return this.peerBcaValue;
  }

  get peerPubkey(): Uint8Array | undefined {
    return this.peerPubkeyValue;
  }

  // ── lifecycle ─────────────────────────────────────────────

  /**
   * Kick off the handshake — send our LicenseHandshakeFrame. Call this
   * from the socket's `open` event (dialer) or `open` handler (listener).
   */
  async start(): Promise<void> {
    if (this.state !== "authenticating") return;

    const frame = await buildHandshakeFrame({
      signer: this.cfg.localIdentity.signer,
      licenseBytes: this.cfg.localIdentity.licenseBytes,
      claimedBca: this.cfg.localIdentity.bca,
    });
    this.writeFrame(frame);

    const timeout = this.cfg.handshakeTimeoutMs ?? 10_000;
    this.handshakeTimer = setTimeout(() => {
      if (this.state === "authenticating") {
        this.log("handshake", "timeout");
        this.failHandshake(4001, "handshake-timeout");
      }
    }, timeout);
  }

  /**
   * Wrap an incoming byte stream — decode and dispatch.
   */
  async handleBytes(bytes: Uint8Array): Promise<void> {
    if (this.state === "closed" || this.state === "closing") return;

    let frame: Frame;
    try {
      frame = decodeFrame(bytes);
    } catch (e) {
      this.log("decode", `malformed frame: ${(e as Error).message}`);
      this.failHandshake(4002, "malformed-frame");
      return;
    }

    await this.handleFrame(frame);
  }

  /**
   * Called by the transport when the socket closes for any reason.
   * Idempotent — safe to call multiple times.
   */
  handleSocketClose(reason?: string): void {
    if (this.state === "closed") return;
    this.state = "closed";
    if (this.handshakeTimer) clearTimeout(this.handshakeTimer);
    this.cfg.onClose?.(this, reason);
  }

  /**
   * Send a frame on this connection. Only valid when authenticated;
   * during `authenticating` the only outbound traffic is the handshake
   * (already handled by `start()`).
   */
  sendFrame(frame: Frame): void {
    if (this.state !== "authenticated") {
      throw new Error(
        `cannot send ${frame.kind} in state ${this.state}`,
      );
    }
    this.writeFrame(frame);
  }

  /**
   * Gracefully close. Sends a `bye` then closes the socket.
   */
  close(reason = "local-close"): void {
    if (this.state === "closed" || this.state === "closing") return;
    const wasAuth = this.state === "authenticated";
    this.state = "closing";
    if (this.handshakeTimer) clearTimeout(this.handshakeTimer);
    if (wasAuth) {
      try {
        this.writeFrame({ kind: FRAME_KIND.GOODBYE, reason });
      } catch {
        /* socket already torn */
      }
    }
    this.cfg.closeSocket(1000, reason);
  }

  // ── internal ──────────────────────────────────────────────

  private async handleFrame(frame: Frame): Promise<void> {
    if (this.state === "authenticating") {
      if (frame.kind !== FRAME_KIND.LICENSE_HANDSHAKE) {
        this.log("handshake", `unexpected ${frame.kind} before auth`);
        this.failHandshake(4003, "unexpected-frame");
        return;
      }
      const verdict = await verifyHandshakeFrame(frame, {
        verifier: this.cfg.verifier,
        deriveBcaFromPubkey: this.cfg.deriveBcaFromPubkey,
        isAcceptableIssuer: this.cfg.isAcceptableIssuer,
      });
      if (!verdict.ok) {
        this.log("handshake", `rejected: ${verdict.reason}`);
        this.failHandshake(4004, `handshake-${verdict.reason}`);
        return;
      }
      this.peerBcaValue = verdict.peerBca;
      this.peerPubkeyValue = verdict.peerPubkey;
      this.state = "authenticated";
      if (this.handshakeTimer) clearTimeout(this.handshakeTimer);
      this.log("handshake", `authenticated peer ${verdict.peerBca}`);
      this.cfg.onAuthenticated?.(this);
      return;
    }

    // authenticated
    if (frame.kind === FRAME_KIND.LICENSE_HANDSHAKE) {
      // Unexpected: peer sent a second handshake. Ignore — could be a
      // retry on their side; dropping is safe.
      return;
    }
    if (
      frame.kind === FRAME_KIND.SESSION_ENVELOPE ||
      frame.kind === FRAME_KIND.HEARTBEAT
    ) {
      this.cfg.onFrame?.(this, frame);
      return;
    }
    if (frame.kind === FRAME_KIND.GOODBYE) {
      this.close(frame.reason ?? "peer-goodbye");
      return;
    }
  }

  private failHandshake(code: number, reason: string): void {
    if (this.state === "closed" || this.state === "closing") return;
    this.state = "closing";
    if (this.handshakeTimer) clearTimeout(this.handshakeTimer);
    this.cfg.closeSocket(code, reason);
  }

  private writeFrame(frame: Frame): void {
    this.cfg.sendBytes(encodeFrame(frame));
  }

  private log(tag: string, msg: string): void {
    this.cfg.log?.(tag, `[${this.role}] ${msg}`);
  }
}

```
