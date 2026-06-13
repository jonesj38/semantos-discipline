---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/ws-node-adapter/src/adapter/envelope-codec.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.335062+00:00
---

# runtime/ws-node-adapter/src/adapter/envelope-codec.ts

```ts
/**
 * adapter/envelope-codec.ts — pure envelope build / sign / verify.
 *
 * Separated from the lifecycle/registry layer so it's testable in
 * isolation: feed in a `PublishableObject` + signer → get a signed
 * `SessionEnvelopeFrame`; feed in a frame + verifier → get a boolean.
 *
 * No socket, no map, no mutable state. The wire-level CBOR codec
 * lives in `../codec.ts`; this module sits one layer above, dealing
 * in `SessionEnvelopeFrame` values rather than raw bytes.
 */

import type { PublishableObject } from "@semantos/protocol-types/network";
import type { Signer, Verifier } from "@semantos/session-protocol";

import { canonicalEnvelopeBytesForSigning } from "../codec.js";
import { FRAME_KIND, type SessionEnvelopeFrame } from "../types.js";

// ---------------------------------------------------------------------------
// Build + sign an outbound envelope
// ---------------------------------------------------------------------------

export interface BuildSignedEnvelopeArgs {
  signer: Signer;
  object: PublishableObject;
  topic: string;
  sessionId: string;
  seq: number;
  sentAt: number;
}

/**
 * Build a `SessionEnvelopeFrame` for an outbound publish, signing it
 * with the holder's signer over canonical bytes. Returns the frame
 * ready to hand to `WsPeerConnection.sendFrame()`.
 */
export async function buildSignedEnvelope(
  args: BuildSignedEnvelopeArgs,
): Promise<SessionEnvelopeFrame> {
  const unsigned: SessionEnvelopeFrame = {
    kind: FRAME_KIND.SESSION_ENVELOPE,
    sessionId: args.sessionId,
    topic: args.topic,
    payload: args.object.cellBytes,
    contentHash: args.object.contentHash,
    ownerCert: args.object.ownerCert,
    typeHash: args.object.typeHash,
    seq: args.seq,
    sig: new Uint8Array(0),
    sentAt: args.sentAt,
  };
  const canonical = canonicalEnvelopeBytesForSigning(unsigned);
  const sig = await args.signer.sign(canonical);
  return { ...unsigned, sig };
}

// ---------------------------------------------------------------------------
// Verify an inbound envelope's per-envelope signature
// ---------------------------------------------------------------------------

/**
 * Re-derive canonical bytes from the received envelope and ask the
 * verifier whether `sig` was made by `peerPubkey`. Fail-closed: any
 * thrown error from the verifier is treated as `false`.
 *
 * The caller must have already authenticated the peer (i.e. holds the
 * peer's handshake-bound pubkey); this layer does not look up keys.
 */
export async function verifyInboundEnvelope(
  verifier: Verifier,
  peerPubkey: Uint8Array,
  envelope: SessionEnvelopeFrame,
): Promise<boolean> {
  const canonical = canonicalEnvelopeBytesForSigning(envelope);
  try {
    return await verifier.verify(peerPubkey, canonical, envelope.sig);
  } catch {
    // Fail-closed: a verifier that throws is indistinguishable from a
    // bad signature for this layer's purposes. Caller logs.
    return false;
  }
}

```
