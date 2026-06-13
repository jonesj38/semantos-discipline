---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/site-dedupe.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.149306+00:00
---

# runtime/legacy-ingest/src/__tests__/site-dedupe.test.ts

```ts
/**
 * D-RTC.1b — site-dedupe conformance tests.
 *
 * Reference: docs/prd/D-Reingest-Typed-Cells.md §Deliverables / D-RTC.1.
 *
 * Acceptance gate: deterministic cellId for the same physical site
 * across address spelling variations; distinct sites do NOT collide;
 * `SitesView.findByLookupKey` is consulted exactly once per call;
 * unsupported addresses return null.
 */

import { describe, test, expect } from 'bun:test';
import {
  proposeSiteCell,
  findOrPropose,
  computeSiteCellId,
  deriveLookupKey,
  type SitesView,
} from '../site-dedupe';

/* ──────────────────────────────────────────────────────────────────────
 * Test helpers
 * ────────────────────────────────────────────────────────────────────── */

/** In-memory SitesView that records all calls + lets tests pre-seed matches. */
function makeView(seed: Record<string, string> = {}): SitesView & {
  calls: string[];
} {
  const calls: string[] = [];
  return {
    calls,
    async findByLookupKey(lookupKey) {
      calls.push(lookupKey);
      return seed[lookupKey] ?? null;
    },
  };
}

/* ──────────────────────────────────────────────────────────────────────
 * proposeSiteCell — pure-function half
 * ────────────────────────────────────────────────────────────────────── */

describe('proposeSiteCell: deterministic id + lookup key', () => {
  test('same raw address → same proposedCellId', () => {
    const a = proposeSiteCell({ rawAddress: '10 List Lane, Brisbane QLD 4000' });
    const b = proposeSiteCell({ rawAddress: '10 List Lane, Brisbane QLD 4000' });
    expect(a).not.toBeNull();
    expect(a!.proposedCellId).toBe(b!.proposedCellId);
    expect(a!.proposedCellId).toHaveLength(64);
    expect(a!.proposedCellId).toMatch(/^[0-9a-f]+$/);
  });

  test('lookupKey shape is "<normalized>|<keyNumber>"', () => {
    const p = proposeSiteCell({ rawAddress: '10 List Lane, Brisbane QLD 4000' });
    expect(p).not.toBeNull();
    expect(p!.lookupKey).toBe('10 list lane brisbane qld 4000|');
  });

  test('keyNumber participates in id derivation', () => {
    const noKey = proposeSiteCell({ rawAddress: '15 Pine Street Brisbane QLD 4000' });
    const withKey = proposeSiteCell({
      rawAddress: '15 Pine Street Brisbane QLD 4000',
      keyNumber: '2',
    });
    expect(noKey).not.toBeNull();
    expect(withKey).not.toBeNull();
    expect(noKey!.proposedCellId).not.toBe(withKey!.proposedCellId);
    expect(withKey!.lookupKey).toBe('15 pine street brisbane qld 4000|2');
  });

  test('keyNumber canonicaliser strips unit/apt/lot prefix words', () => {
    // "Unit 2" and bare "2" must produce the SAME cell — operators
    // write the same sub-address inconsistently.
    const withWord = proposeSiteCell({
      rawAddress: '15 Pine Street Brisbane QLD 4000',
      keyNumber: 'Unit 2',
    });
    const bareNum = proposeSiteCell({
      rawAddress: '15 Pine Street Brisbane QLD 4000',
      keyNumber: '2',
    });
    expect(withWord).not.toBeNull();
    expect(bareNum).not.toBeNull();
    expect(withWord!.proposedCellId).toBe(bareNum!.proposedCellId);
    expect(withWord!.keyNumber).toBe('2');
  });

  test('keyNumber treats empty / null / whitespace identically', () => {
    const a = proposeSiteCell({ rawAddress: '15 Pine Street Brisbane QLD 4000' });
    const b = proposeSiteCell({ rawAddress: '15 Pine Street Brisbane QLD 4000', keyNumber: null });
    const c = proposeSiteCell({ rawAddress: '15 Pine Street Brisbane QLD 4000', keyNumber: '' });
    const d = proposeSiteCell({ rawAddress: '15 Pine Street Brisbane QLD 4000', keyNumber: '   ' });
    expect(a!.proposedCellId).toBe(b!.proposedCellId);
    expect(b!.proposedCellId).toBe(c!.proposedCellId);
    expect(c!.proposedCellId).toBe(d!.proposedCellId);
    expect(a!.keyNumber).toBeNull();
  });

  test('returns null for unsupported addresses', () => {
    expect(proposeSiteCell({ rawAddress: 'PO Box 123, Brisbane QLD 4000' })).toBeNull();
    expect(proposeSiteCell({ rawAddress: 'P.O. Box 456' })).toBeNull();
    expect(proposeSiteCell({ rawAddress: 'Lot 17 DP12345 Rural Road, Wagga NSW' })).toBeNull();
    expect(proposeSiteCell({ rawAddress: '' })).toBeNull();
    expect(proposeSiteCell({ rawAddress: '   ' })).toBeNull();
  });

  test('preserves raw + normalized + keyNumber in payload', () => {
    const p = proposeSiteCell({
      rawAddress: '10 List Ln., Brisbane, Qld 4000',
      keyNumber: 'Unit 3',
    });
    expect(p).not.toBeNull();
    expect(p!.kind).toBe('propose');
    expect(p!.rawAddress).toBe('10 List Ln., Brisbane, Qld 4000');
    expect(p!.normalizedAddress).toBe('10 list lane brisbane qld 4000');
    expect(p!.keyNumber).toBe('3');
  });
});

/* ──────────────────────────────────────────────────────────────────────
 * The KEYSTONE property: equivalent inputs → same cellId
 * ────────────────────────────────────────────────────────────────────── */

describe('proposeSiteCell: dedupe equivalence (keystone)', () => {
  const equivalents: Array<[string, string, string]> = [
    [
      'mixed case + comma styling',
      '10 List Lane, Brisbane QLD 4000',
      '10 LIST LANE BRISBANE QLD 4000',
    ],
    [
      'abbreviation + full name',
      '8 Maple Ln, Melbourne Vic 3000',
      '8 MAPLE LANE MELBOURNE VICTORIA 3000',
    ],
    [
      'country suffix present vs absent',
      '101 Sunset Blvd, Gold Coast QLD 4217',
      '101 Sunset Boulevard Gold Coast QLD 4217 Australia',
    ],
    [
      'extra whitespace',
      '   12 Oak Road,  Sydney  NSW  2000   ',
      '12 Oak Road, Sydney NSW 2000',
    ],
    [
      'periods in suffix',
      '5 Pine St., Brisbane QLD 4000',
      '5 Pine Street Brisbane QLD 4000',
    ],
  ];

  for (const [label, a, b] of equivalents) {
    test(`same cell: ${label}`, () => {
      const pa = proposeSiteCell({ rawAddress: a });
      const pb = proposeSiteCell({ rawAddress: b });
      expect(pa).not.toBeNull();
      expect(pb).not.toBeNull();
      expect(pa!.proposedCellId).toBe(pb!.proposedCellId);
      expect(pa!.lookupKey).toBe(pb!.lookupKey);
    });
  }

  const distinct: Array<[string, string, string]> = [
    [
      'different street number',
      '10 List Lane Brisbane QLD 4000',
      '12 List Lane Brisbane QLD 4000',
    ],
    [
      'different suburb',
      '10 List Lane Brisbane QLD 4000',
      '10 List Lane Cairns QLD 4870',
    ],
    [
      'different state',
      '10 Park Avenue Sydney NSW 2000',
      '10 Park Avenue Melbourne VIC 3000',
    ],
    [
      'street type mismatch (lane vs road)',
      '10 List Lane Brisbane QLD 4000',
      '10 List Road Brisbane QLD 4000',
    ],
  ];

  for (const [label, a, b] of distinct) {
    test(`distinct cells: ${label}`, () => {
      const pa = proposeSiteCell({ rawAddress: a });
      const pb = proposeSiteCell({ rawAddress: b });
      expect(pa).not.toBeNull();
      expect(pb).not.toBeNull();
      expect(pa!.proposedCellId).not.toBe(pb!.proposedCellId);
    });
  }
});

/* ──────────────────────────────────────────────────────────────────────
 * findOrPropose — branches on SitesView result
 * ────────────────────────────────────────────────────────────────────── */

describe('findOrPropose: view-backed branching', () => {
  test('match: returns existing cellId when view finds the key', async () => {
    const proposal = proposeSiteCell({ rawAddress: '10 List Lane, Brisbane QLD 4000' });
    expect(proposal).not.toBeNull();
    const existingCellId = 'a'.repeat(64);
    const view = makeView({ [proposal!.lookupKey]: existingCellId });

    const result = await findOrPropose({ rawAddress: '10 List Lane, Brisbane QLD 4000' }, view);
    expect(result).not.toBeNull();
    expect(result!.kind).toBe('match');
    if (result!.kind === 'match') {
      expect(result.cellId).toBe(existingCellId);
      expect(result.normalizedAddress).toBe('10 list lane brisbane qld 4000');
    }
    expect(view.calls).toHaveLength(1);
  });

  test('propose: returns deterministic cellId when view has no match', async () => {
    const view = makeView();
    const result = await findOrPropose(
      { rawAddress: '10 List Lane, Brisbane QLD 4000' },
      view,
    );
    expect(result).not.toBeNull();
    expect(result!.kind).toBe('propose');
    if (result!.kind === 'propose') {
      expect(result.proposedCellId).toHaveLength(64);
      // Calling again yields the same cellId.
      const result2 = await findOrPropose(
        { rawAddress: '10 List Lane, Brisbane QLD 4000' },
        view,
      );
      if (result2!.kind === 'propose') {
        expect(result2.proposedCellId).toBe(result.proposedCellId);
      } else {
        throw new Error('expected propose');
      }
    }
  });

  test('null: unsupported address never hits the view', async () => {
    const view = makeView();
    const result = await findOrPropose({ rawAddress: 'PO Box 99' }, view);
    expect(result).toBeNull();
    expect(view.calls).toHaveLength(0);
  });

  test('equivalent address shapes both resolve to the same match', async () => {
    const seed = proposeSiteCell({ rawAddress: '8 Maple Lane Melbourne VIC 3000' });
    expect(seed).not.toBeNull();
    const view = makeView({ [seed!.lookupKey]: 'b'.repeat(64) });

    const r1 = await findOrPropose(
      { rawAddress: '8 Maple Ln, Melbourne Vic 3000' },
      view,
    );
    const r2 = await findOrPropose(
      { rawAddress: '8 MAPLE LANE MELBOURNE VICTORIA 3000' },
      view,
    );
    expect(r1!.kind).toBe('match');
    expect(r2!.kind).toBe('match');
    if (r1!.kind === 'match' && r2!.kind === 'match') {
      expect(r1.cellId).toBe(r2.cellId);
    }
  });
});

/* ──────────────────────────────────────────────────────────────────────
 * Formula stability — guards against accidental hash drift
 * ────────────────────────────────────────────────────────────────────── */

describe('formula stability', () => {
  test('computeSiteCellId is stable across calls', () => {
    const a = computeSiteCellId('10 list lane brisbane qld 4000', null);
    const b = computeSiteCellId('10 list lane brisbane qld 4000', null);
    expect(a).toBe(b);
  });

  test('computeSiteCellId is sensitive to keyNumber', () => {
    const a = computeSiteCellId('10 list lane brisbane qld 4000', null);
    const b = computeSiteCellId('10 list lane brisbane qld 4000', '2');
    expect(a).not.toBe(b);
  });

  test('deriveLookupKey is deterministic', () => {
    expect(deriveLookupKey('10 list lane brisbane qld 4000', null)).toBe(
      '10 list lane brisbane qld 4000|',
    );
    expect(deriveLookupKey('10 list lane brisbane qld 4000', '2')).toBe(
      '10 list lane brisbane qld 4000|2',
    );
  });
});

```
