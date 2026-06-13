---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/ws-node-adapter/src/adapter/license-verifier.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.335611+00:00
---

# runtime/ws-node-adapter/src/adapter/license-verifier.ts

```ts
/**
 * adapter/license-verifier.ts — fail-closed envelope gate.
 *
 * Wraps `verifyInboundEnvelope` from envelope-codec.ts with the
 * peer-pubkey lookup + log-and-drop policy used by the WsNodeAdapter
 * facade. Splitting it out makes "an envelope from an unauthenticated
 * peer is dropped" trivially testable as a pure function.
 *
 * Acceptance criterion (prompt 39): "license verification fails closed
 * (rejects unsigned envelopes)" — implemented here. A frame with no
 * peerPubkey, an empty sig, or a verifier verdict of `false` all yield
 * `accept: false`. Only an explicit `true` from the verifier accepts.
 *
 * No socket, no map, no mutable state.
 */

import type { Verifier } from "@semantos/session-protocol";

import type { SessionEnvelopeFrame } from "../types.js";
import { verifyInboundEnvelope } from "./envelope-codec.js";

export interface EnvelopeGateInput {
  envelope: SessionEnvelopeFrame;
  /** The handshake-bound pubkey of the connection that delivered the frame, if any. */
  peerPubkey: Uint8Array | undefined;
}

export type EnvelopeGateVerdict =
  | { accept: true }
  | {
      accept: false;
      reason: "no-peer-pubkey" | "empty-sig" | "sig-invalid";
    };

/**
 * Decide whether to deliver an inbound envelope to local subscribers.
 *
 * Order of checks (cheapest → most expensive):
 *   1. The connection is authenticated (i.e. has a peerPubkey).
 *   2. The envelope carries a non-empty `sig`. An unsigned envelope is
 *      rejected even if the verifier would happen to return `true` for
 *      `verify(pubkey, bytes, emptySig)` (it shouldn't, but defence
 *      in depth).
 *   3. The verifier accepts the sig over canonical bytes.
 */
export async function gateInboundEnvelope(
  verifier: Verifier,
  input: EnvelopeGateInput,
): Promise<EnvelopeGateVerdict> {
  if (!input.peerPubkey) {
    return { accept: false, reason: "no-peer-pubkey" };
  }
  if (input.envelope.sig.length === 0) {
    return { accept: false, reason: "empty-sig" };
  }
  const ok = await verifyInboundEnvelope(
    verifier,
    input.peerPubkey,
    input.envelope,
  );
  return ok ? { accept: true } : { accept: false, reason: "sig-invalid" };
}

```
