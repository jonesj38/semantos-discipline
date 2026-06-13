---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/re-desk-stub/src/cell-types/maintenance-request.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.539229+00:00
---

# packages/re-desk-stub/src/cell-types/maintenance-request.ts

```ts
/**
 * `re-desk.maintenance-request.v1` — LINEAR cell.
 *
 * D-O11 phase O11a — the single cell type the stub re-desk extension
 * ships to validate the chapter-29 federation primitive end-to-end.
 *
 * The MaintenanceRequest is the property-management side of a
 * cross-vertical dispatch. Its state machine mirrors the chapter 29
 * worked example: `draft → dispatched → accepted → in_progress →
 * completed → invoiced → closed`. The `draft → dispatched` transition
 * is the moment the dispatch envelope is created (D-O11 phase O11b).
 * Subsequent state transitions on the PM side fire from patches
 * arriving on the federated envelope.
 *
 * Why minimal: per ODDJOBZ-EXTENSION-PLAN.md §3 phase O11 the stub is
 * intentionally NOT a real re-desk extension — it's the minimum
 * scaffolding sufficient to prove the federation pattern composes
 * with the full oddjobz extension on the receiving side. A real PM
 * vertical would carry richer fields (owner financials, lease
 * terms, …) but those add nothing to the substrate-primitive proof.
 */

import {
  defineCellType,
  type CellTypeDef,
} from '@semantos/oddjobz/cell-types';
import {
  assertEnum,
  assertIsoDateString,
  assertNonEmptyString,
  assertOptionalString,
  assertUuid,
} from './validators.js';

export const MAINTENANCE_REQUEST_STATES = [
  'draft',
  'dispatched',
  'accepted',
  'in_progress',
  'completed',
  'invoiced',
  'closed',
  'cancelled',
] as const;
export type MaintenanceRequestState = (typeof MAINTENANCE_REQUEST_STATES)[number];

export const MAINTENANCE_URGENCIES = [
  'emergency',
  'urgent',
  'flexible',
  'unspecified',
] as const;
export type MaintenanceUrgency = (typeof MAINTENANCE_URGENCIES)[number];

export interface MaintenanceRequest {
  /** Stable maintenance-request identifier (UUID v4). */
  readonly requestId: string;
  /** Free-form customer / tenant identifier (hint, not a structured cell ref). */
  readonly customer: string;
  /** Free-form description of the work needed. */
  readonly description: string;
  /**
   * Dispatch target as `<tenant-domain>#<hat-id>` —
   * e.g. `"oddjobtodd.info#tradie-todd"`. Required from `dispatched`
   * onwards. See `docs/canon/glossary.yml#tenant-hat-reference`.
   */
  readonly dispatchTo: string;
  /** Current FSM state. */
  readonly state: MaintenanceRequestState;
  /** Operator-stated urgency. */
  readonly urgency?: MaintenanceUrgency;
  /** Reference to the dispatch envelope cell hash, once created. */
  readonly envelopeId?: string;
  /** ISO-8601 cell creation. */
  readonly createdAt: string;
  /** ISO-8601 dispatched timestamp (set on draft → dispatched). */
  readonly dispatchedAt?: string;
  /** ISO-8601 accepted timestamp. */
  readonly acceptedAt?: string;
  /** ISO-8601 completed timestamp. */
  readonly completedAt?: string;
  /** ISO-8601 invoiced timestamp. */
  readonly invoicedAt?: string;
  /** ISO-8601 closed timestamp. */
  readonly closedAt?: string;
  /** Last-update timestamp. */
  readonly updatedAt: string;
}

const TENANT_HAT_RE = /^[a-z0-9.-]+#[a-z0-9-]+$/;

function assertTenantHatRef(field: string, value: unknown): asserts value is string {
  if (typeof value !== 'string') throw new Error(`field ${field}: not a string`);
  if (!TENANT_HAT_RE.test(value)) {
    throw new Error(
      `field ${field}: not a tenant-hat reference (expected '<domain>#<hat-id>'; got ${JSON.stringify(value)})`,
    );
  }
}

function validate(v: MaintenanceRequest): void {
  assertUuid('requestId', v.requestId);
  assertNonEmptyString('customer', v.customer);
  assertNonEmptyString('description', v.description);
  assertTenantHatRef('dispatchTo', v.dispatchTo);
  assertEnum('state', v.state, MAINTENANCE_REQUEST_STATES);
  if (v.urgency !== undefined) {
    assertEnum('urgency', v.urgency, MAINTENANCE_URGENCIES);
  }
  if (v.envelopeId !== undefined) assertNonEmptyString('envelopeId', v.envelopeId);
  assertIsoDateString('createdAt', v.createdAt);
  if (v.dispatchedAt !== undefined) assertIsoDateString('dispatchedAt', v.dispatchedAt);
  if (v.acceptedAt !== undefined) assertIsoDateString('acceptedAt', v.acceptedAt);
  if (v.completedAt !== undefined) assertIsoDateString('completedAt', v.completedAt);
  if (v.invoicedAt !== undefined) assertIsoDateString('invoicedAt', v.invoicedAt);
  if (v.closedAt !== undefined) assertIsoDateString('closedAt', v.closedAt);
  assertIsoDateString('updatedAt', v.updatedAt);

  // The state-machine carries the implication: `draft` is the only
  // state that may legally have no envelopeId. Once dispatched, the
  // envelope reference is load-bearing for completion-patch routing.
  if (v.state !== 'draft' && v.envelopeId === undefined) {
    throw new Error(
      `maintenance-request: envelopeId required for state=${v.state}`,
    );
  }

  // Avoid unused-import warning on assertOptionalString; kept for
  // forward compatibility with future field additions.
  void assertOptionalString;
}

function toCanonical(v: MaintenanceRequest): Record<string, unknown> {
  const out: Record<string, unknown> = {
    requestId: v.requestId,
    customer: v.customer,
    description: v.description,
    dispatchTo: v.dispatchTo,
    state: v.state,
    createdAt: v.createdAt,
    updatedAt: v.updatedAt,
  };
  if (v.urgency !== undefined) out.urgency = v.urgency;
  if (v.envelopeId !== undefined) out.envelopeId = v.envelopeId;
  if (v.dispatchedAt !== undefined) out.dispatchedAt = v.dispatchedAt;
  if (v.acceptedAt !== undefined) out.acceptedAt = v.acceptedAt;
  if (v.completedAt !== undefined) out.completedAt = v.completedAt;
  if (v.invoicedAt !== undefined) out.invoicedAt = v.invoicedAt;
  if (v.closedAt !== undefined) out.closedAt = v.closedAt;
  return out;
}

function fromCanonical(c: unknown): MaintenanceRequest {
  if (typeof c !== 'object' || c === null) {
    throw new Error('maintenance-request: payload not an object');
  }
  const r = c as Record<string, unknown>;
  return {
    requestId: r.requestId as string,
    customer: r.customer as string,
    description: r.description as string,
    dispatchTo: r.dispatchTo as string,
    state: r.state as MaintenanceRequestState,
    urgency: r.urgency as MaintenanceUrgency | undefined,
    envelopeId: r.envelopeId as string | undefined,
    createdAt: r.createdAt as string,
    dispatchedAt: r.dispatchedAt as string | undefined,
    acceptedAt: r.acceptedAt as string | undefined,
    completedAt: r.completedAt as string | undefined,
    invoicedAt: r.invoicedAt as string | undefined,
    closedAt: r.closedAt as string | undefined,
    updatedAt: r.updatedAt as string,
  };
}

export const maintenanceRequestCellType: CellTypeDef<MaintenanceRequest> =
  defineCellType({
    name: 're-desk.maintenance-request.v1',
    identity: {
      whatPath: 're-desk.maintenance-request',
      howSlug: 'dispatch-mgmt',
      instPath: 'inst.work.maintenance-request',
    },
    linearity: 'LINEAR',
    toCanonical,
    fromCanonical,
    validate,
  });

```
