---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cdm/cdm/src/lifecycle/economic-effects.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.499748+00:00
---

# packages/cdm/cdm/src/lifecycle/economic-effects.ts

```ts
/**
 * Economic-effect helpers — apply notional/rate-reset deltas to a
 * product's economic terms.
 *
 * Pure module. Used by the reducer + per-flow modules.
 *
 * Refactor 29 / split of `lifecycle.ts`.
 */

import type { CDMProduct, EconomicEffect } from '../types';

/**
 * Apply an `EconomicEffect` to a product's economic terms, returning
 * an updated copy. If `effect` is undefined, returns the original.
 */
export function applyEconomicEffect(
  terms: CDMProduct['economicTerms'],
  effect?: EconomicEffect,
): CDMProduct['economicTerms'] {
  if (!effect) return terms;

  let updated = { ...terms };

  if (effect.notionalChange !== undefined) {
    updated = {
      ...updated,
      notional: {
        ...updated.notional,
        amount: updated.notional.amount + effect.notionalChange,
      },
    };
  }

  if (effect.rateReset) {
    updated = {
      ...updated,
      fixedRate: effect.rateReset.newRate,
    };
  }

  return updated;
}

```
