---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/cell-types/__tests__/pricing-policy.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.531634+00:00
---

# cartridges/oddjobz/brain/src/cell-types/__tests__/pricing-policy.test.ts

```ts
/**
 * oddjobz.pricing_policy.v1 conformance (A5.P0).
 *
 * Guards the Ricardian operator pricing-policy cell: PERSISTENT
 * (wire RELEVANT — accumulate, never consumed; the append-only
 * signed-versioned amendment chain is the app-layer version/
 * prevPolicyHash envelope), type-hash determinism, canonical
 * pack→unpack→pack byte-stability (the public CellTypeDef surface;
 * pack validates+toCanonical+encode, unpack decode+fromCanonical+
 * validate), embedded PricingPolicy structural validation, and the
 * amendment-chain invariants (genesis has no prevPolicyHash;
 * amendments must).
 */

import { describe, expect, test } from 'bun:test';
import {
  pricingPolicyCellType,
  type OddjobzPricingPolicy,
} from '../pricing-policy.js';
import { WireLinearity } from '../linearity.js';
import type { PricingPolicy } from '../../rom.js';

const policy: PricingPolicy = {
  baseRates: { short: { min: 200, max: 400 }, multi_day: { min: 0, max: 0, note: 'requires_formal_quote' } },
  travelModifiers: { core: { surcharge: 0, label: 'Core' }, outside: { surcharge: 0, decline: true, label: 'Outside' } },
  categoryModifiers: { 'services.trades.plumbing': { factor: 1.5, note: 'specialist' } },
  complexityModifiers: { '2_story': { factor: 1.2, label: 'Two-storey' } },
  orgMarkup: { percent: 10, label: 'Founder premium' },
  presentation: { roundTo: 10, rangeLabel: 'Typically', disclaimer: 'Ballpark only.' },
};

const genesis: OddjobzPricingPolicy = {
  policyId: '11111111-2222-3333-4444-555555555555',
  hatId: 'hat-operator-todd',
  version: 1,
  signedByOperatorId: 'abad1deabad1deab',
  policy,
  createdAt: '2026-05-17T00:00:00.000Z',
  updatedAt: '2026-05-17T00:00:00.000Z',
};

describe('pricing_policy — cell-type identity', () => {
  test('PERSISTENT (wire RELEVANT) — accumulate, never consumed; not LINEAR/AFFINE', () => {
    // Operator knows this class as RELEVANT; §O2 high-level label is
    // PERSISTENT. Pricing policy = long-lived config read concurrently
    // (ROM calc + Pask + dashboard); LINEAR's no-DUP would forbid that.
    expect(pricingPolicyCellType.linearity).toBe('PERSISTENT');
    expect(pricingPolicyCellType.wireLinearity).toBe(WireLinearity.RELEVANT);
    expect(pricingPolicyCellType.name).toBe('oddjobz.pricing_policy.v1');
  });

  test('type-hash is a stable frozen 32-byte digest', () => {
    const h = pricingPolicyCellType.typeHash;
    expect(h).toBeInstanceOf(Uint8Array);
    expect(h.length).toBe(32);
    expect(pricingPolicyCellType.typeHashHex).toMatch(/^[0-9a-f]{64}$/);
    expect(Array.from(pricingPolicyCellType.typeHash)).toEqual(Array.from(h));
  });
});

describe('pricing_policy — pack/unpack round-trip', () => {
  test('pack → unpack → pack is byte-stable + value-faithful', () => {
    const b1 = pricingPolicyCellType.pack(genesis);
    const back = pricingPolicyCellType.unpack(b1);
    expect(back.policyId).toBe(genesis.policyId);
    expect(back.version).toBe(1);
    expect(back.policy).toEqual(genesis.policy);
    const b2 = pricingPolicyCellType.pack(back);
    expect(Array.from(b2)).toEqual(Array.from(b1));
  });

  test('genesis omits prevPolicyHash; signedByOperatorId preserved', () => {
    const back = pricingPolicyCellType.unpack(pricingPolicyCellType.pack(genesis));
    expect(back.prevPolicyHash).toBeUndefined();
    expect(back.signedByOperatorId).toBe('abad1deabad1deab');
  });
});

describe('pricing_policy — validate (via pack)', () => {
  test('accepts a well-formed genesis', () => {
    expect(() => pricingPolicyCellType.pack(genesis)).not.toThrow();
  });

  test('amendment-chain invariants', () => {
    expect(() =>
      pricingPolicyCellType.pack({ ...genesis, version: 1, prevPolicyHash: 'deadbeef' }),
    ).toThrow(/genesis .* must not carry prevPolicyHash/);
    expect(() =>
      pricingPolicyCellType.pack({ ...genesis, version: 2 }),
    ).toThrow(/amendment .* must carry prevPolicyHash/);
    expect(() =>
      pricingPolicyCellType.pack({ ...genesis, version: 2, prevPolicyHash: 'a'.repeat(64) }),
    ).not.toThrow();
  });

  test('rejects malformed embedded policy + bad identity', () => {
    const bad = (mut: (p: PricingPolicy) => PricingPolicy) =>
      () => pricingPolicyCellType.pack({ ...genesis, policy: mut(structuredClone(policy)) });
    expect(bad((p) => { (p.baseRates.short as { min: number; max: number }).max = 1; return p; })).toThrow(/max < min/);
    expect(bad((p) => { delete (p as { presentation?: unknown }).presentation; return p; })).toThrow(/presentation needs/);
    expect(bad((p) => { p.orgMarkup = { percent: 99, label: 'x' }; return p; })).toThrow(/orgMarkup\.percent must be 0\.\.50/);
    expect(() =>
      pricingPolicyCellType.pack({ ...genesis, policyId: 'not-a-uuid' }),
    ).toThrow();
  });
});

```
