---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cdm/cdm/src/lifecycle/decrease.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.499114+00:00
---

# packages/cdm/cdm/src/lifecycle/decrease.ts

```ts
/**
 * Decrease flow — notional reduction via the partial-termination event.
 *
 * In CDM terms, "decrease" of notional is the AFFINE-partial-consume
 * realisation of `partial-termination`. The spec asked for one file
 * per flow; this module is the named entry point that delegates to
 * `termination.partialTerminateProduct`.
 *
 * Pure — no IO.
 *
 * Refactor 29 / split of `lifecycle.ts`.
 */

import type { CDMProduct, Result } from '../types';

import {
  partialTerminateProduct,
  type PartialTerminationResult,
} from './termination';

/** Decrease the trade's notional by `amount`. Wraps partial termination. */
export function decreaseNotional(
  product: CDMProduct,
  amount: number,
  actorCertId: string,
  effectiveDate?: string,
): Result<PartialTerminationResult> {
  return partialTerminateProduct(product, amount, actorCertId, effectiveDate);
}

```
