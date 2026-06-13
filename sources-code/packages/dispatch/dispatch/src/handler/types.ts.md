---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/dispatch/dispatch/src/handler/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.517288+00:00
---

# packages/dispatch/dispatch/src/handler/types.ts

```ts
/**
 * D-O11 phase O11b — handler types.
 *
 * The dispatch handler is payload-agnostic. Each receiving extension
 * registers an `AcceptHandler` keyed by the canonical payload-type
 * name (e.g. `re-desk.maintenance-request.v1`). When a dispatch
 * envelope arrives addressed to this brain's hat, the handler:
 *
 *   1. verifies the cert chain (transport-layer; the SignedBundle
 *      receive seam at `runtime/semantos-brain/src/transport/signed_bundle.zig`
 *      does this in production);
 *   2. authenticates the originating hat via the envelope's signedBy
 *      cert chain;
 *   3. checks the K3 hat-isolation gate — the addressed `toHat` must
 *      be a hat this brain is configured to accept dispatches under;
 *   4. checks K1 — the envelope's envelopeId must not have been
 *      previously processed (replay protection);
 *   5. routes the payload to the registered AcceptHandler for the
 *      payloadType;
 *   6. returns the handler's `dispatch.accepted.v1` patch (or a typed
 *      failure that the caller surfaces back to the originator).
 *
 * The K1-EARLY surface — chapter 29 §"Linearity of the envelope
 * itself" — is honoured: if NO accept handler is registered for the
 * payload type, the handler refuses to materialise. The originating
 * brain's caller learns at envelope-creation time (because the
 * receiving brain echoes a `payload_type_unsupported` failure) and
 * the originator's MaintenanceRequest stays in `draft` state. The
 * envelope cannot be silently dropped — the substrate refuses to
 * commit.
 */

import type {
  ConsumedCellSet,
  KernelGateFailure,
  Result,
} from '@semantos/oddjobz';
import type {
  DispatchAccepted,
  DispatchEnvelope,
} from '../cell-types/index.js';
import type { OddjobzHat } from '@semantos/oddjobz';

/**
 * The shape an accept handler returns when a payload is successfully
 * materialised in the receiving extension's substrate.
 */
export interface AcceptOutput {
  readonly localCellId: string;
  readonly localCellType: string;
  /** Hat-id that authored the local materialisation. */
  readonly acceptedByHat: string;
  /** ISO-8601 acceptance timestamp. */
  readonly acceptedAt: string;
}

/**
 * Failure shape distinct from `KernelGateFailure` because the dispatch
 * layer has its own failure modes (unknown payload type, envelope
 * already processed, hat-mismatch routing). The `kind` discriminator
 * is the routing label downstream callers reason about.
 */
export interface DispatchHandlerFailure {
  readonly kind:
    | 'payload_type_unsupported'
    | 'envelope_replay'
    | 'hat_mismatch'
    | 'cert_chain_invalid'
    | 'accept_handler_threw'
    | 'envelope_validation_failed';
  readonly message: string;
  readonly envelopeId?: string;
  readonly payloadType?: string;
}

/**
 * Receiving brain's local context for an accept-handler invocation.
 * The handler decodes the payload (already-canonical-encoded bytes
 * from envelope.payload) and emits an `AcceptOutput`. Throwing is
 * acceptable; the dispatch handler turns it into an
 * `accept_handler_threw` failure.
 */
export interface AcceptHandlerContext {
  readonly envelope: DispatchEnvelope;
  /** Decoded inner payload bytes (canonical encoding). */
  readonly payloadBytes: Uint8Array;
  /** The receiving hat for this dispatch. */
  readonly receivingHat: OddjobzHat;
  /** Wall-clock for timestamp stamping. */
  readonly nowIso: string;
  /**
   * The receiving brain's K1 substrate stub — the dispatch handler
   * adds the envelopeId to this set BEFORE the accept handler runs,
   * so a recursive duplicate-arrival is rejected.
   */
  readonly consumed: ConsumedCellSet;
}

export type AcceptHandlerFn = (
  ctx: AcceptHandlerContext,
) => Promise<AcceptOutput> | AcceptOutput;

/**
 * Registry of accept-handlers keyed by payloadType. Receiving
 * extensions register their handlers at brain boot.
 */
export interface AcceptHandlerRegistry {
  readonly register: (
    payloadType: string,
    handler: AcceptHandlerFn,
  ) => void;
  readonly get: (payloadType: string) => AcceptHandlerFn | undefined;
  readonly registeredTypes: () => readonly string[];
}

/**
 * Re-export oddjobz's Result + KernelGateFailure shapes so consumers
 * don't need to reach into oddjobz for error union types.
 */
export type { ConsumedCellSet, KernelGateFailure, Result };
export type { DispatchAccepted, DispatchEnvelope, OddjobzHat };

```
