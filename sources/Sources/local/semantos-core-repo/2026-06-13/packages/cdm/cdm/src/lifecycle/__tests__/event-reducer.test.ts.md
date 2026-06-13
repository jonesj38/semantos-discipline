---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cdm/cdm/src/lifecycle/__tests__/event-reducer.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.509247+00:00
---

# packages/cdm/cdm/src/lifecycle/__tests__/event-reducer.test.ts

```ts
/**
 * event-reducer module — pure (state, event) → state transition.
 *
 * Refactor 29.
 */

import { describe, expect, test } from 'bun:test';

import { createCDMProduct, type CDMProduct } from '../../types';
import { reduceTradeEvent } from '../event-reducer';
import type { TradeEvent } from '../trade-events';

function makeProduct(state: string = 'proposed'): CDMProduct {
  const p = createCDMProduct(
    'rates.swap.fixed-float',
    {
      notional: { amount: 10_000_000, currency: 'USD' },
      effectiveDate: '2024-06-15',
      terminationDate: '2029-06-15',
      fixedRate: 0.035,
    },
    [
      { partyId: 'bank-a', role: 'buyer', capabilities: [] },
      { partyId: 'bank-b', role: 'seller', capabilities: [] },
    ],
    '2024-06-15',
  );
  p.lifecycleState = state as any;
  return p;
}

describe('reduceTradeEvent', () => {
  test('execution: proposed → executed', () => {
    const product = makeProduct('proposed');
    const event: TradeEvent = {
      type: 'execution',
      effectiveDate: '2024-06-15',
      payload: {},
    };
    const result = reduceTradeEvent(product, event, 'actor-1');
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.value.product.lifecycleState).toBe('executed');
      expect(result.value.event.before).toBe('proposed');
      expect(result.value.event.after).toBe('executed');
      expect(result.value.event.eventType).toBe('execution');
      expect(result.value.product.previousEventCell).toBe(result.value.event.eventId);
    }
  });

  test('rejects invalid transition', () => {
    const product = makeProduct('terminated');
    const event: TradeEvent = {
      type: 'confirmation',
      effectiveDate: '2024-06-16',
      payload: {},
    };
    const result = reduceTradeEvent(product, event, 'actor-1');
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error).toContain("Cannot apply 'confirmation'");
    }
  });

  test('payment carries notionalChange via payload', () => {
    const product = makeProduct('confirmed');
    const event: TradeEvent = {
      type: 'payment',
      effectiveDate: '2024-06-16',
      payload: { notionalChange: -1_000 },
    };
    const result = reduceTradeEvent(product, event, 'actor-1');
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.value.product.economicTerms.notional.amount).toBe(9_999_000);
      expect(result.value.product.lifecycleState).toBe('confirmed');
    }
  });

  test('rate-reset updates fixedRate via payload', () => {
    const product = makeProduct('confirmed');
    const event: TradeEvent = {
      type: 'rate-reset',
      effectiveDate: '2024-07-01',
      payload: { rateReset: { newRate: 0.04, resetDate: '2024-07-01' } },
    };
    const result = reduceTradeEvent(product, event, 'actor-1');
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.value.product.economicTerms.fixedRate).toBe(0.04);
    }
  });

  test('does not mutate input product', () => {
    const product = makeProduct('proposed');
    const before = JSON.parse(JSON.stringify(product));
    const event: TradeEvent = {
      type: 'execution',
      effectiveDate: '2024-06-15',
      payload: {},
    };
    reduceTradeEvent(product, event, 'actor-1');
    expect(product).toEqual(before);
  });
});

```
