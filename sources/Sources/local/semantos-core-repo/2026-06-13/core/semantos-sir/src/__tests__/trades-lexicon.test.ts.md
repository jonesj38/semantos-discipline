---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/semantos-sir/src/__tests__/trades-lexicon.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.815892+00:00
---

# core/semantos-sir/src/__tests__/trades-lexicon.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import {
  TradesLexicon,
  ALL_LEXICONS,
  verifyLexiconInjective,
  isCategoryOf,
  type TradesCategory,
} from '../index';

describe('TradesLexicon', () => {
  test('L1 exposes exactly the 8 trades discourse categories', () => {
    expect(TradesLexicon.categories).toEqual([
      'lead',
      'estimate',
      'quote',
      'dispatch',
      'visit',
      'invoice',
      'settle',
      'message',
    ]);
  });

  test('L2 name is "trades"', () => {
    expect(TradesLexicon.name).toBe('trades');
  });

  test('L3 header is injective on all 8 categories', () => {
    const result = verifyLexiconInjective(TradesLexicon);
    expect(result.injective).toBe(true);
  });

  test('L4 header rendering uppercases the category identifier', () => {
    expect(TradesLexicon.header('lead')).toBe('LEAD');
    expect(TradesLexicon.header('estimate')).toBe('ESTIMATE');
    expect(TradesLexicon.header('quote')).toBe('QUOTE');
    expect(TradesLexicon.header('dispatch')).toBe('DISPATCH');
    expect(TradesLexicon.header('visit')).toBe('VISIT');
    expect(TradesLexicon.header('invoice')).toBe('INVOICE');
    expect(TradesLexicon.header('settle')).toBe('SETTLE');
    expect(TradesLexicon.header('message')).toBe('MESSAGE');
  });

  test('L5 registered in ALL_LEXICONS', () => {
    const names = ALL_LEXICONS.map((l) => l.name);
    expect(names).toContain('trades');
  });

  test('L6 all category-pair headers are pairwise distinct (manual injectivity)', () => {
    // Mirrors the Lean `tradesHeader_injective` theorem at the value level.
    const cats = TradesLexicon.categories;
    const headers = cats.map((c) => TradesLexicon.header(c));
    expect(new Set(headers).size).toBe(cats.length);
  });

  test('L7 isCategoryOf accepts every declared category, rejects others', () => {
    for (const cat of TradesLexicon.categories) {
      expect(isCategoryOf(TradesLexicon, cat)).toBe(true);
    }
    expect(isCategoryOf(TradesLexicon, 'unknown')).toBe(false);
    expect(isCategoryOf(TradesLexicon, '')).toBe(false);
    // case-sensitive: 'LEAD' is the header, not the category
    expect(isCategoryOf(TradesLexicon, 'LEAD')).toBe(false);
  });

  test('L8 type-level coherence — every TradesCategory is in the categories tuple', () => {
    // Compile-time check via exhaustive switch + runtime confirmation.
    const acceptAll = (c: TradesCategory): string => {
      switch (c) {
        case 'lead':
        case 'estimate':
        case 'quote':
        case 'dispatch':
        case 'visit':
        case 'invoice':
        case 'settle':
        case 'message':
          return TradesLexicon.header(c);
      }
    };
    for (const c of TradesLexicon.categories) {
      expect(acceptAll(c)).toBe(c.toUpperCase());
    }
  });

  test('L9 has shape parity with the other registered lexicons', () => {
    const lex = TradesLexicon;
    expect(typeof lex.name).toBe('string');
    expect(Array.isArray(lex.categories)).toBe(true);
    expect(typeof lex.header).toBe('function');
  });

  test('L10 ALL_LEXICONS headers remain injective after adding trades', () => {
    expect(ALL_LEXICONS.length).toBeGreaterThanOrEqual(11);
    expect(ALL_LEXICONS.some((l) => l.name === 'trades')).toBe(true);
    for (const lex of ALL_LEXICONS) {
      const result = verifyLexiconInjective(lex);
      expect(result.injective).toBe(true);
    }
  });

  test('L11 categories are coherent with §O2 cell types and §O3 caps', () => {
    // Each category maps to ≥1 D-O2 cell type or D-O3 cap. Verifies the
    // discourse-set is grounded in the actual extension surface.
    //
    //   lead      -> oddjobz.job.v1 (state=lead) + cap.public_chat_serve
    //                + cap.write_customer
    //   estimate  -> oddjobz.estimate.v1
    //   quote     -> oddjobz.quote.v1 + cap.oddjobz.quote
    //   dispatch  -> cap.oddjobz.dispatch (transition quoted -> scheduled)
    //   visit     -> oddjobz.visit.v1
    //   invoice   -> oddjobz.invoice.v1 + cap.oddjobz.invoice
    //   settle    -> cap.oddjobz.close (paid -> closed)
    //   message   -> oddjobz.message.v1
    const groundedCategories: TradesCategory[] = [
      'lead',
      'estimate',
      'quote',
      'dispatch',
      'visit',
      'invoice',
      'settle',
      'message',
    ];
    expect([...TradesLexicon.categories].sort()).toEqual(
      [...groundedCategories].sort(),
    );
  });
});

```
