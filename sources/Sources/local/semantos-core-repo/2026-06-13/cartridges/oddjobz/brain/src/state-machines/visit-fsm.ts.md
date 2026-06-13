---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/state-machines/visit-fsm.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.530264+00:00
---

# cartridges/oddjobz/brain/src/state-machines/visit-fsm.ts

```ts
/**
 * D-O4 — Visit FSM.
 *
 * Visit transitions mirror the Job FSM's `scheduled → in_progress →
 * completed` segment — a Visit is created in `scheduled` state when a
 * Job's `quoted → scheduled` transition fires (gated by
 * `cap.oddjobz.dispatch` on the Job side); the Visit's own `scheduled
 * → in_progress → completed` chain advances alongside the parent
 * Job's same-named segment.
 *
 * §O4 inferred transition table (justified in PR body):
 *
 *   | From         | To           | Cap   | Principal           |
 *   |--------------|--------------|-------|---------------------|
 *   | scheduled    | in_progress  | none  | service (clock-tick)|
 *   | scheduled    | cancelled    | none  | operator            |
 *   | in_progress  | completed    | none  | operator            |
 *   | in_progress  | cancelled    | none  | operator            |
 *
 * The terminal states (`completed`, `cancelled`) are absorbing — no
 * outgoing transitions. The §O4 spec's gating story for Visit is
 * **delegated to the Job FSM** (the dispatch cap is spent on the Job
 * side; mark-done on the Job side spends nothing). This mirror keeps
 * the Visit FSM gate-free at the cap-mint layer; K1 still applies
 * (each Visit cell consumed once into its successor).
 *
 * Reference:
 *  - docs/design/ODDJOBZ-EXTENSION-PLAN.md §O4
 *  - cartridges/oddjobz/brain/src/cell-types/visit.ts
 *  - proofs/lean/Semantos/Extensions/Oddjobz/StateMachines/VisitFSM.lean
 */

import type { OddjobzVisit, VisitStatus, VisitOutcome } from '../cell-types/visit.js';
import {
  ok,
  err,
  assertLinear,
  checkDomainFlag,
  describeFailure,
  type ConsumedCellSet,
  type KernelGateFailure,
  type OddjobzCapName,
  type PresentedCap,
  type Result,
  type SigningPrincipal,
} from './kernel-gate.js';

/* ══════════════════════════════════════════════════════════════════════
 * Canonical Visit FSM states + transition table
 * ══════════════════════════════════════════════════════════════════════ */

export const VISIT_FSM_STATES = [
  'scheduled',
  'in_progress',
  'completed',
  'cancelled',
] as const;
export type VisitFsmState = (typeof VISIT_FSM_STATES)[number];

export function isVisitFsmState(s: VisitStatus): s is VisitFsmState {
  return (VISIT_FSM_STATES as readonly string[]).includes(s);
}

export interface VisitTransitionSpec {
  readonly from: VisitFsmState;
  readonly to: VisitFsmState;
  readonly capRequired: OddjobzCapName | null;
  readonly principalKinds: readonly SigningPrincipal[];
}

export const VISIT_TRANSITIONS: readonly VisitTransitionSpec[] = Object.freeze([
  Object.freeze({
    from: 'scheduled',
    to: 'in_progress',
    capRequired: null,
    principalKinds: ['service'] as const,
  }),
  Object.freeze({
    from: 'scheduled',
    to: 'cancelled',
    capRequired: null,
    principalKinds: ['operator'] as const,
  }),
  Object.freeze({
    from: 'in_progress',
    to: 'completed',
    capRequired: null,
    principalKinds: ['operator'] as const,
  }),
  Object.freeze({
    from: 'in_progress',
    to: 'cancelled',
    capRequired: null,
    principalKinds: ['operator'] as const,
  }),
]);

export function findVisitTransition(
  from: VisitFsmState,
  to: VisitFsmState,
): VisitTransitionSpec | undefined {
  return VISIT_TRANSITIONS.find((t) => t.from === from && t.to === to);
}

export function allValidVisitTransitions(): ReadonlyArray<{
  readonly from: VisitFsmState;
  readonly to: VisitFsmState;
}> {
  return VISIT_TRANSITIONS.map((t) => ({ from: t.from, to: t.to }));
}

/* ══════════════════════════════════════════════════════════════════════
 * Cell-id derivation
 * ══════════════════════════════════════════════════════════════════════ */

export function visitCellId(visitId: string, status: VisitFsmState): string {
  return `oddjobz.visit:${visitId}:${status}`;
}

/* ══════════════════════════════════════════════════════════════════════
 * Transition function
 * ══════════════════════════════════════════════════════════════════════ */

export interface VisitTransitionInput {
  readonly cell: OddjobzVisit;
  readonly to: VisitFsmState;
  readonly presentedCap?: PresentedCap | null;
  readonly principal: SigningPrincipal;
  readonly nowIso: string;
  readonly consumed: ConsumedCellSet;
  readonly sideEffect?: () => void;
  /** When transitioning to `completed`, the outcome to stamp on the
   *  successor cell; the cell-type validator requires this. */
  readonly outcome?: VisitOutcome;
}

export interface VisitTransitionOutput {
  readonly cell: OddjobzVisit;
  readonly consumedCellId: string;
  readonly successorCellId: string;
  readonly transition: VisitTransitionSpec;
}

export function visitTransition(
  input: VisitTransitionInput,
): Result<VisitTransitionOutput, KernelGateFailure> {
  const { cell, to, presentedCap, principal, nowIso, consumed } = input;

  if (!isVisitFsmState(cell.status)) {
    return err({
      kind: 'from_state_mismatch',
      message: `cell.status=${cell.status} is not a Visit FSM state`,
      attempted: { from: cell.status, to },
    });
  }

  const spec = findVisitTransition(cell.status, to);
  if (spec === undefined) {
    return err({
      kind: 'invalid_state_transition',
      message: `no §O4 row for ${cell.status} → ${to}`,
      attempted: { from: cell.status, to },
    });
  }

  if (cell.status !== spec.from) {
    return err({
      kind: 'from_state_mismatch',
      message: `cell.status=${cell.status} ≠ spec.from=${spec.from}`,
      attempted: { from: cell.status, to },
    });
  }

  const inputCellId = visitCellId(cell.visitId, spec.from);
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

  if (input.sideEffect !== undefined) {
    try {
      input.sideEffect();
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      return err({
        kind: 'induced_io_failure',
        message: `side effect for ${spec.from} → ${spec.to} failed: ${msg}`,
        attempted: { from: spec.from, to: spec.to },
      });
    }
  }

  // Stamp outcome / actualStart / actualEnd as the cell-type validator
  // requires. The validator demands `outcome` when status is `completed`,
  // and accepts it on `cancelled` only when `outcome === 'cancelled'`.
  let actualStart = cell.actualStart;
  let actualEnd = cell.actualEnd;
  let outcome = cell.outcome;
  if (spec.to === 'in_progress' && actualStart === undefined) {
    actualStart = nowIso;
  }
  if (spec.to === 'completed') {
    if (actualEnd === undefined) actualEnd = nowIso;
    if (input.outcome !== undefined) {
      outcome = input.outcome;
    } else if (outcome === undefined) {
      outcome = 'completed';
    }
  }
  if (spec.to === 'cancelled') {
    outcome = 'cancelled';
  }

  const successor: OddjobzVisit = {
    ...cell,
    status: spec.to,
    actualStart,
    actualEnd,
    outcome,
    updatedAt: nowIso,
  };
  consumed.add(inputCellId);

  return ok({
    cell: successor,
    consumedCellId: inputCellId,
    successorCellId: visitCellId(cell.visitId, spec.to),
    transition: spec,
  });
}

export function describeVisitFailure(f: KernelGateFailure): string {
  return `[Visit FSM] ${describeFailure(f)}`;
}

```
