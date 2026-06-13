---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/__tests__/pricing-policy-defaults.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.510081+00:00
---

# cartridges/oddjobz/brain/src/__tests__/pricing-policy-defaults.test.ts

```ts
/**
 * AU default pricing policy conformance (A5.P2).
 *
 * Proves the named AU starting policy is a VALID, packable, editable
 * value (not fabricated calculator constants): it round-trips through
 * the cell-type, genesis-mints via set_pricing_policy under the cap,
 * and drives sane AU ROM ranges + the safe-default branches end-to-end
 * through the Slice-3a estimator factory. Pure/intra-package.
 */

import { describe, expect, test } from 'bun:test';
import {
  AU_DEFAULT_PRICING_POLICY,
  auDefaultGenesisInput,
} from '../pricing-policy-defaults.js';
import { pricingPolicyCellType } from '../cell-types/pricing-policy.js';
import {
  setPricingPolicy,
  makeMemoryPricingPolicyStore,
} from '../set-pricing-policy.js';
import { makeRomEstimatorFn } from '../pricing-policy-projector.js';
import { calculateROM } from '../rom.js';
import { capWritePolicy } from '../capabilities.js';
import type { PresentedCap } from '../state-machines/kernel-gate.js';
import type { EstimatorRequest } from '../conversation/state-manager.js';

const validCap: PresentedCap = {
  kind: 'structural',
  domainFlag: capWritePolicy.domainFlag,
};

const req: EstimatorRequest = {
  jobType: 'general',
  subcategory: null,
  quantity: null,
  scopeDescription: 'fix a sticking door',
  materials: null,
  accessDifficulty: 'ground_level',
  suburb: 'Paddington',
  postcode: '4064',
  urgency: 'flexible',
  allowWidenedBand: false,
};

describe('AU_DEFAULT_PRICING_POLICY — valid editable value', () => {
  test('packs + round-trips through the cell-type (validate passes)', () => {
    const cell = {
      policyId: '11111111-2222-3333-4444-555555555555',
      hatId: 'hat-operator-todd',
      version: 1,
      policy: AU_DEFAULT_PRICING_POLICY,
      createdAt: '2026-05-18T00:00:00.000Z',
      updatedAt: '2026-05-18T00:00:00.000Z',
    };
    const back = pricingPolicyCellType.unpack(pricingPolicyCellType.pack(cell));
    expect(back.policy).toEqual(AU_DEFAULT_PRICING_POLICY);
  });

  test('home postcode is blank by design (operator sets it)', () => {
    expect(AU_DEFAULT_PRICING_POLICY.serviceArea?.homePostcode).toBe('');
  });

  test('drives a sane AU ballpark for an ordinary short job', () => {
    const rom = calculateROM(
      { effortBand: 'short', suburbGroup: 'core', categoryPath: 'general', urgency: 'flexible', complexityHints: [] },
      AU_DEFAULT_PRICING_POLICY,
    );
    expect(rom.requiresQuote).toBe(false);
    expect(rom.declined).toBe(false);
    expect(rom.min).toBeGreaterThanOrEqual(120); // minimumCallout floor
    expect(rom.min).toBeLessThan(rom.max);
    expect(rom.max).toBeLessThanOrEqual(600); // sane AU short-job ceiling
  });

  test('emergency applies the +50% urgency premium', () => {
    const base = calculateROM(
      { effortBand: 'short', suburbGroup: 'core', categoryPath: 'general', urgency: 'flexible', complexityHints: [] },
      AU_DEFAULT_PRICING_POLICY,
    );
    const emerg = calculateROM(
      { effortBand: 'short', suburbGroup: 'core', categoryPath: 'general', urgency: 'emergency', complexityHints: [] },
      AU_DEFAULT_PRICING_POLICY,
    );
    expect(emerg.max).toBeGreaterThan(base.max);
    expect(emerg.breakdown.find((b) => b.component === 'urgency')?.effect).toContain('+50%');
  });

  test('multi_day band ⇒ formal quote (one-man over-capacity safe default)', () => {
    const rom = calculateROM(
      { effortBand: 'multi_day', suburbGroup: 'core', categoryPath: 'x', urgency: 'flexible', complexityHints: [] },
      AU_DEFAULT_PRICING_POLICY,
    );
    expect(rom.requiresQuote).toBe(true);
  });

  test('outside service area ⇒ declined', () => {
    const rom = calculateROM(
      { effortBand: 'short', suburbGroup: 'outside', categoryPath: 'x', urgency: 'flexible', complexityHints: [] },
      AU_DEFAULT_PRICING_POLICY,
    );
    expect(rom.declined).toBe(true);
  });
});

describe('AU default — genesis-mint + estimator end-to-end', () => {
  test('auDefaultGenesisInput → setPricingPolicy mints a v1 cell with the AU policy', () => {
    const store = makeMemoryPricingPolicyStore();
    const r = setPricingPolicy(
      auDefaultGenesisInput({
        hatId: 'hat-operator-todd',
        operatorCertId: 'abad1deabad1deab',
        presentedCap: validCap,
        nowIso: '2026-05-18T00:00:00.000Z',
      }),
      store,
    );
    expect(r.ok).toBe(true);
    if (!r.ok) throw new Error('genesis failed');
    expect(r.value.isGenesis).toBe(true);
    expect(r.value.cell.version).toBe(1);
    expect(r.value.cell.policy).toEqual(AU_DEFAULT_PRICING_POLICY);

    // The minted cell drives the Slice-3a estimator: a real ballpark,
    // never a fabricated price when it shouldn't be.
    const est = makeRomEstimatorFn(r.value.cell);
    const wording = est(req);
    expect(wording).toContain('Typically');
    expect(wording).toContain('Ballpark estimate only');
  });
});

```
