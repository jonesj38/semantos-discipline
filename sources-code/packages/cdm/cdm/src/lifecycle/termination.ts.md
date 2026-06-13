---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cdm/cdm/src/lifecycle/termination.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.499420+00:00
---

# packages/cdm/cdm/src/lifecycle/termination.ts

```ts
/**
 * Termination flows — full + partial termination + close-out netting.
 *
 * Full termination is a LINEAR consume (state → 'terminated'). Partial
 * termination is an AFFINE partial consume of notional (state →
 * 'partially-terminated'). Close-out netting computes net obligations
 * across a portfolio of defaulted products.
 *
 * Pure — no IO. Mutations return new objects (immutable updates).
 *
 * Refactor 29 / split of `lifecycle.ts`.
 */

import {
  createLifecycleEvent,
  type CDMLifecycleEvent,
  type CDMPartyRole,
  type CDMProduct,
  type CloseOutResult,
  type Result,
} from '../types';

import { canTransition, validEventsFor } from './trade-events';

// ── Partial Termination ───────────────────────────────────────

export interface PartialTerminationResult {
  product: CDMProduct;
  event: CDMLifecycleEvent;
}

/**
 * Reduce notional by `reductionAmount`. Validates:
 *
 *  - state allows partial termination (transition table)
 *  - reduction is positive
 *  - reduction is strictly less than current notional
 */
export function partialTerminateProduct(
  product: CDMProduct,
  reductionAmount: number,
  actorCertId: string,
  effectiveDate?: string,
): Result<PartialTerminationResult> {
  if (!canTransition(product.lifecycleState, 'partial-termination')) {
    return {
      ok: false,
      error:
        `Cannot partially terminate product in state '${product.lifecycleState}'. ` +
        `Valid events: [${validEventsFor(product.lifecycleState).join(', ')}]`,
    };
  }

  if (reductionAmount <= 0) {
    return { ok: false, error: 'Reduction amount must be positive' };
  }

  if (reductionAmount >= product.economicTerms.notional.amount) {
    return {
      ok: false,
      error:
        `Reduction amount (${reductionAmount}) must be less than notional ` +
        `(${product.economicTerms.notional.amount}). Use full termination instead.`,
    };
  }

  const newNotional = product.economicTerms.notional.amount - reductionAmount;

  const event = createLifecycleEvent(
    'partial-termination',
    product,
    effectiveDate ?? new Date().toISOString().split('T')[0],
    product.lifecycleState,
    'partially-terminated',
    actorCertId,
    { notionalChange: -reductionAmount },
  );

  const updatedProduct: CDMProduct = {
    ...product,
    lifecycleState: 'partially-terminated',
    previousEventCell: event.eventId,
    economicTerms: {
      ...product.economicTerms,
      notional: {
        ...product.economicTerms.notional,
        amount: newNotional,
      },
    },
  };

  return { ok: true, value: { product: updatedProduct, event } };
}

// ── Close-Out Netting ─────────────────────────────────────────

/**
 * Close-out netting — compute net obligations across a portfolio of
 * defaulted products. Validates:
 *
 *  - portfolio is non-empty
 *  - every product is in the `'defaulted'` state
 *  - all products share a single currency
 *
 * The `defaultingParty.partyId` determines the sign of each notional:
 * if the defaulting party is the buyer on a product, that notional
 * counts as `+`; if seller, `-`. Sums to `netAmount`.
 */
export function closeOutNetPortfolio(
  products: CDMProduct[],
  defaultingParty: CDMPartyRole,
  actorCertId: string,
  effectiveDate?: string,
): Result<CloseOutResult> {
  if (products.length === 0) {
    return { ok: false, error: 'Portfolio is empty' };
  }

  const nonDefaulted = products.filter((p) => p.lifecycleState !== 'defaulted');
  if (nonDefaulted.length > 0) {
    return {
      ok: false,
      error:
        `Cannot net — ${nonDefaulted.length} product(s) not in 'defaulted' state: ` +
        `[${nonDefaulted.map((p) => p.cellId).join(', ')}]`,
    };
  }

  const currencies = new Set(
    products.map((p) => p.economicTerms.notional.currency),
  );
  if (currencies.size > 1) {
    return {
      ok: false,
      error: `Multi-currency netting not supported. Found currencies: [${[...currencies].join(', ')}]`,
    };
  }

  const currency = products[0].economicTerms.notional.currency;
  const date = effectiveDate ?? new Date().toISOString().split('T')[0];

  let netAmount = 0;
  const events: CDMLifecycleEvent[] = [];
  const updatedProducts: CDMProduct[] = [];

  for (const product of products) {
    const isBuyer = product.parties.some(
      (p) => p.partyId === defaultingParty.partyId && p.role === 'buyer',
    );
    const sign = isBuyer ? 1 : -1;
    netAmount += sign * product.economicTerms.notional.amount;

    const event = createLifecycleEvent(
      'close-out-netting',
      product,
      date,
      'defaulted',
      'close-out',
      actorCertId,
    );
    events.push(event);

    updatedProducts.push({
      ...product,
      lifecycleState: 'close-out',
      previousEventCell: event.eventId,
    });
  }

  return {
    ok: true,
    value: { netAmount, currency, events, products: updatedProducts },
  };
}

```
