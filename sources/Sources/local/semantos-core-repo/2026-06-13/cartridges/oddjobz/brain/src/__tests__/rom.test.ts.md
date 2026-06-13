---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/__tests__/rom.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.514060+00:00
---

# cartridges/oddjobz/brain/src/__tests__/rom.test.ts

```ts
/**
 * ROM Calculator — canonical-copy conformance.
 *
 * Guards the cherry-picked cartridges/oddjobz/brain/src/rom.ts (ported from
 * runtime/shell/src/rom.ts during the REPL-canonicalisation pass).
 * Asserts the deterministic price-derivation paths an
 * oddjobz.estimate.v1 (auto_rom) is minted from: base rate, travel
 * surcharge / decline, category + complexity + service-type + org
 * markup + emergency modifiers, rounding/min<max, requires-quote,
 * and complexity-hint extraction.
 */

import { describe, expect, test } from 'bun:test';
import {
  calculateROM,
  extractComplexityHints,
  type PricingPolicy,
} from '../rom.js';

const policy: PricingPolicy = {
  baseRates: {
    short: { min: 200, max: 400 },
    multi_day: { min: 0, max: 0, note: 'requires_formal_quote' },
  },
  travelModifiers: {
    core: { surcharge: 0, label: 'Core area' },
    extended: { surcharge: 50, label: 'Extended area' },
    outside: { surcharge: 0, decline: true, label: 'Outside service area' },
  },
  categoryModifiers: {
    'services.trades.plumbing': { factor: 1.5, note: 'specialist' },
  },
  complexityModifiers: {
    '2_story': { factor: 1.2, label: 'Two-storey access' },
    emergency: { factor: 2.0, label: 'Emergency call-out' },
  },
  serviceTypeModifiers: {
    'services.trades.plumbing': { factor: 1.0 },
  },
  orgMarkup: { percent: 10, label: 'Founder premium' },
  presentation: { roundTo: 10, rangeLabel: 'Typically', disclaimer: 'Ballpark only.' },
};

describe('ROM canonical-copy — calculateROM', () => {
  test('base rate + org markup, no modifiers', () => {
    const r = calculateROM(
      { effortBand: 'short', suburbGroup: 'core', categoryPath: 'x', urgency: 'flexible', complexityHints: [] },
      policy,
    );
    expect(r.declined).toBe(false);
    expect(r.requiresQuote).toBe(false);
    // 200/400 → +10% orgMarkup → 220/440, round-to-10.
    expect(r.min).toBe(220);
    expect(r.max).toBe(440);
    expect(r.min).toBeLessThan(r.max);
    expect(r.breakdown.some((b) => b.component === 'orgMarkup')).toBe(true);
  });

  test('travel surcharge stacks before multiplicative modifiers', () => {
    const r = calculateROM(
      { effortBand: 'short', suburbGroup: 'extended', categoryPath: 'x', urgency: 'flexible', complexityHints: [] },
      policy,
    );
    // (200+50)/(400+50)=250/450 → +10% → 275/495 → round 280/500.
    expect(r.min).toBe(280);
    expect(r.max).toBe(500);
    expect(r.breakdown.some((b) => b.component === 'travel')).toBe(true);
  });

  test('outside service area → declined, no range', () => {
    const r = calculateROM(
      { effortBand: 'short', suburbGroup: 'outside', categoryPath: 'x', urgency: 'flexible', complexityHints: [] },
      policy,
    );
    expect(r.declined).toBe(true);
    expect(r.min).toBe(0);
    expect(r.max).toBe(0);
    expect(r.declineReason).toContain('outside');
  });

  test('multi_day base note → requiresQuote, not an auto ROM', () => {
    const r = calculateROM(
      { effortBand: 'multi_day', suburbGroup: 'core', categoryPath: 'x', urgency: 'flexible', complexityHints: [] },
      policy,
    );
    expect(r.requiresQuote).toBe(true);
    expect(r.declined).toBe(false);
  });

  test('category + complexity + emergency modifiers compound', () => {
    const r = calculateROM(
      {
        effortBand: 'short',
        suburbGroup: 'core',
        categoryPath: 'services.trades.plumbing',
        urgency: 'emergency',
        complexityHints: ['2_story'],
      },
      policy,
    );
    // 200/400 ×1.5 (cat) ×1.2 (2_story) ×1.0 (serviceType) ×1.1 (org)
    //  ×2.0 (emergency) = 792/1584 → round 790/1580.
    expect(r.min).toBe(790);
    expect(r.max).toBe(1580);
    const comps = r.breakdown.map((b) => b.component);
    expect(comps).toContain('category');
    expect(comps).toContain('complexity');
    expect(comps).toContain('urgency');
  });

  test('unknown effort band falls back to short; min<max enforced', () => {
    const r = calculateROM(
      { effortBand: 'nonsense', suburbGroup: 'core', categoryPath: 'x', urgency: 'flexible', complexityHints: [] },
      policy,
    );
    expect(r.min).toBeLessThan(r.max);
  });
});

describe('ROM canonical-copy — A5.P1b additive-optional fields', () => {
  test('absent new fields ⇒ byte-identical to pre-P1b (legacy emergency path)', () => {
    // Same policy as above (no urgencyModifiers/minimumCallout); the
    // legacy complexityModifiers.emergency path must still fire.
    const r = calculateROM(
      {
        effortBand: 'short',
        suburbGroup: 'core',
        categoryPath: 'services.trades.plumbing',
        urgency: 'emergency',
        complexityHints: ['2_story'],
      },
      policy,
    );
    expect(r.min).toBe(790);
    expect(r.max).toBe(1580);
    expect(r.breakdown.find((b) => b.component === 'urgency')?.effect).toContain('×2');
  });

  test('urgencyModifiers supersedes the legacy emergency path + covers the full enum', () => {
    const p: PricingPolicy = {
      ...policy,
      urgencyModifiers: {
        emergency: { premiumPct: 50, label: 'Emergency response' },
        after_hours: { premiumPct: 25, label: 'After hours' },
        flexible: { premiumPct: 0, label: 'Flexible' },
      },
    };
    // emergency: 200/400 → +10% org → 220/440 → +50% urgency → 330/660.
    const e = calculateROM(
      { effortBand: 'short', suburbGroup: 'core', categoryPath: 'x', urgency: 'emergency', complexityHints: [] },
      p,
    );
    expect(e.min).toBe(330);
    expect(e.max).toBe(660);
    expect(e.breakdown.find((b) => b.component === 'urgency')?.effect).toContain('+50%');
    // after_hours: 220/440 → +25% → 280/550 (round-to-10 of 275/550).
    const a = calculateROM(
      { effortBand: 'short', suburbGroup: 'core', categoryPath: 'x', urgency: 'after_hours', complexityHints: [] },
      p,
    );
    expect(a.min).toBe(280);
    expect(a.max).toBe(550);
    // 0% premium ⇒ no urgency breakdown entry, base org-only result.
    const f = calculateROM(
      { effortBand: 'short', suburbGroup: 'core', categoryPath: 'x', urgency: 'flexible', complexityHints: [] },
      p,
    );
    expect(f.min).toBe(220);
    expect(f.max).toBe(440);
    expect(f.breakdown.some((b) => b.component === 'urgency')).toBe(false);
    // urgencyModifiers present ⇒ legacy complexityModifiers.emergency
    // is NOT double-applied (would have been ×2 → 660/1320).
    expect(e.min).not.toBe(660);
  });

  test('minimumCallout raises the floor; absent ⇒ no floor', () => {
    const p: PricingPolicy = {
      ...policy,
      minimumCallout: { amount: 300, label: 'Min call-out' },
    };
    // base 200/400 +10% org → 220/440; floor 300 raises min.
    const r = calculateROM(
      { effortBand: 'short', suburbGroup: 'core', categoryPath: 'x', urgency: 'flexible', complexityHints: [] },
      p,
    );
    expect(r.min).toBe(300);
    expect(r.max).toBe(440);
    expect(r.breakdown.some((b) => b.component === 'minimumCallout')).toBe(true);
    // Already-above-floor ⇒ no floor entry.
    const hi = calculateROM(
      { effortBand: 'short', suburbGroup: 'core', categoryPath: 'services.trades.plumbing', urgency: 'flexible', complexityHints: ['2_story'] },
      p,
    );
    expect(hi.breakdown.some((b) => b.component === 'minimumCallout')).toBe(false);
  });

  test('declined / requiresQuote short-circuits are unaffected by new fields', () => {
    const p: PricingPolicy = {
      ...policy,
      urgencyModifiers: { emergency: { premiumPct: 50, label: 'E' } },
      minimumCallout: { amount: 999, label: 'M' },
    };
    const declined = calculateROM(
      { effortBand: 'short', suburbGroup: 'outside', categoryPath: 'x', urgency: 'emergency', complexityHints: [] },
      p,
    );
    expect(declined.declined).toBe(true);
    expect(declined.min).toBe(0);
    const quote = calculateROM(
      { effortBand: 'multi_day', suburbGroup: 'core', categoryPath: 'x', urgency: 'emergency', complexityHints: [] },
      p,
    );
    expect(quote.requiresQuote).toBe(true);
    expect(quote.min).toBe(0);
  });
});

describe('ROM canonical-copy — extractComplexityHints', () => {
  test('detects two-storey + tricky access from free text', () => {
    const hints = extractComplexityHints({
      accessNotes: 'Double storey terrace, tight space out back',
      description: 'replace gutters',
    });
    expect(hints).toContain('2_story');
    expect(hints).toContain('tricky_access');
  });

  test('no signals → empty', () => {
    expect(extractComplexityHints({ description: 'standard tap swap' })).toEqual([]);
  });
});

```
