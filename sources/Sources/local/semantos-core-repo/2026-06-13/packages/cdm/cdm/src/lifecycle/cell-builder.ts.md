---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cdm/cdm/src/lifecycle/cell-builder.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.501189+00:00
---

# packages/cdm/cdm/src/lifecycle/cell-builder.ts

```ts
/**
 * Cell builder — packs a `(product, event, payload)` triple into a
 * Semantos cell with the canonical CDM type-hash + linearity flags.
 *
 * Kept in its own module so `lifecycle-facade.ts` doesn't import
 * `core/cell-ops` directly; one localised cross-tier import keeps the
 * boundary clean.
 *
 * Refactor 29 / split of `lifecycle.ts`.
 */

import {
  buildCellHeader,
  computeTypeHash,
  contentHash,
  LINEARITY,
  packCell,
} from '../../../../core/cell-ops/src/typeHashRegistry';
import { computeDomainPayloadRoot } from '../../../../core/plexus-schema-registry/src/hash';
import {
  commerceSchemaV1,
  commercePayload,
} from '../../../../core/plexus-schema-registry/src/schemas/commerce';

import type {
  CDMEventType,
  CDMLifecycleEvent,
  CDMLifecycleState,
  CDMProduct,
} from '../types';
import type { TradeEventPayload } from './trade-events';

export interface BuiltEventCell {
  cell: Uint8Array;
  /** Hex content hash of the payload — used for prevStateHash chains. */
  cellHash: string;
}

/**
 * Pack a CDM lifecycle event into a cell. The payload JSON is the
 * canonical event-cell shape used by Phase 28 consumers; do not change
 * the field set or order without coordinating with regulatory bridges.
 */
export function buildEventCell(args: {
  product: CDMProduct;
  event: CDMLifecycleEvent;
  eventType: CDMEventType;
  before: CDMLifecycleState;
  after: CDMLifecycleState;
  effectiveDate: string;
  actorCertId: string;
  extra: TradeEventPayload;
}): BuiltEventCell {
  const payloadJson = JSON.stringify({
    eventId: args.event.eventId,
    eventType: args.eventType,
    productCellId: args.product.cellId,
    before: args.before,
    after: args.after,
    effectiveDate: args.effectiveDate,
    timestamp: args.event.timestamp,
    actorCertId: args.actorCertId,
    ...args.extra,
  });
  const payloadBuf = Buffer.from(payloadJson, 'utf-8');

  const prevHash = args.product.previousEventCell
    ? Buffer.from(
        args.product.previousEventCell.padEnd(64, '0').slice(0, 64),
        'hex',
      )
    : Buffer.alloc(32, 0);

  const typeHash = computeTypeHash(
    `cdm.event.${args.eventType}`,
    'lifecycle',
    'inst.derivative.otc',
  );

  // RM-041: commerce taxonomy (phase=action, dimension=composite) encodes
  // into the cell payload under commerceSchemaV1; the resulting 32B root
  // binds via the header's domainPayloadRoot slot. prevStateHash chain
  // semantics remain as a first-class header field (RM-032b kept it as
  // a non-commerce chain field; buildCellHeader continues to accept it).
  const domainPayload = Buffer.from(
    computeDomainPayloadRoot(
      commerceSchemaV1,
      commercePayload({ phase: 'action', dimension: 'composite' }),
    ),
  );
  const header = buildCellHeader({
    typeHash,
    linearity: LINEARITY.LINEAR,
    ownerId: Buffer.alloc(16, 0),
    prevStateHash: prevHash,
    domainPayload,
    payloadSize: payloadBuf.length,
  });

  const cell = packCell(header, payloadBuf);
  const cellHash = contentHash(payloadBuf).toString('hex');

  return { cell, cellHash };
}

```
