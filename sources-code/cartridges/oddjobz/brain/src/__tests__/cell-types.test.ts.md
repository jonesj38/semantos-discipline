---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/__tests__/cell-types.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.512259+00:00
---

# cartridges/oddjobz/brain/src/__tests__/cell-types.test.ts

```ts
/**
 * D-O2 acceptance tests.
 *
 * For every committed conformance vector and for the cell-type
 * registry as a whole, asserts:
 *
 *   1. **Round-trip**: each type packs → unpacks → byte-identical re-pack.
 *   2. **Linearity**: each type carries the §O2 high-level label and
 *      the canonical wire-level code.
 *   3. **Type-hash stability**: each type's typeHash matches the
 *      committed entry in `docs/canon/glossary.yml`.
 *   4. **Vector parity**: every committed vector loads, deserialises,
 *      and re-serialises to byte-identical input.
 */

import { describe, expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  ODDJOBZ_CELL_TYPES,
  cellTypeByName,
  cellTypeByHashHex,
  customerCellType,
  siteCellType,
  jobCellType,
  quoteCellType,
  visitCellType,
  invoiceCellType,
  estimateCellType,
  messageCellType,
  leadCellType,
  attachmentCellType,
  pricingPolicyCellType,
  computeTypeHash,
  typeHashHex,
  WireLinearity,
  type AnyOddjobzCellTypeDef,
  type Linearity,
} from '../cell-types/index.js';

const HERE = dirname(fileURLToPath(import.meta.url));
const VECTORS_DIR = resolve(HERE, '..', '..', 'tests', 'vectors');
const GLOSSARY_PATH = resolve(HERE, '..', '..', '..', '..', 'docs', 'canon', 'glossary.yml');

interface Vector {
  name: string;
  input: unknown;
  packed: string;
  typeHash: string;
  linearity: string;
}

function hexToBytes(hex: string): Uint8Array {
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) {
    out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }
  return out;
}

function bytesToHex(b: Uint8Array): string {
  let out = '';
  for (let i = 0; i < b.length; i++) {
    out += (b[i] as number).toString(16).padStart(2, '0');
  }
  return out;
}

function loadVectors(filename: string): Vector[] {
  const raw = readFileSync(resolve(VECTORS_DIR, filename), 'utf-8');
  return JSON.parse(raw) as Vector[];
}

// Expected linearity table — the §O2 contract verbatim.
const expectedLinearity: ReadonlyArray<{
  type: AnyOddjobzCellTypeDef;
  vectorFile: string;
  label: Linearity;
  wire: number;
}> = [
  { type: jobCellType, vectorFile: 'oddjobz_job.json', label: 'LINEAR', wire: WireLinearity.LINEAR },
  { type: quoteCellType, vectorFile: 'oddjobz_quote.json', label: 'LINEAR', wire: WireLinearity.LINEAR },
  { type: visitCellType, vectorFile: 'oddjobz_visit.json', label: 'LINEAR', wire: WireLinearity.LINEAR },
  { type: invoiceCellType, vectorFile: 'oddjobz_invoice.json', label: 'LINEAR', wire: WireLinearity.LINEAR },
  { type: customerCellType, vectorFile: 'oddjobz_customer.json', label: 'PERSISTENT', wire: WireLinearity.RELEVANT },
  { type: siteCellType, vectorFile: 'oddjobz_site.json', label: 'PERSISTENT', wire: WireLinearity.RELEVANT },
  { type: estimateCellType, vectorFile: 'oddjobz_estimate.json', label: 'AFFINE', wire: WireLinearity.AFFINE },
  { type: messageCellType, vectorFile: 'oddjobz_message.json', label: 'PERSISTENT', wire: WireLinearity.RELEVANT },
  // D-O6b — Lead cell (AFFINE) appended to the registry.
  { type: leadCellType, vectorFile: 'oddjobz_lead.json', label: 'AFFINE', wire: WireLinearity.AFFINE },
  // D-O5m.followup-8 substrate — Attachment cell (LINEAR) appended.
  { type: attachmentCellType, vectorFile: 'oddjobz_attachment.json', label: 'LINEAR', wire: WireLinearity.LINEAR },
];

describe('§O2 / §O6b — cell-type registry', () => {
  test('exports all ten cell types (8 from D-O2 + lead from D-O6b + attachment from D-O5m.followup-8)', () => {
    expect(ODDJOBZ_CELL_TYPES).toHaveLength(10);
    const names = ODDJOBZ_CELL_TYPES.map((t) => t.name).sort();
    expect(names).toEqual(
      [
        'oddjobz.attachment.v1',
        'oddjobz.customer.v1',
        'oddjobz.estimate.v1',
        'oddjobz.invoice.v1',
        'oddjobz.job.v1',
        'oddjobz.lead.v1',
        'oddjobz.message.v1',
        'oddjobz.quote.v1',
        'oddjobz.site.v1',
        'oddjobz.visit.v1',
      ].sort(),
    );
  });

  test('byName / byHashHex registries agree with ODDJOBZ_CELL_TYPES', () => {
    for (const t of ODDJOBZ_CELL_TYPES) {
      expect(cellTypeByName[t.name]).toBe(t);
      expect(cellTypeByHashHex[t.typeHashHex]).toBe(t);
    }
  });

  test('typeHash is 32 bytes per type', () => {
    for (const t of ODDJOBZ_CELL_TYPES) {
      expect(t.typeHash.length).toBe(32);
      expect(t.typeHashHex.length).toBe(64);
    }
  });

  test('typeHash hex strings are unique across the eight types', () => {
    const seen = new Set<string>();
    for (const t of ODDJOBZ_CELL_TYPES) {
      expect(seen.has(t.typeHashHex)).toBe(false);
      seen.add(t.typeHashHex);
    }
  });
});

describe('§O2 — linearity flags', () => {
  for (const { type, label, wire } of expectedLinearity) {
    test(`${type.name} is ${label} (wire=${wire})`, () => {
      expect(type.linearity).toBe(label);
      expect(type.wireLinearity).toBe(wire as never);
    });
  }
});

describe('§O2 — typeHash stability (recompute matches frozen value)', () => {
  for (const t of ODDJOBZ_CELL_TYPES) {
    test(`${t.name} typeHash matches recomputation from identity triple`, () => {
      const recomputed = computeTypeHash(t.identity);
      expect(typeHashHex(recomputed)).toBe(t.typeHashHex);
      expect(recomputed.length).toBe(t.typeHash.length);
      for (let i = 0; i < recomputed.length; i++) {
        expect(recomputed[i]).toBe(t.typeHash[i] as number);
      }
    });
  }
});

describe('§O2 — typeHash stability (matches glossary.yml)', () => {
  // Cheap regex parse — avoids pulling in a YAML dep just for this check.
  const glossary = readFileSync(GLOSSARY_PATH, 'utf-8');

  for (const t of ODDJOBZ_CELL_TYPES) {
    test(`${t.name} typeHash matches glossary.yml entry`, () => {
      // Find the canonical: <name> line, then look forward for type_hash:.
      const canonicalIdx = glossary.indexOf(`canonical: ${t.name}`);
      expect(canonicalIdx).toBeGreaterThan(-1);
      const slice = glossary.slice(canonicalIdx, canonicalIdx + 4000);
      const m = slice.match(/^\s+type_hash:\s+([0-9a-f]{64})\s*$/m);
      expect(m).not.toBeNull();
      expect(m![1]).toBe(t.typeHashHex);
    });
  }
});

describe('§O2 — round-trip identity (registry-driven)', () => {
  // Synthetic minimal inputs to stress the pack/unpack pipeline at the
  // type-system level (in addition to the committed vector parity tests).
  // Each type's vector file already covers richer cases; this tier
  // ensures every type actually round-trips at all before vector tests run.
  const samples: Array<{ type: AnyOddjobzCellTypeDef; sample: unknown }> = [
    {
      type: customerCellType,
      sample: {
        customerId: '00000001-0000-4000-8000-000000000001',
        name: 'X',
        createdAt: '2026-01-01T00:00:00Z',
        updatedAt: '2026-01-01T00:00:00Z',
      },
    },
    {
      type: siteCellType,
      sample: {
        siteId: '00000002-0000-4000-8000-000000000002',
        customerId: '00000001-0000-4000-8000-000000000001',
        createdAt: '2026-01-01T00:00:00Z',
        updatedAt: '2026-01-01T00:00:00Z',
      },
    },
    {
      type: jobCellType,
      sample: {
        jobId: '00000003-0000-4000-8000-000000000003',
        status: 'lead',
        createdAt: '2026-01-01T00:00:00Z',
        updatedAt: '2026-01-01T00:00:00Z',
      },
    },
    {
      type: quoteCellType,
      sample: {
        quoteId: '00000004-0000-4000-8000-000000000004',
        jobId: '00000003-0000-4000-8000-000000000003',
        status: 'draft',
        costMin: 100,
        costMax: 200,
        createdAt: '2026-01-01T00:00:00Z',
        updatedAt: '2026-01-01T00:00:00Z',
      },
    },
    {
      type: visitCellType,
      sample: {
        visitId: '00000005-0000-4000-8000-000000000005',
        jobId: '00000003-0000-4000-8000-000000000003',
        visitType: 'inspection',
        status: 'scheduled',
        createdAt: '2026-01-01T00:00:00Z',
        updatedAt: '2026-01-01T00:00:00Z',
      },
    },
    {
      type: invoiceCellType,
      sample: {
        invoiceId: '00000006-0000-4000-8000-000000000006',
        jobId: '00000003-0000-4000-8000-000000000003',
        status: 'draft',
        amount: 0,
        createdAt: '2026-01-01T00:00:00Z',
        updatedAt: '2026-01-01T00:00:00Z',
      },
    },
    {
      type: estimateCellType,
      sample: {
        estimateId: '00000007-0000-4000-8000-000000000007',
        jobId: '00000003-0000-4000-8000-000000000003',
        estimateType: 'auto_rom',
        createdAt: '2026-01-01T00:00:00Z',
        updatedAt: '2026-01-01T00:00:00Z',
      },
    },
    {
      type: messageCellType,
      sample: {
        messageId: '00000008-0000-4000-8000-000000000008',
        jobId: '00000003-0000-4000-8000-000000000003',
        senderType: 'customer',
        messageType: 'text',
        rawContent: 'hi',
        createdAt: '2026-01-01T00:00:00Z',
      },
    },
    {
      type: leadCellType,
      sample: {
        leadId: '00000009-0000-4000-8000-000000000009',
        chatSessionId: 'sess-1',
        extractedEstimateId: '00000007-0000-4000-8000-000000000007',
        customerHint: 'Pat / 0400-000-000',
        jobId: '00000003-0000-4000-8000-000000000003',
        ratifiedBy: '00112233445566778899aabbccddeeff',
        ratifiedAt: '2026-01-01T00:00:00Z',
        provenance: 'from_chat',
      },
    },
    {
      type: attachmentCellType,
      sample: {
        attachmentId: '0000000a-0000-4000-8000-00000000000a',
        visitId: '00000005-0000-4000-8000-000000000005',
        kind: 'photo',
        contentHash: 'a'.repeat(64),
        contentSize: 1024,
        mimeType: 'image/jpeg',
        capturedAt: '2026-05-15T14:30:00Z',
        capturedByCertId: '00112233445566778899aabbccddeeff',
        createdAt: '2026-05-15T14:30:01Z',
      },
    },
  ];

  for (const { type, sample } of samples) {
    test(`${type.name} packs → unpacks → re-packs byte-identical`, () => {
      const packed1 = (type as { pack: (v: unknown) => Uint8Array }).pack(sample);
      const unpacked = (type as { unpack: (b: Uint8Array) => unknown }).unpack(packed1);
      const packed2 = (type as { pack: (v: unknown) => Uint8Array }).pack(unpacked);
      expect(bytesToHex(packed2)).toBe(bytesToHex(packed1));
    });
  }
});

describe('§O2 — vector parity (every committed vector round-trips)', () => {
  for (const { type, vectorFile, label } of expectedLinearity) {
    describe(`${type.name}`, () => {
      const vectors = loadVectors(vectorFile);

      test(`vector file has at least 3 entries`, () => {
        expect(vectors.length).toBeGreaterThanOrEqual(3);
      });

      for (const vec of vectors) {
        test(`vector ${JSON.stringify(vec.name)} round-trips byte-identical`, () => {
          // Vector consistency: typeHash and linearity match the type def.
          expect(vec.typeHash).toBe(type.typeHashHex);
          expect(vec.linearity).toBe(label);

          // Re-pack the input and assert hex equality with the committed bytes.
          const repacked = (type as { pack: (v: unknown) => Uint8Array }).pack(vec.input);
          expect(bytesToHex(repacked)).toBe(vec.packed);

          // Unpack the committed bytes and re-pack — byte-identical.
          const bytes = hexToBytes(vec.packed);
          const unpacked = (type as { unpack: (b: Uint8Array) => unknown }).unpack(bytes);
          const repacked2 = (type as { pack: (v: unknown) => Uint8Array }).pack(unpacked);
          expect(bytesToHex(repacked2)).toBe(vec.packed);
        });
      }
    });
  }
});

describe('A5 / DEBT-XLANG-CELL-CONTRACT — pricing_policy vector parity (the canonical Zig oracle)', () => {
  // pricing_policy is operator CONFIG, not a §O2 entity — kept OUT of
  // the `expectedLinearity` table (so the v1-length-10 assertions stay
  // green) but held to the SAME byte-parity contract. These committed
  // vectors are the single source of truth the Zig P2.d
  // set_pricing_policy handler's conformance test will consume, so a
  // hand-mirrored Zig implementation cannot silently drift from the TS
  // encoding / validation / amendment-chain invariants.
  const vectors = loadVectors('oddjobz_pricing_policy.json');

  test('vector file has at least 3 entries (genesis + amendments)', () => {
    expect(vectors.length).toBeGreaterThanOrEqual(3);
  });

  for (const vec of vectors) {
    test(`vector ${JSON.stringify(vec.name)} round-trips byte-identical`, () => {
      expect(vec.typeHash).toBe(pricingPolicyCellType.typeHashHex);
      expect(vec.linearity).toBe('PERSISTENT'); // → wire RELEVANT

      const repacked = pricingPolicyCellType.pack(
        vec.input as Parameters<typeof pricingPolicyCellType.pack>[0],
      );
      expect(bytesToHex(repacked)).toBe(vec.packed);

      const bytes = hexToBytes(vec.packed);
      const unpacked = pricingPolicyCellType.unpack(bytes);
      const repacked2 = pricingPolicyCellType.pack(unpacked);
      expect(bytesToHex(repacked2)).toBe(vec.packed);
    });
  }
});

describe('§O2 — canonical-JSON determinism', () => {
  test('object-key order does not affect output bytes', () => {
    // Build the same Customer twice with different insertion orders; bytes must match.
    const a = customerCellType.pack({
      customerId: '00000001-0000-4000-8000-000000000001',
      name: 'X',
      createdAt: '2026-01-01T00:00:00Z',
      updatedAt: '2026-01-01T00:00:00Z',
      phone: '+1',
      email: 'x@y.z',
    });
    const b = customerCellType.pack({
      email: 'x@y.z',
      updatedAt: '2026-01-01T00:00:00Z',
      phone: '+1',
      customerId: '00000001-0000-4000-8000-000000000001',
      createdAt: '2026-01-01T00:00:00Z',
      name: 'X',
    });
    expect(bytesToHex(a)).toBe(bytesToHex(b));
  });
});

```
