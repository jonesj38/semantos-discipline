---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/reducer/__tests__/analogical-rank-pass.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.359037+00:00
---

# runtime/intent/src/reducer/__tests__/analogical-rank-pass.test.ts

```ts
/**
 * WI-B4 analogical-rank-pass tests.
 *
 * Three test groups per the implementation plan:
 *   WI-B4-T-self-similarity-one
 *   WI-B4-T-monotonic-similarity
 *   WI-B4-T-rank-pass-behaviour
 */

import { describe, it, expect } from 'bun:test';
import type { Intent, TaggedCategory } from '@semantos/semantos-sir';
import { encodePartialIntent, cosine } from '@semantos/hrr';
import { analogicalRankPass } from '../analogical-rank-pass';
import type { PassContext, GrammarSpec } from '../types';

// ── Shared stubs ──────────────────────────────────────────────────────────────

const TRADES_GRAMMAR: GrammarSpec = {
  extensionId: 'trades',
  domainFlag: 7,
  lexicon: { name: 'jural', categories: ['obligation', 'declaration', 'power'] },
  defaultTaxonomyWhat: 'maintenance.job',
  objectTypes: [{ name: 'maintenance.job', description: '' }],
  actions: [{ name: 'report_issue', category: 'declaration', authoredBy: ['tenant'], description: '' }],
  trustClass: 'interpretive',
};

function makeStubLibrary(
  entries: Array<{ domainFlag: number; juralCategory: string; cellId: string; similarity: number }>,
): PassContext['analogicalLibrary'] {
  return {
    nearest(
      _q: Float64Array,
      domainFlag: number,
      juralCategory: string,
      k: number,
      _caps: Set<number>,
    ) {
      return entries
        .filter(e => e.domainFlag === domainFlag && e.juralCategory === juralCategory)
        .slice(0, k)
        .map(e => ({ cellId: e.cellId, similarity: e.similarity }));
    },
  };
}

function makeCategory(category: string, lexicon: string): TaggedCategory {
  return { lexicon, category } as unknown as TaggedCategory;
}

function makeCtx(
  grammar: GrammarSpec,
  library?: PassContext['analogicalLibrary'],
): PassContext {
  return {
    state: { taggedFacts: [], conversationSummary: 'test' },
    grammar,
    analogicalLibrary: library,
  };
}

function candidateTemplates(cellIds: string[]) {
  return cellIds.map(id => ({ templateCellId: id, similarity: 0.9 }));
}

// ── WI-B4-T-self-similarity-one ──────────────────────────────────────────────

describe('WI-B4-T-self-similarity-one', () => {
  it('encoding the same opts twice gives cosine 1', () => {
    const opts = { domainFlag: 7, juralCategory: 'obligation', lexicon: 'jural', action: 'report_issue', objectType: 'maintenance.job', trustClass: 'interpretive', howTaxonomy: 'how.technical.api.rest' };
    const a = encodePartialIntent(opts);
    const b = encodePartialIntent(opts);
    expect(cosine(a, b)).toBeCloseTo(1, 10);
  });

  it('different actions produce cosine < 1', () => {
    const base = { domainFlag: 7, juralCategory: 'obligation', lexicon: 'jural' };
    const a = encodePartialIntent({ ...base, action: 'report_issue' });
    const b = encodePartialIntent({ ...base, action: 'close_job' });
    expect(cosine(a, b)).toBeLessThan(1);
  });

  it('adding howTaxonomy changes the vector', () => {
    const base = { domainFlag: 7, juralCategory: 'obligation', lexicon: 'jural', action: 'report_issue' };
    const withoutHow = encodePartialIntent(base);
    const withHow = encodePartialIntent({ ...base, howTaxonomy: 'how.technical.api.rest' });
    expect(cosine(withoutHow, withHow)).toBeLessThan(1);
    expect(cosine(withoutHow, withHow)).toBeGreaterThan(0.5); // still highly similar
  });
});

// ── WI-B4-T-monotonic-similarity ─────────────────────────────────────────────

describe('WI-B4-T-monotonic-similarity', () => {
  it('each additional mutation reduces similarity to the original', () => {
    const base = encodePartialIntent({
      domainFlag: 7,
      juralCategory: 'obligation',
      lexicon: 'jural',
      action: 'report_issue',
      objectType: 'maintenance.job',
    });

    const oneChange = encodePartialIntent({
      domainFlag: 7,
      juralCategory: 'obligation',
      lexicon: 'jural',
      action: 'close_job',        // one field mutated
      objectType: 'maintenance.job',
    });

    const twoChanges = encodePartialIntent({
      domainFlag: 7,
      juralCategory: 'obligation',
      lexicon: 'jural',
      action: 'close_job',        // mutated
      objectType: 'invoice',      // also mutated
    });

    const simOne = cosine(base, oneChange);
    const simTwo = cosine(base, twoChanges);

    expect(cosine(base, base)).toBeCloseTo(1, 10);
    expect(simOne).toBeLessThan(1);
    expect(simTwo).toBeLessThan(simOne);
  });

  it('cross-domain similarity is near zero', () => {
    const trades = encodePartialIntent({ domainFlag: 7,  juralCategory: 'obligation', lexicon: 'jural', action: 'report_issue' });
    const scada  = encodePartialIntent({ domainFlag: 11, juralCategory: 'obligation', lexicon: 'control-systems', action: 'open_valve' });
    expect(Math.abs(cosine(trades, scada))).toBeLessThan(0.1);
  });
});

// ── WI-B4-T-rank-pass-behaviour ──────────────────────────────────────────────

describe('WI-B4-T-rank-pass-behaviour', () => {
  it('returns empty analogicalMatches when no library is provided', async () => {
    const acc: Partial<Intent> = {
      category: makeCategory('obligation', 'jural'),
      action: 'report_issue',
      producerMeta: { candidateTemplates: candidateTemplates(['t1', 't2']) } as unknown as Intent['producerMeta'],
    };
    const result = await analogicalRankPass(acc, makeCtx(TRADES_GRAMMAR));
    expect(result.pass).toBe('analogical_rank');
    expect((result.contribution.producerMeta as { analogicalMatches: unknown[] }).analogicalMatches).toEqual([]);
    expect(result.confidence).toBe(1);
  });

  it('returns empty analogicalMatches when WI-B3 produced no candidates', async () => {
    const lib = makeStubLibrary([{ domainFlag: 7, juralCategory: 'obligation', cellId: 'x', similarity: 0.9 }]);
    const acc: Partial<Intent> = {
      category: makeCategory('obligation', 'jural'),
      producerMeta: { candidateTemplates: [] } as unknown as Intent['producerMeta'],
    };
    const result = await analogicalRankPass(acc, makeCtx(TRADES_GRAMMAR, lib));
    expect((result.contribution.producerMeta as { analogicalMatches: unknown[] }).analogicalMatches).toEqual([]);
  });

  it('returns empty when no category in accumulated', async () => {
    const lib = makeStubLibrary([{ domainFlag: 7, juralCategory: 'obligation', cellId: 'x', similarity: 0.9 }]);
    const acc: Partial<Intent> = {
      producerMeta: { candidateTemplates: candidateTemplates(['x']) } as unknown as Intent['producerMeta'],
    };
    const result = await analogicalRankPass(acc, makeCtx(TRADES_GRAMMAR, lib));
    expect((result.contribution.producerMeta as { analogicalMatches: unknown[] }).analogicalMatches).toEqual([]);
  });

  it('writes analogicalMatches from library re-query', async () => {
    const lib = makeStubLibrary([
      { domainFlag: 7, juralCategory: 'obligation', cellId: 'rank-1', similarity: 0.91 },
      { domainFlag: 7, juralCategory: 'obligation', cellId: 'rank-2', similarity: 0.75 },
    ]);
    const acc: Partial<Intent> = {
      category: makeCategory('obligation', 'jural'),
      action: 'report_issue',
      taxonomy: { what: 'maintenance.job', how: 'how.technical.api.rest', why: '' },
      producerMeta: { candidateTemplates: candidateTemplates(['rank-1', 'rank-2']) } as unknown as Intent['producerMeta'],
    };
    const result = await analogicalRankPass(acc, makeCtx(TRADES_GRAMMAR, lib));
    const matches = (result.contribution.producerMeta as { analogicalMatches: Array<{ templateCellId: string; similarity: number }> }).analogicalMatches;
    expect(matches.length).toBeGreaterThanOrEqual(1);
    expect(matches.map(m => m.templateCellId)).toContain('rank-1');
    for (const m of matches) {
      expect(typeof m.templateCellId).toBe('string');
      expect(typeof m.similarity).toBe('number');
    }
  });

  it('pass confidence is always 1', async () => {
    const lib = makeStubLibrary([{ domainFlag: 7, juralCategory: 'obligation', cellId: 'c', similarity: 0.8 }]);
    const acc: Partial<Intent> = {
      category: makeCategory('obligation', 'jural'),
      producerMeta: { candidateTemplates: candidateTemplates(['c']) } as unknown as Intent['producerMeta'],
    };
    const result = await analogicalRankPass(acc, makeCtx(TRADES_GRAMMAR, lib));
    expect(result.confidence).toBe(1);
    expect(result.flags).toEqual([]);
  });
});

```
