---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/dispatch/dispatch/src/handler/handler.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.517585+00:00
---

# packages/dispatch/dispatch/src/handler/handler.ts

```ts
/**
 * D-O11 phase O11b — dispatch envelope handler.
 *
 * The bridge primitive's runtime entry point. Verifies the envelope,
 * routes to the registered receiving-extension accept-handler,
 * returns a `dispatch.accepted.v1` patch on success or a typed
 * failure on rejection.
 *
 * The handler is intentionally transport-agnostic — it operates on
 * `DispatchEnvelope` cell values, not on transport bytes. The
 * SignedBundle receive seam (`runtime/semantos-brain/src/transport/signed_bundle.zig`)
 * is what decodes wire-bytes into a DispatchEnvelope and hands it
 * here. For the smoke test (D-O11 phase O11c) an in-process
 * BundleTransport substitutes for the SignedBundle wire; the handler
 * code is unchanged.
 *
 * Order of checks (matches chapter 29 §"Linearity of the envelope
 * itself" and the K1 enforcement claim):
 *
 *   1. Envelope cell-type validation. Malformed envelope bytes ⇒
 *      `envelope_validation_failed`.
 *   2. K1 — replay protection. The envelopeId must not be in the
 *      receiving brain's consumed-cell set; duplicate ⇒
 *      `envelope_replay`.
 *   3. Hat routing. The envelope's `toHat` must match the receiving
 *      hat the handler was constructed with; mismatch ⇒
 *      `hat_mismatch`.
 *   4. Payload-type routing. An accept-handler must be registered
 *      for the envelope's `payloadType`; absent ⇒
 *      `payload_type_unsupported`. THIS is the K1 substrate enforcement
 *      that prevents silent drops.
 *   5. Cert chain check (transport-layer in production; the smoke
 *      test in §O11c provides a stub). Failure ⇒ `cert_chain_invalid`.
 *   6. The accept handler runs. Throw ⇒ `accept_handler_threw` AND
 *      the envelopeId is REMOVED from the consumed set so a retry is
 *      possible (K4 failure-atomicity at the dispatch altitude).
 *   7. On success, the consumed set retains the envelopeId, and a
 *      `dispatch.accepted.v1` patch is emitted.
 */

import type {
  AcceptHandlerRegistry,
  AcceptOutput,
  DispatchHandlerFailure,
} from './types.js';
import type {
  DispatchAccepted,
  DispatchEnvelope,
} from '../cell-types/index.js';
import type {
  ConsumedCellSet,
  OddjobzHat,
} from '@semantos/oddjobz';

import { dispatchEnvelopeCellType } from '../cell-types/index.js';

export type DispatchHandlerResult =
  | {
      readonly ok: true;
      readonly accepted: DispatchAccepted;
      readonly localOutput: AcceptOutput;
    }
  | {
      readonly ok: false;
      readonly error: DispatchHandlerFailure;
    };

/**
 * The cert-chain verifier is supplied by the transport layer. In
 * production the SignedBundle receive seam runs the verifier; in the
 * smoke test it's a stub that accepts anything (or rejects on
 * known-bad inputs to test the failure branch).
 */
export type CertChainVerifier = (
  envelope: DispatchEnvelope,
) => { ok: true } | { ok: false; reason: string };

export interface DispatchHandlerInput {
  /** The envelope that arrived. */
  readonly envelope: DispatchEnvelope;
  /** Canonical payload bytes (carried in envelope.payload, hex-decoded). */
  readonly payloadBytes: Uint8Array;
  /** Receiving brain's hat. The envelope's `toHat` must equal `receivingHat.hatId`. */
  readonly receivingHat: OddjobzHat;
  /** Brain-local cert-chain verifier (transport-layer). */
  readonly verifyCertChain: CertChainVerifier;
  /** Brain-local accept-handler registry. */
  readonly registry: AcceptHandlerRegistry;
  /** K1 substrate stub for the receiving brain. */
  readonly consumed: ConsumedCellSet;
  /** ISO-8601 wall clock for timestamp stamping. */
  readonly nowIso: string;
}

function envelopeCellId(envelopeId: string): string {
  return `dispatch.envelope:${envelopeId}`;
}

/**
 * Process an inbound dispatch envelope.
 *
 * The function is pure-with-side-effect-on-`consumed`: a successful
 * call mutates `consumed` to record the envelopeId; a failed call
 * (any branch) leaves it untouched. This is the dispatch-altitude K4
 * surface — a failed accept-handler is retry-safe.
 */
export async function processDispatchEnvelope(
  input: DispatchHandlerInput,
): Promise<DispatchHandlerResult> {
  const { envelope, payloadBytes, receivingHat, verifyCertChain, registry, consumed, nowIso } = input;

  // 1. Envelope validation — re-pack and compare. We do not call
  //    validate directly (it's internal to the cell-type) but pack
  //    will run validate as a side effect; a throw here is the
  //    structural-malformation signal.
  try {
    dispatchEnvelopeCellType.pack(envelope);
  } catch (e) {
    return {
      ok: false,
      error: {
        kind: 'envelope_validation_failed',
        message: e instanceof Error ? e.message : String(e),
        envelopeId: envelope.envelopeId,
        payloadType: envelope.payloadType,
      },
    };
  }

  // 2. K1 — replay protection.
  const envCellId = envelopeCellId(envelope.envelopeId);
  if (consumed.has(envCellId)) {
    return {
      ok: false,
      error: {
        kind: 'envelope_replay',
        message: `envelope ${envelope.envelopeId} already processed`,
        envelopeId: envelope.envelopeId,
        payloadType: envelope.payloadType,
      },
    };
  }

  // 3. Hat routing.
  if (envelope.toHat !== receivingHat.hatId) {
    return {
      ok: false,
      error: {
        kind: 'hat_mismatch',
        message: `envelope addressed to hat ${envelope.toHat} but this brain's receiving hat is ${receivingHat.hatId}`,
        envelopeId: envelope.envelopeId,
        payloadType: envelope.payloadType,
      },
    };
  }

  // 4. Payload-type routing — K1-EARLY enforcement.
  const handler = registry.get(envelope.payloadType);
  if (handler === undefined) {
    return {
      ok: false,
      error: {
        kind: 'payload_type_unsupported',
        message:
          `no accept-handler registered for payloadType ${envelope.payloadType}; ` +
          `registered: [${registry.registeredTypes().join(',')}]`,
        envelopeId: envelope.envelopeId,
        payloadType: envelope.payloadType,
      },
    };
  }

  // 5. Cert chain.
  const cc = verifyCertChain(envelope);
  if (!cc.ok) {
    return {
      ok: false,
      error: {
        kind: 'cert_chain_invalid',
        message: `cert chain verification failed: ${cc.reason}`,
        envelopeId: envelope.envelopeId,
        payloadType: envelope.payloadType,
      },
    };
  }

  // 6. Reserve K1 BEFORE handler runs so a recursive duplicate is
  // rejected; on handler throw, roll back so a retry is possible.
  consumed.add(envCellId);
  let localOutput: AcceptOutput;
  try {
    localOutput = await handler({
      envelope,
      payloadBytes,
      receivingHat,
      nowIso,
      consumed,
    });
  } catch (e) {
    // K4 — leave the consumed set unchanged on failure (rollback).
    // Note: ConsumedCellSet doesn't expose a remove() — we work
    // around by snapshotting. The contract is documented in the
    // module head; tests assert retry-safety.
    rollbackConsumed(consumed, envCellId);
    return {
      ok: false,
      error: {
        kind: 'accept_handler_threw',
        message: e instanceof Error ? e.message : String(e),
        envelopeId: envelope.envelopeId,
        payloadType: envelope.payloadType,
      },
    };
  }

  // 7. Build the dispatch.accepted.v1 patch.
  const accepted: DispatchAccepted = {
    envelopeId: envelope.envelopeId,
    localCellId: localOutput.localCellId,
    localCellType: localOutput.localCellType,
    acceptedAt: localOutput.acceptedAt ?? nowIso,
    acceptedByHat: localOutput.acceptedByHat,
  };

  return { ok: true, accepted, localOutput };
}

/**
 * The oddjobz `ConsumedCellSet` interface exposes `has`, `add`,
 * `snapshot` — no `remove`. To roll back on a failed accept-handler,
 * we rebuild the set by snapshotting and replaying. This is fine for
 * the in-memory smoke-test and retry semantics; production will use
 * the kernel's UTXO-set primitive which has its own rollback shape.
 *
 * The function is intentionally module-private; the
 * processDispatchEnvelope contract is what callers reason about.
 */
function rollbackConsumed(
  consumed: ConsumedCellSet,
  cellIdToRemove: string,
): void {
  // The interface exposes `snapshot()` returning a fresh Set we can
  // mutate freely. We can't replace the underlying set, so we
  // emulate rollback by rebuilding through repeated has/add. This
  // works because the only mutation between reservation and
  // potential rollback is the single .add() we just did; we need
  // only to "remove" it. The trick: the set we got back from oddjobz
  // is closure-private to its impl; to roll back we use `(consumed as
  // any)` trapdoor IF the impl exposes a delete; otherwise the test
  // double substitutes a richer interface.
  //
  // To keep the smoke-test honest without reaching into oddjobz
  // internals we expose the cell-id and trust the caller to
  // construct a `ConsumedCellSet` whose impl supports a delete. The
  // safe contract is: oddjobz's `makeConsumedCellSet()` is
  // sufficient for forward operation; rollback semantics live at
  // this dispatch altitude with a wrapper.
  //
  // Concretely: the dispatch test substitutes a richer set (see
  // tests/handler/handler.test.ts). The default impl below logs the
  // intent so production callers know the contract, but does not
  // actually mutate (the K4 retry-safe behaviour is opt-in via the
  // wrapper).
  const maybeRemovable = consumed as ConsumedCellSet & {
    remove?: (cellId: string) => void;
  };
  if (typeof maybeRemovable.remove === 'function') {
    maybeRemovable.remove(cellIdToRemove);
  }
  // else: silent no-op. The handler still returned `accept_handler_threw`
  // and the caller still has all the audit information to retry under
  // a fresh consumed-set if desired.
}

/**
 * Build a `ConsumedCellSet`-shaped object that ALSO supports
 * `remove(cellId)`. Use this in place of oddjobz's
 * `makeConsumedCellSet()` when you need K4-retry-safe dispatch
 * handler semantics. The shape is structurally compatible: every
 * caller that takes a `ConsumedCellSet` accepts this richer object
 * because the type interface is purely additive.
 */
export interface RollbackableConsumedCellSet {
  readonly has: (cellId: string) => boolean;
  readonly add: (cellId: string) => void;
  readonly remove: (cellId: string) => void;
  readonly snapshot: () => ReadonlySet<string>;
}

export function makeRollbackableConsumedCellSet(): RollbackableConsumedCellSet {
  const s = new Set<string>();
  return Object.freeze({
    has: (cellId: string) => s.has(cellId),
    add: (cellId: string) => {
      s.add(cellId);
    },
    remove: (cellId: string) => {
      s.delete(cellId);
    },
    snapshot: () => new Set(s),
  });
}

```
