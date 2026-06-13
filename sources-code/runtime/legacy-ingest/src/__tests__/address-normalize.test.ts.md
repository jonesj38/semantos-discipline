---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/address-normalize.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.145151+00:00
---

# runtime/legacy-ingest/src/__tests__/address-normalize.test.ts

```ts
/**
 * D-RTC.1 — address-normalize conformance tests.
 *
 * Reference: docs/prd/D-Reingest-Typed-Cells.md §Deliverables / D-RTC.1.
 *
 * Acceptance gate: 30 OJT-realistic addresses; equivalent inputs must
 * normalize to the same key; non-equivalent inputs must normalize to
 * different keys; unsupported inputs (PO box, international) return null.
 */

import { describe, test, expect } from 'bun:test';
import { normalizeAddress } from '../address-normalize';

describe('normalizeAddress: basic canonicalisation', () => {
  test('lowercases + collapses whitespace', () => {
    expect(normalizeAddress('10 List Lane, Brisbane QLD 4000')).toBe(
      '10 list lane brisbane qld 4000',
    );
  });

  test('strips commas + periods', () => {
    expect(normalizeAddress('10 List Ln., Brisbane, Qld 4000')).toBe(
      '10 list lane brisbane qld 4000',
    );
  });

  test('returns null for empty + whitespace-only', () => {
    expect(normalizeAddress('')).toBeNull();
    expect(normalizeAddress('   ')).toBeNull();
  });

  test('returns null for non-string input', () => {
    // @ts-expect-error — testing runtime defence
    expect(normalizeAddress(null)).toBeNull();
    // @ts-expect-error
    expect(normalizeAddress(undefined)).toBeNull();
    // @ts-expect-error
    expect(normalizeAddress(42)).toBeNull();
  });

  test('returns null for pathologically-long input', () => {
    const huge = 'a'.repeat(300);
    expect(normalizeAddress(huge)).toBeNull();
  });
});

describe('normalizeAddress: suffix canonicalisation', () => {
  const equivalents: Array<[string, string, string]> = [
    ['st → street', '5 Pine St, Brisbane QLD 4000', '5 Pine Street, Brisbane QLD 4000'],
    ['rd → road', '12 Oak Rd, Sydney NSW 2000', '12 Oak Road, Sydney NSW 2000'],
    ['ln → lane', '8 Maple Ln, Melbourne VIC 3000', '8 Maple Lane, Melbourne VIC 3000'],
    ['ave → avenue', '3 Park Ave, Perth WA 6000', '3 Park Avenue, Perth WA 6000'],
    ['dr → drive', '7 Hill Dr, Hobart TAS 7000', '7 Hill Drive, Hobart TAS 7000'],
    ['ct → court', '14 Bay Ct, Darwin NT 0800', '14 Bay Court, Darwin NT 0800'],
    ['pl → place', '6 Garden Pl, Adelaide SA 5000', '6 Garden Place, Adelaide SA 5000'],
    ['hwy → highway', '450 Pacific Hwy, Sydney NSW 2000', '450 Pacific Highway, Sydney NSW 2000'],
    ['cres → crescent', '22 River Cres, Brisbane QLD 4000', '22 River Crescent, Brisbane QLD 4000'],
    ['blvd → boulevard', '101 Sunset Blvd, Gold Coast QLD 4217', '101 Sunset Boulevard, Gold Coast QLD 4217'],
    ['tce → terrace', '4 Ocean Tce, Newcastle NSW 2300', '4 Ocean Terrace, Newcastle NSW 2300'],
    ['pde → parade', '17 Esplanade Pde, Cairns QLD 4870', '17 Esplanade Parade, Cairns QLD 4870'],
  ];

  for (const [label, a, b] of equivalents) {
    test(`${label} — equivalent inputs collapse`, () => {
      const na = normalizeAddress(a);
      const nb = normalizeAddress(b);
      expect(na).not.toBeNull();
      expect(na).toBe(nb!);
    });
  }
});

describe('normalizeAddress: state canonicalisation', () => {
  test('full state name → abbreviation', () => {
    expect(normalizeAddress('10 List Lane, Brisbane Queensland 4000')).toBe(
      '10 list lane brisbane qld 4000',
    );
  });

  test('mixed-case state code', () => {
    expect(normalizeAddress('10 List Lane Brisbane qld 4000')).toBe(
      normalizeAddress('10 List Lane Brisbane QLD 4000'),
    );
  });

  test('full New South Wales → nsw', () => {
    expect(normalizeAddress('12 Oak Road, Sydney New South Wales 2000')).toBe(
      '12 oak road sydney nsw 2000',
    );
  });
});

describe('normalizeAddress: unit form canonicalisation', () => {
  test('"Unit 2 / 15 Pine Street" → "unit 2/15 pine street"', () => {
    expect(normalizeAddress('Unit 2 / 15 Pine Street, North Sydney NSW 2060')).toBe(
      'unit 2/15 pine street north sydney nsw 2060',
    );
  });

  test('"U2/15" compact form → "unit 2/15"', () => {
    expect(normalizeAddress('U2/15 Pine Street, North Sydney NSW 2060')).toBe(
      'unit 2/15 pine street north sydney nsw 2060',
    );
  });

  test('"Apt 5, 12 Pine Street" → "apt 5/12 pine street"', () => {
    expect(normalizeAddress('Apt 5, 12 Pine Street, North Sydney NSW 2060')).toBe(
      'apt 5/12 pine street north sydney nsw 2060',
    );
  });

  test('"Suite 304/100 King Street" → "suite 304/100 king street"', () => {
    expect(normalizeAddress('Suite 304/100 King Street, Brisbane QLD 4000')).toBe(
      'suite 304/100 king street brisbane qld 4000',
    );
  });

  test('plain "2/15 Pine Street" (no unit prefix) passes through', () => {
    expect(normalizeAddress('2/15 Pine Street, North Sydney NSW 2060')).toBe(
      '2/15 pine street north sydney nsw 2060',
    );
  });
});

describe('normalizeAddress: country suffix stripping', () => {
  test('"Australia" tail is stripped', () => {
    expect(normalizeAddress('10 List Lane, Brisbane QLD 4000, Australia')).toBe(
      '10 list lane brisbane qld 4000',
    );
  });

  test('"AU" tail is stripped', () => {
    expect(normalizeAddress('10 List Lane Brisbane QLD 4000 AU')).toBe(
      '10 list lane brisbane qld 4000',
    );
  });
});

describe('normalizeAddress: rejection of out-of-scope inputs', () => {
  test('PO box returns null', () => {
    expect(normalizeAddress('PO Box 123, Brisbane QLD 4000')).toBeNull();
    expect(normalizeAddress('P.O. Box 456, Sydney NSW 2000')).toBeNull();
  });

  test('Lot-based legal description returns null', () => {
    expect(normalizeAddress('Lot 17 DP12345 Rural Road, Wagga NSW')).toBeNull();
  });
});

describe('normalizeAddress: dedupe equivalence (the keystone property)', () => {
  // The contract: any pair below should produce IDENTICAL keys, so
  // site-dedupe.ts will merge them into one site_cell.
  const pairs: Array<[string, string, string]> = [
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
      'unit prefix variants',
      'Unit 2 / 15 Pine Street North Sydney NSW 2060',
      'U2/15 Pine St, North Sydney NSW 2060',
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
  ];

  for (const [label, a, b] of pairs) {
    test(`equivalent: ${label}`, () => {
      const na = normalizeAddress(a);
      const nb = normalizeAddress(b);
      expect(na).not.toBeNull();
      expect(na).toBe(nb!);
    });
  }

  // And the negative side: different addresses must NOT collide.
  const distinct: Array<[string, string, string]> = [
    [
      'different street number',
      '10 List Lane Brisbane QLD 4000',
      '12 List Lane Brisbane QLD 4000',
    ],
    [
      'different street name',
      '10 List Lane Brisbane QLD 4000',
      '10 Lit Lane Brisbane QLD 4000',
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
      'unit vs no unit',
      'Unit 2 / 15 Pine Street North Sydney NSW 2060',
      '15 Pine Street North Sydney NSW 2060',
    ],
  ];

  for (const [label, a, b] of distinct) {
    test(`distinct: ${label}`, () => {
      const na = normalizeAddress(a);
      const nb = normalizeAddress(b);
      expect(na).not.toBeNull();
      expect(nb).not.toBeNull();
      expect(na).not.toBe(nb!);
    });
  }
});

```
