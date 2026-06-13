---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/cell-types/visit.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.507623+00:00
---

# cartridges/oddjobz/brain/src/cell-types/visit.ts

```ts
/**
 * `oddjobz.visit.v1` — LINEAR cell.
 *
 * A scheduled site visit. Per §O2: a Visit is consumed when completed
 * (produces a Visit-completed cell) — i.e. the §O4 FSM moves
 * `scheduled → in_progress → completed` by spending the current visit
 * cell and minting a successor.
 *
 * Field shape derived from the legacy `visits` table and
 * `sem_trades_visits` (`schema.trades.ts`). Operator assignment is by
 * UUID; outcome captures terminal-state context for the Visit-completed
 * successor.
 */

import { defineCellType, type CellTypeDef } from './cell-type.js';
import {
  assertUuid,
  assertOptionalUuid,
  assertOptionalString,
  assertEnum,
  assertOptionalEnum,
  assertIsoDateString,
  assertOptionalIsoDateString,
} from './validators.js';

export const VISIT_TYPES = [
  'inspection',
  'quote_visit',
  'scheduled_work',
  'return_visit',
  'emergency',
] as const;
export type VisitType = (typeof VISIT_TYPES)[number];

export const VISIT_OUTCOMES = [
  'completed',
  'partial',
  'rescheduled',
  'no_access',
  'cancelled',
] as const;
export type VisitOutcome = (typeof VISIT_OUTCOMES)[number];

export const VISIT_STATUSES = [
  'scheduled',
  'in_progress',
  'completed',
  'cancelled',
] as const;
export type VisitStatus = (typeof VISIT_STATUSES)[number];

export interface OddjobzVisit {
  /** Stable visit identifier (UUID v4). */
  readonly visitId: string;
  /** Job the visit serves (UUID v4). */
  readonly jobId: string;
  /** Site the visit is to (UUID v4). May be inferred from job in the §O4 FSM. */
  readonly siteId?: string;
  /** Operator assigned to the visit (UUID v4). */
  readonly assignedOperatorId?: string;

  /** Kind of visit. */
  readonly visitType: VisitType;
  /** Current status. */
  readonly status: VisitStatus;

  /** Scheduled start (ISO-8601). */
  readonly scheduledStart?: string;
  /** Scheduled end (ISO-8601). */
  readonly scheduledEnd?: string;
  /** Actual start (ISO-8601), set when status moves to in_progress. */
  readonly actualStart?: string;
  /** Actual end (ISO-8601), set when status moves to completed. */
  readonly actualEnd?: string;

  /** Outcome — set on the completed-state successor cell. */
  readonly outcome?: VisitOutcome;
  /** Operator notes about the visit. */
  readonly notes?: string;
  /** What needs to happen next (free-form). */
  readonly nextAction?: string;

  /** ISO-8601 cell creation timestamp. */
  readonly createdAt: string;
  /** ISO-8601 last-update timestamp. */
  readonly updatedAt: string;
}

function validate(v: OddjobzVisit): void {
  assertUuid('visitId', v.visitId);
  assertUuid('jobId', v.jobId);
  assertOptionalUuid('siteId', v.siteId);
  assertOptionalUuid('assignedOperatorId', v.assignedOperatorId);
  assertEnum('visitType', v.visitType, VISIT_TYPES);
  assertEnum('status', v.status, VISIT_STATUSES);
  assertOptionalEnum('outcome', v.outcome, VISIT_OUTCOMES);
  assertOptionalIsoDateString('scheduledStart', v.scheduledStart);
  assertOptionalIsoDateString('scheduledEnd', v.scheduledEnd);
  assertOptionalIsoDateString('actualStart', v.actualStart);
  assertOptionalIsoDateString('actualEnd', v.actualEnd);
  assertOptionalString('notes', v.notes);
  assertOptionalString('nextAction', v.nextAction);
  assertIsoDateString('createdAt', v.createdAt);
  assertIsoDateString('updatedAt', v.updatedAt);

  // status/outcome consistency
  if (v.status === 'completed' && v.outcome === undefined) {
    throw new Error('visit: status=completed requires outcome');
  }
  if (v.status !== 'completed' && v.outcome !== undefined) {
    // Allow setting outcome ahead of time only for `cancelled`
    if (!(v.status === 'cancelled' && v.outcome === 'cancelled')) {
      throw new Error('visit: outcome set without status=completed');
    }
  }
  if (
    v.scheduledStart !== undefined &&
    v.scheduledEnd !== undefined &&
    v.scheduledEnd < v.scheduledStart
  ) {
    throw new Error('visit: scheduledEnd before scheduledStart');
  }
  if (
    v.actualStart !== undefined &&
    v.actualEnd !== undefined &&
    v.actualEnd < v.actualStart
  ) {
    throw new Error('visit: actualEnd before actualStart');
  }
}

function toCanonical(v: OddjobzVisit): Record<string, unknown> {
  const out: Record<string, unknown> = {
    visitId: v.visitId,
    jobId: v.jobId,
    visitType: v.visitType,
    status: v.status,
    createdAt: v.createdAt,
    updatedAt: v.updatedAt,
  };
  if (v.siteId !== undefined) out.siteId = v.siteId;
  if (v.assignedOperatorId !== undefined) out.assignedOperatorId = v.assignedOperatorId;
  if (v.scheduledStart !== undefined) out.scheduledStart = v.scheduledStart;
  if (v.scheduledEnd !== undefined) out.scheduledEnd = v.scheduledEnd;
  if (v.actualStart !== undefined) out.actualStart = v.actualStart;
  if (v.actualEnd !== undefined) out.actualEnd = v.actualEnd;
  if (v.outcome !== undefined) out.outcome = v.outcome;
  if (v.notes !== undefined) out.notes = v.notes;
  if (v.nextAction !== undefined) out.nextAction = v.nextAction;
  return out;
}

function fromCanonical(c: unknown): OddjobzVisit {
  if (typeof c !== 'object' || c === null) throw new Error('visit: payload not an object');
  const r = c as Record<string, unknown>;
  return {
    visitId: r.visitId as string,
    jobId: r.jobId as string,
    siteId: r.siteId as string | undefined,
    assignedOperatorId: r.assignedOperatorId as string | undefined,
    visitType: r.visitType as VisitType,
    status: r.status as VisitStatus,
    scheduledStart: r.scheduledStart as string | undefined,
    scheduledEnd: r.scheduledEnd as string | undefined,
    actualStart: r.actualStart as string | undefined,
    actualEnd: r.actualEnd as string | undefined,
    outcome: r.outcome as VisitOutcome | undefined,
    notes: r.notes as string | undefined,
    nextAction: r.nextAction as string | undefined,
    createdAt: r.createdAt as string,
    updatedAt: r.updatedAt as string,
  };
}

export const visitCellType: CellTypeDef<OddjobzVisit> = defineCellType({
  name: 'oddjobz.visit.v1',
  identity: {
    whatPath: 'oddjobz.visit',
    howSlug: 'inspect',
    instPath: 'inst.work.site-visit',
  },
  linearity: 'LINEAR',
  toCanonical,
  fromCanonical,
  validate,
});

```
