---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/ws-node-adapter/src/codec.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.332968+00:00
---

# runtime/ws-node-adapter/src/codec.ts

```ts
/**
 * codec.ts — CBOR frame codec + canonical-bytes helpers for signing.
 *
 * Every frame on the wire is a CBOR map with a leading `kind` key that
 * dispatches the decoder. Maps (rather than positional tuples) are used
 * here so wire evolution — adding new optional fields — stays backward-
 * compatible.
 *
 * For signing we sidestep CBOR map-key-order ambiguity by using a fixed-
 * order positional tuple encoding. `canonicalEnvelopeBytesForSigning`
 * produces deterministic bytes regardless of which field happens to be
 * iterated first by the runtime.
 */

import { createHash } from "node:crypto";
import { Encoder, Decoder } from "cbor-x";
import {
  FRAME_KIND,
  type Frame,
  type LicenseHandshakeFrame,
  type SessionEnvelopeFrame,
  type HeartbeatFrame,
  type GoodbyeFrame,
} from "./types.js";

// cbor-x Encoder/Decoder — `useRecords: false` so we get plain arrays/objects
// rather than cbor-x's tagged record format (critical for interop).
const encoder = new Encoder({ useRecords: false });
const decoder = new Decoder({ useRecords: false });

// ---------------------------------------------------------------------------
// encodeFrame
// ---------------------------------------------------------------------------

/**
 * Encode a `Frame` union value to CBOR bytes ready to send on the wire.
 */
export function encodeFrame(frame: Frame): Uint8Array {
  return new Uint8Array(encoder.encode(frame));
}

// ---------------------------------------------------------------------------
// decodeFrame
// ---------------------------------------------------------------------------

/**
 * Decode CBOR bytes into a validated `Frame`. Throws with a
 * `"malformed frame:"` prefix on any shape violation, and
 * `"unknown frame kind:"` on an unrecognised `kind` discriminator.
 */
export function decodeFrame(bytes: Uint8Array): Frame {
  let decoded: unknown;
  try {
    decoded = decoder.decode(bytes);
  } catch (e) {
    throw new Error(`malformed frame: ${(e as Error).message}`);
  }

  if (!isPlainObject(decoded)) {
    throw new Error(`malformed frame: expected CBOR map, got ${typeof decoded}`);
  }

  const kind = (decoded as { kind?: unknown }).kind;
  switch (kind) {
    case FRAME_KIND.LICENSE_HANDSHAKE:
      return decodeLicenseHandshake(decoded as Record<string, unknown>);
    case FRAME_KIND.SESSION_ENVELOPE:
      return decodeSessionEnvelope(decoded as Record<string, unknown>);
    case FRAME_KIND.HEARTBEAT:
      return decodeHeartbeat(decoded as Record<string, unknown>);
    case FRAME_KIND.GOODBYE:
      return decodeGoodbye(decoded as Record<string, unknown>);
    default:
      throw new Error(`unknown frame kind: ${String(kind)}`);
  }
}

function decodeLicenseHandshake(
  raw: Record<string, unknown>,
): LicenseHandshakeFrame {
  return {
    kind: FRAME_KIND.LICENSE_HANDSHAKE,
    license: toUint8(raw.license, "license"),
    sig: toUint8(raw.sig, "sig"),
    challenge: toUint8(raw.challenge, "challenge"),
    claimedBca: toString(raw.claimedBca, "claimedBca"),
  };
}

function decodeSessionEnvelope(
  raw: Record<string, unknown>,
): SessionEnvelopeFrame {
  return {
    kind: FRAME_KIND.SESSION_ENVELOPE,
    sessionId: toString(raw.sessionId, "sessionId"),
    topic: toString(raw.topic, "topic"),
    payload: toUint8(raw.payload, "payload"),
    contentHash: toString(raw.contentHash, "contentHash"),
    ownerCert: toString(raw.ownerCert, "ownerCert"),
    typeHash: toString(raw.typeHash, "typeHash"),
    seq: toNumber(raw.seq, "seq"),
    sig: toUint8(raw.sig, "sig"),
    sentAt: toNumber(raw.sentAt, "sentAt"),
  };
}

function decodeHeartbeat(raw: Record<string, unknown>): HeartbeatFrame {
  return {
    kind: FRAME_KIND.HEARTBEAT,
    at: toNumber(raw.at, "at"),
    peerBca: toString(raw.peerBca, "peerBca"),
  };
}

function decodeGoodbye(raw: Record<string, unknown>): GoodbyeFrame {
  const out: GoodbyeFrame = { kind: FRAME_KIND.GOODBYE };
  if (raw.reason !== undefined && raw.reason !== null) {
    out.reason = toString(raw.reason, "reason");
  }
  return out;
}

// ---------------------------------------------------------------------------
// canonicalEnvelopeBytesForSigning
// ---------------------------------------------------------------------------

/**
 * Deterministic byte representation of a SessionEnvelopeFrame with the
 * `sig` field omitted. The sender signs these bytes; the recipient
 * re-computes the same bytes from the received frame and verifies.
 *
 * Wire format for signing (fixed-order tuple):
 *
 *   [ sessionId, topic, payload, contentHash, ownerCert, typeHash, seq, sentAt ]
 */
export function canonicalEnvelopeBytesForSigning(
  env: SessionEnvelopeFrame,
): Uint8Array {
  const tuple = [
    env.sessionId,
    env.topic,
    env.payload,
    env.contentHash,
    env.ownerCert,
    env.typeHash,
    env.seq,
    env.sentAt,
  ];
  return new Uint8Array(encoder.encode(tuple));
}

// ---------------------------------------------------------------------------
// handshakeSigPayload
// ---------------------------------------------------------------------------

/**
 * Build the handshake signature payload: `challenge || sha256(licenseBytes)`.
 *
 * The returned 64-byte buffer is what `Signer.sign()` takes — the Signer
 * seam internally SHA-256s before applying ECDSA, so the on-wire sig is
 * ultimately over `sha256(challenge || sha256(licenseBytes))`.
 */
export function handshakeSigPayload(
  challenge: Uint8Array,
  licenseBytes: Uint8Array,
): Uint8Array {
  const licenseHash = createHash("sha256").update(licenseBytes).digest();
  const out = new Uint8Array(challenge.length + 32);
  out.set(challenge, 0);
  out.set(licenseHash, challenge.length);
  return out;
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

function isPlainObject(x: unknown): x is Record<string, unknown> {
  return x !== null && typeof x === "object" && !Array.isArray(x);
}

function toUint8(x: unknown, field: string): Uint8Array {
  if (x instanceof Uint8Array) {
    // Buffer is a Uint8Array subclass — normalise so `instanceof Uint8Array`
    // and downstream comparisons are predictable.
    return x.constructor === Uint8Array ? x : new Uint8Array(x);
  }
  throw new Error(
    `malformed frame: field "${field}" expected byte string, got ${typeof x}`,
  );
}

function toString(x: unknown, field: string): string {
  if (typeof x !== "string") {
    throw new Error(
      `malformed frame: field "${field}" expected string, got ${typeof x}`,
    );
  }
  return x;
}

function toNumber(x: unknown, field: string): number {
  if (typeof x !== "number") {
    throw new Error(
      `malformed frame: field "${field}" expected number, got ${typeof x}`,
    );
  }
  return x;
}

```
