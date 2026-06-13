---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-ops/src/wasm/__tests__/policy-eval.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.833270+00:00
---

# core/cell-ops/src/wasm/__tests__/policy-eval.test.ts

```ts
import { describe, expect, test } from 'bun:test';

import { hasSpvExports } from '../policy-eval';

describe('hasSpvExports', () => {
  test('returns true when all four SPV functions are present', () => {
    const handle = {
      kernel_beef_version: () => 0,
      kernel_verify_beef: () => 0,
      kernel_verify_bump: () => 0,
      kernel_verify_beef_spv: () => 0,
    };
    expect(hasSpvExports(handle)).toBe(true);
  });

  test('returns false when any SPV function is missing', () => {
    expect(hasSpvExports({})).toBe(false);
    expect(
      hasSpvExports({
        kernel_beef_version: () => 0,
      }),
    ).toBe(false);
    expect(
      hasSpvExports({
        kernel_beef_version: () => 0,
        kernel_verify_beef: () => 0,
        kernel_verify_bump: () => 0,
        // missing kernel_verify_beef_spv
      }),
    ).toBe(false);
  });

  test('returns false when SPV functions are non-callable', () => {
    expect(
      hasSpvExports({
        kernel_beef_version: 0 as unknown as () => number,
        kernel_verify_beef: () => 0,
        kernel_verify_bump: () => 0,
        kernel_verify_beef_spv: () => 0,
      }),
    ).toBe(false);
  });
});

```
