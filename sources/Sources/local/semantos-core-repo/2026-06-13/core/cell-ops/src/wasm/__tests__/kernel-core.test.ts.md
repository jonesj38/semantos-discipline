---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-ops/src/wasm/__tests__/kernel-core.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.832985+00:00
---

# core/cell-ops/src/wasm/__tests__/kernel-core.test.ts

```ts
import { describe, expect, test } from 'bun:test';

import { KernelError } from '../error-codes';
import {
  executeScript,
  initKernelCore,
  resetKernel,
  type PlexusKernelCoreExports,
} from '../kernel-core';

function fakeKernel(
  overrides: Partial<PlexusKernelCoreExports> = {},
): PlexusKernelCoreExports {
  const noop = () => 0;
  const voidNoop = () => {};
  return {
    kernel_init: noop,
    kernel_reset: voidNoop,
    kernel_load_script: noop,
    kernel_load_unlock: noop,
    kernel_execute: noop,
    kernel_get_type_class: noop,
    kernel_get_opcount: noop,
    kernel_get_error: noop,
    kernel_stack_depth: noop,
    kernel_stack_peek: noop,
    kernel_step: noop,
    kernel_get_pc: noop,
    kernel_get_current_op: noop,
    kernel_alt_stack_depth: noop,
    kernel_alt_stack_peek: noop,
    kernel_stack_value_length: noop,
    kernel_alt_stack_value_length: noop,
    kernel_load_tx_context: noop,
    kernel_set_output_index: noop,
    kernel_set_enforcement: voidNoop,
    ...overrides,
  };
}

describe('initKernelCore', () => {
  test('returns silently when kernel_init returns SUCCESS', () => {
    const handle = fakeKernel({ kernel_init: () => 0 });
    expect(() => initKernelCore(handle)).not.toThrow();
  });

  test('throws when kernel_init returns non-zero', () => {
    const handle = fakeKernel({
      kernel_init: () => KernelError.STACK_OVERFLOW,
    });
    expect(() => initKernelCore(handle)).toThrow(/code 1/);
  });
});

describe('executeScript', () => {
  test('returns the typed KernelError', () => {
    const handle = fakeKernel({
      kernel_execute: () => KernelError.VERIFY_FAILED,
    });
    expect(executeScript(handle)).toBe(KernelError.VERIFY_FAILED);
  });

  test('returns SUCCESS=0 on success', () => {
    const handle = fakeKernel({ kernel_execute: () => 0 });
    expect(executeScript(handle)).toBe(KernelError.SUCCESS);
  });
});

describe('resetKernel', () => {
  test('delegates to kernel_reset', () => {
    let called = 0;
    const handle = fakeKernel({
      kernel_reset: () => {
        called++;
      },
    });
    resetKernel(handle);
    expect(called).toBe(1);
  });
});

```
