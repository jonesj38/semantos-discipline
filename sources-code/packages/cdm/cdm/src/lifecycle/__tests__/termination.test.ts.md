---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cdm/cdm/src/lifecycle/__tests__/termination.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.507055+00:00
---

# packages/cdm/cdm/src/lifecycle/__tests__/termination.test.ts

```ts
/**
 * termination module — partial termination + close-out netting.
 *
 * Refactor 29.
 */

import { describe, expect, test } from 'bun:test';

import { createCDMProduct, type CDMPartyRole, type CDMProduct } from '../../types';
import {
  partialTerminateProduct,
  closeOutNetPortfolio,
} from '../termination';

function makeProduct(opts?: {
  state?: string;
  notional?: number;
  currency?: string;
  buyer?: string;
  seller?: string;
}): CDMProduct {
  const state = opts?.state ?? 'confirmed';
  const p = createCDMProduct(
    'rates.swap.fixed-float',
    {
      notional: {
        amount: opts?.notional ?? 10_000_000,
        currency: opts?.currency ?? 'USD',
      },
      effectiveDate: '2024-06-15',
      terminationDate: '2029-06-15',
    },
    [
      { partyId: opts?.buyer ?? 'bank-a', role: 'buyer', capabilities: [] },
      { partyId: opts?.seller ?? 'bank-b', role: 'seller', capabilities: [] },
    ],
    '2024-06-15',
  );
  p.lifecycleState = state as any;
  return p;
}

describe('partialTerminateProduct', () => {
  test('reduces notional and advances state', () => {
    const product = makeProduct();
    const result = partialTerminateProduct(product, 3_000_000, 'actor-1');
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.value.product.lifecycleState).toBe('partially-terminated');
      expect(result.value.product.economicTerms.notional.amount).toBe(7_000_000);
      expect(result.value.event.economicEffect?.notionalChange).toBe(-3_000_000);
    }
  });

  test('rejects zero / negative reduction', () => {
    const product = makeProduct();
    const r1 = partialTerminateProduct(product, 0, 'actor-1');
    expect(r1.ok).toBe(false);
    const r2 = partialTerminateProduct(product, -10, 'actor-1');
    expect(r2.ok).toBe(false);
  });

  test('rejects reduction >= current notional', () => {
    const product = makeProduct({ notional: 1_000_000 });
    const result = partialTerminateProduct(product, 1_000_000, 'actor-1');
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error).toContain('must be less than notional');
    }
  });

  test('rejects when state does not permit partial termination', () => {
    const product = makeProduct({ state: 'terminated' });
    const result = partialTerminateProduct(product, 1_000, 'actor-1');
    expect(result.ok).toBe(false);
  });
});

describe('closeOutNetPortfolio', () => {
  test('rejects empty portfolio', () => {
    const result = closeOutNetPortfolio(
      [],
      { partyId: 'bank-a', role: 'buyer', capabilities: [] },
      'actor-1',
    );
    expect(result.ok).toBe(false);
  });

  test('rejects portfolio with non-defaulted products', () => {
    const product = makeProduct({ state: 'confirmed' });
    const result = closeOutNetPortfolio(
      [product],
      { partyId: 'bank-a', role: 'buyer', capabilities: [] },
      'actor-1',
    );
    expect(result.ok).toBe(false);
  });

  test('rejects multi-currency portfolio', () => {
    const usd = makeProduct({ state: 'defaulted', currency: 'USD' });
    const eur = makeProduct({ state: 'defaulted', currency: 'EUR' });
    const result = closeOutNetPortfolio(
      [usd, eur],
      { partyId: 'bank-a', role: 'buyer', capabilities: [] },
      'actor-1',
    );
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error).toContain('Multi-currency');
    }
  });

  test('computes signed net for buyer-side defaulting party', () => {
    const a = makeProduct({ state: 'defaulted', notional: 5_000_000 });
    const b = makeProduct({ state: 'defaulted', notional: 3_000_000 });
    const defaultingParty: CDMPartyRole = {
      partyId: 'bank-a',
      role: 'buyer',
      capabilities: [],
    };
    const result = closeOutNetPortfolio([a, b], defaultingParty, 'actor-1');
    expect(result.ok).toBe(true);
    if (result.ok) {
      // bank-a is buyer on both → +5M + +3M = +8M
      expect(result.value.netAmount).toBe(8_000_000);
      expect(result.value.currency).toBe('USD');
      expect(result.value.products.every((p) => p.lifecycleState === 'close-out')).toBe(true);
      expect(result.value.events.length).toBe(2);
    }
  });

  test('computes signed net when defaulting party is seller', () => {
    const product = makeProduct({ state: 'defaulted', notional: 2_000_000 });
    const result = closeOutNetPortfolio(
      [product],
      { partyId: 'bank-b', role: 'seller', capabilities: [] },
      'actor-1',
    );
    expect(result.ok).toBe(true);
    if (result.ok) {
      // bank-b is seller → -2M
      expect(result.value.netAmount).toBe(-2_000_000);
    }
  });
});

```
