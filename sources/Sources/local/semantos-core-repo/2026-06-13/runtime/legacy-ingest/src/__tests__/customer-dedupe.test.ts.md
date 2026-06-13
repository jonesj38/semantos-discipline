---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/customer-dedupe.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.143970+00:00
---

# runtime/legacy-ingest/src/__tests__/customer-dedupe.test.ts

```ts
/**
 * Customer-dedupe conformance tests (handoff §6.2).
 *
 * The keystone property: the SAME contact recurring across many
 * proposals collapses onto ONE customer_cell — agency contacts
 * site-independently, landlords by name, tenants by name+site — so the
 * canonicalized 152 don't regrow. Genuinely distinct contacts do not
 * collapse. Keys mirror canonicalize.py's `ckey`.
 */

import { describe, test, expect } from 'bun:test';
import {
  deriveCustomerLookupKey,
  proposeCustomerCell,
  findOrProposeCustomer,
  computeCustomerCellId,
  normaliseCustomerField,
  type CustomersDedupeView,
} from '../customer-dedupe';

function viewWith(seed: Record<string, string> = {}): CustomersDedupeView & {
  calls: string[];
} {
  const calls: string[] = [];
  return {
    calls,
    async findCustomerByLookupKey(k) {
      calls.push(k);
      return seed[k] ?? null;
    },
  };
}

/* ──────────────────────────────────────────────────────────────────────
 * normaliseCustomerField — mirrors canonicalize.py `norm`
 * ────────────────────────────────────────────────────────────────────── */

describe('normaliseCustomerField', () => {
  const cases: Array<[string | null | undefined, string]> = [
    ['Tanya Healy', 'tanya healy'],
    ['  Tanya   Healy  ', 'tanya healy'],
    ['CLEVER@PROPERTY.com', 'clever@property.com'],
    ['Robert  James\tRealty', 'robert james realty'],
    [null, ''],
    [undefined, ''],
    ['', ''],
    ['   ', ''],
  ];
  for (const [raw, expected] of cases) {
    test(`"${raw}" → "${expected}"`, () => {
      expect(normaliseCustomerField(raw)).toBe(expected);
    });
  }
});

/* ──────────────────────────────────────────────────────────────────────
 * deriveCustomerLookupKey — role-aware natural keys
 * ────────────────────────────────────────────────────────────────────── */

describe('deriveCustomerLookupKey', () => {
  test('agent → person:<email>, site-independent', () => {
    const k1 = deriveCustomerLookupKey({
      role: 'agent',
      name: 'Tanya Healy',
      email: 'tanya@clever.com',
      siteRef: 'a'.repeat(64),
    });
    const k2 = deriveCustomerLookupKey({
      role: 'agent',
      name: 'Tanya Healy',
      email: 'tanya@clever.com',
      siteRef: 'b'.repeat(64), // different site
    });
    expect(k1).toBe('person:tanya@clever.com');
    expect(k1).toBe(k2); // same person across sites ⇒ one cell
  });

  test('property_manager keys the same way as agent (person:)', () => {
    expect(
      deriveCustomerLookupKey({
        role: 'property_manager',
        name: 'Tanya Healy',
        email: 'tanya@clever.com',
        siteRef: null,
      }),
    ).toBe('person:tanya@clever.com');
  });

  test('agent with no email falls back to person:<name>', () => {
    expect(
      deriveCustomerLookupKey({
        role: 'agent',
        name: 'Robert James Realty',
        email: null,
        siteRef: 'c'.repeat(64),
      }),
    ).toBe('person:robert james realty');
  });

  test('site_owner (landlord) → landlord:<name>', () => {
    const k1 = deriveCustomerLookupKey({
      role: 'site_owner',
      name: 'Jane Owner',
      email: 'jane@example.com', // ignored for landlords
      siteRef: 'd'.repeat(64),
    });
    expect(k1).toBe('landlord:jane owner');
  });

  test('tenant → tenant:<name>|<site> (identity-bound to one site)', () => {
    const site = 'e'.repeat(64);
    const k1 = deriveCustomerLookupKey({
      role: 'tenant',
      name: 'Sam Tenant',
      email: null,
      siteRef: site,
    });
    expect(k1).toBe(`tenant:sam tenant|${site}`);
  });

  test('same-named tenants at DIFFERENT sites do NOT collapse', () => {
    const a = deriveCustomerLookupKey({ role: 'tenant', name: 'Sam', email: null, siteRef: 'a'.repeat(64) });
    const b = deriveCustomerLookupKey({ role: 'tenant', name: 'Sam', email: null, siteRef: 'b'.repeat(64) });
    expect(a).not.toBe(b);
  });

  test('contractor/witness/unknown key by role+name+site', () => {
    const site = 'f'.repeat(64);
    expect(
      deriveCustomerLookupKey({ role: 'contractor', name: 'Bob Builder', email: null, siteRef: site }),
    ).toBe(`contractor:bob builder|${site}`);
    expect(
      deriveCustomerLookupKey({ role: 'unknown', name: 'Mystery', email: null, siteRef: null }),
    ).toBe('unknown:mystery|');
  });

  test('empty role → other:<name>|<site> (matches canonicalize.py `role or "other"`)', () => {
    expect(
      deriveCustomerLookupKey({ role: '', name: 'No Role', email: null, siteRef: null }),
    ).toBe('other:no role|');
  });

  test('no usable key → unkeyed: sentinel', () => {
    // person with neither email nor name
    expect(
      deriveCustomerLookupKey({ role: 'agent', name: null, email: null, siteRef: 'a'.repeat(64) }),
    ).toBe('unkeyed:');
    // landlord with no name
    expect(
      deriveCustomerLookupKey({ role: 'site_owner', name: '   ', email: 'x@y.com', siteRef: null }),
    ).toBe('unkeyed:');
    // tenant with no name
    expect(
      deriveCustomerLookupKey({ role: 'tenant', name: null, email: null, siteRef: 'a'.repeat(64) }),
    ).toBe('unkeyed:');
  });

  test('keys are case/whitespace-insensitive (norm applied)', () => {
    const a = deriveCustomerLookupKey({ role: 'AGENT', name: 'Tanya  Healy', email: ' Tanya@Clever.com ', siteRef: null });
    const b = deriveCustomerLookupKey({ role: 'agent', name: 'tanya healy', email: 'tanya@clever.com', siteRef: null });
    expect(a).toBe(b);
  });
});

/* ──────────────────────────────────────────────────────────────────────
 * proposeCustomerCell — deterministic id
 * ────────────────────────────────────────────────────────────────────── */

describe('proposeCustomerCell', () => {
  test('same natural key → same proposedCellId', () => {
    const a = proposeCustomerCell({ role: 'agent', name: 'Tanya', email: 't@c.com', siteRef: 'a'.repeat(64) });
    const b = proposeCustomerCell({ role: 'agent', name: 'Tanya', email: 't@c.com', siteRef: 'z'.repeat(64) });
    expect(a.proposedCellId).toBe(b.proposedCellId);
    expect(a.proposedCellId).toHaveLength(64);
    expect(a.proposedCellId).toMatch(/^[0-9a-f]+$/);
  });

  test('distinct keys → distinct ids', () => {
    const a = proposeCustomerCell({ role: 'agent', name: 'Tanya', email: 't@c.com', siteRef: null });
    const b = proposeCustomerCell({ role: 'agent', name: 'Other', email: 'o@c.com', siteRef: null });
    expect(a.proposedCellId).not.toBe(b.proposedCellId);
  });

  test('computeCustomerCellId is stable + namespaced', () => {
    expect(computeCustomerCellId('person:t@c.com')).toBe(computeCustomerCellId('person:t@c.com'));
    expect(computeCustomerCellId('person:t@c.com')).not.toBe(computeCustomerCellId('person:o@c.com'));
  });
});

/* ──────────────────────────────────────────────────────────────────────
 * findOrProposeCustomer — the keystone dedupe behaviour
 * ────────────────────────────────────────────────────────────────────── */

describe('findOrProposeCustomer', () => {
  test('first proposal proposes; same contact second matches', async () => {
    const existing = 'f'.repeat(64);
    const view1 = viewWith();
    const r1 = await findOrProposeCustomer(
      { role: 'agent', name: 'Tanya', email: 't@c.com', siteRef: 's'.repeat(64) },
      view1,
    );
    expect(r1.kind).toBe('propose');

    // Second proposal (different site, same agent): index now has it → match.
    const view2 = viewWith({ 'person:t@c.com': existing });
    const r2 = await findOrProposeCustomer(
      { role: 'agent', name: 'Tanya', email: 't@c.com', siteRef: 'different'.padEnd(64, '0') },
      view2,
    );
    expect(r2.kind).toBe('match');
    if (r2.kind === 'match') expect(r2.cellId).toBe(existing);
  });

  test('unkeyed contacts never match (always propose)', async () => {
    const view = viewWith({ 'unkeyed:': 'z'.repeat(64) });
    const r = await findOrProposeCustomer(
      { role: 'agent', name: null, email: null, siteRef: null },
      view,
    );
    expect(r.kind).toBe('propose');
    expect(view.calls).toHaveLength(0); // view not even consulted
  });

  test('landlord dedupes by name across sites', async () => {
    const existing = 'b'.repeat(64);
    const view = viewWith({ 'landlord:jane owner': existing });
    const r = await findOrProposeCustomer(
      { role: 'site_owner', name: 'Jane Owner', email: null, siteRef: 'newsite'.padEnd(64, '0') },
      view,
    );
    expect(r.kind).toBe('match');
    if (r.kind === 'match') expect(r.cellId).toBe(existing);
  });
});

/* ──────────────────────────────────────────────────────────────────────
 * OJT corpus scenario — the actual bug this fixes
 * ────────────────────────────────────────────────────────────────────── */

describe('OJT agent-fanout duplicate scenario', () => {
  test('one Clever agent across 130 properties → ONE customer cell', async () => {
    // The exact OJT failure: Tanya Healy minted 130× (once per site).
    const liveIndex = new Map<string, string>();
    const view: CustomersDedupeView = {
      async findCustomerByLookupKey(k) {
        return liveIndex.get(k) ?? null;
      },
    };

    let mints = 0;
    // 130 proposals at 130 distinct sites, all the same agent.
    for (let i = 0; i < 130; i++) {
      const res = await findOrProposeCustomer(
        { role: 'agent', name: 'Tanya Healy', email: 'tanya@clever.com', siteRef: String(i).padEnd(64, '0') },
        view,
      );
      if (res.kind === 'propose') {
        mints += 1;
        liveIndex.set(res.lookupKey, `CUST_TANYA`.padEnd(64, '0'));
      }
    }
    expect(mints).toBe(1); // 130 proposals → exactly ONE mint
    expect(liveIndex.size).toBe(1);
  });
});

```
