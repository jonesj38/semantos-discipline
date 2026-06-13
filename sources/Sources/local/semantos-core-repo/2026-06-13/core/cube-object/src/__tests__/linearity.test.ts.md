---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cube-object/src/__tests__/linearity.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.011750+00:00
---

# core/cube-object/src/__tests__/linearity.test.ts

```ts
import { describe, test, expect } from 'bun:test';
import {
  type Linearity,
  type LinearityClass,
  linearityName,
  linearityColor,
  linearityClassColor,
  linearityClassToNumeric,
  linearityToClass,
} from '../linearity.js';

describe('linearity — names', () => {
  test('numeric → name covers all four codes', () => {
    expect(linearityName(0)).toBe('LINEAR');
    expect(linearityName(1)).toBe('AFFINE');
    expect(linearityName(2)).toBe('RELEVANT');
    expect(linearityName(3)).toBe('UNRESTRICTED');
  });
});

describe('linearity — colors', () => {
  test('every linearity has a unique color', () => {
    const colors = new Set([
      linearityColor(0),
      linearityColor(1),
      linearityColor(2),
      linearityColor(3),
    ]);
    expect(colors.size).toBe(4);
  });

  test('linearity colors are stable hex values', () => {
    expect(linearityColor(0)).toBe(0x2cb2a5);
    expect(linearityColor(1)).toBe(0xd98e23);
    expect(linearityColor(2)).toBe(0x8b5cf6);
    expect(linearityColor(3)).toBe(0x64748b);
  });

  test('linearityClassColor agrees with linearityColor on the three kernel classes', () => {
    expect(linearityClassColor('linear')).toBe(linearityColor(0));
    expect(linearityClassColor('affine')).toBe(linearityColor(1));
    expect(linearityClassColor('relevant')).toBe(linearityColor(2));
  });
});

describe('linearity — string ↔ numeric round-trips', () => {
  test('numeric → class → numeric is identity for kernel classes', () => {
    const cases: Array<[Linearity, LinearityClass]> = [
      [0, 'linear'],
      [1, 'affine'],
      [2, 'relevant'],
    ];
    for (const [n, c] of cases) {
      expect(linearityToClass(n)).toBe(c);
      expect(linearityClassToNumeric(c)).toBe(n);
    }
  });

  test('UNRESTRICTED falls back to "linear" with a console warning', () => {
    const warnings: unknown[][] = [];
    const orig = console.warn;
    console.warn = (...args: unknown[]) => warnings.push(args);
    try {
      const result = linearityToClass(3);
      expect(result).toBe('linear');
      expect(warnings.length).toBe(1);
    } finally {
      console.warn = orig;
    }
  });
});

```
