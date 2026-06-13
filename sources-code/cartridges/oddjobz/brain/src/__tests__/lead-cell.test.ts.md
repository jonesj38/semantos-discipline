---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/__tests__/lead-cell.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.510982+00:00
---

# cartridges/oddjobz/brain/src/__tests__/lead-cell.test.ts

```ts
/**
 * D-O6b — `oddjobz.lead.v1` cell-type focused tests.
 *
 * Acceptance scope:
 *  - the new AFFINE cell type is registered in `ODDJOBZ_CELL_TYPES`
 *    (covered by `cell-types.test.ts` registry test).
 *  - the cell's pack/unpack round-trip is exercised by the §O2 vector-
 *    parity matrix (covered by the registry-driven loop).
 *  - this file covers the *negative* validate paths + the cross-field
 *    invariants specific to the Lead cell.
 */

import { describe, expect, test } from 'bun:test';
import { leadCellType, LEAD_PROVENANCES, type OddjobzLead } from '../cell-types/lead.js';

const VALID: OddjobzLead = {
  leadId: '30303030-3030-4030-8030-303030303030',
  chatSessionId: 'sess-abc',
  extractedEstimateId: '13131313-1313-4131-8131-131313131313',
  customerHint: 'Sam / 0400-111-222 / deck repair',
  jobId: '55555555-5555-4555-8555-555555555555',
  ratifiedBy: '20202020202040208020202020202020',
  ratifiedAt: '2026-05-01T09:30:00Z',
  provenance: 'from_chat',
};

describe('§O6b — oddjobz.lead.v1 — validate', () => {
  test('accepts a fully-populated valid Lead', () => {
    expect(() => leadCellType.pack(VALID)).not.toThrow();
  });

  test('rejects bad leadId (not a UUID)', () => {
    expect(() => leadCellType.pack({ ...VALID, leadId: 'not-a-uuid' })).toThrow(
      /leadId/,
    );
  });

  test('rejects bad extractedEstimateId', () => {
    expect(() =>
      leadCellType.pack({ ...VALID, extractedEstimateId: 'nope' }),
    ).toThrow(/extractedEstimateId/);
  });

  test('rejects bad jobId', () => {
    expect(() => leadCellType.pack({ ...VALID, jobId: 'not-a-uuid' })).toThrow(
      /jobId/,
    );
  });

  test('rejects bad ratifiedBy (not 16-byte hex)', () => {
    expect(() =>
      leadCellType.pack({ ...VALID, ratifiedBy: 'too-short' }),
    ).toThrow(/ratifiedBy/);
    expect(() =>
      leadCellType.pack({
        ...VALID,
        // wrong length
        ratifiedBy: '20202020202040208020202020202020a',
      }),
    ).toThrow(/ratifiedBy/);
    expect(() =>
      leadCellType.pack({
        ...VALID,
        // upper-case rejected — canonical form is lower-case hex
        ratifiedBy: 'AABBCCDDEEFF00112233445566778899',
      }),
    ).toThrow(/ratifiedBy/);
    expect(() =>
      leadCellType.pack({
        ...VALID,
        // non-hex char rejected
        ratifiedBy: '20202020202040208020202020202020'.replace('0', 'g'),
      }),
    ).toThrow(/ratifiedBy/);
  });

  test('rejects bad ratifiedAt (not ISO-8601)', () => {
    expect(() =>
      leadCellType.pack({ ...VALID, ratifiedAt: 'yesterday' }),
    ).toThrow(/ratifiedAt/);
  });

  test('rejects bad provenance', () => {
    expect(() =>
      leadCellType.pack({
        ...VALID,
        // @ts-expect-error — runtime check
        provenance: 'from_skywriting',
      }),
    ).toThrow(/provenance/);
  });

  test('rejects oversized chatSessionId', () => {
    const tooLong = 'a'.repeat(257);
    expect(() =>
      leadCellType.pack({ ...VALID, chatSessionId: tooLong }),
    ).toThrow(/chatSessionId/);
  });

  test('rejects oversized customerHint', () => {
    const tooLong = 'a'.repeat(4001);
    expect(() =>
      leadCellType.pack({ ...VALID, customerHint: tooLong }),
    ).toThrow(/customerHint/);
  });

  test('cross-field invariant: from_chat requires chatSessionId', () => {
    expect(() =>
      leadCellType.pack({ ...VALID, chatSessionId: '' }),
    ).toThrow(/from_chat requires non-empty chatSessionId/);
  });

  test('non-chat provenances allow empty chatSessionId', () => {
    for (const p of LEAD_PROVENANCES) {
      if (p === 'from_chat') continue;
      expect(() =>
        leadCellType.pack({ ...VALID, chatSessionId: '', provenance: p }),
      ).not.toThrow();
    }
  });
});

describe('§O6b — oddjobz.lead.v1 — round-trip identity', () => {
  test('pack → unpack → re-pack is byte-identical', () => {
    const a = leadCellType.pack(VALID);
    const v = leadCellType.unpack(a);
    const b = leadCellType.pack(v);
    expect(a.length).toBe(b.length);
    for (let i = 0; i < a.length; i++) expect(a[i]).toBe(b[i] as number);
  });

  test('canonical-JSON ordering: insertion order does not affect bytes', () => {
    const v1: OddjobzLead = { ...VALID };
    // Build a different insertion order — TS object literals preserve
    // insertion order in V8 / JSC. We construct the keys explicitly via
    // Object.fromEntries to scramble.
    const entries: [string, unknown][] = Object.entries(v1).reverse();
    const v2 = Object.fromEntries(entries) as unknown as OddjobzLead;
    expect(leadCellType.pack(v1).length).toBe(leadCellType.pack(v2).length);
    const a = leadCellType.pack(v1);
    const b = leadCellType.pack(v2);
    for (let i = 0; i < a.length; i++) expect(a[i]).toBe(b[i] as number);
  });
});

describe('§O6b — oddjobz.lead.v1 — linearity + identity metadata', () => {
  test('AFFINE high-level + wire code 2', () => {
    expect(leadCellType.linearity).toBe('AFFINE');
    expect(leadCellType.wireLinearity).toBe(2);
  });

  test('canonical name', () => {
    expect(leadCellType.name).toBe('oddjobz.lead.v1');
  });

  test('typeHash is 32 bytes / 64 hex chars', () => {
    expect(leadCellType.typeHash.length).toBe(32);
    expect(leadCellType.typeHashHex.length).toBe(64);
  });

  test('typeHash matches the value committed in glossary.yml', () => {
    // Stable as of D-O6b (2026-05-01).
    expect(leadCellType.typeHashHex).toBe(
      '3f3241ffbd0741bce50d214364383a0baac44ab6512fd0a4553d1f910afe4cc5',
    );
  });
});

```
