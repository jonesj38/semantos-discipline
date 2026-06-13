---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/state-machines/quote-fsm.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.529650+00:00
---

# cartridges/oddjobz/brain/src/state-machines/quote-fsm.ts

```ts
/**
 * D-O4 — Quote FSM.
 *
 * §O4 spells out the Job FSM in full. The Quote FSM is named in the
 * spec but its transitions are inferred from:
 *
 *   1. the cell-type's `QUOTE_STATUSES` enum
 *      (cartridges/oddjobz/brain/src/cell-types/quote.ts) — which
 *      enumerates `draft | presented | accepted | rejected | expired
 *      | superseded`;
 *   2. the spec's claim that `cap.oddjobz.quote` is spent on the
 *      sibling Job FSM's `lead → quoted` transition (which mints the
 *      Quote cell in `draft` state) — so the **gating** of the Quote
 *      lifecycle happens at the Job side. The Quote FSM internally
 *      handles `draft → presented`, `presented → accepted`,
 *      `presented → rejected` (and the `expired` / `superseded`
 *      auto-state-changes for housekeeping).
 *
 * §O4 inferred transition table (justified in the PR body):
 *
 *   | From       | To         | Cap         | Principal       |
 *   |------------|------------|-------------|-----------------|
 *   | draft      | presented  | none        | operator        |
 *   | draft      | superseded | none        | operator        |
 *   | presented  | accepted   | none        | service*        |
 *   | presented  | rejected   | none        | service*        |
 *   | presented  | expired    | none        | service         |
 *   | presented  | superseded | none        | operator        |
 *
 * (* — accepted / rejected carry the customer's signature in
 * production. At the TS-FSM altitude we model these as `service`
 * because the customer is not an operator-hat principal; the actual
 * cryptographic check is the customer cert's spend-bundle. The §O5p
 * pairing flow + customer-side helm path will refine this once
 * customer-side keys land.)
 *
 * The terminal states (`accepted`, `rejected`, `expired`,
 * `superseded`) are absorbing — no outgoing transitions.
 *
 * Reference:
 *  - docs/design/ODDJOBZ-EXTENSION-PLAN.md §O4
 *  - cartridges/oddjobz/brain/src/cell-types/quote.ts
 *  - proofs/lean/Semantos/Extensions/Oddjobz/StateMachines/QuoteFSM.lean
 */

import type { OddjobzQuote, QuoteStatus } from '../cell-types/quote.js';
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
 * Canonical Quote FSM states + transition table
 * ══════════════════════════════════════════════════════════════════════ */

export const QUOTE_FSM_STATES = [
  'draft',
  'presented',
  'accepted',
  'rejected',
  'expired',
  'superseded',
] as const;
export type QuoteFsmState = (typeof QUOTE_FSM_STATES)[number];

export function isQuoteFsmState(s: QuoteStatus): s is QuoteFsmState {
  return (QUOTE_FSM_STATES as readonly string[]).includes(s);
}

export interface QuoteTransitionSpec {
  readonly from: QuoteFsmState;
  readonly to: QuoteFsmState;
  readonly capRequired: OddjobzCapName | null;
  readonly principalKinds: readonly SigningPrincipal[];
}

export const QUOTE_TRANSITIONS: readonly QuoteTransitionSpec[] = Object.freeze([
  Object.freeze({
    from: 'draft',
    to: 'presented',
    capRequired: null,
    principalKinds: ['operator'] as const,
  }),
  Object.freeze({
    from: 'draft',
    to: 'superseded',
    capRequired: null,
    principalKinds: ['operator'] as const,
  }),
  Object.freeze({
    from: 'presented',
    to: 'accepted',
    capRequired: null,
    principalKinds: ['service'] as const,
  }),
  Object.freeze({
    from: 'presented',
    to: 'rejected',
    capRequired: null,
    principalKinds: ['service'] as const,
  }),
  Object.freeze({
    from: 'presented',
    to: 'expired',
    capRequired: null,
    principalKinds: ['service'] as const,
  }),
  Object.freeze({
    from: 'presented',
    to: 'superseded',
    capRequired: null,
    principalKinds: ['operator'] as const,
  }),
]);

export function findQuoteTransition(
  from: QuoteFsmState,
  to: QuoteFsmState,
): QuoteTransitionSpec | undefined {
  return QUOTE_TRANSITIONS.find((t) => t.from === from && t.to === to);
}

export function allValidQuoteTransitions(): ReadonlyArray<{
  readonly from: QuoteFsmState;
  readonly to: QuoteFsmState;
}> {
  return QUOTE_TRANSITIONS.map((t) => ({ from: t.from, to: t.to }));
}

/* ══════════════════════════════════════════════════════════════════════
 * Cell-id derivation
 * ══════════════════════════════════════════════════════════════════════ */

export function quoteCellId(quoteId: string, status: QuoteFsmState): string {
  return `oddjobz.quote:${quoteId}:${status}`;
}

/* ══════════════════════════════════════════════════════════════════════
 * Transition function
 * ══════════════════════════════════════════════════════════════════════ */

export interface QuoteTransitionInput {
  readonly cell: OddjobzQuote;
  readonly to: QuoteFsmState;
  readonly presentedCap?: PresentedCap | null;
  readonly principal: SigningPrincipal;
  readonly nowIso: string;
  readonly consumed: ConsumedCellSet;
  readonly sideEffect?: () => void;
}

export interface QuoteTransitionOutput {
  readonly cell: OddjobzQuote;
  readonly consumedCellId: string;
  readonly successorCellId: string;
  readonly transition: QuoteTransitionSpec;
}

export function quoteTransition(
  input: QuoteTransitionInput,
): Result<QuoteTransitionOutput, KernelGateFailure> {
  const { cell, to, presentedCap, principal, nowIso, consumed } = input;

  if (!isQuoteFsmState(cell.status)) {
    return err({
      kind: 'from_state_mismatch',
      message: `cell.status=${cell.status} is not a Quote FSM state`,
      attempted: { from: cell.status, to },
    });
  }

  const spec = findQuoteTransition(cell.status, to);
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

  const inputCellId = quoteCellId(cell.quoteId, spec.from);
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

  // Validation-required-on-cell-state fields that the cell-type's
  // `validate` checks. We respect these so successor cells round-trip.
  // `acceptedAt` / `rejectedAt` are stamped on terminal-state successors.
  let acceptedAt = cell.acceptedAt;
  let rejectedAt = cell.rejectedAt;
  if (spec.to === 'accepted' && acceptedAt === undefined) acceptedAt = nowIso;
  if (spec.to === 'rejected' && rejectedAt === undefined) rejectedAt = nowIso;

  const successor: OddjobzQuote = {
    ...cell,
    status: spec.to,
    acceptedAt,
    rejectedAt,
    updatedAt: nowIso,
  };
  consumed.add(inputCellId);

  return ok({
    cell: successor,
    consumedCellId: inputCellId,
    successorCellId: quoteCellId(cell.quoteId, spec.to),
    transition: spec,
  });
}

export function describeQuoteFailure(f: KernelGateFailure): string {
  return `[Quote FSM] ${describeFailure(f)}`;
}

```
