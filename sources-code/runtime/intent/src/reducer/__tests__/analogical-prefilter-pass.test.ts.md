---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/reducer/__tests__/analogical-prefilter-pass.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.358729+00:00
---

# runtime/intent/src/reducer/__tests__/analogical-prefilter-pass.test.ts

```ts
/**
 * WI-B3 analogical-prefilter-pass tests.
 *
 * Three RED→GREEN tests per the implementation plan:
 *   WI-B3-T-emits-empty-on-cold-library
 *   WI-B3-T-finds-known-template
 *   WI-B3-T-respects-domain-flag
 */

import { describe, it, expect } from 'bun:test';
import type { Intent, TaggedCategory } from '@semantos/semantos-sir';
import { analogicalPrefilterPass } from '../analogical-prefilter-pass';
import type { PassContext, GrammarSpec } from '../types';

// ── Minimal stub library ──────────────────────────────────────────────────────

interface StubEntry { cellId: string; similarity: number }

/** Stub HRR library — returns a fixed list of entries for a given (domain, category). */
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
    ): StubEntry[] {
      return entries
        .filter(e => e.domainFlag === domainFlag && e.juralCategory === juralCategory)
        .slice(0, k)
        .map(e => ({ cellId: e.cellId, similarity: e.similarity }));
    },
  };
}

// ── Grammar stubs ─────────────────────────────────────────────────────────────

const TRADES_GRAMMAR: GrammarSpec = {
  extensionId: 'trades',
  domainFlag: 7,
  lexicon: { name: 'jural', categories: ['declaration', 'obligation', 'power', 'condition', 'transfer'] },
  defaultTaxonomyWhat: 'maintenance.job',
  objectTypes: [{ name: 'maintenance.job', description: '' }],
  actions: [{ name: 'report_issue', category: 'declaration', authoredBy: ['tenant'], description: '' }],
  trustClass: 'interpretive',
};

const SCADA_GRAMMAR: GrammarSpec = {
  extensionId: 'scada',
  domainFlag: 11,
  lexicon: { name: 'control-systems', categories: ['measurement', 'actuation', 'interlock', 'alarm'] },
  defaultTaxonomyWhat: 'scada.equipment',
  objectTypes: [{ name: 'scada.equipment', description: '' }],
  actions: [{ name: 'open_valve', category: 'actuation', authoredBy: ['operator'], description: '' }],
  trustClass: 'authoritative',
};

function makeCategory(category: string, lexicon: string): TaggedCategory {
  return { lexicon, category } as unknown as TaggedCategory;
}

function makeCtx(
  grammar: GrammarSpec,
  accumulated: Partial<Intent>,
  library?: PassContext['analogicalLibrary'],
): [Partial<Intent>, PassContext] {
  return [
    accumulated,
    {
      state: { taggedFacts: [], conversationSummary: 'test' },
      grammar,
      analogicalLibrary: library,
    },
  ];
}

// ── WI-B3-T-emits-empty-on-cold-library ──────────────────────────────────────

describe('WI-B3-T-emits-empty-on-cold-library', () => {
  it('returns empty candidateTemplates when no library is provided', async () => {
    const [acc, ctx] = makeCtx(TRADES_GRAMMAR, {
      category: makeCategory('obligation', 'jural'),
      action: 'report_issue',
    });
    const result = await analogicalPrefilterPass(acc, ctx);
    expect(result.pass).toBe('analogical_prefilter');
    expect((result.contribution.producerMeta as { candidateTemplates: unknown[] }).candidateTemplates).toEqual([]);
  });

  it('confidence is 1 when library is absent (vacuously satisfied)', async () => {
    const [acc, ctx] = makeCtx(TRADES_GRAMMAR, { category: makeCategory('obligation', 'jural') });
    const result = await analogicalPrefilterPass(acc, ctx);
    expect(result.confidence).toBe(1);
    expect(result.flags).toEqual([]);
  });

  it('returns empty candidateTemplates when library has no matching entries', async () => {
    const emptyLib = makeStubLibrary([]); // no entries at all
    const [acc, ctx] = makeCtx(TRADES_GRAMMAR, {
      category: makeCategory('obligation', 'jural'),
      action: 'report_issue',
    }, emptyLib);
    const result = await analogicalPrefilterPass(acc, ctx);
    expect((result.contribution.producerMeta as { candidateTemplates: unknown[] }).candidateTemplates).toEqual([]);
    expect(result.confidence).toBe(1);
  });

  it('returns empty when accumulated has no category yet', async () => {
    const lib = makeStubLibrary([{ domainFlag: 7, juralCategory: 'obligation', cellId: 'c1', similarity: 0.9 }]);
    const [acc, ctx] = makeCtx(TRADES_GRAMMAR, {}, lib); // no category
    const result = await analogicalPrefilterPass(acc, ctx);
    expect((result.contribution.producerMeta as { candidateTemplates: unknown[] }).candidateTemplates).toEqual([]);
  });
});

// ── WI-B3-T-finds-known-template ─────────────────────────────────────────────

describe('WI-B3-T-finds-known-template', () => {
  it('writes top-K matches to producerMeta.candidateTemplates', async () => {
    const lib = makeStubLibrary([
      { domainFlag: 7, juralCategory: 'obligation', cellId: 'template-1', similarity: 0.88 },
      { domainFlag: 7, juralCategory: 'obligation', cellId: 'template-2', similarity: 0.74 },
      { domainFlag: 7, juralCategory: 'obligation', cellId: 'template-3', similarity: 0.61 },
    ]);
    const [acc, ctx] = makeCtx(TRADES_GRAMMAR, {
      category: makeCategory('obligation', 'jural'),
      action: 'report_issue',
      taxonomy: { what: 'maintenance.job', how: 'how.technical', why: 'why.integration.trades' },
    }, lib);

    const result = await analogicalPrefilterPass(acc, ctx);
    const templates = (result.contribution.producerMeta as { candidateTemplates: Array<{ templateCellId: string; similarity: number }> }).candidateTemplates;

    expect(templates.length).toBeGreaterThanOrEqual(1);
    // template-1 should appear (highest similarity)
    expect(templates.map(t => t.templateCellId)).toContain('template-1');
    // each entry has templateCellId and similarity
    for (const t of templates) {
      expect(typeof t.templateCellId).toBe('string');
      expect(typeof t.similarity).toBe('number');
    }
  });

  it('candidate count does not exceed TOP_K', async () => {
    const lib = makeStubLibrary(
      Array.from({ length: 10 }, (_, i) => ({
        domainFlag: 7,
        juralCategory: 'obligation',
        cellId: `c${i}`,
        similarity: 1 - i * 0.05,
      })),
    );
    const [acc, ctx] = makeCtx(TRADES_GRAMMAR, {
      category: makeCategory('obligation', 'jural'),
    }, lib);

    const result = await analogicalPrefilterPass(acc, ctx);
    const templates = (result.contribution.producerMeta as { candidateTemplates: unknown[] }).candidateTemplates;
    expect(templates.length).toBeLessThanOrEqual(5); // TOP_K = 5
  });

  it('pass confidence is 1 even when candidates are found', async () => {
    const lib = makeStubLibrary([{ domainFlag: 7, juralCategory: 'obligation', cellId: 'c1', similarity: 0.9 }]);
    const [acc, ctx] = makeCtx(TRADES_GRAMMAR, { category: makeCategory('obligation', 'jural') }, lib);
    const result = await analogicalPrefilterPass(acc, ctx);
    expect(result.confidence).toBe(1);
  });
});

// ── WI-B3-T-respects-domain-flag ─────────────────────────────────────────────

describe('WI-B3-T-respects-domain-flag', () => {
  it('trades query with trades library returns trades templates', async () => {
    const lib = makeStubLibrary([
      { domainFlag: 7,  juralCategory: 'obligation', cellId: 'trades-t1',  similarity: 0.85 },
      { domainFlag: 11, juralCategory: 'obligation', cellId: 'scada-t1',   similarity: 0.85 },
    ]);
    const [acc, ctx] = makeCtx(TRADES_GRAMMAR, { category: makeCategory('obligation', 'jural') }, lib);
    const result = await analogicalPrefilterPass(acc, ctx);
    const ids = (result.contribution.producerMeta as { candidateTemplates: Array<{ templateCellId: string }> }).candidateTemplates.map(t => t.templateCellId);
    expect(ids).toContain('trades-t1');
    expect(ids).not.toContain('scada-t1');
  });

  it('SCADA query with SCADA grammar returns SCADA templates only', async () => {
    const lib = makeStubLibrary([
      { domainFlag: 7,  juralCategory: 'actuation', cellId: 'trades-a1', similarity: 0.90 },
      { domainFlag: 11, juralCategory: 'actuation', cellId: 'scada-a1',  similarity: 0.90 },
    ]);
    const [acc, ctx] = makeCtx(SCADA_GRAMMAR, { category: makeCategory('actuation', 'control-systems') }, lib);
    const result = await analogicalPrefilterPass(acc, ctx);
    const ids = (result.contribution.producerMeta as { candidateTemplates: Array<{ templateCellId: string }> }).candidateTemplates.map(t => t.templateCellId);
    expect(ids).toContain('scada-a1');
    expect(ids).not.toContain('trades-a1');
  });

  it('pass uses grammar.domainFlag, not state.domainFlag, for the query', async () => {
    const lib = makeStubLibrary([
      { domainFlag: 7, juralCategory: 'obligation', cellId: 'correct', similarity: 0.9 },
    ]);
    // state carries a mismatched domainFlag — grammar's should win
    const [acc, ctx] = makeCtx(
      TRADES_GRAMMAR,
      { category: makeCategory('obligation', 'jural') },
      lib,
    );
    // Override state.domainFlag to something wrong
    (ctx.state as { domainFlag?: number }).domainFlag = 99;
    const result = await analogicalPrefilterPass(acc, ctx);
    const ids = (result.contribution.producerMeta as { candidateTemplates: Array<{ templateCellId: string }> }).candidateTemplates.map(t => t.templateCellId);
    expect(ids).toContain('correct');
  });
});

```
