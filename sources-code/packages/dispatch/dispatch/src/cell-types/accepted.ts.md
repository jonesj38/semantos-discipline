---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/dispatch/dispatch/src/cell-types/accepted.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.516012+00:00
---

# packages/dispatch/dispatch/src/cell-types/accepted.ts

```ts
/**
 * `dispatch.accepted.v1` — LINEAR cell.
 *
 * D-O11 phase O11b — the receive-side acknowledgement patch flowing
 * back from a receiving extension to the originating tenant after a
 * dispatch envelope is successfully materialised. Carries the
 * envelopeId of the predecessor dispatch envelope and the
 * receiving-tenant's local cell id (e.g. an `oddjobz.job.v1` jobId)
 * for cross-vertical reference.
 *
 * The originating tenant's FSM listens for this patch on the
 * federated envelope and advances its own state machine accordingly
 * (e.g. MaintenanceRequest dispatched → accepted).
 */

import {
  defineCellType,
  type CellTypeDef,
} from '@semantos/oddjobz/cell-types';
import {
  assertIsoDateString,
  assertNonEmptyString,
  assertUuid,
} from './validators.js';

export interface DispatchAccepted {
  /** The envelopeId this acknowledges. */
  readonly envelopeId: string;
  /**
   * The receiving-tenant's local cell id (e.g. the `jobId` of the
   * materialised `oddjobz.job.v1`). Free-form string per the receiving
   * extension's id scheme.
   */
  readonly localCellId: string;
  /** The receiving-tenant's local cell type (e.g. `oddjobz.job.v1`). */
  readonly localCellType: string;
  /** ISO-8601 timestamp of acceptance. */
  readonly acceptedAt: string;
  /** Hat-id that authored the acceptance (the receiving tradie). */
  readonly acceptedByHat: string;
}

function validate(v: DispatchAccepted): void {
  assertUuid('envelopeId', v.envelopeId);
  assertNonEmptyString('localCellId', v.localCellId);
  assertNonEmptyString('localCellType', v.localCellType);
  assertIsoDateString('acceptedAt', v.acceptedAt);
  assertNonEmptyString('acceptedByHat', v.acceptedByHat);
}

function toCanonical(v: DispatchAccepted): Record<string, unknown> {
  return {
    envelopeId: v.envelopeId,
    localCellId: v.localCellId,
    localCellType: v.localCellType,
    acceptedAt: v.acceptedAt,
    acceptedByHat: v.acceptedByHat,
  };
}

function fromCanonical(c: unknown): DispatchAccepted {
  if (typeof c !== 'object' || c === null) {
    throw new Error('dispatch.accepted.v1: payload not an object');
  }
  const r = c as Record<string, unknown>;
  return {
    envelopeId: r.envelopeId as string,
    localCellId: r.localCellId as string,
    localCellType: r.localCellType as string,
    acceptedAt: r.acceptedAt as string,
    acceptedByHat: r.acceptedByHat as string,
  };
}

export const dispatchAcceptedCellType: CellTypeDef<DispatchAccepted> =
  defineCellType({
    name: 'dispatch.accepted.v1',
    identity: {
      whatPath: 'dispatch.accepted',
      howSlug: 'federation-bridge',
      instPath: 'inst.signal.dispatch-accepted',
    },
    linearity: 'LINEAR',
    toCanonical,
    fromCanonical,
    validate,
  });

```
