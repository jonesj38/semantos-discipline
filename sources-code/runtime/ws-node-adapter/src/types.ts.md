---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/ws-node-adapter/src/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.331858+00:00
---

# runtime/ws-node-adapter/src/types.ts

```ts
/**
 * Wire-envelope types for @semantos/ws-node-adapter.
 *
 * Every frame on a WsNodeAdapter connection is CBOR-encoded with a
 * leading `kind` string that dispatches the codec. Four kinds ship in
 * Phase 35B.1:
 *
 *   - license_handshake   First frame in both directions; establishes
 *                         identity + authorisation. No other frames are
 *                         accepted until handshake completes.
 *
 *   - session_envelope    Carries an opaque PublishableObject from
 *                         publish() on the sender, delivered to topic
 *                         subscribers on the recipient. Signed by the
 *                         sender over canonical bytes (codec.ts).
 *
 *   - heartbeat           Idle filler every 30s. Keeps the connection
 *                         from being killed by NAT / proxy idle timers.
 *
 *   - bye                 Graceful shutdown announcement.
 *
 * These are the ONLY TypeScript types — the wire format itself is
 * CBOR. `codec.ts` owns encode/decode. Callers never synthesise raw
 * bytes; they always hand `Frame`-typed values to `encodeFrame()`.
 */

// ---------------------------------------------------------------------------
// Frame kind discriminator
// ---------------------------------------------------------------------------

export const FRAME_KIND = {
  LICENSE_HANDSHAKE: "license_handshake",
  SESSION_ENVELOPE: "session_envelope",
  HEARTBEAT: "heartbeat",
  GOODBYE: "bye",
} as const;

export type FrameKind = (typeof FRAME_KIND)[keyof typeof FRAME_KIND];

// ---------------------------------------------------------------------------
// LicenseHandshake
// ---------------------------------------------------------------------------

/**
 * First frame of a connection, exchanged in BOTH directions (client → server
 * and server → client — the connection is bidirectional, both sides prove
 * their identity).
 *
 * `sig` is an ECDSA signature by the HOLDER's private key over
 * `challenge || sha256(licenseBytes)`. See `codec.ts::handshakeSigPayload`.
 *
 * `challenge` is 32 fresh random bytes picked by the sender per connection,
 * preventing signature caching. Real replay protection is provided by TLS
 * at the transport layer.
 *
 * `claimedBca` is the sender's self-declared BCA. Recipients should cross-
 * check this against the BCA derivable from `license.pubkey` — any
 * mismatch is `bca-mismatch` and the connection is dropped.
 */
export interface LicenseHandshakeFrame {
  kind: typeof FRAME_KIND.LICENSE_HANDSHAKE;
  /** Full encoded License cell (see `@semantos/protocol-types/license`). */
  license: Uint8Array;
  /** DER-ECDSA over `challenge || sha256(licenseBytes)`. */
  sig: Uint8Array;
  /** 32 random bytes picked fresh per connection. */
  challenge: Uint8Array;
  /** Sender's self-declared BCA, must match `license.pubkey` derivation. */
  claimedBca: string;
}

// ---------------------------------------------------------------------------
// SessionEnvelope
// ---------------------------------------------------------------------------

/**
 * Post-handshake frame carrying an object from `publish()` on the sender
 * to topic subscribers on the recipient.
 *
 * Mirrors `PublishableObject` fields with transport-level sig. The sig is
 * ECDSA over `canonicalEnvelopeBytesForSigning(env)` (see `codec.ts`),
 * keyed on the sender's holder private key — the same key that signed
 * the license handshake. `ownerCert` must match BCA-derived cert for the
 * authenticated peer; mismatches are dropped.
 */
export interface SessionEnvelopeFrame {
  kind: typeof FRAME_KIND.SESSION_ENVELOPE;
  /** Session identifier, e.g. a poker table id. */
  sessionId: string;
  /** Topic driving MulticastAdapter-style subscribe() on the recipient. */
  topic: string;
  /** Opaque cellBytes — the recipient doesn't parse them here. */
  payload: Uint8Array;
  /** SHA-256 hex of `payload`. */
  contentHash: string;
  /** BCA-derived owner cert; must match the authenticated peer. */
  ownerCert: string;
  /** SHA-256 hex of the object's semantic type. */
  typeHash: string;
  /** Monotonic per-sender sequence number. */
  seq: number;
  /** DER-ECDSA over `canonicalEnvelopeBytesForSigning(this)`. */
  sig: Uint8Array;
  /** Wall-clock send time (unix ms). */
  sentAt: number;
}

// ---------------------------------------------------------------------------
// Heartbeat
// ---------------------------------------------------------------------------

/**
 * Sent every 30s (configurable) when the connection has been idle, so NATs,
 * proxies, and load balancers don't tear it down. Unsigned — spoofed
 * heartbeats can't do anything interesting.
 */
export interface HeartbeatFrame {
  kind: typeof FRAME_KIND.HEARTBEAT;
  /** Wall-clock at the sender (unix ms). */
  at: number;
  /** Sender's authenticated BCA — recipient can sanity-check. */
  peerBca: string;
}

// ---------------------------------------------------------------------------
// Goodbye
// ---------------------------------------------------------------------------

/**
 * Optional graceful shutdown announcement. Recipients can skip auto-reconnect
 * when they see this.
 */
export interface GoodbyeFrame {
  kind: typeof FRAME_KIND.GOODBYE;
  reason?: string;
}

// ---------------------------------------------------------------------------
// Union
// ---------------------------------------------------------------------------

export type Frame =
  | LicenseHandshakeFrame
  | SessionEnvelopeFrame
  | HeartbeatFrame
  | GoodbyeFrame;

/**
 * Connection states in the per-peer state machine. Frames other than
 * `license_handshake` are dropped while not `authenticated`.
 */
export type ConnectionState =
  | "connecting"
  | "authenticating"
  | "authenticated"
  | "closing"
  | "closed";

```
