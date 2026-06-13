---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cdm/cdm/src/lifecycle/__tests__/economic-effects.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.507656+00:00
---

# packages/cdm/cdm/src/lifecycle/__tests__/economic-effects.test.ts

```ts
/**
 * economic-effects module — pure helpers for economic-term mutation.
 *
 * Refactor 29.
 */

import { describe, expect, test } from 'bun:test';

import { applyEconomicEffect } from '../economic-effects';

const baseTerms = {
  notional: { amount: 10_000_000, currency: 'USD' },
  effectiveDate: '2024-06-15',
  terminationDate: '2029-06-15',
  fixedRate: 0.035,
  floatingRateIndex: 'SOFR',
};

describe('applyEconomicEffect', () => {
  test('returns the input unchanged when no effect supplied', () => {
    expect(applyEconomicEffect(baseTerms)).toEqual(baseTerms);
  });

  test('applies a positive notionalChange', () => {
    const out = applyEconomicEffect(baseTerms, { notionalChange: 5_000 });
    expect(out.notional.amount).toBe(10_005_000);
    expect(out.notional.currency).toBe('USD');
  });

  test('applies a negative notionalChange', () => {
    const out = applyEconomicEffect(baseTerms, { notionalChange: -2_000_000 });
    expect(out.notional.amount).toBe(8_000_000);
  });

  test('applies a rateReset', () => {
    const out = applyEconomicEffect(baseTerms, {
      rateReset: { newRate: 0.04, resetDate: '2024-09-15' },
    });
    expect(out.fixedRate).toBe(0.04);
    // Other fields preserved
    expect(out.notional.amount).toBe(10_000_000);
  });

  test('does not mutate the input terms', () => {
    const before = JSON.parse(JSON.stringify(baseTerms));
    applyEconomicEffect(baseTerms, { notionalChange: -1 });
    expect(baseTerms).toEqual(before);
  });
});

```
