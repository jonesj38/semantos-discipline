---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/cell-types/quote.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.504268+00:00
---

# cartridges/oddjobz/brain/src/cell-types/quote.ts

```ts
/**
 * `oddjobz.quote.v1` — LINEAR cell.
 *
 * A priced offer to a customer. Per §O2: a Quote is consumed when accepted
 * (becomes a Job) or rejected. The §O4 FSM gates the
 * `lead → quoted` transition with `cap.oddjobz.quote`; minting a Quote
 * cell is what spends that capability.
 *
 * Field shape derived from the legacy `estimates` table when
 * `estimateType = formal_quote` (per the OJT design: a "formal_quote" is
 * the priced offer; "auto_rom" / "operator_rom" are the rough estimates
 * that map to the separate Estimate cell type). See PR body for the
 * Estimate-vs-Quote model split rationale.
 */

import { defineCellType, type CellTypeDef } from './cell-type.js';
import {
  assertUuid,
  assertOptionalUuid,
  assertOptionalString,
  assertOptionalNonNegativeInt,
  assertOptionalFiniteNumber,
  assertOptionalBoolean,
  assertEnum,
  assertOptionalEnum,
  assertIsoDateString,
  assertOptionalIsoDateString,
  assertNonEmptyString,
} from './validators.js';
import { EFFORT_BANDS, type EffortBand } from './job.js';

export const QUOTE_STATUSES = [
  'draft',
  'presented',
  'accepted',
  'rejected',
  'expired',
  'superseded',
] as const;
export type QuoteStatus = (typeof QUOTE_STATUSES)[number];

export interface OddjobzQuote {
  /** Stable quote identifier (UUID v4). */
  readonly quoteId: string;
  /** Job the quote prices (UUID v4). */
  readonly jobId: string;
  /** Operator who issued the quote (UUID v4). */
  readonly issuedByOperatorId?: string;

  /** Current quote state. */
  readonly status: QuoteStatus;

  /** Effort band the price is based on. */
  readonly effortBand?: EffortBand;
  readonly hoursMin?: number;
  readonly hoursMax?: number;
  /** Lower bound of price quoted, in cents (smallest currency unit). */
  readonly costMin: number;
  /** Upper bound of price quoted, in cents. */
  readonly costMax: number;

  /** Whether the price is labour-only (no materials). */
  readonly labourOnly?: boolean;
  /** Free-form note about materials. */
  readonly materialsNote?: string;
  /** Free-form note about scope assumptions. */
  readonly assumptionNotes?: string;

  /** Customer-facing quote body (summary text presented). */
  readonly customerSummary?: string;

  /** Optional expiry timestamp (ISO-8601). */
  readonly expiresAt?: string;
  /** ISO-8601 timestamp at which customer accepted (if accepted). */
  readonly acceptedAt?: string;
  /** ISO-8601 timestamp at which the quote was rejected (if rejected). */
  readonly rejectedAt?: string;

  /** ISO-8601 cell creation timestamp. */
  readonly createdAt: string;
  /** ISO-8601 last-update timestamp. */
  readonly updatedAt: string;
}

function validate(v: OddjobzQuote): void {
  assertUuid('quoteId', v.quoteId);
  assertUuid('jobId', v.jobId);
  assertOptionalUuid('issuedByOperatorId', v.issuedByOperatorId);
  assertEnum('status', v.status, QUOTE_STATUSES);
  assertOptionalEnum('effortBand', v.effortBand, EFFORT_BANDS);
  assertOptionalFiniteNumber('hoursMin', v.hoursMin);
  assertOptionalFiniteNumber('hoursMax', v.hoursMax);
  assertOptionalNonNegativeInt('costMin', v.costMin);
  assertOptionalNonNegativeInt('costMax', v.costMax);
  // costMin/costMax are required for a Quote (vs Estimate); enforce here
  if (typeof v.costMin !== 'number' || typeof v.costMax !== 'number') {
    throw new Error('quote: costMin and costMax are required');
  }
  if (v.costMax < v.costMin) {
    throw new Error('quote: costMax less than costMin');
  }
  assertOptionalBoolean('labourOnly', v.labourOnly);
  assertOptionalString('materialsNote', v.materialsNote);
  assertOptionalString('assumptionNotes', v.assumptionNotes);
  if (v.customerSummary !== undefined) assertNonEmptyString('customerSummary', v.customerSummary);
  assertOptionalIsoDateString('expiresAt', v.expiresAt);
  assertOptionalIsoDateString('acceptedAt', v.acceptedAt);
  assertOptionalIsoDateString('rejectedAt', v.rejectedAt);
  assertIsoDateString('createdAt', v.createdAt);
  assertIsoDateString('updatedAt', v.updatedAt);
  if (
    v.hoursMin !== undefined &&
    v.hoursMax !== undefined &&
    v.hoursMax < v.hoursMin
  ) {
    throw new Error('quote: hoursMax less than hoursMin');
  }
  if (v.status === 'accepted' && v.acceptedAt === undefined) {
    throw new Error('quote: status=accepted requires acceptedAt');
  }
  if (v.status === 'rejected' && v.rejectedAt === undefined) {
    throw new Error('quote: status=rejected requires rejectedAt');
  }
}

function toCanonical(v: OddjobzQuote): Record<string, unknown> {
  const out: Record<string, unknown> = {
    quoteId: v.quoteId,
    jobId: v.jobId,
    status: v.status,
    costMin: v.costMin,
    costMax: v.costMax,
    createdAt: v.createdAt,
    updatedAt: v.updatedAt,
  };
  if (v.issuedByOperatorId !== undefined) out.issuedByOperatorId = v.issuedByOperatorId;
  if (v.effortBand !== undefined) out.effortBand = v.effortBand;
  if (v.hoursMin !== undefined) out.hoursMin = v.hoursMin;
  if (v.hoursMax !== undefined) out.hoursMax = v.hoursMax;
  if (v.labourOnly !== undefined) out.labourOnly = v.labourOnly;
  if (v.materialsNote !== undefined) out.materialsNote = v.materialsNote;
  if (v.assumptionNotes !== undefined) out.assumptionNotes = v.assumptionNotes;
  if (v.customerSummary !== undefined) out.customerSummary = v.customerSummary;
  if (v.expiresAt !== undefined) out.expiresAt = v.expiresAt;
  if (v.acceptedAt !== undefined) out.acceptedAt = v.acceptedAt;
  if (v.rejectedAt !== undefined) out.rejectedAt = v.rejectedAt;
  return out;
}

function fromCanonical(c: unknown): OddjobzQuote {
  if (typeof c !== 'object' || c === null) throw new Error('quote: payload not an object');
  const r = c as Record<string, unknown>;
  return {
    quoteId: r.quoteId as string,
    jobId: r.jobId as string,
    issuedByOperatorId: r.issuedByOperatorId as string | undefined,
    status: r.status as QuoteStatus,
    effortBand: r.effortBand as EffortBand | undefined,
    hoursMin: r.hoursMin as number | undefined,
    hoursMax: r.hoursMax as number | undefined,
    costMin: r.costMin as number,
    costMax: r.costMax as number,
    labourOnly: r.labourOnly as boolean | undefined,
    materialsNote: r.materialsNote as string | undefined,
    assumptionNotes: r.assumptionNotes as string | undefined,
    customerSummary: r.customerSummary as string | undefined,
    expiresAt: r.expiresAt as string | undefined,
    acceptedAt: r.acceptedAt as string | undefined,
    rejectedAt: r.rejectedAt as string | undefined,
    createdAt: r.createdAt as string,
    updatedAt: r.updatedAt as string,
  };
}

export const quoteCellType: CellTypeDef<OddjobzQuote> = defineCellType({
  name: 'oddjobz.quote.v1',
  identity: {
    whatPath: 'oddjobz.quote',
    howSlug: 'price',
    instPath: 'inst.contract.priced-offer',
  },
  linearity: 'LINEAR',
  toCanonical,
  fromCanonical,
  validate,
});

```
