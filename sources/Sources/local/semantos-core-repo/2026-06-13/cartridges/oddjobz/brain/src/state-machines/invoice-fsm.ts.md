---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/state-machines/invoice-fsm.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.529053+00:00
---

# cartridges/oddjobz/brain/src/state-machines/invoice-fsm.ts

```ts
/**
 * D-O4 — Invoice FSM.
 *
 * The Invoice FSM is the cell-side mirror of the Job FSM's
 * `completed → invoiced → paid` segment. The Job FSM spends
 * `cap.oddjobz.invoice` on `completed → invoiced`, which mints the
 * Invoice cell in `draft` state. The Invoice's own lifecycle then
 * proceeds:
 *
 *   draft → sent → paid
 *
 * §O4 inferred transition table (justified in PR body):
 *
 *   | From  | To        | Cap   | Principal           |
 *   |-------|-----------|-------|---------------------|
 *   | draft | sent      | none  | operator            |
 *   | draft | cancelled | none  | operator            |
 *   | sent  | viewed    | none  | service             |
 *   | sent  | partial   | none  | service             |
 *   | sent  | paid      | none  | service             |
 *   | sent  | overdue   | none  | service             |
 *   | sent  | cancelled | none  | operator            |
 *   | viewed| partial   | none  | service             |
 *   | viewed| paid      | none  | service             |
 *   | viewed| overdue   | none  | service             |
 *   | viewed| cancelled | none  | operator            |
 *   | partial | paid    | none  | service             |
 *   | partial | overdue | none  | service             |
 *   | overdue | paid    | none  | service             |
 *   | overdue | partial | none  | service             |
 *
 * The `paid` and `cancelled` states are absorbing.
 *
 * The §O4 spec calls out specifically that:
 *
 *   - `completed → invoiced` (Job FSM) spends `cap.oddjobz.invoice`
 *     and creates the Invoice cell in `draft` state. The Invoice
 *     itself doesn't gate creation — that's the Job side.
 *   - `invoiced → paid` (Job FSM) is gateless, fired by an incoming-
 *     funds receipt (service principal). The Invoice FSM mirrors
 *     this on the cell side: `sent → paid` (or any ancestor → `paid`)
 *     is service-signed and ungated.
 *
 * The K4 acceptance test from §O4 is grounded in the Stripe webhook
 * for `sent → paid` (or equivalent ancestor → paid) — an induced HTTP
 * failure mid-transition leaves the Invoice cell byte-for-byte
 * unchanged and a retry succeeds. The `sideEffect` parameter on
 * `invoiceTransition` is the seam the test injects through.
 *
 * Reference:
 *  - docs/design/ODDJOBZ-EXTENSION-PLAN.md §O4
 *  - cartridges/oddjobz/brain/src/cell-types/invoice.ts
 *  - proofs/lean/Semantos/Extensions/Oddjobz/StateMachines/InvoiceFSM.lean
 */

import type {
  OddjobzInvoice,
  InvoiceStatus,
} from '../cell-types/invoice.js';
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
 * Canonical Invoice FSM states + transition table
 * ══════════════════════════════════════════════════════════════════════ */

export const INVOICE_FSM_STATES = [
  'draft',
  'sent',
  'viewed',
  'partial',
  'paid',
  'overdue',
  'cancelled',
] as const;
export type InvoiceFsmState = (typeof INVOICE_FSM_STATES)[number];

export function isInvoiceFsmState(s: InvoiceStatus): s is InvoiceFsmState {
  return (INVOICE_FSM_STATES as readonly string[]).includes(s);
}

export interface InvoiceTransitionSpec {
  readonly from: InvoiceFsmState;
  readonly to: InvoiceFsmState;
  readonly capRequired: OddjobzCapName | null;
  readonly principalKinds: readonly SigningPrincipal[];
}

export const INVOICE_TRANSITIONS: readonly InvoiceTransitionSpec[] = Object.freeze([
  Object.freeze({
    from: 'draft',
    to: 'sent',
    capRequired: null,
    principalKinds: ['operator'] as const,
  }),
  Object.freeze({
    from: 'draft',
    to: 'cancelled',
    capRequired: null,
    principalKinds: ['operator'] as const,
  }),
  Object.freeze({
    from: 'sent',
    to: 'viewed',
    capRequired: null,
    principalKinds: ['service'] as const,
  }),
  Object.freeze({
    from: 'sent',
    to: 'partial',
    capRequired: null,
    principalKinds: ['service'] as const,
  }),
  Object.freeze({
    from: 'sent',
    to: 'paid',
    capRequired: null,
    principalKinds: ['service'] as const,
  }),
  Object.freeze({
    from: 'sent',
    to: 'overdue',
    capRequired: null,
    principalKinds: ['service'] as const,
  }),
  Object.freeze({
    from: 'sent',
    to: 'cancelled',
    capRequired: null,
    principalKinds: ['operator'] as const,
  }),
  Object.freeze({
    from: 'viewed',
    to: 'partial',
    capRequired: null,
    principalKinds: ['service'] as const,
  }),
  Object.freeze({
    from: 'viewed',
    to: 'paid',
    capRequired: null,
    principalKinds: ['service'] as const,
  }),
  Object.freeze({
    from: 'viewed',
    to: 'overdue',
    capRequired: null,
    principalKinds: ['service'] as const,
  }),
  Object.freeze({
    from: 'viewed',
    to: 'cancelled',
    capRequired: null,
    principalKinds: ['operator'] as const,
  }),
  Object.freeze({
    from: 'partial',
    to: 'paid',
    capRequired: null,
    principalKinds: ['service'] as const,
  }),
  Object.freeze({
    from: 'partial',
    to: 'overdue',
    capRequired: null,
    principalKinds: ['service'] as const,
  }),
  Object.freeze({
    from: 'overdue',
    to: 'paid',
    capRequired: null,
    principalKinds: ['service'] as const,
  }),
  Object.freeze({
    from: 'overdue',
    to: 'partial',
    capRequired: null,
    principalKinds: ['service'] as const,
  }),
]);

export function findInvoiceTransition(
  from: InvoiceFsmState,
  to: InvoiceFsmState,
): InvoiceTransitionSpec | undefined {
  return INVOICE_TRANSITIONS.find((t) => t.from === from && t.to === to);
}

export function allValidInvoiceTransitions(): ReadonlyArray<{
  readonly from: InvoiceFsmState;
  readonly to: InvoiceFsmState;
}> {
  return INVOICE_TRANSITIONS.map((t) => ({ from: t.from, to: t.to }));
}

/* ══════════════════════════════════════════════════════════════════════
 * Cell-id derivation
 * ══════════════════════════════════════════════════════════════════════ */

export function invoiceCellId(invoiceId: string, status: InvoiceFsmState): string {
  return `oddjobz.invoice:${invoiceId}:${status}`;
}

/* ══════════════════════════════════════════════════════════════════════
 * Transition function
 * ══════════════════════════════════════════════════════════════════════ */

export interface InvoiceTransitionInput {
  readonly cell: OddjobzInvoice;
  readonly to: InvoiceFsmState;
  readonly presentedCap?: PresentedCap | null;
  readonly principal: SigningPrincipal;
  readonly nowIso: string;
  readonly consumed: ConsumedCellSet;
  readonly sideEffect?: () => void;
  /** When transitioning to `paid`, the amount paid in cents (defaults
   *  to the invoice's `amount` for full-payment paths). The cell-type
   *  validator requires `amountPaid === amount` on a `paid` cell. */
  readonly amountPaid?: number;
}

export interface InvoiceTransitionOutput {
  readonly cell: OddjobzInvoice;
  readonly consumedCellId: string;
  readonly successorCellId: string;
  readonly transition: InvoiceTransitionSpec;
}

export function invoiceTransition(
  input: InvoiceTransitionInput,
): Result<InvoiceTransitionOutput, KernelGateFailure> {
  const { cell, to, presentedCap, principal, nowIso, consumed } = input;

  if (!isInvoiceFsmState(cell.status)) {
    return err({
      kind: 'from_state_mismatch',
      message: `cell.status=${cell.status} is not an Invoice FSM state`,
      attempted: { from: cell.status, to },
    });
  }

  const spec = findInvoiceTransition(cell.status, to);
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

  const inputCellId = invoiceCellId(cell.invoiceId, spec.from);
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

  // Stamp the validator-required derived fields. The Invoice cell-type
  // requires `paidAt` + `amountPaid === amount` for `status === 'paid'`,
  // and `sentAt` for `status === 'sent'`.
  let sentAt = cell.sentAt;
  let viewedAt = cell.viewedAt;
  let paidAt = cell.paidAt;
  let amountPaid = cell.amountPaid;

  if (spec.to === 'sent' && sentAt === undefined) sentAt = nowIso;
  if (spec.to === 'viewed' && viewedAt === undefined) viewedAt = nowIso;
  if (spec.to === 'paid') {
    if (paidAt === undefined) paidAt = nowIso;
    amountPaid = input.amountPaid ?? cell.amount;
    if (amountPaid !== cell.amount) {
      return err({
        kind: 'invalid_state_transition',
        message: `paid transition requires amountPaid (${amountPaid}) === amount (${cell.amount})`,
        attempted: { from: spec.from, to: spec.to },
      });
    }
  }
  if (spec.to === 'partial') {
    amountPaid = input.amountPaid ?? cell.amountPaid ?? 0;
    if (amountPaid >= cell.amount || amountPaid < 0) {
      return err({
        kind: 'invalid_state_transition',
        message: `partial transition requires 0 <= amountPaid (${amountPaid}) < amount (${cell.amount})`,
        attempted: { from: spec.from, to: spec.to },
      });
    }
  }

  const successor: OddjobzInvoice = {
    ...cell,
    status: spec.to,
    sentAt,
    viewedAt,
    paidAt,
    amountPaid,
    updatedAt: nowIso,
  };
  consumed.add(inputCellId);

  return ok({
    cell: successor,
    consumedCellId: inputCellId,
    successorCellId: invoiceCellId(cell.invoiceId, spec.to),
    transition: spec,
  });
}

export function describeInvoiceFailure(f: KernelGateFailure): string {
  return `[Invoice FSM] ${describeFailure(f)}`;
}

```
