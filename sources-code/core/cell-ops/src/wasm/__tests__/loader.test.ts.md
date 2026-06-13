---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-ops/src/wasm/__tests__/loader.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.833829+00:00
---

# core/cell-ops/src/wasm/__tests__/loader.test.ts

```ts
import { describe, expect, test } from 'bun:test';

import { REQUIRED_KERNEL_EXPORTS, validateKernelExports } from '../loader';

describe('REQUIRED_KERNEL_EXPORTS', () => {
  test('includes every both-profile kernel export', () => {
    // Sanity floor — every essential phase is represented.
    expect(REQUIRED_KERNEL_EXPORTS).toContain('kernel_init');
    expect(REQUIRED_KERNEL_EXPORTS).toContain('kernel_execute');
    expect(REQUIRED_KERNEL_EXPORTS).toContain('cell_pack');
    expect(REQUIRED_KERNEL_EXPORTS).toContain('multicell_unpack');
    expect(REQUIRED_KERNEL_EXPORTS).toContain('bca_derive');
    expect(REQUIRED_KERNEL_EXPORTS).toContain('kernel_verify_capability');
    expect(REQUIRED_KERNEL_EXPORTS).toContain('memory');
  });

  test('excludes optional full-profile-only SPV exports', () => {
    // These exist only in the full profile and must not be in the
    // shared required-list — including them would break embedded.
    expect(REQUIRED_KERNEL_EXPORTS).not.toContain('kernel_verify_beef');
    expect(REQUIRED_KERNEL_EXPORTS).not.toContain('kernel_verify_bump');
    expect(REQUIRED_KERNEL_EXPORTS).not.toContain('kernel_beef_version');
    expect(REQUIRED_KERNEL_EXPORTS).not.toContain('kernel_verify_beef_spv');
  });

  test('list is read-only (const tuple)', () => {
    // Type test masquerading as runtime: `as const` ensures the
    // values are not mutated at runtime in the (unlikely) event a
    // consumer tries.
    expect(Array.isArray(REQUIRED_KERNEL_EXPORTS)).toBe(true);
    expect(REQUIRED_KERNEL_EXPORTS.length).toBeGreaterThan(20);
  });
});

describe('validateKernelExports', () => {
  test('passes when every required export is present', () => {
    const exports: Record<string, unknown> = {};
    for (const name of REQUIRED_KERNEL_EXPORTS) exports[name] = () => 0;
    expect(() => validateKernelExports(exports)).not.toThrow();
  });

  test('throws naming the first missing export', () => {
    const exports: Record<string, unknown> = {};
    for (const name of REQUIRED_KERNEL_EXPORTS) exports[name] = () => 0;
    delete exports['kernel_init'];
    expect(() => validateKernelExports(exports)).toThrow(
      /missing required export: kernel_init/,
    );
  });

  test('rejects a completely empty export object', () => {
    expect(() => validateKernelExports({})).toThrow(
      /missing required export/,
    );
  });
});

```
