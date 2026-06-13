---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/semantos-sir/src/__tests__/tessera-lexicon.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.814498+00:00
---

# core/semantos-sir/src/__tests__/tessera-lexicon.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import {
  TesseraLexicon,
  ALL_LEXICONS,
  verifyLexiconInjective,
  isCategoryOf,
  type TesseraCategory,
} from '../index';

describe('TesseraLexicon', () => {
  test('L1 exposes exactly the 13 tessera discourse categories', () => {
    expect(TesseraLexicon.categories).toEqual([
      'harvest',
      'ferment',
      'rack',
      'blend',
      'addition',
      'bottle',
      'label',
      'custody-transfer',
      'care-event',
      'excursion',
      'tamper-event',
      'scan',
      'tasting-note',
    ]);
  });

  test('L2 name is "tessera"', () => {
    expect(TesseraLexicon.name).toBe('tessera');
  });

  test('L3 header is injective on all 13 categories', () => {
    const result = verifyLexiconInjective(TesseraLexicon);
    expect(result.injective).toBe(true);
  });

  test('L4 header rendering uppercases + underscore-substitutes the category identifier', () => {
    expect(TesseraLexicon.header('harvest')).toBe('TESSERA_HARVEST');
    expect(TesseraLexicon.header('blend')).toBe('TESSERA_BLEND');
    expect(TesseraLexicon.header('custody-transfer')).toBe('TESSERA_CUSTODY_TRANSFER');
    expect(TesseraLexicon.header('care-event')).toBe('TESSERA_CARE_EVENT');
    expect(TesseraLexicon.header('tamper-event')).toBe('TESSERA_TAMPER_EVENT');
    expect(TesseraLexicon.header('tasting-note')).toBe('TESSERA_TASTING_NOTE');
  });

  test('L5 registered in ALL_LEXICONS', () => {
    const names = ALL_LEXICONS.map((l) => l.name);
    expect(names).toContain('tessera');
  });

  test('L6 all category-pair headers are pairwise distinct (manual injectivity)', () => {
    // Mirrors the Lean `tesseraHeader_injective` theorem at the value level.
    // V5.7 lands the Lean proof; V0.4 holds the runtime equivalent here.
    const cats = TesseraLexicon.categories;
    const headers = cats.map((c) => TesseraLexicon.header(c));
    expect(new Set(headers).size).toBe(cats.length);
  });

  test('L7 isCategoryOf accepts every declared category, rejects others', () => {
    for (const cat of TesseraLexicon.categories) {
      expect(isCategoryOf(TesseraLexicon, cat)).toBe(true);
    }
    expect(isCategoryOf(TesseraLexicon, 'unknown')).toBe(false);
    expect(isCategoryOf(TesseraLexicon, '')).toBe(false);
    // case-sensitive: 'HARVEST' is the header, not the category
    expect(isCategoryOf(TesseraLexicon, 'HARVEST')).toBe(false);
    // shape-sensitive: 'custody_transfer' is not the category form
    expect(isCategoryOf(TesseraLexicon, 'custody_transfer')).toBe(false);
  });

  test('L8 type-level coherence — every TesseraCategory is in the categories tuple', () => {
    // Compile-time check via exhaustive switch + runtime confirmation.
    const acceptAll = (c: TesseraCategory): string => {
      switch (c) {
        case 'harvest':
        case 'ferment':
        case 'rack':
        case 'blend':
        case 'addition':
        case 'bottle':
        case 'label':
        case 'custody-transfer':
        case 'care-event':
        case 'excursion':
        case 'tamper-event':
        case 'scan':
        case 'tasting-note':
          return TesseraLexicon.header(c);
      }
    };
    for (const c of TesseraLexicon.categories) {
      expect(acceptAll(c)).toBeTruthy();
    }
  });

  test('L9 has shape parity with the other registered lexicons', () => {
    const lex = TesseraLexicon;
    expect(typeof lex.name).toBe('string');
    expect(Array.isArray(lex.categories)).toBe(true);
    expect(typeof lex.header).toBe('function');
  });

  test('L10 ALL_LEXICONS headers remain injective after adding tessera', () => {
    expect(ALL_LEXICONS.length).toBeGreaterThanOrEqual(12);
    expect(ALL_LEXICONS.some((l) => l.name === 'tessera')).toBe(true);
    for (const lex of ALL_LEXICONS) {
      const result = verifyLexiconInjective(lex);
      expect(result.injective).toBe(true);
    }
  });

  test('L11 categories cover the 13 speech acts named in TESSERA-CARTRIDGE.md §3.4', () => {
    // The §3.4 categories drive the V5.7 ritual obligation; this ties the
    // TypeScript authority to the canon document so a drift fails the gate.
    const speechActs = new Set([
      'harvest',
      'ferment',
      'rack',
      'blend',
      'addition',
      'bottle',
      'label',
      'custody-transfer',
      'care-event',
      'excursion',
      'tamper-event',
      'scan',
      'tasting-note',
    ]);
    for (const cat of TesseraLexicon.categories) {
      expect(speechActs.has(cat)).toBe(true);
      speechActs.delete(cat);
    }
    expect(speechActs.size).toBe(0);
  });
});

```
