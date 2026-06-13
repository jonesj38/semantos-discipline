---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/dispatch/dispatch/src/cell-types/completion.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.516353+00:00
---

# packages/dispatch/dispatch/src/cell-types/completion.ts

```ts
/**
 * `dispatch.completion.v1` — LINEAR cell.
 *
 * D-O11 phase O11b — completion-and-billing patch flowing from a
 * receiving vertical back to the originating tenant after the
 * receiving extension's work-of-record reaches its terminal-on-the-
 * receiving-side state (e.g. `oddjobz.job` → `completed` and
 * `invoiced`).
 *
 * The originating tenant's FSM advances on receipt of this patch:
 *   - `accepted → completed` when the patch arrives;
 *   - `completed → invoiced` if the patch carries an `invoiceAmount`.
 *
 * The shape is the same envelope-acknowledgement-patch pattern as
 * `dispatch.accepted.v1` (D-O11 §O11d's "(d) Completion patch shape"
 * — mirror the dispatch.envelope.v1 layout, payload carries the FSM
 * state transition).
 */

import {
  defineCellType,
  type CellTypeDef,
} from '@semantos/oddjobz/cell-types';
import {
  assertEnum,
  assertIsoDateString,
  assertNonEmptyString,
  assertUuid,
} from './validators.js';

export const COMPLETION_KINDS = ['completed', 'invoiced', 'cancelled'] as const;
export type CompletionKind = (typeof COMPLETION_KINDS)[number];

export interface DispatchCompletion {
  /** Envelope this completion patch references. */
  readonly envelopeId: string;
  /** Which receiving-side terminal-or-near-terminal state this patch represents. */
  readonly completionKind: CompletionKind;
  /** Timestamp the receiving side reached the state. */
  readonly completedAt: string;
  /** Optional invoice amount in cents (for `completionKind = invoiced`). */
  readonly invoiceAmountCents?: number;
  /** Hat-id that authored the completion. */
  readonly completedByHat: string;
  /** Free-form note (operator-readable summary). */
  readonly note?: string;
}

function validate(v: DispatchCompletion): void {
  assertUuid('envelopeId', v.envelopeId);
  assertEnum('completionKind', v.completionKind, COMPLETION_KINDS);
  assertIsoDateString('completedAt', v.completedAt);
  assertNonEmptyString('completedByHat', v.completedByHat);

  if (v.invoiceAmountCents !== undefined) {
    if (
      typeof v.invoiceAmountCents !== 'number' ||
      !Number.isInteger(v.invoiceAmountCents) ||
      v.invoiceAmountCents < 0
    ) {
      throw new Error('field invoiceAmountCents: not a non-negative integer');
    }
  }
  if (v.note !== undefined) {
    if (typeof v.note !== 'string') throw new Error('field note: not a string');
    if (v.note.length > 4000) {
      throw new Error('field note: too long (max 4000 chars)');
    }
  }

  if (v.completionKind === 'invoiced' && v.invoiceAmountCents === undefined) {
    throw new Error(
      "dispatch.completion.v1: completionKind='invoiced' requires invoiceAmountCents",
    );
  }
}

function toCanonical(v: DispatchCompletion): Record<string, unknown> {
  const out: Record<string, unknown> = {
    envelopeId: v.envelopeId,
    completionKind: v.completionKind,
    completedAt: v.completedAt,
    completedByHat: v.completedByHat,
  };
  if (v.invoiceAmountCents !== undefined)
    out.invoiceAmountCents = v.invoiceAmountCents;
  if (v.note !== undefined) out.note = v.note;
  return out;
}

function fromCanonical(c: unknown): DispatchCompletion {
  if (typeof c !== 'object' || c === null) {
    throw new Error('dispatch.completion.v1: payload not an object');
  }
  const r = c as Record<string, unknown>;
  return {
    envelopeId: r.envelopeId as string,
    completionKind: r.completionKind as CompletionKind,
    completedAt: r.completedAt as string,
    invoiceAmountCents: r.invoiceAmountCents as number | undefined,
    completedByHat: r.completedByHat as string,
    note: r.note as string | undefined,
  };
}

export const dispatchCompletionCellType: CellTypeDef<DispatchCompletion> =
  defineCellType({
    name: 'dispatch.completion.v1',
    identity: {
      whatPath: 'dispatch.completion',
      howSlug: 'federation-bridge',
      instPath: 'inst.signal.dispatch-completion',
    },
    linearity: 'LINEAR',
    toCanonical,
    fromCanonical,
    validate,
  });

```
