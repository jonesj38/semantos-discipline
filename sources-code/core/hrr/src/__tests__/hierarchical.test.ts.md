---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/hrr/src/__tests__/hierarchical.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.022534+00:00
---

# core/hrr/src/__tests__/hierarchical.test.ts

```ts
/**
 * WI-B5 hierarchical HRR tests.
 *
 *   WI-B5-T-summary-stable   — summary is unchanged by clause count
 *   WI-B5-T-detail-encodes   — detail captures clause content
 *   WI-B5-T-noise-budget     — retrieval quality within octave-0 budget at 10+ clauses
 */

import { describe, it, expect } from 'bun:test';
import { cosine } from '../encode';
import { encodeHierarchical, detailSimilarity } from '../hierarchical';

// ── WI-B5-T-summary-stable ────────────────────────────────────────────────────

describe('WI-B5-T-summary-stable', () => {
  it('summary is identical regardless of clause count', () => {
    const base = { domainFlag: 7, juralCategory: 'obligation', lexicon: 'jural', action: 'report_issue' };
    const zero  = encodeHierarchical({ ...base, clauses: [] });
    const three = encodeHierarchical({ ...base, clauses: [
      { role: 'payment_clause', filler: 'rent_due' },
      { role: 'condition_clause', filler: 'no_smoking' },
      { role: 'obligation_clause', filler: 'maintain_property' },
    ]});
    const ten = encodeHierarchical({ ...base, clauses: Array.from({ length: 10 }, (_, i) => ({
      role: `clause_${i}`,
      filler: `value_${i}`,
    }))});

    // Summary must be exactly the same regardless of how many clauses
    expect(cosine(zero.summary, three.summary)).toBeCloseTo(1, 10);
    expect(cosine(zero.summary, ten.summary)).toBeCloseTo(1, 10);
  });

  it('summary is the same as encodePartialIntent for the same metadata', () => {
    const { encodePartialIntent } = require('../encode');
    const opts = { domainFlag: 7, juralCategory: 'obligation', lexicon: 'jural', action: 'report_issue' };
    const hier = encodeHierarchical({ ...opts, clauses: [{ role: 'r', filler: 'f' }] });
    const partial = encodePartialIntent(opts);
    expect(cosine(hier.summary, partial)).toBeCloseTo(1, 10);
  });

  it('clause count is recorded on the result', () => {
    const base = { domainFlag: 7, juralCategory: 'obligation', lexicon: 'jural', clauses: [{ role: 'r', filler: 'f' }, { role: 'r2', filler: 'f2' }] };
    expect(encodeHierarchical(base).clauseCount).toBe(2);
    expect(encodeHierarchical({ ...base, clauses: [] }).clauseCount).toBe(0);
  });
});

// ── WI-B5-T-detail-encodes ────────────────────────────────────────────────────

describe('WI-B5-T-detail-encodes', () => {
  it('two contracts with identical clauses produce detailSimilarity = 1', () => {
    const opts = {
      domainFlag: 7, juralCategory: 'obligation', lexicon: 'jural',
      clauses: [{ role: 'payment_clause', filler: 'rent_due' }],
    };
    const a = encodeHierarchical(opts);
    const b = encodeHierarchical(opts);
    expect(detailSimilarity(a, b)).toBeCloseTo(1, 10);
  });

  it('more shared clauses → higher detail similarity', () => {
    const base = { domainFlag: 7, juralCategory: 'obligation', lexicon: 'jural' };
    const ref = encodeHierarchical({
      ...base,
      clauses: [
        { role: 'c1', filler: 'v1' },
        { role: 'c2', filler: 'v2' },
        { role: 'c3', filler: 'v3' },
      ],
    });

    const twoShared = encodeHierarchical({
      ...base,
      clauses: [
        { role: 'c1', filler: 'v1' },
        { role: 'c2', filler: 'v2' },
        { role: 'c4', filler: 'v4' }, // different
      ],
    });

    const oneShared = encodeHierarchical({
      ...base,
      clauses: [
        { role: 'c1', filler: 'v1' },
        { role: 'c5', filler: 'v5' }, // different
        { role: 'c6', filler: 'v6' }, // different
      ],
    });

    expect(detailSimilarity(ref, twoShared)).toBeGreaterThan(detailSimilarity(ref, oneShared));
  });

  it('cross-domain detail similarity is near zero', () => {
    const tradesClauses = [{ role: 'obligation_clause', filler: 'maintenance_required' }];
    const scadaClauses  = [{ role: 'interlock_clause', filler: 'pressure_trip' }];

    const trades = encodeHierarchical({ domainFlag: 7,  juralCategory: 'obligation', lexicon: 'jural',           clauses: tradesClauses });
    const scada  = encodeHierarchical({ domainFlag: 11, juralCategory: 'obligation', lexicon: 'control-systems', clauses: scadaClauses  });

    expect(Math.abs(detailSimilarity(trades, scada))).toBeLessThan(0.15);
  });
});

// ── WI-B5-T-noise-budget ──────────────────────────────────────────────────────

describe('WI-B5-T-noise-budget', () => {
  it('summary self-similarity is 1 even for a 10-clause contract', () => {
    const opts = {
      domainFlag: 7, juralCategory: 'obligation', lexicon: 'jural', action: 'report_issue',
      clauses: Array.from({ length: 10 }, (_, i) => ({ role: `r${i}`, filler: `f${i}` })),
    };
    const a = encodeHierarchical(opts);
    const b = encodeHierarchical(opts);
    expect(cosine(a.summary, b.summary)).toBeCloseTo(1, 10);
  });

  it('summary similarity to same-category contract exceeds octave-0 threshold (0.7)', () => {
    const sharedMeta = { domainFlag: 7, juralCategory: 'obligation', lexicon: 'jural', action: 'report_issue' };
    const a = encodeHierarchical({
      ...sharedMeta,
      clauses: Array.from({ length: 8 }, (_, i) => ({ role: `r${i}`, filler: `f${i}` })),
    });
    const b = encodeHierarchical({
      ...sharedMeta,
      clauses: Array.from({ length: 12 }, (_, i) => ({ role: `s${i}`, filler: `g${i}` })),
    });
    // Summaries share all metadata → cosine should be 1 (summaries don't encode clauses)
    expect(cosine(a.summary, b.summary)).toBeGreaterThan(0.7);
  });

  it('detail self-similarity is 1 for a 15-clause contract', () => {
    const opts = {
      domainFlag: 7, juralCategory: 'obligation', lexicon: 'jural',
      clauses: Array.from({ length: 15 }, (_, i) => ({ role: `clause_${i}`, filler: `term_${i}` })),
    };
    const a = encodeHierarchical(opts);
    const b = encodeHierarchical(opts);
    expect(detailSimilarity(a, b)).toBeCloseTo(1, 10);
  });
});

```
