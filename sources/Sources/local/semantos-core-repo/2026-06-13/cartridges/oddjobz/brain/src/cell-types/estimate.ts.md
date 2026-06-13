---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/cell-types/estimate.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.503960+00:00
---

# cartridges/oddjobz/brain/src/cell-types/estimate.ts

```ts
/**
 * `oddjobz.estimate.v1` — AFFINE cell.
 *
 * Pre-quote draft. Per §O2: an Estimate "can be discarded without becoming
 * a Quote" — that's wire-level AFFINE (no DUP, DROP permitted). Estimates
 * are the rough order-of-magnitude figures the OJT prototype calls
 * `auto_rom` and `operator_rom`; the Quote cell is the priced offer that
 * forms the §O4 `lead → quoted` transition.
 *
 * Field shape derived from the legacy `estimates` table for non-formal
 * estimate types. Customer-acknowledgement is tracked but does not
 * promote the cell to a Quote — that's an explicit operator-driven
 * mint of a separate Quote cell (gated by `cap.oddjobz.quote`).
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
} from './validators.js';
import { EFFORT_BANDS, type EffortBand } from './job.js';

export const ESTIMATE_TYPES = ['auto_rom', 'operator_rom', 'revised'] as const;
export type EstimateType = (typeof ESTIMATE_TYPES)[number];

export const ESTIMATE_ACK_STATUSES = [
  'pending',
  'accepted',
  'tentative',
  'pushback',
  'rejected',
  'wants_exact_price',
  'rate_shopping',
] as const;
export type EstimateAckStatus = (typeof ESTIMATE_ACK_STATUSES)[number];

export interface OddjobzEstimate {
  /** Stable estimate identifier (UUID v4). */
  readonly estimateId: string;
  /** Job the estimate is for (UUID v4). */
  readonly jobId: string;
  /** Operator who authored the estimate (UUID v4); null for `auto_rom`. */
  readonly authoredByOperatorId?: string;

  /** Kind of estimate. */
  readonly estimateType: EstimateType;

  /** Effort band. */
  readonly effortBand?: EffortBand;
  readonly hoursMin?: number;
  readonly hoursMax?: number;
  /** Lower bound in cents. */
  readonly costMin?: number;
  /** Upper bound in cents. */
  readonly costMax?: number;

  readonly labourOnly?: boolean;
  readonly materialsNote?: string;
  readonly assumptionNotes?: string;

  /** Customer acknowledgement state. */
  readonly ackStatus?: EstimateAckStatus;
  /** ISO-8601 timestamp at which the customer acknowledged. */
  readonly acknowledgedAt?: string;
  readonly customerAcknowledgedEstimate?: boolean;

  /** ISO-8601 cell creation timestamp. */
  readonly createdAt: string;
  /** ISO-8601 last-update timestamp. */
  readonly updatedAt: string;
}

function validate(v: OddjobzEstimate): void {
  assertUuid('estimateId', v.estimateId);
  assertUuid('jobId', v.jobId);
  assertOptionalUuid('authoredByOperatorId', v.authoredByOperatorId);
  assertEnum('estimateType', v.estimateType, ESTIMATE_TYPES);
  assertOptionalEnum('effortBand', v.effortBand, EFFORT_BANDS);
  assertOptionalFiniteNumber('hoursMin', v.hoursMin);
  assertOptionalFiniteNumber('hoursMax', v.hoursMax);
  assertOptionalNonNegativeInt('costMin', v.costMin);
  assertOptionalNonNegativeInt('costMax', v.costMax);
  assertOptionalBoolean('labourOnly', v.labourOnly);
  assertOptionalString('materialsNote', v.materialsNote);
  assertOptionalString('assumptionNotes', v.assumptionNotes);
  assertOptionalEnum('ackStatus', v.ackStatus, ESTIMATE_ACK_STATUSES);
  assertOptionalIsoDateString('acknowledgedAt', v.acknowledgedAt);
  assertOptionalBoolean('customerAcknowledgedEstimate', v.customerAcknowledgedEstimate);
  assertIsoDateString('createdAt', v.createdAt);
  assertIsoDateString('updatedAt', v.updatedAt);

  if (
    v.hoursMin !== undefined &&
    v.hoursMax !== undefined &&
    v.hoursMax < v.hoursMin
  ) {
    throw new Error('estimate: hoursMax less than hoursMin');
  }
  if (
    v.costMin !== undefined &&
    v.costMax !== undefined &&
    v.costMax < v.costMin
  ) {
    throw new Error('estimate: costMax less than costMin');
  }
}

function toCanonical(v: OddjobzEstimate): Record<string, unknown> {
  const out: Record<string, unknown> = {
    estimateId: v.estimateId,
    jobId: v.jobId,
    estimateType: v.estimateType,
    createdAt: v.createdAt,
    updatedAt: v.updatedAt,
  };
  if (v.authoredByOperatorId !== undefined) out.authoredByOperatorId = v.authoredByOperatorId;
  if (v.effortBand !== undefined) out.effortBand = v.effortBand;
  if (v.hoursMin !== undefined) out.hoursMin = v.hoursMin;
  if (v.hoursMax !== undefined) out.hoursMax = v.hoursMax;
  if (v.costMin !== undefined) out.costMin = v.costMin;
  if (v.costMax !== undefined) out.costMax = v.costMax;
  if (v.labourOnly !== undefined) out.labourOnly = v.labourOnly;
  if (v.materialsNote !== undefined) out.materialsNote = v.materialsNote;
  if (v.assumptionNotes !== undefined) out.assumptionNotes = v.assumptionNotes;
  if (v.ackStatus !== undefined) out.ackStatus = v.ackStatus;
  if (v.acknowledgedAt !== undefined) out.acknowledgedAt = v.acknowledgedAt;
  if (v.customerAcknowledgedEstimate !== undefined)
    out.customerAcknowledgedEstimate = v.customerAcknowledgedEstimate;
  return out;
}

function fromCanonical(c: unknown): OddjobzEstimate {
  if (typeof c !== 'object' || c === null) throw new Error('estimate: payload not an object');
  const r = c as Record<string, unknown>;
  return {
    estimateId: r.estimateId as string,
    jobId: r.jobId as string,
    authoredByOperatorId: r.authoredByOperatorId as string | undefined,
    estimateType: r.estimateType as EstimateType,
    effortBand: r.effortBand as EffortBand | undefined,
    hoursMin: r.hoursMin as number | undefined,
    hoursMax: r.hoursMax as number | undefined,
    costMin: r.costMin as number | undefined,
    costMax: r.costMax as number | undefined,
    labourOnly: r.labourOnly as boolean | undefined,
    materialsNote: r.materialsNote as string | undefined,
    assumptionNotes: r.assumptionNotes as string | undefined,
    ackStatus: r.ackStatus as EstimateAckStatus | undefined,
    acknowledgedAt: r.acknowledgedAt as string | undefined,
    customerAcknowledgedEstimate: r.customerAcknowledgedEstimate as boolean | undefined,
    createdAt: r.createdAt as string,
    updatedAt: r.updatedAt as string,
  };
}

export const estimateCellType: CellTypeDef<OddjobzEstimate> = defineCellType({
  name: 'oddjobz.estimate.v1',
  identity: {
    whatPath: 'oddjobz.estimate',
    howSlug: 'estimate',
    instPath: 'inst.draft.rom-estimate',
  },
  linearity: 'AFFINE',
  toCanonical,
  fromCanonical,
  validate,
});

```
