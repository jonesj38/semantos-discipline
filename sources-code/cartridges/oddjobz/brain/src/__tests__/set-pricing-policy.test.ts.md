---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/__tests__/set-pricing-policy.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.513171+00:00
---

# cartridges/oddjobz/brain/src/__tests__/set-pricing-policy.test.ts

```ts
/**
 * set_pricing_policy conformance (A5.P2.c).
 *
 * Pins the operator pricing-policy WRITE seam: kernel-gate on
 * cap.oddjobz.write_policy, the append-only signed amendment chain
 * (genesis ⇒ no prevPolicyHash; amendment ⇒ sha256-of-predecessor
 * link, monotonic version, stable policyId, signedByOperatorId
 * provenance), and pack-validated round-trip. Memory-store-backed +
 * structural cap ⇒ runnable in this worktree (no @semantos/intent).
 */

import { describe, expect, test } from 'bun:test';
import {
  setPricingPolicy,
  makeMemoryPricingPolicyStore,
  policyCellHash,
} from '../set-pricing-policy.js';
import { pricingPolicyCellType } from '../cell-types/pricing-policy.js';
import { capWritePolicy } from '../capabilities.js';
import type { PresentedCap } from '../state-machines/kernel-gate.js';
import type { PricingPolicy } from '../rom.js';

const policy: PricingPolicy = {
  baseRates: { short: { min: 200, max: 400 } },
  travelModifiers: { core: { surcharge: 0, label: 'Core' } },
  categoryModifiers: {},
  complexityModifiers: {},
  presentation: { roundTo: 10, rangeLabel: 'Typically', disclaimer: 'Ballpark.' },
};

const validCap: PresentedCap = {
  kind: 'structural',
  domainFlag: capWritePolicy.domainFlag,
};
const wrongCap: PresentedCap = { kind: 'structural', domainFlag: 0xdeadbeef };

const base = {
  hatId: 'hat-operator-todd',
  operatorCertId: 'abad1deabad1deab',
  policy,
  nowIso: '2026-05-18T00:00:00.000Z',
};

describe('setPricingPolicy — kernel gate', () => {
  test('no cap presented ⇒ cap_required, nothing minted', () => {
    const store = makeMemoryPricingPolicyStore();
    const r = setPricingPolicy({ ...base, presentedCap: null }, store);
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.kind).toBe('cap_required');
    expect(store.all()).toHaveLength(0);
  });

  test('wrong domain flag ⇒ wrong_cap, nothing minted', () => {
    const store = makeMemoryPricingPolicyStore();
    const r = setPricingPolicy({ ...base, presentedCap: wrongCap }, store);
    expect(r.ok).toBe(false);
    if (!r.ok) {
      expect(r.error.kind).toBe('wrong_cap');
      expect(r.error.presentedDomainFlag).toBe(0xdeadbeef);
    }
    expect(store.all()).toHaveLength(0);
  });
});

describe('setPricingPolicy — append-only signed amendment chain', () => {
  test('genesis: version 1, no prevPolicyHash, signed provenance', () => {
    const store = makeMemoryPricingPolicyStore();
    const r = setPricingPolicy(
      { ...base, presentedCap: validCap, newPolicyId: '11111111-2222-3333-4444-555555555555' },
      store,
    );
    expect(r.ok).toBe(true);
    if (!r.ok) throw new Error('expected ok');
    expect(r.value.isGenesis).toBe(true);
    expect(r.value.cell.version).toBe(1);
    expect(r.value.cell.prevPolicyHash).toBeUndefined();
    expect(r.value.cell.policyId).toBe('11111111-2222-3333-4444-555555555555');
    expect(r.value.cell.signedByOperatorId).toBe('abad1deabad1deab');
    // Packed bytes round-trip through the cell-type.
    expect(pricingPolicyCellType.unpack(r.value.cellBytes).version).toBe(1);
    expect(store.all()).toHaveLength(1);
  });

  test('amendment: version+1, prevPolicyHash links predecessor, policyId + createdAt stable', () => {
    const store = makeMemoryPricingPolicyStore();
    const g = setPricingPolicy({ ...base, presentedCap: validCap }, store);
    if (!g.ok) throw new Error('genesis failed');

    const policy2: PricingPolicy = {
      ...policy,
      orgMarkup: { percent: 12, label: 'Founder premium' },
    };
    const a = setPricingPolicy(
      { ...base, policy: policy2, presentedCap: validCap, nowIso: '2026-06-01T00:00:00.000Z' },
      store,
    );
    expect(a.ok).toBe(true);
    if (!a.ok) throw new Error('amendment failed');

    expect(a.value.isGenesis).toBe(false);
    expect(a.value.cell.version).toBe(2);
    expect(a.value.cell.policyId).toBe(g.value.cell.policyId); // stable
    expect(a.value.cell.createdAt).toBe(g.value.cell.createdAt); // policy created once
    expect(a.value.cell.updatedAt).toBe('2026-06-01T00:00:00.000Z'); // this revision
    // The chain link is exactly sha256(predecessor canonical bytes).
    expect(a.value.cell.prevPolicyHash).toBe(policyCellHash(g.value.cellBytes));
    expect(a.value.cell.prevPolicyHash).toMatch(/^[0-9a-f]{64}$/);
    expect(a.value.cell.policy.orgMarkup?.percent).toBe(12);
    expect(store.all()).toHaveLength(2);
  });

  test('three-link chain: each amendment points at its immediate predecessor', () => {
    const store = makeMemoryPricingPolicyStore();
    const r1 = setPricingPolicy({ ...base, presentedCap: validCap }, store);
    const r2 = setPricingPolicy({ ...base, presentedCap: validCap }, store);
    const r3 = setPricingPolicy({ ...base, presentedCap: validCap }, store);
    if (!r1.ok || !r2.ok || !r3.ok) throw new Error('chain failed');
    expect([r1.value.cell.version, r2.value.cell.version, r3.value.cell.version]).toEqual([1, 2, 3]);
    expect(r2.value.cell.prevPolicyHash).toBe(policyCellHash(r1.value.cellBytes));
    expect(r3.value.cell.prevPolicyHash).toBe(policyCellHash(r2.value.cellBytes));
    // policyId stable across the whole chain.
    expect(new Set(store.all().map((c) => c.policyId)).size).toBe(1);
  });

  test('hat isolation: a different hat starts its own genesis', () => {
    const store = makeMemoryPricingPolicyStore();
    setPricingPolicy({ ...base, presentedCap: validCap }, store);
    const other = setPricingPolicy(
      { ...base, hatId: 'hat-operator-other', presentedCap: validCap },
      store,
    );
    if (!other.ok) throw new Error('expected ok');
    expect(other.value.isGenesis).toBe(true);
    expect(other.value.cell.version).toBe(1);
  });

  test('malformed embedded policy surfaces (throws) rather than a silent gate-pass', () => {
    const store = makeMemoryPricingPolicyStore();
    const bad = { ...policy, presentation: undefined } as unknown as PricingPolicy;
    expect(() =>
      setPricingPolicy({ ...base, policy: bad, presentedCap: validCap }, store),
    ).toThrow(/presentation needs/);
    expect(store.all()).toHaveLength(0);
  });
});

```
