---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cdm/cdm/src/lifecycle/__tests__/increase-decrease.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.508357+00:00
---

# packages/cdm/cdm/src/lifecycle/__tests__/increase-decrease.test.ts

```ts
/**
 * increase + decrease flows.
 *
 * Refactor 29.
 */

import { describe, expect, test } from 'bun:test';

import { createCDMProduct } from '../../types';
import { decreaseNotional } from '../decrease';
import { increaseNotional } from '../increase';

function makeProduct(state: string = 'confirmed') {
  const p = createCDMProduct(
    'rates.swap.fixed-float',
    {
      notional: { amount: 10_000_000, currency: 'USD' },
      effectiveDate: '2024-06-15',
      terminationDate: '2029-06-15',
    },
    [{ partyId: 'p1', role: 'buyer', capabilities: [] }],
    '2024-06-15',
  );
  p.lifecycleState = state as any;
  return p;
}

describe('decreaseNotional', () => {
  test('delegates to partialTerminateProduct semantics', () => {
    const product = makeProduct();
    const result = decreaseNotional(product, 1_000_000, 'actor-1');
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.value.product.economicTerms.notional.amount).toBe(9_000_000);
      expect(result.value.product.lifecycleState).toBe('partially-terminated');
    }
  });

  test('rejects negative amount', () => {
    const product = makeProduct();
    const result = decreaseNotional(product, -1, 'actor-1');
    expect(result.ok).toBe(false);
  });
});

describe('increaseNotional', () => {
  test('adds to notional via a payment event', () => {
    const product = makeProduct('confirmed');
    const result = increaseNotional(product, 500_000, 'actor-1');
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.value.product.economicTerms.notional.amount).toBe(10_500_000);
      // payment in 'confirmed' is a self-loop transition
      expect(result.value.product.lifecycleState).toBe('confirmed');
      expect(result.value.event.economicEffect?.notionalChange).toBe(500_000);
    }
  });

  test('rejects zero or negative amounts', () => {
    const product = makeProduct();
    expect(increaseNotional(product, 0, 'actor-1').ok).toBe(false);
    expect(increaseNotional(product, -10, 'actor-1').ok).toBe(false);
  });

  test('rejects when state does not allow payment', () => {
    const product = makeProduct('terminated');
    const result = increaseNotional(product, 500_000, 'actor-1');
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error).toContain('Cannot increase');
    }
  });
});

```
