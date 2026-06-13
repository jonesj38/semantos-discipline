---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/cell-types/job.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.506141+00:00
---

# cartridges/oddjobz/brain/src/cell-types/job.ts

```ts
/**
 * `oddjobz.job.v1` — LINEAR cell.
 *
 * The work-unit. Per §O2: state machine
 * `lead → quoted → scheduled → in_progress → completed → invoiced → paid → closed`.
 * Each FSM transition (Phase O4) consumes the current Job cell and mints
 * a successor with `prevStateHash` pointing back. Linearity is hard at the
 * kernel gate via `OP_ASSERTLINEAR` (0xC5).
 *
 * Field shape derived from the legacy `jobs` table and the
 * `sem_trades_jobs` projection. Scoring/recommendation columns from the
 * legacy schema are kept (operators rely on them for the queue) and
 * faithfully forwarded to the cell payload; downstream §O4 transitions
 * may freeze a subset into the cell at quote-time.
 *
 * Customer/site references are by ID only — the canonical Customer and
 * Site cells live in their own type-streams.
 */

import { defineCellType, type CellTypeDef } from './cell-type.js';
import {
  assertUuid,
  assertOptionalUuid,
  assertNonEmptyString,
  assertOptionalString,
  assertOptionalNonNegativeInt,
  assertOptionalFiniteNumber,
  assertOptionalBoolean,
  assertEnum,
  assertOptionalEnum,
  assertIsoDateString,
} from './validators.js';

export const JOB_STATUSES = [
  'lead',
  // Lead-nurture front (the twelve-state remodel — canonical, NOT
  // legacy: these are real FSM states, see state-machines/job-fsm.ts).
  'qualified',
  'visit_pending',
  'visit_scheduled',
  'visited',
  'quoted',
  // Directly-authorised (no-quote, e.g. REA WO) branch parallel to
  // `quoted`; both feed `scheduled`.
  'authorized',
  'scheduled',
  'in_progress',
  'completed',
  'invoiced',
  'paid',
  'closed',
  // Legacy statuses kept for OJT migration round-trips. The FSM only
  // permits transitions over the thirteen canonical states above;
  // legacy values pass validation but are flagged "needs review".
  'new_lead',
  'partial_intake',
  'awaiting_customer',
  'ready_for_review',
  'estimate_presented',
  'estimate_accepted',
  'not_price_aligned',
  'not_a_fit',
  'needs_site_visit',
  'bookable',
  'hanging_weather',
  'hanging_parts',
  'return_visit_required',
  'complete',
  'invoice_pending',
  'archived',
] as const;
export type JobStatus = (typeof JOB_STATUSES)[number];

export const URGENCIES = [
  'emergency',
  'urgent',
  'next_week',
  'next_2_weeks',
  'flexible',
  'when_convenient',
  'unspecified',
] as const;
export type Urgency = (typeof URGENCIES)[number];

export const EFFORT_BANDS = [
  'quick',
  'short',
  'quarter_day',
  'half_day',
  'full_day',
  'multi_day',
  'unknown',
] as const;
export type EffortBand = (typeof EFFORT_BANDS)[number];

export const LEAD_SOURCES = [
  'website_chat',
  'facebook',
  'instagram',
  'phone',
  'referral',
  'repeat',
  'walk_in',
  'agent_pdf',
  'other',
] as const;
export type LeadSource = (typeof LEAD_SOURCES)[number];

export const RECOMMENDATIONS = [
  'ignore',
  'only_if_nearby',
  'needs_site_visit',
  'probably_bookable',
  'worth_quoting',
  'priority_lead',
  'not_price_aligned',
  'not_a_fit',
] as const;
export type Recommendation = (typeof RECOMMENDATIONS)[number];

export interface OddjobzJob {
  /** Stable job identifier (UUID v4). */
  readonly jobId: string;
  /** Owning customer (UUID v4). Optional during early lead intake. */
  readonly customerId?: string;
  /** Site where the work is performed (UUID v4). */
  readonly siteId?: string;
  /** Operator who created the job (UUID v4). */
  readonly createdByOperatorId?: string;
  /** Operator currently assigned to the job (UUID v4). */
  readonly assignedOperatorId?: string;

  /** Universal taxonomy: WHAT axis (e.g. `services.trades.plumbing`). */
  readonly categoryPath?: string;
  /** Universal taxonomy: HOW axis (e.g. `hire`). */
  readonly txType?: string;
  /** Universal taxonomy: INSTRUMENT axis (e.g. `inst.contract.service-agreement`). */
  readonly instrumentType?: string;

  /** Free-form description of the work. */
  readonly descriptionRaw?: string;
  /** Operator-/AI-condensed summary. */
  readonly descriptionSummary?: string;

  /** Current FSM state. */
  readonly status: JobStatus;
  /** Operator/customer-stated urgency. */
  readonly urgency?: Urgency;
  /** Lead source (where the job came from). */
  readonly leadSource?: LeadSource;

  /** Effort band estimate. */
  readonly effortBand?: EffortBand;
  readonly estimatedHoursMin?: number;
  readonly estimatedHoursMax?: number;
  /** Cost in cents (smallest currency unit). */
  readonly estimatedCostMin?: number;
  /** Cost in cents (smallest currency unit). */
  readonly estimatedCostMax?: number;

  /** Customer-fit score 0-100. */
  readonly customerFitScore?: number;
  /** Quote-worthiness score 0-100. */
  readonly quoteWorthinessScore?: number;
  /** Confidence score 0-100. */
  readonly confidenceScore?: number;
  /** Completeness 0-100 (how complete the intake is). */
  readonly completenessScore?: number;
  /** Recommendation surfaced by the scoring engine. */
  readonly recommendation?: Recommendation;

  /** Operator-decided needs-review flag. */
  readonly needsReview?: boolean;
  /** Whether the customer is a repeat. */
  readonly isRepeatCustomer?: boolean;
  /** Repeat job count (0 if first-time). */
  readonly repeatJobCount?: number;
  /** Whether a site visit is required before quoting. */
  readonly requiresSiteVisit?: boolean;

  /**
   * Work-order / PO / reference number from the property-management
   * platform (e.g. PropertyMe, BricksAndAgent). Preserved verbatim so
   * repeat emails about the same order can be de-duplicated and the
   * operator doesn't need to log back into the platform's dashboard.
   */
  readonly referenceNumber?: string;

  /**
   * Email Message-IDs or provider item IDs (e.g. Gmail message IDs) that
   * contributed to this job. Maintained as a set across scope-update emails
   * so there's an audit trail back to every raw item.
   */
  readonly sourceEmails?: string[];

  /** Legacy job ID from the OJT prototype (UUID), for migration. */
  readonly legacyJobId?: string;

  /** ISO-8601 cell creation timestamp. */
  readonly createdAt: string;
  /** ISO-8601 last-update timestamp. */
  readonly updatedAt: string;
}

function validate(v: OddjobzJob): void {
  assertUuid('jobId', v.jobId);
  assertOptionalUuid('customerId', v.customerId);
  assertOptionalUuid('siteId', v.siteId);
  assertOptionalUuid('createdByOperatorId', v.createdByOperatorId);
  assertOptionalUuid('assignedOperatorId', v.assignedOperatorId);
  assertOptionalString('categoryPath', v.categoryPath);
  assertOptionalString('txType', v.txType);
  assertOptionalString('instrumentType', v.instrumentType);
  assertOptionalString('descriptionRaw', v.descriptionRaw);
  assertOptionalString('descriptionSummary', v.descriptionSummary);
  assertEnum('status', v.status, JOB_STATUSES);
  assertOptionalEnum('urgency', v.urgency, URGENCIES);
  assertOptionalEnum('leadSource', v.leadSource, LEAD_SOURCES);
  assertOptionalEnum('effortBand', v.effortBand, EFFORT_BANDS);
  assertOptionalFiniteNumber('estimatedHoursMin', v.estimatedHoursMin);
  assertOptionalFiniteNumber('estimatedHoursMax', v.estimatedHoursMax);
  assertOptionalNonNegativeInt('estimatedCostMin', v.estimatedCostMin);
  assertOptionalNonNegativeInt('estimatedCostMax', v.estimatedCostMax);
  assertOptionalNonNegativeInt('customerFitScore', v.customerFitScore);
  assertOptionalNonNegativeInt('quoteWorthinessScore', v.quoteWorthinessScore);
  assertOptionalNonNegativeInt('confidenceScore', v.confidenceScore);
  assertOptionalNonNegativeInt('completenessScore', v.completenessScore);
  assertOptionalEnum('recommendation', v.recommendation, RECOMMENDATIONS);
  assertOptionalBoolean('needsReview', v.needsReview);
  assertOptionalBoolean('isRepeatCustomer', v.isRepeatCustomer);
  assertOptionalNonNegativeInt('repeatJobCount', v.repeatJobCount);
  assertOptionalBoolean('requiresSiteVisit', v.requiresSiteVisit);
  assertOptionalString('referenceNumber', v.referenceNumber);
  if (v.sourceEmails !== undefined) {
    if (!Array.isArray(v.sourceEmails)) throw new Error('field sourceEmails: not an array');
    for (const e of v.sourceEmails) {
      if (typeof e !== 'string') throw new Error('field sourceEmails[]: not a string');
    }
  }
  if (v.legacyJobId !== undefined) assertUuid('legacyJobId', v.legacyJobId);
  assertIsoDateString('createdAt', v.createdAt);
  assertIsoDateString('updatedAt', v.updatedAt);

  // Bound checks
  for (const [k, val] of [
    ['customerFitScore', v.customerFitScore],
    ['quoteWorthinessScore', v.quoteWorthinessScore],
    ['confidenceScore', v.confidenceScore],
    ['completenessScore', v.completenessScore],
  ] as const) {
    if (val !== undefined && (val < 0 || val > 100)) {
      throw new Error(`field ${k}: outside [0, 100]`);
    }
  }
  if (
    v.estimatedHoursMin !== undefined &&
    v.estimatedHoursMax !== undefined &&
    v.estimatedHoursMax < v.estimatedHoursMin
  ) {
    throw new Error('field estimatedHoursMax: less than estimatedHoursMin');
  }
  if (
    v.estimatedCostMin !== undefined &&
    v.estimatedCostMax !== undefined &&
    v.estimatedCostMax < v.estimatedCostMin
  ) {
    throw new Error('field estimatedCostMax: less than estimatedCostMin');
  }

  // Description sanity (if provided)
  if (v.descriptionRaw !== undefined && v.descriptionRaw.length > 0) {
    assertNonEmptyString('descriptionRaw', v.descriptionRaw);
  }
}

function toCanonical(v: OddjobzJob): Record<string, unknown> {
  // canonical-JSON sorts keys before serialising, so insertion order
  // here is irrelevant; optional fields are emitted iff defined to
  // keep payload size minimal.
  const out: Record<string, unknown> = {
    jobId: v.jobId,
    status: v.status,
    createdAt: v.createdAt,
    updatedAt: v.updatedAt,
  };
  if (v.customerId !== undefined) out.customerId = v.customerId;
  if (v.siteId !== undefined) out.siteId = v.siteId;
  if (v.createdByOperatorId !== undefined) out.createdByOperatorId = v.createdByOperatorId;
  if (v.assignedOperatorId !== undefined) out.assignedOperatorId = v.assignedOperatorId;
  if (v.categoryPath !== undefined) out.categoryPath = v.categoryPath;
  if (v.txType !== undefined) out.txType = v.txType;
  if (v.instrumentType !== undefined) out.instrumentType = v.instrumentType;
  if (v.descriptionRaw !== undefined) out.descriptionRaw = v.descriptionRaw;
  if (v.descriptionSummary !== undefined) out.descriptionSummary = v.descriptionSummary;
  if (v.urgency !== undefined) out.urgency = v.urgency;
  if (v.leadSource !== undefined) out.leadSource = v.leadSource;
  if (v.effortBand !== undefined) out.effortBand = v.effortBand;
  if (v.estimatedHoursMin !== undefined) out.estimatedHoursMin = v.estimatedHoursMin;
  if (v.estimatedHoursMax !== undefined) out.estimatedHoursMax = v.estimatedHoursMax;
  if (v.estimatedCostMin !== undefined) out.estimatedCostMin = v.estimatedCostMin;
  if (v.estimatedCostMax !== undefined) out.estimatedCostMax = v.estimatedCostMax;
  if (v.customerFitScore !== undefined) out.customerFitScore = v.customerFitScore;
  if (v.quoteWorthinessScore !== undefined) out.quoteWorthinessScore = v.quoteWorthinessScore;
  if (v.confidenceScore !== undefined) out.confidenceScore = v.confidenceScore;
  if (v.completenessScore !== undefined) out.completenessScore = v.completenessScore;
  if (v.recommendation !== undefined) out.recommendation = v.recommendation;
  if (v.needsReview !== undefined) out.needsReview = v.needsReview;
  if (v.isRepeatCustomer !== undefined) out.isRepeatCustomer = v.isRepeatCustomer;
  if (v.repeatJobCount !== undefined) out.repeatJobCount = v.repeatJobCount;
  if (v.requiresSiteVisit !== undefined) out.requiresSiteVisit = v.requiresSiteVisit;
  if (v.referenceNumber !== undefined) out.referenceNumber = v.referenceNumber;
  if (v.sourceEmails !== undefined && v.sourceEmails.length > 0) out.sourceEmails = v.sourceEmails;
  if (v.legacyJobId !== undefined) out.legacyJobId = v.legacyJobId;
  return out;
}

function fromCanonical(c: unknown): OddjobzJob {
  if (typeof c !== 'object' || c === null) throw new Error('job: payload not an object');
  const r = c as Record<string, unknown>;
  return {
    jobId: r.jobId as string,
    customerId: r.customerId as string | undefined,
    siteId: r.siteId as string | undefined,
    createdByOperatorId: r.createdByOperatorId as string | undefined,
    assignedOperatorId: r.assignedOperatorId as string | undefined,
    categoryPath: r.categoryPath as string | undefined,
    txType: r.txType as string | undefined,
    instrumentType: r.instrumentType as string | undefined,
    descriptionRaw: r.descriptionRaw as string | undefined,
    descriptionSummary: r.descriptionSummary as string | undefined,
    status: r.status as JobStatus,
    urgency: r.urgency as Urgency | undefined,
    leadSource: r.leadSource as LeadSource | undefined,
    effortBand: r.effortBand as EffortBand | undefined,
    estimatedHoursMin: r.estimatedHoursMin as number | undefined,
    estimatedHoursMax: r.estimatedHoursMax as number | undefined,
    estimatedCostMin: r.estimatedCostMin as number | undefined,
    estimatedCostMax: r.estimatedCostMax as number | undefined,
    customerFitScore: r.customerFitScore as number | undefined,
    quoteWorthinessScore: r.quoteWorthinessScore as number | undefined,
    confidenceScore: r.confidenceScore as number | undefined,
    completenessScore: r.completenessScore as number | undefined,
    recommendation: r.recommendation as Recommendation | undefined,
    needsReview: r.needsReview as boolean | undefined,
    isRepeatCustomer: r.isRepeatCustomer as boolean | undefined,
    repeatJobCount: r.repeatJobCount as number | undefined,
    requiresSiteVisit: r.requiresSiteVisit as boolean | undefined,
    referenceNumber: r.referenceNumber as string | undefined,
    sourceEmails: r.sourceEmails as string[] | undefined,
    legacyJobId: r.legacyJobId as string | undefined,
    createdAt: r.createdAt as string,
    updatedAt: r.updatedAt as string,
  };
}

export const jobCellType: CellTypeDef<OddjobzJob> = defineCellType({
  name: 'oddjobz.job.v1',
  identity: {
    whatPath: 'oddjobz.job',
    howSlug: 'worktrack',
    instPath: 'inst.work.job-record',
  },
  linearity: 'LINEAR',
  toCanonical,
  fromCanonical,
  validate,
});

```
