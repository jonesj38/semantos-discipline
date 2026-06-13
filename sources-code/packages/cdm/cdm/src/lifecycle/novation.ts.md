---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cdm/cdm/src/lifecycle/novation.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.500324+00:00
---

# packages/cdm/cdm/src/lifecycle/novation.ts

```ts
/**
 * Novation flow — transfer trade from one counterparty to another.
 *
 * Wraps Phase 17 `createTransferRecord()` with a CDM-shaped result and
 * uses the shared transition table to validate the move from the
 * current state into `'novated'`.
 *
 * Pure — no IO, no `Date.now()` (the lifecycle-event factory inside
 * `createLifecycleEvent` provides the timestamp).
 *
 * Refactor 29 / split of `lifecycle.ts`.
 */

import {
  createTransferRecord,
  type TransferRecord,
} from '@semantos/core/types/transfer.js';

import {
  createLifecycleEvent,
  type CDMLifecycleEvent,
  type CDMPartyRole,
  type CDMProduct,
  type Result,
} from '../types';

import { canTransition, validEventsFor } from './trade-events';

export interface NovationResult {
  product: CDMProduct;
  transferRecord: TransferRecord;
  event: CDMLifecycleEvent;
}

/**
 * Novate a product — replace `oldParty` with `newParty` and transition
 * to `'novated'`. Validates that:
 *
 *  - the current state allows novation (transition table)
 *  - `oldParty.partyId` is present on the trade
 *
 * Returns `{ product, transferRecord, event }` on success.
 */
export function novateProduct(
  product: CDMProduct,
  oldParty: CDMPartyRole,
  newParty: CDMPartyRole,
  actorCertId: string,
  effectiveDate?: string,
): Result<NovationResult> {
  if (!canTransition(product.lifecycleState, 'novation')) {
    return {
      ok: false,
      error:
        `Cannot novate product in state '${product.lifecycleState}'. ` +
        `Valid events: [${validEventsFor(product.lifecycleState).join(', ')}]`,
    };
  }

  const partyIndex = product.parties.findIndex(
    (p) => p.partyId === oldParty.partyId,
  );
  if (partyIndex === -1) {
    return {
      ok: false,
      error: `Party '${oldParty.partyId}' is not a counterparty on this trade`,
    };
  }

  const transferRecord = createTransferRecord(
    product.cellId,
    oldParty.hatCertId ?? oldParty.partyId,
    newParty.hatCertId ?? newParty.partyId,
    `novation-tx-${Date.now().toString(16)}`,
    `${product.cellId}.0`,
    `${product.cellId}.1`,
    {
      capTransferOutpoint: null,
      edgeVerified: false,
      previousChildIndex: 0,
      newChildIndex: 0,
    },
  );

  const event = createLifecycleEvent(
    'novation',
    product,
    effectiveDate ?? new Date().toISOString().split('T')[0],
    product.lifecycleState,
    'novated',
    actorCertId,
  );

  const updatedParties = [...product.parties];
  updatedParties[partyIndex] = newParty;

  const updatedProduct: CDMProduct = {
    ...product,
    lifecycleState: 'novated',
    parties: updatedParties,
    previousEventCell: event.eventId,
  };

  return { ok: true, value: { product: updatedProduct, transferRecord, event } };
}

```
