---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/semantos-sir/src/__tests__/betterment-lexicon.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.815328+00:00
---

# core/semantos-sir/src/__tests__/betterment-lexicon.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import {
  BettermentLexicon,
  ALL_LEXICONS,
  verifyLexiconInjective,
  isCategoryOf,
  type BettermentCategory,
} from '../index';

describe('BettermentLexicon', () => {
  test('L1 exposes exactly the 12 betterment-practice discourse categories', () => {
    expect(BettermentLexicon.categories).toEqual([
      'release',
      'intention',
      'session',
      'insight',
      'pattern',
      'connect',
      'vacuum',
      'seal',
      'morning',
      'review',
      'pulse',
      'inquire',
    ]);
  });

  test('L2 name is "betterment"', () => {
    expect(BettermentLexicon.name).toBe('betterment');
  });

  test('L3 header is injective on all 12 categories', () => {
    const result = verifyLexiconInjective(BettermentLexicon);
    expect(result.injective).toBe(true);
  });

  test('L4 header rendering: BETTERMENT_<UPPERCASE_CATEGORY>', () => {
    expect(BettermentLexicon.header('release')).toBe('BETTERMENT_RELEASE');
    expect(BettermentLexicon.header('intention')).toBe('BETTERMENT_INTENTION');
    expect(BettermentLexicon.header('vacuum')).toBe('BETTERMENT_VACUUM');
    expect(BettermentLexicon.header('inquire')).toBe('BETTERMENT_INQUIRE');
  });

  test('L5 registered in ALL_LEXICONS', () => {
    const names = ALL_LEXICONS.map((l) => l.name);
    expect(names).toContain('betterment');
  });

  test('L6 isCategoryOf accepts known categories, rejects unknown', () => {
    expect(isCategoryOf(BettermentLexicon, 'release')).toBe(true);
    expect(isCategoryOf(BettermentLexicon, 'seal')).toBe(true);
    expect(isCategoryOf(BettermentLexicon, 'unknown')).toBe(false);
    expect(isCategoryOf(BettermentLexicon, '')).toBe(false);
  });

  test('L7 — TS type matches runtime categories (compile-time check)', () => {
    // If BettermentCategory drifts from the runtime categories list, this
    // assignment fails to compile.
    const valid: BettermentCategory[] = [
      'release',
      'intention',
      'session',
      'insight',
      'pattern',
      'connect',
      'vacuum',
      'seal',
      'morning',
      'review',
      'pulse',
      'inquire',
    ];
    expect(valid.length).toBe(BettermentLexicon.categories.length);
  });
});

```
