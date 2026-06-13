---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-ops/src/wasm/__tests__/error-codes.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.832706+00:00
---

# core/cell-ops/src/wasm/__tests__/error-codes.test.ts

```ts
import { describe, expect, test } from 'bun:test';

import {
  KernelError,
  TypeClassification,
  isKnownKernelError,
  kernelErrorMessage,
} from '../error-codes';

describe('KernelError enum', () => {
  test('SUCCESS is 0', () => {
    expect(KernelError.SUCCESS).toBe(0);
  });

  test('phase boundaries match wire contract', () => {
    // Phase 1-2 starts at 9 (INVALID_MAGIC)
    expect(KernelError.INVALID_MAGIC).toBe(9);
    // Phase 3 starts at 16 (INVALID_SCRIPT)
    expect(KernelError.INVALID_SCRIPT).toBe(16);
    // Phase 4 starts at 22 (CANNOT_DUPLICATE_LINEAR)
    expect(KernelError.CANNOT_DUPLICATE_LINEAR).toBe(22);
    // Phase 5 starts at 33 (BEEF_PARSE_ERROR)
    expect(KernelError.BEEF_PARSE_ERROR).toBe(33);
    // Phase 6 starts at 41 (INVALID_POINTER_CELL)
    expect(KernelError.INVALID_POINTER_CELL).toBe(41);
    // Reserved sentinel
    expect(KernelError.NOT_IMPLEMENTED).toBe(255);
  });
});

describe('TypeClassification enum', () => {
  test('numeric values match wasm-interface contract', () => {
    expect(TypeClassification.LINEAR).toBe(0);
    expect(TypeClassification.AFFINE).toBe(1);
    expect(TypeClassification.RELEVANT).toBe(2);
    expect(TypeClassification.UNCLASSIFIED).toBe(-1);
  });
});

describe('kernelErrorMessage', () => {
  test('SUCCESS → "success"', () => {
    expect(kernelErrorMessage(KernelError.SUCCESS)).toBe('success');
  });

  test('every known error has a non-default message', () => {
    for (const key of Object.keys(KernelError)) {
      const numeric = Number(key);
      if (!Number.isFinite(numeric)) continue;
      const msg = kernelErrorMessage(numeric);
      expect(msg).not.toMatch(/^kernel error \d+$/);
      expect(msg.length).toBeGreaterThan(0);
    }
  });

  test('unknown code falls back to "kernel error N" (total function)', () => {
    expect(kernelErrorMessage(9999)).toBe('kernel error 9999');
    expect(kernelErrorMessage(-42)).toBe('kernel error -42');
  });

  test('selected canonical messages', () => {
    expect(kernelErrorMessage(KernelError.STACK_OVERFLOW)).toBe('stack overflow');
    expect(kernelErrorMessage(KernelError.INVALID_MAGIC)).toBe('invalid magic bytes');
    expect(kernelErrorMessage(KernelError.HOST_FETCH_FAILED)).toBe('host fetch failed');
    expect(kernelErrorMessage(KernelError.NOT_IMPLEMENTED)).toBe('not implemented');
  });
});

describe('isKnownKernelError', () => {
  test('returns true for known codes', () => {
    expect(isKnownKernelError(KernelError.SUCCESS)).toBe(true);
    expect(isKnownKernelError(KernelError.NOT_IMPLEMENTED)).toBe(true);
    expect(isKnownKernelError(42)).toBe(true); // HOST_FETCH_FAILED
  });

  test('returns false for unrecognized codes', () => {
    expect(isKnownKernelError(9999)).toBe(false);
    expect(isKnownKernelError(100)).toBe(false);
  });
});

```
