---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cdm/cdm/src/lifecycle/__tests__/novation.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.508651+00:00
---

# packages/cdm/cdm/src/lifecycle/__tests__/novation.test.ts

```ts
/**
 * novation module — Phase 17 transfer wrapper.
 *
 * Refactor 29.
 */

import { describe, expect, test } from 'bun:test';

import { createCDMProduct, type CDMPartyRole } from '../../types';
import { novateProduct } from '../novation';

function makeProduct(state: string = 'confirmed') {
  const p = createCDMProduct(
    'rates.swap.fixed-float',
    {
      notional: { amount: 5_000_000, currency: 'USD' },
      effectiveDate: '2024-06-15',
      terminationDate: '2029-06-15',
    },
    [
      { partyId: 'bank-a', role: 'buyer', capabilities: [], hatCertId: 'cert-a' },
      { partyId: 'bank-b', role: 'seller', capabilities: [], hatCertId: 'cert-b' },
    ],
    '2024-06-15',
  );
  p.lifecycleState = state as any;
  return p;
}

describe('novateProduct', () => {
  test('replaces oldParty with newParty + advances state', () => {
    const product = makeProduct('confirmed');
    const oldParty = product.parties[0];
    const newParty: CDMPartyRole = {
      partyId: 'bank-c',
      role: 'buyer',
      capabilities: [],
      hatCertId: 'cert-c',
    };
    const result = novateProduct(product, oldParty, newParty, 'actor-1');
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.value.product.lifecycleState).toBe('novated');
      expect(result.value.product.parties.find((p) => p.partyId === 'bank-c')).toBeTruthy();
      expect(result.value.product.parties.find((p) => p.partyId === 'bank-a')).toBeUndefined();
      expect(result.value.transferRecord.fromParentCertId).toBe('cert-a');
      expect(result.value.transferRecord.toParentCertId).toBe('cert-c');
    }
  });

  test('rejects when state does not allow novation', () => {
    const product = makeProduct('terminated');
    const oldParty = product.parties[0];
    const newParty: CDMPartyRole = { partyId: 'bank-c', role: 'buyer', capabilities: [] };
    const result = novateProduct(product, oldParty, newParty, 'actor-1');
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error).toContain('Cannot novate');
    }
  });

  test('rejects when oldParty is not on the trade', () => {
    const product = makeProduct('confirmed');
    const phantomParty: CDMPartyRole = {
      partyId: 'unknown-party',
      role: 'buyer',
      capabilities: [],
    };
    const newParty: CDMPartyRole = { partyId: 'bank-c', role: 'buyer', capabilities: [] };
    const result = novateProduct(product, phantomParty, newParty, 'actor-1');
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error).toContain("'unknown-party' is not a counterparty");
    }
  });

  test('falls back to partyId when hatCertId is missing', () => {
    const product = makeProduct('confirmed');
    // Strip hatCertIds.
    product.parties = product.parties.map((p) => ({ ...p, hatCertId: undefined }));
    const oldParty = product.parties[0];
    const newParty: CDMPartyRole = { partyId: 'bank-c', role: 'buyer', capabilities: [] };
    const result = novateProduct(product, oldParty, newParty, 'actor-1');
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.value.transferRecord.fromParentCertId).toBe('bank-a');
      expect(result.value.transferRecord.toParentCertId).toBe('bank-c');
    }
  });
});

```
