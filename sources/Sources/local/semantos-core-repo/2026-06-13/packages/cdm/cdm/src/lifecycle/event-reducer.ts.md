---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cdm/cdm/src/lifecycle/event-reducer.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.500034+00:00
---

# packages/cdm/cdm/src/lifecycle/event-reducer.ts

```ts
/**
 * CDM event reducer — pure `(tradeState, event) → tradeState` transition.
 *
 * Mirrors the prompt-13 `channelReducer` shape: takes a current product
 * state, an event, and returns either the next product (with an updated
 * lifecycle state + economic terms + previousEventCell pointer) or a
 * `Result.error` describing why the transition was rejected.
 *
 * No IO. No `Date.now()`, no `Math.random()`, no policy evaluation, no
 * cell building, no anchor emission. Side effects belong in the facade
 * + persistence effect modules.
 *
 * The reducer also returns the synthesised `CDMLifecycleEvent` record
 * for the transition. Callers who need to chain events (e.g. the
 * facade building a cell + emitting persistence) take both back.
 *
 * Refactor 29 / split of `lifecycle.ts`.
 */

import {
  createLifecycleEvent,
  type CDMLifecycleEvent,
  type CDMProduct,
  type Result,
} from '../types';

import {
  economicEffectFrom,
  nextStateFor,
  validateTradeEvent,
  type TradeEvent,
} from './trade-events';
import { applyEconomicEffect } from './economic-effects';

// ── Reducer Output ────────────────────────────────────────────

export interface ReducerResult {
  /** Updated product (immutable copy of input with state advanced). */
  product: CDMProduct;
  /** Synthesised event record describing the transition. */
  event: CDMLifecycleEvent;
}

// ── Pure Reducer ──────────────────────────────────────────────

/**
 * Apply a `TradeEvent` to a `CDMProduct`. Returns either the
 * `{ product, event }` pair or an error string.
 *
 * Pure — given the same `product` and `event`, the only non-determinism
 * is `event.eventId` + `event.timestamp` (delegated to `createLifecycleEvent`).
 * Tests can stub via DI in `lifecycle-facade.ts` if needed.
 */
export function reduceTradeEvent(
  product: CDMProduct,
  event: TradeEvent,
  actorCertId: string,
): Result<ReducerResult> {
  const validation = validateTradeEvent(product, event);
  if (!validation.ok) {
    return { ok: false, error: validation.error };
  }

  const nextState = nextStateFor(product.lifecycleState, event.type);
  if (nextState === undefined) {
    // validateTradeEvent already covers this; defensive.
    return {
      ok: false,
      error: `No transition for '${event.type}' from '${product.lifecycleState}'`,
    };
  }

  const economicEffect = economicEffectFrom(event.payload);

  const lifecycleEvent = createLifecycleEvent(
    event.type,
    product,
    event.effectiveDate,
    product.lifecycleState,
    nextState,
    actorCertId,
    economicEffect,
  );

  const updatedProduct: CDMProduct = {
    ...product,
    lifecycleState: nextState,
    previousEventCell: lifecycleEvent.eventId,
    economicTerms: applyEconomicEffect(product.economicTerms, economicEffect),
  };

  return {
    ok: true,
    value: { product: updatedProduct, event: lifecycleEvent },
  };
}

```
