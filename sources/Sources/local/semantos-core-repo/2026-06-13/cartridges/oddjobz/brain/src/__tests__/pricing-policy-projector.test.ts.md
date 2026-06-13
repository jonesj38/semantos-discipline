---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/__tests__/pricing-policy-projector.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.510387+00:00
---

# cartridges/oddjobz/brain/src/__tests__/pricing-policy-projector.test.ts

```ts
/**
 * Pricing-policy projector conformance (A5.P1a).
 *
 * Pins the safe-default contract: no policy cell ⇒ not configured
 * (caller routes to formal quote, never calls calculateROM); a
 * present cell ⇒ its embedded `policy` verbatim. Pure; intra-package
 * only (no @semantos/intent) → runnable in this worktree.
 */

import { describe, expect, test } from 'bun:test';
import {
  resolvePricingPolicy,
  shouldAutoRom,
  classifySuburbGroup,
  classifyEffortBand,
  mapEstimatorRequestToRomInput,
  makeRomEstimatorFn,
  formatRomWording,
} from '../pricing-policy-projector.js';
import type { OddjobzPricingPolicy } from '../cell-types/index.js';
import type { PricingPolicy } from '../rom.js';
import type { EstimatorRequest } from '../conversation/state-manager.js';

const baseReq: EstimatorRequest = {
  jobType: 'plumbing',
  subcategory: null,
  quantity: null,
  scopeDescription: 'leaking tap',
  materials: null,
  accessDifficulty: 'ground_level',
  suburb: 'Paddington',
  postcode: '4064',
  urgency: 'flexible',
  allowWidenedBand: false,
};

const serviceArea: NonNullable<PricingPolicy['serviceArea']> = {
  homePostcode: '4000',
  radiusBands: [
    { maxKm: 10, suburbGroup: 'core' },
    { maxKm: 30, suburbGroup: 'extended' },
    { maxKm: 9999, suburbGroup: 'outside' },
  ],
  outsideDeclines: true,
};

const policy: PricingPolicy = {
  baseRates: { short: { min: 200, max: 400 } },
  travelModifiers: { core: { surcharge: 0, label: 'Core' } },
  categoryModifiers: {},
  complexityModifiers: {},
  presentation: { roundTo: 10, rangeLabel: 'Typically', disclaimer: 'Ballpark.' },
};

const cell: OddjobzPricingPolicy = {
  policyId: '11111111-2222-3333-4444-555555555555',
  hatId: 'hat-operator-todd',
  version: 1,
  policy,
  createdAt: '2026-05-17T00:00:00.000Z',
  updatedAt: '2026-05-17T00:00:00.000Z',
};

describe('resolvePricingPolicy — safe-default contract', () => {
  test('null/undefined ⇒ not configured (route to formal quote)', () => {
    for (const c of [null, undefined]) {
      const r = resolvePricingPolicy(c);
      expect(r.configured).toBe(false);
      expect(shouldAutoRom(r)).toBe(false);
      if (!r.configured) expect(r.reason).toBe('no_policy_cell');
    }
  });

  test('present cell ⇒ configured, embedded policy verbatim', () => {
    const r = resolvePricingPolicy(cell);
    expect(r.configured).toBe(true);
    expect(shouldAutoRom(r)).toBe(true);
    if (r.configured) {
      expect(r.policy).toBe(cell.policy); // same reference — single source of truth
      expect(r.policy.baseRates.short).toEqual({ min: 200, max: 400 });
    }
  });

  test('shouldAutoRom narrows the type for the caller branch', () => {
    const r = resolvePricingPolicy(cell);
    // Mirrors the documented call-site pattern.
    if (shouldAutoRom(r)) {
      const p: PricingPolicy = r.policy; // type-narrowed, compiles
      expect(p.presentation.roundTo).toBe(10);
    } else {
      throw new Error('expected configured');
    }
  });
});

describe('classifySuburbGroup — honest geo (no fake postcode math)', () => {
  test('no serviceArea ⇒ core (behaviour-neutral default)', () => {
    expect(classifySuburbGroup(baseReq)).toBe('core');
    expect(classifySuburbGroup(baseReq, undefined, () => 5)).toBe('core');
  });

  test('serviceArea set but no geo fn / null distance ⇒ core, never decline on uncertainty', () => {
    expect(classifySuburbGroup(baseReq, serviceArea)).toBe('core');
    expect(classifySuburbGroup(baseReq, serviceArea, () => null)).toBe('core');
    expect(
      classifySuburbGroup({ postcode: '', suburb: null }, serviceArea, () => 5),
    ).toBe('core');
  });

  test('resolvable distance picks the first band whose maxKm ≥ distance', () => {
    expect(classifySuburbGroup(baseReq, serviceArea, () => 5)).toBe('core');
    expect(classifySuburbGroup(baseReq, serviceArea, () => 10)).toBe('core');
    expect(classifySuburbGroup(baseReq, serviceArea, () => 25)).toBe('extended');
    expect(classifySuburbGroup(baseReq, serviceArea, () => 500)).toBe('outside');
  });

  test('unsorted bands tolerated; beyond all ⇒ farthest band group', () => {
    const sa: NonNullable<PricingPolicy['serviceArea']> = {
      homePostcode: '4000',
      radiusBands: [
        { maxKm: 30, suburbGroup: 'extended' },
        { maxKm: 10, suburbGroup: 'core' },
        { maxKm: 50, suburbGroup: 'far' },
      ],
    };
    expect(classifySuburbGroup(baseReq, sa, () => 8)).toBe('core');
    expect(classifySuburbGroup(baseReq, sa, () => 9999)).toBe('far');
  });
});

describe('classifyEffortBand — one-man-team HR escalation', () => {
  test('ordinary access ⇒ short (pre-P1b default band)', () => {
    expect(classifyEffortBand(baseReq)).toBe('short');
    expect(
      classifyEffortBand({ accessDifficulty: 'ladder_required', scopeDescription: null }),
    ).toBe('short');
  });

  test('scaffolding + one-man (hrCapacity ≤ 1) ⇒ multi_day → formal quote', () => {
    expect(
      classifyEffortBand(
        { accessDifficulty: 'scaffolding_required', scopeDescription: null },
        { hrCapacity: 1 },
      ),
    ).toBe('multi_day');
  });

  test('scaffolding + a 2-person team ⇒ not escalated', () => {
    expect(
      classifyEffortBand(
        { accessDifficulty: 'scaffolding_required', scopeDescription: null },
        { hrCapacity: 2 },
      ),
    ).toBe('short');
  });

  test('operator-tuned explicit access→band mapping overrides the heuristic', () => {
    expect(
      classifyEffortBand(
        { accessDifficulty: 'scaffolding_required', scopeDescription: null },
        { hrCapacity: 1, bands: { scaffolding_required: { maxScore: 0, band: 'half_day' } } },
      ),
    ).toBe('half_day');
  });
});

describe('mapEstimatorRequestToRomInput — full projection', () => {
  test('composes classifiers + verbatim category/urgency pass-through', () => {
    const policy: PricingPolicy = {
      baseRates: { short: { min: 200, max: 400 } },
      travelModifiers: { core: { surcharge: 0, label: 'Core' } },
      categoryModifiers: {},
      complexityModifiers: {},
      presentation: { roundTo: 10, rangeLabel: 'Typically', disclaimer: '.' },
      serviceArea,
      effortRubric: { hrCapacity: 1 },
    };
    const rom = mapEstimatorRequestToRomInput(
      { ...baseReq, accessDifficulty: 'difficult_access', urgency: 'emergency' },
      policy,
      { geoDistanceKm: () => 25 },
    );
    expect(rom).toEqual({
      effortBand: 'short',
      suburbGroup: 'extended',
      categoryPath: 'plumbing',
      urgency: 'emergency',
      complexityHints: ['tricky_access'],
    });
  });

  test('null urgency/jobType ⇒ safe defaults; no geo dep ⇒ core', () => {
    const policy: PricingPolicy = {
      baseRates: { short: { min: 1, max: 2 } },
      travelModifiers: { core: { surcharge: 0, label: 'C' } },
      categoryModifiers: {},
      complexityModifiers: {},
      presentation: { roundTo: 10, rangeLabel: 'T', disclaimer: '.' },
      serviceArea,
    };
    const rom = mapEstimatorRequestToRomInput(
      { ...baseReq, jobType: null, urgency: null },
      policy,
    );
    expect(rom.categoryPath).toBe('');
    expect(rom.urgency).toBe('unspecified');
    expect(rom.suburbGroup).toBe('core');
  });
});

describe('makeRomEstimatorFn — A5 safe-default contract end-to-end', () => {
  const richPolicy: PricingPolicy = {
    baseRates: {
      short: { min: 200, max: 400 },
      multi_day: { min: 0, max: 0, note: 'requires_formal_quote' },
    },
    travelModifiers: {
      core: { surcharge: 0, label: 'Core' },
      extended: { surcharge: 50, label: 'Extended' },
      outside: { surcharge: 0, decline: true, label: 'Outside' },
    },
    categoryModifiers: {},
    complexityModifiers: {},
    presentation: { roundTo: 10, rangeLabel: 'Typically', disclaimer: 'Ballpark only.' },
    serviceArea,
  };
  const richCell: OddjobzPricingPolicy = { ...cell, policy: richPolicy };

  test('no policy cell ⇒ formal-quote wording, NEVER a number', () => {
    for (const c of [null, undefined]) {
      const est = makeRomEstimatorFn(c);
      const out = est(baseReq);
      expect(out).toContain('no_auto_price');
      expect(out).not.toMatch(/\$\d/); // no fabricated dollar figure
    }
  });

  test('present cell, normal job ⇒ ROM range label', () => {
    const est = makeRomEstimatorFn(richCell, { geoDistanceKm: () => 5 });
    const out = est(baseReq);
    expect(out).toContain('Typically $200');
    expect(out).toContain('Ballpark only.');
  });

  test('out-of-area (geo → declining travel band) ⇒ decline wording', () => {
    const est = makeRomEstimatorFn(richCell, { geoDistanceKm: () => 9999 });
    const out = est(baseReq);
    expect(out).toContain('decline:');
    expect(out).not.toMatch(/\$\d/);
  });

  test('over one-man HR capacity (scaffolding) ⇒ requires_formal_quote wording', () => {
    const est = makeRomEstimatorFn(
      { ...richCell, policy: { ...richPolicy, effortRubric: { hrCapacity: 1 } } },
      { geoDistanceKm: () => 5 },
    );
    const out = est({ ...baseReq, accessDifficulty: 'scaffolding_required' });
    expect(out).toContain('requires_formal_quote');
    expect(out).not.toMatch(/\$\d/);
  });

  test('pure: same cell + same request ⇒ identical wording', () => {
    const est = makeRomEstimatorFn(richCell, { geoDistanceKm: () => 25 });
    expect(est(baseReq)).toBe(est(baseReq));
  });

  test('formatRomWording branches directly', () => {
    expect(formatRomWording({ configured: false, reason: 'no_policy_cell' }, null)).toContain('no_auto_price');
    expect(
      formatRomWording(
        { configured: true, policy: richPolicy },
        { min: 0, max: 0, label: '', disclaimer: '', declined: true, declineReason: 'outside service area', requiresQuote: false, breakdown: [] },
      ),
    ).toContain('decline:');
    expect(
      formatRomWording(
        { configured: true, policy: richPolicy },
        { min: 0, max: 0, label: '', disclaimer: '', declined: false, requiresQuote: true, breakdown: [] },
      ),
    ).toContain('requires_formal_quote');
    expect(
      formatRomWording(
        { configured: true, policy: richPolicy },
        { min: 200, max: 400, label: 'Typically $200–$400', disclaimer: 'BP.', declined: false, requiresQuote: false, breakdown: [] },
      ),
    ).toBe('Typically $200–$400 — BP.');
  });
});

```
