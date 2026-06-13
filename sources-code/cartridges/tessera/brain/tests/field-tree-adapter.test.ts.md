---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/tessera/brain/tests/field-tree-adapter.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.637213+00:00
---

# cartridges/tessera/brain/tests/field-tree-adapter.test.ts

```ts
/**
 * Tessera × L8 field-tree adapter tests.
 *
 * Reference:
 *   docs/canon/cw-lift-matrix.yml L8.
 *   docs/prd/TESSERA-CARTRIDGE.md §0.1.
 *
 * Exercises realistic care-chain disclosure scenarios:
 *   - bottle cell: producer commits all fields; consumer scans QR + sees
 *     only origin/vintage/certifications, not cost_basis/internal_sku;
 *     retailer sees lot_id/batch_id, not producer margins.
 *   - care-event cell: full chain of custody for auditors; tampered
 *     proof bodies rejected.
 *   - cross-cell-type binding: same payload under different cell types
 *     produces different roots (no replay).
 */

import { describe, expect, test } from 'bun:test';
import {
  buildTesseraFieldTree,
  computeTesseraFieldCommitments,
  discloseTesseraField,
  tesseraSchemaFingerprint,
  verifyTesseraFieldDisclosure,
} from '../src/field-tree-adapter';

function hex(b: Uint8Array): string {
  return Buffer.from(b).toString('hex');
}

// Realistic shapes — these aren't formal cell-type schemas (tessera
// uses opaque JSON), they're what an operator would actually commit.

function sampleBottle() {
  return {
    bottleId: 'btl-11111111-1111-4111-8111-111111111111',
    lotId: 'lot-bla-2024-shiraz-bin-29',
    batchId: 'btl-batch-2024-09-A',
    origin: 'Barossa Valley, SA, AU',
    vintage: 2024,
    varietal: 'Shiraz',
    certifications: ['BWS-organic', 'GI-Barossa'],
    expectedShelfYears: 8,
    // PRIVATE — the auditor / consumer should NOT see these:
    costBasisCents: 850,
    internalSku: 'PROD-SHZ-29-2024',
    distributorMarginPct: 18,
  };
}

function sampleCareEvent() {
  return {
    eventId: 'ce-22222222-2222-4222-8222-222222222222',
    subjectId: 'btl-11111111-1111-4111-8111-111111111111',
    eventType: 'transit-arrival',
    timestamp: '2026-06-02T14:00:00.000Z',
    location: 'Adelaide port warehouse, dock 7',
    handlerId: 'hdlr-d99f-1c4b',
    tempLogRoot: '0x1234abcd...',
    transitDurationHours: 36,
  };
}

describe('tessera × L8: field-tree adapter — schema fingerprint', () => {
  test('tesseraSchemaFingerprint is deterministic and cellType-bound', () => {
    const a = tesseraSchemaFingerprint('tessera.bottle');
    const b = tesseraSchemaFingerprint('tessera.bottle');
    expect(a.byteLength).toBe(32);
    expect(hex(a)).toBe(hex(b));
  });

  test('different cell types → different fingerprints', () => {
    const bottle = tesseraSchemaFingerprint('tessera.bottle');
    const event = tesseraSchemaFingerprint('tessera.care-event');
    expect(hex(bottle)).not.toBe(hex(event));
  });
});

describe('tessera × L8: bottle disclosure scenarios', () => {
  test('buildTesseraFieldTree produces a 32B root with cellType fingerprint', () => {
    const body = sampleBottle();
    const tree = buildTesseraFieldTree('tessera.bottle', body);
    expect(tree.root.byteLength).toBe(32);
    expect(hex(tree.schemaFingerprint)).toBe(hex(tesseraSchemaFingerprint('tessera.bottle')));
    // 11 fields in sampleBottle
    expect(tree.leafCount).toBe(11);
    expect(tree.fields.map((f) => f.label)).toContain('origin');
    expect(tree.fields.map((f) => f.label)).toContain('costBasisCents');
  });

  test('consumer scenario: disclose only public fields, NOT cost/sku/margin', () => {
    const body = sampleBottle();
    const tree = buildTesseraFieldTree('tessera.bottle', body);

    // Consumer disclosure: origin, vintage, certifications
    const pOrigin = discloseTesseraField('tessera.bottle', body, 'origin');
    const pVintage = discloseTesseraField('tessera.bottle', body, 'vintage');
    const pCerts = discloseTesseraField('tessera.bottle', body, 'certifications');

    for (const proof of [pOrigin, pVintage, pCerts]) {
      expect(verifyTesseraFieldDisclosure('tessera.bottle', proof, tree.root)).toBe(true);
    }

    // Each disclosure carries the disclosed field value but NOT the others
    const allProofsBlob = JSON.stringify(
      [pOrigin, pVintage, pCerts],
      (_k, v) => (v instanceof Uint8Array ? hex(v) : v),
    );
    // Cost/sku/margin must not appear in any plaintext OR hex form
    expect(allProofsBlob).not.toContain('850'); // costBasisCents
    expect(allProofsBlob).not.toContain('PROD-SHZ-29-2024');
    expect(allProofsBlob).not.toContain(Buffer.from('PROD-SHZ-29-2024').toString('hex'));
    expect(allProofsBlob).not.toContain('distributorMarginPct'); // label is in committed leaves only via hash
  });

  test('retailer scenario: see batch/lot/expected-arrival without producer margins', () => {
    const body = sampleBottle();
    const tree = buildTesseraFieldTree('tessera.bottle', body);

    const pLot = discloseTesseraField('tessera.bottle', body, 'lotId');
    const pBatch = discloseTesseraField('tessera.bottle', body, 'batchId');
    expect(verifyTesseraFieldDisclosure('tessera.bottle', pLot, tree.root)).toBe(true);
    expect(verifyTesseraFieldDisclosure('tessera.bottle', pBatch, tree.root)).toBe(true);

    const blob = JSON.stringify([pLot, pBatch], (_k, v) =>
      v instanceof Uint8Array ? hex(v) : v,
    );
    expect(blob).not.toContain('distributorMarginPct');
    expect(blob).not.toContain(Buffer.from('PROD-SHZ-29-2024').toString('hex'));
  });

  test('fail-closed: tampered proof.value rejected', () => {
    const body = sampleBottle();
    const tree = buildTesseraFieldTree('tessera.bottle', body);
    const proof = discloseTesseraField('tessera.bottle', body, 'origin');
    const tampered = { ...proof, value: new TextEncoder().encode('"FakeOrigin"') };
    expect(verifyTesseraFieldDisclosure('tessera.bottle', tampered, tree.root)).toBe(false);
  });

  test('fail-closed: proof asserted against the wrong cell type rejected', () => {
    const body = sampleBottle();
    const tree = buildTesseraFieldTree('tessera.bottle', body);
    const proof = discloseTesseraField('tessera.bottle', body, 'origin');
    // Caller swaps cellType in the verifier — defensive check rejects.
    expect(verifyTesseraFieldDisclosure('tessera.care-event', proof, tree.root)).toBe(false);
  });

  test('every field of the bottle body is individually disclosable', () => {
    const body = sampleBottle();
    const tree = buildTesseraFieldTree('tessera.bottle', body);
    for (const key of Object.keys(body)) {
      const proof = discloseTesseraField('tessera.bottle', body, key);
      expect(verifyTesseraFieldDisclosure('tessera.bottle', proof, tree.root)).toBe(true);
    }
  });

  test('determinism — same body → same root', () => {
    const a = buildTesseraFieldTree('tessera.bottle', sampleBottle());
    const b = buildTesseraFieldTree('tessera.bottle', sampleBottle());
    expect(hex(a.root)).toBe(hex(b.root));
  });

  test('different bottle bodies → different roots', () => {
    const a = buildTesseraFieldTree('tessera.bottle', sampleBottle());
    const altered = { ...sampleBottle(), origin: 'McLaren Vale, SA, AU' };
    const b = buildTesseraFieldTree('tessera.bottle', altered);
    expect(hex(a.root)).not.toBe(hex(b.root));
  });
});

describe('tessera × L8: care-event auditor disclosure', () => {
  test('full chain of custody fields are disclosable per-leaf for an auditor', () => {
    const body = sampleCareEvent();
    const tree = buildTesseraFieldTree('tessera.care-event', body);
    for (const key of Object.keys(body)) {
      const proof = discloseTesseraField('tessera.care-event', body, key);
      expect(verifyTesseraFieldDisclosure('tessera.care-event', proof, tree.root)).toBe(true);
    }
  });

  test('care-event root differs from bottle root with the same id field by typeHash binding', () => {
    // Even if a bottle cell and a care-event cell happened to share the
    // same id value, the schema fingerprint binding gives different
    // roots — preventing proof replay across cell types.
    const bottleTree = buildTesseraFieldTree('tessera.bottle', { id: 'same' });
    const eventTree = buildTesseraFieldTree('tessera.care-event', { id: 'same' });
    expect(hex(bottleTree.root)).not.toBe(hex(eventTree.root));
  });
});

describe('tessera × L8: structural validation', () => {
  test('rejects non-object body', () => {
    expect(() => buildTesseraFieldTree('tessera.bottle', 'just a string' as unknown)).toThrow();
    expect(() => buildTesseraFieldTree('tessera.bottle', 42 as unknown)).toThrow();
    expect(() => buildTesseraFieldTree('tessera.bottle', [1, 2, 3] as unknown)).toThrow();
    expect(() => buildTesseraFieldTree('tessera.bottle', null as unknown)).toThrow();
  });

  test('rejects empty body', () => {
    expect(() => buildTesseraFieldTree('tessera.bottle', {})).toThrow('zero fields');
  });

  test('computeTesseraFieldCommitments matches buildTesseraFieldTree leaf commitments', () => {
    const body = sampleBottle();
    const tree = buildTesseraFieldTree('tessera.bottle', body);
    const commits = computeTesseraFieldCommitments('tessera.bottle', body);
    expect(commits.length).toBe(tree.fields.length);
    for (let i = 0; i < commits.length; i++) {
      expect(commits[i].label).toBe(tree.fields[i].label);
      expect(hex(commits[i].commitment)).toBe(hex(tree.fields[i].commitment));
    }
  });
});

```
