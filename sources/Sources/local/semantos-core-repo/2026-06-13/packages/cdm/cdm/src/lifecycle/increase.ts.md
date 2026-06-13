---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cdm/cdm/src/lifecycle/increase.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.498814+00:00
---

# packages/cdm/cdm/src/lifecycle/increase.ts

```ts
/**
 * Increase flow — notional increase via a `rate-reset` style event that
 * carries an `EconomicEffect.notionalChange > 0`.
 *
 * The CDM event set on this codebase does not include a dedicated
 * "increase" event. Per the refactor-29 spec we still expose an
 * `increaseNotional` entry point so per-flow validators remain
 * symmetric. It dispatches a `payment` event (an in-place transition
 * that preserves state) carrying a positive `notionalChange`. Callers
 * who want a stricter event identity can extend `CDMEventType` later
 * — out of scope for prompt 29.
 *
 * Validation:
 *   - amount must be strictly positive
 *   - the current state must accept either `payment` or `rate-reset`
 *     (in-place transitions); we use `payment` as the default.
 *
 * Pure — no IO.
 *
 * Refactor 29 / split of `lifecycle.ts`.
 */

import {
  createLifecycleEvent,
  type CDMLifecycleEvent,
  type CDMProduct,
  type Result,
} from '../types';

import { applyEconomicEffect } from './economic-effects';
import { canTransition, validEventsFor, nextStateFor } from './trade-events';

export interface IncreaseResult {
  product: CDMProduct;
  event: CDMLifecycleEvent;
}

/**
 * Increase the trade's notional by `amount`. Emits a `payment` event
 * carrying `notionalChange = +amount`. The lifecycle state is
 * preserved (payment is an in-place transition).
 */
export function increaseNotional(
  product: CDMProduct,
  amount: number,
  actorCertId: string,
  effectiveDate?: string,
): Result<IncreaseResult> {
  if (amount <= 0) {
    return { ok: false, error: 'Increase amount must be positive' };
  }

  if (!canTransition(product.lifecycleState, 'payment')) {
    return {
      ok: false,
      error:
        `Cannot increase notional from state '${product.lifecycleState}'. ` +
        `Valid events: [${validEventsFor(product.lifecycleState).join(', ')}]`,
    };
  }

  const nextState = nextStateFor(product.lifecycleState, 'payment');
  if (!nextState) {
    return {
      ok: false,
      error: `No 'payment' transition from '${product.lifecycleState}'`,
    };
  }

  const event = createLifecycleEvent(
    'payment',
    product,
    effectiveDate ?? new Date().toISOString().split('T')[0],
    product.lifecycleState,
    nextState,
    actorCertId,
    { notionalChange: amount },
  );

  const updatedProduct: CDMProduct = {
    ...product,
    lifecycleState: nextState,
    previousEventCell: event.eventId,
    economicTerms: applyEconomicEffect(product.economicTerms, { notionalChange: amount }),
  };

  return { ok: true, value: { product: updatedProduct, event } };
}

```
