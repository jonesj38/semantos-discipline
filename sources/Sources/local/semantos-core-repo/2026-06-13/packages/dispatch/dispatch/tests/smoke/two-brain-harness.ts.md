---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/dispatch/dispatch/tests/smoke/two-brain-harness.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.513823+00:00
---

# packages/dispatch/dispatch/tests/smoke/two-brain-harness.ts

```ts
/**
 * D-O11 phase O11c — two-brain test harness.
 *
 * Stands up two in-process "brains" — a PM brain running the
 * re-desk-stub extension, and a tradie brain running the oddjobz
 * extension. They communicate via an `InMemoryBundleTransport`
 * that simulates the SignedBundle mesh wire (D-W1 Phase 4).
 *
 * The harness is what the smoke tests use to drive the cross-vertical
 * federation flow end-to-end:
 *
 *   pmBrain.dispatch(maintenanceRequest)
 *     -> transport.send(envelope)
 *        -> tradieBrain.processDispatchEnvelope(envelope)
 *           -> tradie's accept-handler materialises an oddjobz Job
 *           -> emits dispatch.accepted.v1 via transport
 *              -> pmBrain.processAcceptance(accepted)
 *                 -> advances MaintenanceRequest from dispatched → accepted
 *
 *   tradieBrain.completeJob(jobId)
 *     -> emits dispatch.completion.v1 via transport
 *        -> pmBrain.processCompletion(completion)
 *           -> advances MaintenanceRequest accepted → completed → invoiced
 *
 * The harness does NOT model real brain dispatchers — that's an order
 * of magnitude more setup than the smoke test needs. What it models
 * is the SAME shape: each brain owns a (consumed-set, hat, accept-
 * handler-registry) tuple and routes inbound bundles via the
 * dispatch handler. The substitution from in-memory to
 * SignedBundle-mesh is "swap the transport; everything above
 * stays" — exactly the architectural seam D-W1 Phase 4 was
 * designed to expose.
 */

import { buildHat, type OddjobzHat, makeConsumedCellSet } from '@semantos/oddjobz';
import {
  capDispatch,
  capQuote,
  capInvoice,
  capClose,
  capWriteCustomer,
  mintCapabilityCell,
  type PresentedCap,
} from '@semantos/oddjobz';
import {
  jobTransition,
  genesisJobLead,
  type ConsumedCellSet,
} from '@semantos/oddjobz';
import {
  capDispatchReDesk,
  mintReDeskCapability,
  genesisDraft,
  maintenanceRequestTransition,
  type MaintenanceRequest,
} from '@semantos/re-desk-stub';
import {
  bytesToHex,
  dispatchEnvelopeCellType,
  dispatchAcceptedCellType,
  dispatchCompletionCellType,
  hexToBytes,
  InMemoryBundleTransport,
  makeAcceptHandlerRegistry,
  makeRollbackableConsumedCellSet,
  processDispatchEnvelope,
  type AcceptHandlerRegistry,
  type CertChainVerifier,
  type DispatchAccepted,
  type DispatchCompletion,
  type DispatchEnvelope,
  type DispatchHandlerResult,
  type RollbackableConsumedCellSet,
} from '../../src/index.js';

import type { OddjobzJob } from '@semantos/oddjobz';
import type {
  MaintenanceRequestFsmState,
} from '@semantos/re-desk-stub';
import { dispatchCompletionCellType as _completionType } from '../../src/cell-types/index.js';

/* ──────────────────────────────────────────────────────────────────────
 * Brain config + state
 * ────────────────────────────────────────────────────────────────────── */

const STABLE_PM_OWNER_ID = new Uint8Array([
  0x01, 0x70, 0x6d, 0x2d, 0x6f, 0x70, 0x65, 0x72,
  0x61, 0x74, 0x6f, 0x72, 0x2d, 0x69, 0x64, 0x21,
]);
const STABLE_TRADIE_OWNER_ID = new Uint8Array([
  0x02, 0x74, 0x72, 0x61, 0x64, 0x69, 0x65, 0x2d,
  0x6f, 0x70, 0x65, 0x72, 0x61, 0x74, 0x6f, 0x72,
]);

/** ContextTag for the PM operator hat. */
export const PM_HAT_CONTEXT_TAG = 0x20;
/** ContextTag for the tradie operator hat. */
export const TRADIE_HAT_CONTEXT_TAG = 0x10;
/** ContextTag for the OWNER hat (sub-hat under PM brain — for the
 *  K3 isolation test that asserts owner-financial AFFINE patches are
 *  invisible to tradie). */
export const PM_OWNER_HAT_CONTEXT_TAG = 0x21;
/** ContextTag for the tradie's MARGIN-NOTES sub-hat. */
export const TRADIE_MARGIN_HAT_CONTEXT_TAG = 0x11;

/** PM brain — runs re-desk-stub. */
export interface PmBrain {
  readonly tenantDomain: string;
  readonly hat: OddjobzHat;
  /** Per-MaintenanceRequest local state: the latest cell. */
  readonly maintenanceRequests: Map<string, MaintenanceRequest>;
  /**
   * Patches the PM hat has authored under context-tag 0x21 (owner-
   * financial AFFINE). Stored separately because they are encrypted
   * to the PM hat's contextTag and never leave the brain.
   */
  readonly ownerFinancialPatches: Array<{
    readonly requestId: string;
    readonly contextTag: number;
    readonly note: string;
  }>;
  /** PM-side dispatch.accepted.v1 patches that have flowed back. */
  readonly acceptedPatches: DispatchAccepted[];
  /** PM-side dispatch.completion.v1 patches that have flowed back. */
  readonly completionPatches: DispatchCompletion[];
  /** K1 substrate for the PM brain's MaintenanceRequest cells. */
  readonly consumed: ConsumedCellSet;
  readonly transport: InMemoryBundleTransport;
}

/** Tradie brain — runs oddjobz + dispatch. */
export interface TradieBrain {
  readonly tenantDomain: string;
  readonly hat: OddjobzHat;
  /** Per-job local state. */
  readonly jobs: Map<string, OddjobzJob>;
  /**
   * Mapping from envelope ID to the local job ID materialised from
   * that envelope. Used by `completeJob` to emit the completion
   * patch back to the originating brain via the federated envelope.
   */
  readonly envelopeIdToJobId: Map<string, string>;
  /** Margin-note AFFINE patches authored under contextTag 0x11. */
  readonly marginNotePatches: Array<{
    readonly jobId: string;
    readonly contextTag: number;
    readonly note: string;
  }>;
  /** K1 substrate for the tradie brain's Job cells. */
  readonly jobConsumed: ConsumedCellSet;
  /** K1 substrate for the dispatch envelopes the tradie processes. */
  readonly dispatchConsumed: RollbackableConsumedCellSet;
  /** Accept-handler registry. */
  readonly registry: AcceptHandlerRegistry;
  readonly transport: InMemoryBundleTransport;
}

/* ──────────────────────────────────────────────────────────────────────
 * Universe — owns the shared transport
 * ────────────────────────────────────────────────────────────────────── */

export interface FederationUniverse {
  readonly transport: InMemoryBundleTransport;
  readonly pmBrain: PmBrain;
  readonly tradieBrain: TradieBrain;
}

const ACCEPTING_VERIFIER: CertChainVerifier = () => ({ ok: true });

export interface BuildUniverseOptions {
  readonly pmTenant?: string;
  readonly tradieTenant?: string;
  readonly pmHatId?: string;
  readonly tradieHatId?: string;
  /** Override for `verifyCertChain`. Defaults to "always accept". */
  readonly verifyCertChain?: CertChainVerifier;
  /**
   * If set true, the tradie brain registers NO accept-handler for
   * the re-desk maintenance-request type. Used to test the K1
   * "envelope can't be silently dropped" enforcement: the receiving
   * brain rejects with payload_type_unsupported, the originating
   * brain's MaintenanceRequest stays in `draft`.
   */
  readonly omitTradieAcceptHandler?: boolean;
}

export function buildFederationUniverse(
  opts: BuildUniverseOptions = {},
): FederationUniverse {
  const transport = new InMemoryBundleTransport();
  const pmTenant = opts.pmTenant ?? 'acme-pm.com.au';
  const tradieTenant = opts.tradieTenant ?? 'oddjobtodd.info';
  const pmHatId = opts.pmHatId ?? 'pm-alice';
  const tradieHatId = opts.tradieHatId ?? 'tradie-todd';

  const pmHat = buildHat({
    hatId: pmHatId,
    contextTag: PM_HAT_CONTEXT_TAG,
    principal: 'operator',
    facetId: `${pmTenant}-${pmHatId}-facet`,
  });
  const tradieHat = buildHat({
    hatId: tradieHatId,
    contextTag: TRADIE_HAT_CONTEXT_TAG,
    principal: 'operator',
    facetId: `${tradieTenant}-${tradieHatId}-facet`,
  });

  /* ── PM brain ── */
  const pmConsumed = makeConsumedCellSet();
  const pmAccepted: DispatchAccepted[] = [];
  const pmCompletions: DispatchCompletion[] = [];
  const pmMaintenanceRequests = new Map<string, MaintenanceRequest>();
  const pmOwnerPatches: PmBrain['ownerFinancialPatches'] = [];

  const pmBrain: PmBrain = {
    tenantDomain: pmTenant,
    hat: pmHat,
    maintenanceRequests: pmMaintenanceRequests,
    ownerFinancialPatches: pmOwnerPatches,
    acceptedPatches: pmAccepted,
    completionPatches: pmCompletions,
    consumed: pmConsumed,
    transport,
  };

  // PM subscribes for inbound acceptances + completions on its own hat.
  transport.registerReceiver(pmTenant, pmHatId, async (env, payloadBytes) => {
    if (env.payloadType === 'dispatch.accepted.v1') {
      const accepted = dispatchAcceptedCellType.unpack(payloadBytes);
      pmAccepted.push(accepted);
      // Advance the corresponding MaintenanceRequest dispatched → accepted
      const found = findRequestByEnvelope(pmMaintenanceRequests, accepted.envelopeId);
      if (found && found.state === 'dispatched') {
        const r = maintenanceRequestTransition({
          cell: found,
          to: 'accepted',
          principal: 'service',
          nowIso: accepted.acceptedAt,
          consumed: pmConsumed,
          envelopeId: accepted.envelopeId,
        });
        if (r.ok) pmMaintenanceRequests.set(found.requestId, r.value.cell);
      }
    } else if (env.payloadType === 'dispatch.completion.v1') {
      const completion = dispatchCompletionCellType.unpack(payloadBytes);
      pmCompletions.push(completion);
      const found = findRequestByEnvelope(pmMaintenanceRequests, completion.envelopeId);
      if (found === undefined) return;

      // Advance: accepted → in_progress → completed → invoiced
      // Mirroring chapter 29's "the property vertical's MaintenanceRequest
      // FSM listens for RELEVANT patches on the envelope" claim.
      let cell = found;
      const advance = (
        target: MaintenanceRequestFsmState,
        ts: string,
      ): boolean => {
        if (cell.state === target) return true;
        const r = maintenanceRequestTransition({
          cell,
          to: target,
          principal: 'service',
          nowIso: ts,
          consumed: pmConsumed,
          envelopeId: completion.envelopeId,
        });
        if (!r.ok) return false;
        cell = r.value.cell;
        return true;
      };
      // Bring the cell forward through any in-between states (a
      // completion patch implies the work passed through in_progress
      // implicitly on the receiving side; PM's bookkeeping advances
      // state-by-state to record the audit trail).
      if (cell.state === 'accepted') {
        if (!advance('in_progress', completion.completedAt)) return;
      }
      if (cell.state === 'in_progress' && completion.completionKind !== 'cancelled') {
        if (!advance('completed', completion.completedAt)) return;
      }
      if (
        cell.state === 'completed' &&
        completion.completionKind === 'invoiced'
      ) {
        if (!advance('invoiced', completion.completedAt)) return;
      }
      pmMaintenanceRequests.set(cell.requestId, cell);
    }
  });

  /* ── Tradie brain ── */
  const tradieJobConsumed = makeConsumedCellSet();
  const tradieDispatchConsumed = makeRollbackableConsumedCellSet();
  const registry = makeAcceptHandlerRegistry();
  const tradieJobs = new Map<string, OddjobzJob>();
  const envelopeIdToJobId = new Map<string, string>();
  const tradieMarginPatches: TradieBrain['marginNotePatches'] = [];

  if (!opts.omitTradieAcceptHandler) {
    registry.register('re-desk.maintenance-request.v1', (ctx) => {
      // Decode the inner payload and materialise an oddjobz Job.
      // Per the §O11e clarification: the receiving handler creates a
      // Job AND a Lead with provenance="from_dispatch"; the dispatch
      // envelope IS the ratification.
      const payloadJson = new TextDecoder('utf-8', { fatal: true }).decode(
        ctx.payloadBytes,
      );
      const inner = JSON.parse(payloadJson) as {
        readonly requestId: string;
        readonly description: string;
      };
      // Use the maintenance request's UUID as the jobId — keeps the
      // cross-cell binding readable.
      const job = genesisJobLead({
        jobId: inner.requestId,
        principal: 'operator',
        presentedCap: tradieCapBytes(capWriteCustomer),
        nowIso: ctx.nowIso,
      });
      if (!job.ok) {
        throw new Error(
          `tradie genesisJobLead failed: ${job.error.kind}: ${job.error.message}`,
        );
      }
      tradieJobs.set(inner.requestId, job.value);
      envelopeIdToJobId.set(ctx.envelope.envelopeId, inner.requestId);
      return {
        localCellId: inner.requestId,
        localCellType: 'oddjobz.job.v1',
        acceptedByHat: ctx.receivingHat.hatId,
        acceptedAt: ctx.nowIso,
      };
    });
  }

  const tradieBrain: TradieBrain = {
    tenantDomain: tradieTenant,
    hat: tradieHat,
    jobs: tradieJobs,
    envelopeIdToJobId,
    marginNotePatches: tradieMarginPatches,
    jobConsumed: tradieJobConsumed,
    dispatchConsumed: tradieDispatchConsumed,
    registry,
    transport,
  };

  // Tradie subscribes for inbound envelopes addressed to its hat.
  transport.registerReceiver(
    tradieTenant,
    tradieHatId,
    async (envelope, payloadBytes) => {
      const result = await processDispatchEnvelope({
        envelope,
        payloadBytes,
        receivingHat: tradieHat,
        verifyCertChain: opts.verifyCertChain ?? ACCEPTING_VERIFIER,
        registry,
        consumed: tradieDispatchConsumed,
        nowIso: '2026-05-01T09:05:00.000Z',
      });
      if (result.ok) {
        // Wrap the dispatch.accepted.v1 patch in another envelope and
        // send it back to the originating PM hat. In production this
        // is the same SignedBundle shape; the simulation reuses the
        // dispatch.envelope.v1 cell-type as the wrapper because it
        // already carries from/to addressing and a payload-type
        // discriminant.
        const acceptanceEnv: DispatchEnvelope = {
          envelopeId: `acc-${envelope.envelopeId}`,
          fromTenant: envelope.toTenant,
          fromHat: envelope.toHat,
          toTenant: envelope.fromTenant,
          toHat: envelope.fromHat,
          payloadType: 'dispatch.accepted.v1',
          payload: bytesToHex(dispatchAcceptedCellType.pack(result.accepted)),
          signedBy: 'cert-id-of-tradie-todd-aaaabbbbccccdddd',
          createdAt: result.accepted.acceptedAt,
        };
        await transport.send(acceptanceEnv);
      }
      // Note: failure paths (payload_type_unsupported,
      // cert_chain_invalid, etc.) do NOT echo a SignedBundle response
      // back in this simulation — the originating brain learns about
      // the failure by observing the transport-delivery audit
      // (`transport.send()` returned 0 for an unaddressed envelope,
      // or the dispatchConsumed set still rejects on retry). This
      // matches the K1 surface chapter 29 calls out.
      void result;
    },
  );

  return { transport, pmBrain, tradieBrain };
}

function findRequestByEnvelope(
  store: Map<string, MaintenanceRequest>,
  envelopeId: string,
): MaintenanceRequest | undefined {
  for (const cell of store.values()) {
    if (cell.envelopeId === envelopeId) return cell;
  }
  return undefined;
}

/* ──────────────────────────────────────────────────────────────────────
 * High-level brain operations
 * ────────────────────────────────────────────────────────────────────── */

/**
 * PM creates a draft, advances `draft → dispatched`, and posts the
 * envelope. Returns the envelope (so the test can inspect it) and
 * the post-dispatch MaintenanceRequest (state = `dispatched`).
 *
 * If the receiving brain rejects (no accept-handler registered, etc.)
 * the MaintenanceRequest's local state still advances to `dispatched`
 * — the reject lands later via the transport. The K1 enforcement is
 * that the originating brain MUST roll back to `draft` on a
 * not-deliverable envelope. We surface that here by returning the
 * transport.send delivery count: 0 means it was undeliverable; the
 * caller is expected to issue a `rollback()` operation.
 *
 * For simplicity the caller can use `dispatchAndRequireDelivery()`
 * which performs the rollback automatically when delivery count is 0.
 */
export interface DispatchOutcome {
  readonly envelope: DispatchEnvelope;
  readonly maintenanceRequestAfter: MaintenanceRequest;
  readonly deliveryCount: number;
}

export async function pmDispatchMaintenanceRequest(
  pmBrain: PmBrain,
  args: {
    readonly requestId: string;
    readonly customer: string;
    readonly description: string;
    readonly tradieRef: string; // tenant#hat
    readonly nowIso: string;
  },
): Promise<DispatchOutcome> {
  const draft = genesisDraft({
    requestId: args.requestId,
    customer: args.customer,
    description: args.description,
    dispatchTo: args.tradieRef,
    nowIso: args.nowIso,
  });
  pmBrain.maintenanceRequests.set(args.requestId, draft);

  // Build the envelope.
  const [tradieTenant, tradieHat] = args.tradieRef.split('#') as [
    string,
    string,
  ];
  const envelopeId = mintEnvelopeId(args.requestId);

  // Encode the MaintenanceRequest as the inner payload. We use a
  // thin JSON encoding because the smoke test's accept-handler
  // expects to read back `requestId`/`description`. In production the
  // payload would be the canonical-encoded
  // `re-desk.maintenance-request.v1` cell bytes.
  const payloadJson = JSON.stringify({
    requestId: draft.requestId,
    customer: draft.customer,
    description: draft.description,
    dispatchTo: draft.dispatchTo,
  });
  const payloadHex = bytesToHex(new TextEncoder().encode(payloadJson));

  const envelope: DispatchEnvelope = {
    envelopeId,
    fromTenant: pmBrain.tenantDomain,
    fromHat: pmBrain.hat.hatId,
    toTenant: tradieTenant,
    toHat: tradieHat,
    payloadType: 're-desk.maintenance-request.v1',
    payload: payloadHex,
    signedBy: 'cert-id-of-pm-alice-1234567890abcdef',
    createdAt: args.nowIso,
  };

  // Advance draft → dispatched LOCAL FIRST, then post the envelope.
  // The K1 contract says the local advance is conditional on the
  // envelope being deliverable. We model it the way chapter 29
  // describes: advance optimistically, observe delivery, roll back if
  // not deliverable. The rollback happens in
  // `dispatchAndRequireDelivery` below.
  const presentedCap = pmCapBytes(capDispatchReDesk);
  const advance = maintenanceRequestTransition({
    cell: { ...draft, envelopeId },
    to: 'dispatched',
    presentedCap,
    principal: 'operator',
    nowIso: args.nowIso,
    consumed: pmBrain.consumed,
  });
  if (!advance.ok) {
    throw new Error(
      `pm draft → dispatched failed: ${advance.error.kind}: ${advance.error.message}`,
    );
  }
  pmBrain.maintenanceRequests.set(
    args.requestId,
    advance.value.cell,
  );

  const deliveryCount = await pmBrain.transport.send(envelope);
  return {
    envelope,
    maintenanceRequestAfter: advance.value.cell,
    deliveryCount,
  };
}

/**
 * Same as {@link pmDispatchMaintenanceRequest} but enforces K1: if
 * delivery is not possible (no subscriber for the addressed hat),
 * roll the MaintenanceRequest back to `draft`. This is the chapter-29
 * "envelope can't be silently dropped" contract: the originating
 * brain's FSM observes the not-deliverable signal and refuses to
 * commit the dispatch.
 *
 * The roll-back is structural — we re-create the draft cell and
 * remove the dispatched-state record. In production the K1
 * enforcement is at kernel-gate level (the cell-engine refuses the
 * transition when the receiving brain returns
 * payload_type_unsupported); here we model the same shape.
 */
export async function pmDispatchAndRequireDelivery(
  pmBrain: PmBrain,
  args: Parameters<typeof pmDispatchMaintenanceRequest>[1],
): Promise<{
  readonly outcome: DispatchOutcome;
  readonly delivered: boolean;
  readonly rolledBack: boolean;
}> {
  const outcome = await pmDispatchMaintenanceRequest(pmBrain, args);
  if (outcome.deliveryCount === 0) {
    // Roll back.
    const restoredDraft = genesisDraft({
      requestId: args.requestId,
      customer: args.customer,
      description: args.description,
      dispatchTo: args.tradieRef,
      nowIso: args.nowIso,
    });
    pmBrain.maintenanceRequests.set(args.requestId, restoredDraft);
    return { outcome, delivered: false, rolledBack: true };
  }
  return { outcome, delivered: true, rolledBack: false };
}

/**
 * Drive the tradie's local Job through the FSM and emit a
 * dispatch.completion.v1 patch back to the PM. The smoke test uses
 * this to assert that the PM's MaintenanceRequest fast-forwards
 * `accepted → completed → invoiced` on patch arrival.
 */
export async function tradieCompleteJob(
  tradieBrain: TradieBrain,
  args: {
    readonly envelopeId: string;
    readonly invoiceAmountCents: number;
    readonly nowIso: string;
    readonly originatorTenant: string;
    readonly originatorHat: string;
  },
): Promise<{ readonly job: OddjobzJob; readonly completion: DispatchCompletion }> {
  const jobId = tradieBrain.envelopeIdToJobId.get(args.envelopeId);
  if (jobId === undefined) {
    throw new Error(
      `tradieCompleteJob: no job materialised for envelopeId ${args.envelopeId}`,
    );
  }
  const lead = tradieBrain.jobs.get(jobId);
  if (lead === undefined) {
    throw new Error(`tradieCompleteJob: no job ${jobId}`);
  }

  // Drive lead → quoted → scheduled → in_progress → completed.
  let cell = lead;
  const advance = (
    to: 'quoted' | 'scheduled' | 'in_progress' | 'completed' | 'invoiced',
    cap: PresentedCap | null,
    principal: 'operator' | 'service',
  ) => {
    const r = jobTransition({
      cell,
      to,
      presentedCap: cap,
      principal,
      nowIso: args.nowIso,
      consumed: tradieBrain.jobConsumed,
    });
    if (!r.ok) {
      throw new Error(
        `tradie ${cell.status} → ${to} failed: ${r.error.kind}: ${r.error.message}`,
      );
    }
    cell = r.value.cell;
  };
  advance('quoted', tradieCapBytes(capQuote), 'operator');
  advance('scheduled', tradieCapBytes(capDispatch), 'operator');
  advance('in_progress', null, 'service');
  advance('completed', null, 'operator');
  advance('invoiced', tradieCapBytes(capInvoice), 'operator');

  tradieBrain.jobs.set(jobId, cell);

  const completion: DispatchCompletion = {
    envelopeId: args.envelopeId,
    completionKind: 'invoiced',
    completedAt: args.nowIso,
    invoiceAmountCents: args.invoiceAmountCents,
    completedByHat: tradieBrain.hat.hatId,
    note: 'Work completed; invoice attached',
  };

  // Wrap in a dispatch envelope addressed back to PM.
  const wrapEnv: DispatchEnvelope = {
    envelopeId: `cmp-${args.envelopeId}`,
    fromTenant: tradieBrain.tenantDomain,
    fromHat: tradieBrain.hat.hatId,
    toTenant: args.originatorTenant,
    toHat: args.originatorHat,
    payloadType: 'dispatch.completion.v1',
    payload: bytesToHex(dispatchCompletionCellType.pack(completion)),
    signedBy: 'cert-id-of-tradie-todd-aaaabbbbccccdddd',
    createdAt: args.nowIso,
  };
  await tradieBrain.transport.send(wrapEnv);

  return { job: cell, completion };
}

/* ──────────────────────────────────────────────────────────────────────
 * Helpers — cap presentations + envelope-id minting
 * ────────────────────────────────────────────────────────────────────── */

function pmCapBytes(cap: { readonly domainFlag: number; readonly name: string }): PresentedCap {
  if (cap.name === 'cap.re-desk.dispatch') {
    return {
      kind: 'cell',
      cell: mintReDeskCapability(capDispatchReDesk, PM_HAT_CONTEXT_TAG, STABLE_PM_OWNER_ID),
    };
  }
  // Fallback for any oddjobz cap that the PM might present (none in
  // the smoke test today, but kept for forward compatibility).
  return {
    kind: 'cell',
    cell: mintCapabilityCell(
      cap as never,
      PM_HAT_CONTEXT_TAG,
      STABLE_PM_OWNER_ID,
    ),
  };
}

function tradieCapBytes(cap: {
  readonly name: string;
  readonly domainFlag: number;
}): PresentedCap {
  // tradieCapBytes mints under the tradie's contextTag — the K3
  // cryptographic isolation gate keys against this byte.
  // capQuote, capDispatch, capInvoice, capWriteCustomer, capClose are
  // re-exports from oddjobz.
  if (cap.name === 'cap.oddjobz.quote') {
    return {
      kind: 'cell',
      cell: mintCapabilityCell(capQuote, TRADIE_HAT_CONTEXT_TAG, STABLE_TRADIE_OWNER_ID),
    };
  }
  if (cap.name === 'cap.oddjobz.dispatch') {
    return {
      kind: 'cell',
      cell: mintCapabilityCell(capDispatch, TRADIE_HAT_CONTEXT_TAG, STABLE_TRADIE_OWNER_ID),
    };
  }
  if (cap.name === 'cap.oddjobz.invoice') {
    return {
      kind: 'cell',
      cell: mintCapabilityCell(capInvoice, TRADIE_HAT_CONTEXT_TAG, STABLE_TRADIE_OWNER_ID),
    };
  }
  if (cap.name === 'cap.oddjobz.close') {
    return {
      kind: 'cell',
      cell: mintCapabilityCell(capClose, TRADIE_HAT_CONTEXT_TAG, STABLE_TRADIE_OWNER_ID),
    };
  }
  if (cap.name === 'cap.oddjobz.write_customer') {
    return {
      kind: 'cell',
      cell: mintCapabilityCell(
        capWriteCustomer,
        TRADIE_HAT_CONTEXT_TAG,
        STABLE_TRADIE_OWNER_ID,
      ),
    };
  }
  throw new Error(`tradieCapBytes: unsupported cap ${cap.name}`);
}

function mintEnvelopeId(seed: string): string {
  // Deterministic 16-byte → 8-4-4-4-12 layout from the seed string,
  // for stable test output. Real envelopes would use a UUIDv4.
  const enc = new TextEncoder().encode(`env:${seed}`);
  const bytes = new Uint8Array(16);
  for (let i = 0; i < 16; i++) bytes[i] = enc[i % enc.length] ?? 0;
  // Force version+variant nibbles so it parses as UUIDv4.
  bytes[6] = ((bytes[6] ?? 0) & 0x0f) | 0x40;
  bytes[8] = ((bytes[8] ?? 0) & 0x3f) | 0x80;
  let s = '';
  for (let i = 0; i < 16; i++) s += (bytes[i] as number).toString(16).padStart(2, '0');
  return `${s.slice(0, 8)}-${s.slice(8, 12)}-${s.slice(12, 16)}-${s.slice(16, 20)}-${s.slice(20, 32)}`;
}

/* ──────────────────────────────────────────────────────────────────────
 * AFFINE patches — the K3 hat-isolation surface
 * ────────────────────────────────────────────────────────────────────── */

/**
 * PM authors an AFFINE owner-financial patch on the envelope. The
 * patch is encrypted to the PM-OWNER hat's contextTag (0x21); a
 * different hat presenting against the patch fails the cryptographic
 * spend gate. The smoke test asserts: tradie cannot read this patch.
 */
export function pmWriteOwnerFinancialPatch(
  pmBrain: PmBrain,
  args: { readonly requestId: string; readonly note: string },
): void {
  pmBrain.ownerFinancialPatches.push({
    requestId: args.requestId,
    contextTag: PM_OWNER_HAT_CONTEXT_TAG,
    note: args.note,
  });
}

/**
 * Tradie authors an AFFINE margin-notes patch on the local Job. The
 * patch is encrypted to the tradie-MARGIN hat's contextTag (0x11); a
 * different hat (e.g. the PM hat at 0x20) cannot read it.
 */
export function tradieWriteMarginNotePatch(
  tradieBrain: TradieBrain,
  args: { readonly jobId: string; readonly note: string },
): void {
  tradieBrain.marginNotePatches.push({
    jobId: args.jobId,
    contextTag: TRADIE_MARGIN_HAT_CONTEXT_TAG,
    note: args.note,
  });
}

/**
 * Read AFFINE patches under the requesting hat's contextTag. Returns
 * only patches whose contextTag matches the reader's. Models the
 * D-O7 cryptographic K3 enforcement: patches authored under
 * contextTag=A are structurally invisible to a reader presenting as
 * contextTag=B (BKDS-derived child key cannot decrypt).
 *
 * In production, decryption-failure is the seam; here we filter at
 * read time. The harness contract is: patches "leak" to the reader
 * only if (and only if) the reader's contextTag matches the
 * authoring contextTag.
 */
export function readAffinePatchesUnderHat<P extends { readonly contextTag: number }>(
  patches: readonly P[],
  readerContextTag: number,
): readonly P[] {
  return patches.filter((p) => p.contextTag === readerContextTag);
}

void _completionType;

```
