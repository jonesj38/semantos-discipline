---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/semantos-sir/src/__tests__/brap-lexicon.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.814226+00:00
---

# core/semantos-sir/src/__tests__/brap-lexicon.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import {
  BRAPLexicon,
  BRAP_VERBS,
  isBRAPCategory,
  isBRAPVerb,
  ALL_LEXICONS,
  verifyLexiconInjective,
} from '../index';

describe('BRAPLexicon', () => {
  test('L1 exposes exactly the 9 BREM cell keys', () => {
    expect(BRAPLexicon.categories).toEqual([
      'na',
      'nc',
      'ns',
      'se',
      'sm',
      'sf',
      'ls',
      'lr',
      'lp',
    ]);
  });

  test('L2 name is "brap"', () => {
    expect(BRAPLexicon.name).toBe('brap');
  });

  test('L3 header is injective on the 9 cells', () => {
    const result = verifyLexiconInjective(BRAPLexicon);
    expect(result.injective).toBe(true);
  });

  test('L4 header renders with BRAP_ prefix', () => {
    expect(BRAPLexicon.header('sm')).toBe('BRAP_SM');
    expect(BRAPLexicon.header('nc')).toBe('BRAP_NC');
  });

  test('L5 registered in ALL_LEXICONS', () => {
    const names = ALL_LEXICONS.map((l) => l.name);
    expect(names).toContain('brap');
  });

  test('L6 isBRAPCategory accepts all 9 cells, rejects others', () => {
    for (const cell of ['na', 'nc', 'ns', 'se', 'sm', 'sf', 'ls', 'lr', 'lp']) {
      expect(isBRAPCategory(cell)).toBe(true);
    }
    expect(isBRAPCategory('nope')).toBe(false);
    expect(isBRAPCategory('')).toBe(false);
    expect(isBRAPCategory('NA')).toBe(false); // case-sensitive
  });

  test('L7 BRAP_VERBS has the 8 expected actions', () => {
    expect(BRAP_VERBS).toEqual([
      'score',
      'refine',
      'probe',
      'mitigate',
      'escalate',
      'classify',
      'accept',
      'reject',
    ]);
  });

  test('L8 isBRAPVerb accepts known verbs, rejects unknown', () => {
    expect(isBRAPVerb('score')).toBe(true);
    expect(isBRAPVerb('mitigate')).toBe(true);
    expect(isBRAPVerb('refine')).toBe(true);
    expect(isBRAPVerb('reject')).toBe(true);
    expect(isBRAPVerb('unknown-action')).toBe(false);
    expect(isBRAPVerb('')).toBe(false);
  });

  test('L9 parity with existing lexicon shape', () => {
    // Every lexicon in ALL_LEXICONS must have { name, categories, header }
    for (const lex of ALL_LEXICONS) {
      expect(typeof lex.name).toBe('string');
      expect(Array.isArray(lex.categories)).toBe(true);
      expect(typeof lex.header).toBe('function');
    }
  });

  test('L10 ALL_LEXICONS headers are all injective', () => {
    for (const lex of ALL_LEXICONS) {
      const result = verifyLexiconInjective(lex);
      expect(result.injective).toBe(true);
    }
  });
});

```
