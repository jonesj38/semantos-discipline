---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/re-desk-stub/src/state-machines/maintenance-request-fsm.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.539568+00:00
---

# packages/re-desk-stub/src/state-machines/maintenance-request-fsm.ts

```ts
/**
 * D-O11 phase O11a — MaintenanceRequest FSM.
 *
 * Mirrors the chapter-29 worked example state machine on the property-
 * management side:
 *
 *   ∅ → draft → dispatched → accepted → in_progress → completed →
 *               invoiced → closed
 *                 ↘
 *                  cancelled (terminal; only from dispatched / accepted)
 *
 * The `draft → dispatched` transition is the moment the dispatch
 * envelope is created; it consumes `cap.re-desk.dispatch`. From
 * `dispatched` onward the transitions fire from RELEVANT patches
 * arriving on the federated envelope (carried by the dispatch
 * extension — D-O11 phase O11b — over the SignedBundle mesh wire).
 *
 * Same K1/K2/K4 invariants pattern as the oddjobz Job FSM. The K3
 * (hat-isolation) check is a separate gate threaded through the
 * dispatch handler, not the FSM module itself; the FSM just refuses
 * a transition whose cap or principal is wrong.
 *
 * Reference:
 *   docs/textbook/29-cross-vertical-dispatch-and-federation.md
 *   docs/design/ODDJOBZ-EXTENSION-PLAN.md §3 phase O11
 *   extensions/oddjobz/src/state-machines/job-fsm.ts (the analogous
 *     FSM for the trades-vertical receiving side)
 */

import {
  assertLinear,
  checkDomainFlag,
  err,
  ok,
  type ConsumedCellSet,
  type KernelGateFailure,
  type PresentedCap,
  type Result,
  type SigningPrincipal,
} from './kernel-gate.js';

import type { ReDeskCapName } from '../capabilities.js';
import type {
  MaintenanceRequest,
  MaintenanceRequestState,
} from '../cell-types/maintenance-request.js';

/* ══════════════════════════════════════════════════════════════════════
 * FSM table
 * ══════════════════════════════════════════════════════════════════════ */

export const MAINTENANCE_REQUEST_FSM_STATES = [
  'draft',
  'dispatched',
  'accepted',
  'in_progress',
  'completed',
  'invoiced',
  'closed',
  'cancelled',
] as const;

export type MaintenanceRequestFsmState =
  (typeof MAINTENANCE_REQUEST_FSM_STATES)[number];

export interface MaintenanceRequestTransitionSpec {
  readonly from: MaintenanceRequestFsmState;
  readonly to: MaintenanceRequestFsmState;
  readonly capRequired: ReDeskCapName | null;
  readonly principalKinds: readonly SigningPrincipal[];
}

/**
 * Transition table — declaration order = chapter-29 worked-example
 * order. The `∅ → draft` row (genesis) is handled by `genesisDraft`;
 * this table covers the LINEAR-consumption transitions.
 */
export const MAINTENANCE_REQUEST_TRANSITIONS: readonly MaintenanceRequestTransitionSpec[] =
  Object.freeze([
    Object.freeze({
      from: 'draft',
      to: 'dispatched',
      capRequired: 'cap.re-desk.dispatch',
      principalKinds: ['operator'] as const,
    }),
    Object.freeze({
      from: 'dispatched',
      to: 'accepted',
      capRequired: null,
      // Service-signed because the receiving brain's dispatch handler
      // emits the `dispatch.accepted.v1` patch — the PM operator does
      // not author the accepted state directly. The patch flows over
      // the federated envelope and the PM-side dispatch subscriber
      // applies it as a service-principal transition.
      principalKinds: ['service'] as const,
    }),
    Object.freeze({
      from: 'accepted',
      to: 'in_progress',
      capRequired: null,
      principalKinds: ['service'] as const,
    }),
    Object.freeze({
      from: 'in_progress',
      to: 'completed',
      capRequired: null,
      principalKinds: ['service'] as const,
    }),
    Object.freeze({
      from: 'completed',
      to: 'invoiced',
      capRequired: null,
      principalKinds: ['service'] as const,
    }),
    Object.freeze({
      from: 'invoiced',
      to: 'closed',
      capRequired: null,
      principalKinds: ['operator'] as const,
    }),
    // Cancellation paths — `dispatched → cancelled` and
    // `accepted → cancelled`. Operator-signed because cancellation is
    // authored by the PM hat (rejecting the dispatch / withdrawing the
    // job). Ungated for v0.1; a future cap (`cap.re-desk.cancel`) could
    // tighten this.
    Object.freeze({
      from: 'dispatched',
      to: 'cancelled',
      capRequired: null,
      principalKinds: ['operator'] as const,
    }),
    Object.freeze({
      from: 'accepted',
      to: 'cancelled',
      capRequired: null,
      principalKinds: ['operator'] as const,
    }),
  ]);

export function findMaintenanceRequestTransition(
  from: MaintenanceRequestFsmState,
  to: MaintenanceRequestFsmState,
): MaintenanceRequestTransitionSpec | undefined {
  return MAINTENANCE_REQUEST_TRANSITIONS.find(
    (t) => t.from === from && t.to === to,
  );
}

export function isMaintenanceRequestFsmState(
  s: MaintenanceRequestState,
): s is MaintenanceRequestFsmState {
  return (MAINTENANCE_REQUEST_FSM_STATES as readonly string[]).includes(s);
}

/* ══════════════════════════════════════════════════════════════════════
 * Cell-id derivation
 * ══════════════════════════════════════════════════════════════════════ */

export function maintenanceRequestCellId(
  requestId: string,
  state: MaintenanceRequestFsmState,
): string {
  return `re-desk.maintenance-request:${requestId}:${state}`;
}

/* ══════════════════════════════════════════════════════════════════════
 * Transition function
 * ══════════════════════════════════════════════════════════════════════ */

export interface MaintenanceRequestTransitionInput {
  readonly cell: MaintenanceRequest;
  readonly to: MaintenanceRequestFsmState;
  readonly presentedCap?: PresentedCap | null;
  readonly principal: SigningPrincipal;
  readonly nowIso: string;
  readonly consumed: ConsumedCellSet;
  /**
   * For transitions that fire from inbound dispatch patches, the
   * envelopeId of the federated envelope. Validated against the cell's
   * `envelopeId` field; mismatch raises `from_state_mismatch`.
   */
  readonly envelopeId?: string;
}

export interface MaintenanceRequestTransitionOutput {
  readonly cell: MaintenanceRequest;
  readonly consumedCellId: string;
  readonly successorCellId: string;
  readonly transition: MaintenanceRequestTransitionSpec;
}

export function maintenanceRequestTransition(
  input: MaintenanceRequestTransitionInput,
): Result<MaintenanceRequestTransitionOutput, KernelGateFailure> {
  const { cell, to, presentedCap, principal, nowIso, consumed, envelopeId } = input;

  if (!isMaintenanceRequestFsmState(cell.state)) {
    return err({
      kind: 'from_state_mismatch',
      message: `cell.state=${cell.state} is not a canonical FSM state`,
      attempted: { from: cell.state, to },
    });
  }

  const spec = findMaintenanceRequestTransition(cell.state, to);
  if (spec === undefined) {
    return err({
      kind: 'invalid_state_transition',
      message: `no transition row for ${cell.state} → ${to}`,
      attempted: { from: cell.state, to },
    });
  }

  if (cell.state !== spec.from) {
    return err({
      kind: 'from_state_mismatch',
      message: `cell.state=${cell.state} ≠ spec.from=${spec.from}`,
      attempted: { from: cell.state, to },
    });
  }

  const inputCellId = maintenanceRequestCellId(cell.requestId, spec.from);
  const linChk = assertLinear(consumed, inputCellId);
  if (!linChk.ok) return linChk;

  if (!spec.principalKinds.includes(principal)) {
    return err({
      kind: 'bad_signing_principal',
      message: `principal=${principal} not in [${spec.principalKinds.join(',')}] for ${spec.from} → ${spec.to}`,
      expectedPrincipal: spec.principalKinds[0],
      attempted: { from: spec.from, to: spec.to },
    });
  }

  if (spec.capRequired !== null) {
    const capChk = checkDomainFlag(spec.capRequired, presentedCap ?? null);
    if (!capChk.ok) return capChk;
  }

  // Patch-driven transitions (everything past `dispatched`) require
  // the supplied envelopeId match the cell's recorded envelopeId. This
  // is what stops a stray completion patch from fast-forwarding the
  // wrong MaintenanceRequest. K1 already prevents replay; this is the
  // K2 cross-cell binding check.
  if (
    spec.from !== 'draft' &&
    cell.envelopeId !== undefined &&
    envelopeId !== undefined &&
    envelopeId !== cell.envelopeId
  ) {
    return err({
      kind: 'wrong_cap',
      message: `envelopeId mismatch for ${spec.from} → ${spec.to}: expected ${cell.envelopeId} got ${envelopeId}`,
      attempted: { from: spec.from, to: spec.to },
    });
  }

  const successor: MaintenanceRequest = {
    ...cell,
    state: spec.to,
    updatedAt: nowIso,
    ...(spec.to === 'dispatched' ? { dispatchedAt: nowIso } : {}),
    ...(spec.to === 'accepted' ? { acceptedAt: nowIso } : {}),
    ...(spec.to === 'completed' ? { completedAt: nowIso } : {}),
    ...(spec.to === 'invoiced' ? { invoicedAt: nowIso } : {}),
    ...(spec.to === 'closed' ? { closedAt: nowIso } : {}),
  };
  consumed.add(inputCellId);

  return ok({
    cell: successor,
    consumedCellId: inputCellId,
    successorCellId: maintenanceRequestCellId(cell.requestId, spec.to),
    transition: spec,
  });
}

/* ══════════════════════════════════════════════════════════════════════
 * Genesis (∅ → draft)
 * ══════════════════════════════════════════════════════════════════════ */

export interface MaintenanceRequestGenesisInput {
  readonly requestId: string;
  readonly customer: string;
  readonly description: string;
  readonly dispatchTo: string;
  readonly nowIso: string;
}

/**
 * Build a fresh MaintenanceRequest in `draft` state. Ungated — the
 * jural power exercised at the `draft → dispatched` transition is
 * what's gated; creating a draft is a private operator action that
 * doesn't yet commit to anything.
 */
export function genesisDraft(
  input: MaintenanceRequestGenesisInput,
): MaintenanceRequest {
  return {
    requestId: input.requestId,
    customer: input.customer,
    description: input.description,
    dispatchTo: input.dispatchTo,
    state: 'draft',
    createdAt: input.nowIso,
    updatedAt: input.nowIso,
  };
}

```
