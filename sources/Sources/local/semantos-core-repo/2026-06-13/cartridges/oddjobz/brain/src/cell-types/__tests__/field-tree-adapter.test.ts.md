---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/cell-types/__tests__/field-tree-adapter.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.531324+00:00
---

# cartridges/oddjobz/brain/src/cell-types/__tests__/field-tree-adapter.test.ts

```ts
/**
 * Field-tree adapter — first L8 consumer (oddjobz cell types).
 *
 * Exercises the worked-example flow on real oddjobz cell types:
 *   - invoice: structured payload with ~14 fields, the canonical L8
 *     candidate (auditor wants `amount` + `dueAt`, NOT customerId/summary)
 *   - quote, customer: secondary smoke tests
 *
 * Verifies:
 *   - Building a field tree from a real invoice value
 *   - schemaFingerprint === cellType.typeHash
 *   - Per-field disclosure round-trips
 *   - Selective disclosure: proof for one field doesn't carry the others
 *   - Same value via different cell types → different roots (binding works)
 *   - Cross-type proof rejection (proof from invoice doesn't verify
 *     against a quote root with same nominal fields)
 *
 * Reference: docs/canon/cw-lift-matrix.yml L8 (per-field intra-tx
 * Merkle); docs/prd/CW-LIFT-ROADMAP.md §2.
 */

import { describe, expect, test } from 'bun:test';
import { invoiceCellType, type OddjobzInvoice } from '../invoice.js';
import { quoteCellType, type OddjobzQuote } from '../quote.js';
import { customerCellType, type OddjobzCustomer } from '../customer.js';
import {
  buildCellFieldTree,
  computeCellFieldCommitments,
  discloseCellField,
  verifyCellFieldDisclosure,
} from '../field-tree-adapter.js';

function hex(b: Uint8Array): string {
  return Buffer.from(b).toString('hex');
}

function sampleInvoice(): OddjobzInvoice {
  return {
    invoiceId: '11111111-1111-4111-8111-111111111111',
    jobId: '22222222-2222-4222-8222-222222222222',
    customerId: '33333333-3333-4333-8333-333333333333',
    status: 'sent',
    externalInvoiceId: 'XERO-INV-7142',
    currency: 'GBP',
    amount: 150000, // £1,500.00 in cents
    sentAt: '2026-06-01T10:00:00.000Z',
    dueAt: '2026-06-15T23:59:59.000Z',
    summary: 'Bathroom retile + grout reseal, 14 m² · labour + materials',
    createdAt: '2026-06-01T09:30:00.000Z',
    updatedAt: '2026-06-01T10:00:00.000Z',
  };
}

describe('oddjobz × L8: invoice field-tree adoption', () => {
  test('buildCellFieldTree produces a 32B root with the invoice typeHash as fingerprint', () => {
    const inv = sampleInvoice();
    const tree = buildCellFieldTree(invoiceCellType, inv);

    expect(tree.root.byteLength).toBe(32);
    expect(hex(tree.schemaFingerprint)).toBe(hex(invoiceCellType.typeHash));
    // Top-level field count (createdAt, updatedAt, status, etc.; all
    // present fields from sampleInvoice — undefined fields are dropped
    // by toCanonical, so the count varies by value).
    expect(tree.leafCount).toBeGreaterThan(0);
    expect(tree.fields.map(f => f.label)).toContain('amount');
    expect(tree.fields.map(f => f.label)).toContain('customerId');
    expect(tree.fields.map(f => f.label)).toContain('summary');
  });

  test('field labels are canonically sorted (lex ascending)', () => {
    const tree = buildCellFieldTree(invoiceCellType, sampleInvoice());
    const labels = tree.fields.map(f => f.label);
    const sorted = [...labels].sort();
    expect(labels).toEqual(sorted);
  });

  test('disclose `amount` + verify against root — round-trip green', () => {
    const inv = sampleInvoice();
    const tree = buildCellFieldTree(invoiceCellType, inv);
    const proof = discloseCellField(invoiceCellType, inv, 'amount');
    expect(verifyCellFieldDisclosure(invoiceCellType, proof, tree.root)).toBe(true);
    // The disclosed value bytes contain the invoice amount in canonical-JSON
    expect(new TextDecoder().decode(proof.value)).toBe('150000');
  });

  test('every field in the canonical projection can be individually disclosed', () => {
    const inv = sampleInvoice();
    const tree = buildCellFieldTree(invoiceCellType, inv);
    for (const f of tree.fields) {
      const proof = discloseCellField(invoiceCellType, inv, f.label);
      expect(verifyCellFieldDisclosure(invoiceCellType, proof, tree.root)).toBe(true);
    }
  });

  test('selective disclosure — proof for one field does NOT carry the others', () => {
    // Auditor scenario: disclose amount + dueAt to the auditor, NOT
    // customerId or summary. Verify the proofs they receive don't
    // expose the omitted fields as plaintext.
    const inv = sampleInvoice();
    const tree = buildCellFieldTree(invoiceCellType, inv);
    const proofAmount = discloseCellField(invoiceCellType, inv, 'amount');
    const proofDueAt = discloseCellField(invoiceCellType, inv, 'dueAt');

    // Both verify against the root
    expect(verifyCellFieldDisclosure(invoiceCellType, proofAmount, tree.root)).toBe(true);
    expect(verifyCellFieldDisclosure(invoiceCellType, proofDueAt, tree.root)).toBe(true);

    // The customerId UUID + summary text appear in the original value;
    // they MUST NOT appear in the disclosed proof bodies (only sibling
    // hashes of the undisclosed leaves are carried).
    const serialise = (p: unknown) =>
      JSON.stringify(p, (_k, v) => (v instanceof Uint8Array ? hex(v) : v));
    const proofAmountSerialised = serialise(proofAmount);
    const proofDueAtSerialised = serialise(proofDueAt);

    expect(proofAmountSerialised).not.toContain(inv.customerId!);
    expect(proofAmountSerialised).not.toContain('Bathroom retile');
    expect(proofDueAtSerialised).not.toContain(inv.customerId!);
    expect(proofDueAtSerialised).not.toContain('Bathroom retile');
  });

  test('fail-closed: tampered proof.value rejected', () => {
    const inv = sampleInvoice();
    const tree = buildCellFieldTree(invoiceCellType, inv);
    const proof = discloseCellField(invoiceCellType, inv, 'amount');
    const tampered = { ...proof, value: new TextEncoder().encode('999999') };
    expect(verifyCellFieldDisclosure(invoiceCellType, tampered, tree.root)).toBe(false);
  });

  test('fail-closed: proof with foreign schemaFingerprint rejected', () => {
    const inv = sampleInvoice();
    const tree = buildCellFieldTree(invoiceCellType, inv);
    const proof = discloseCellField(invoiceCellType, inv, 'amount');
    // Swap the schemaFingerprint to the quote cell's typeHash
    const tampered = { ...proof, schemaFingerprint: quoteCellType.typeHash };
    expect(verifyCellFieldDisclosure(invoiceCellType, tampered, tree.root)).toBe(false);
  });

  test('fail-closed: invoice proof rejected against a different cellType', () => {
    // The verifier helper has a defensive check: if you call
    // verifyCellFieldDisclosure with a cellType whose typeHash differs
    // from the proof's fingerprint, it rejects without invoking the
    // underlying merkle walk. Stronger surface than the bare
    // verifyFieldDisclosure (which would also reject, but via leaf
    // mismatch).
    const inv = sampleInvoice();
    const tree = buildCellFieldTree(invoiceCellType, inv);
    const proof = discloseCellField(invoiceCellType, inv, 'amount');
    expect(verifyCellFieldDisclosure(quoteCellType, proof, tree.root)).toBe(false);
  });

  test('computeCellFieldCommitments returns per-leaf commitments matching the tree', () => {
    const inv = sampleInvoice();
    const tree = buildCellFieldTree(invoiceCellType, inv);
    const commits = computeCellFieldCommitments(invoiceCellType, inv);
    expect(commits.length).toBe(tree.fields.length);
    for (let i = 0; i < commits.length; i++) {
      expect(commits[i].label).toBe(tree.fields[i].label);
      expect(hex(commits[i].commitment)).toBe(hex(tree.fields[i].commitment));
    }
  });

  test('determinism — same invoice → same root across two invocations', () => {
    const inv = sampleInvoice();
    const a = buildCellFieldTree(invoiceCellType, inv);
    const b = buildCellFieldTree(invoiceCellType, inv);
    expect(hex(a.root)).toBe(hex(b.root));
  });

  test('different invoice values → different roots', () => {
    const inv1 = sampleInvoice();
    const inv2 = { ...sampleInvoice(), amount: 200000 };
    expect(hex(buildCellFieldTree(invoiceCellType, inv1).root)).not.toBe(
      hex(buildCellFieldTree(invoiceCellType, inv2).root),
    );
  });
});

describe('oddjobz × L8: cross-cell-type binding', () => {
  function sampleQuote(): OddjobzQuote {
    return {
      quoteId: '44444444-4444-4444-8444-444444444444',
      jobId: '22222222-2222-4222-8222-222222222222',
      status: 'presented',
      costMin: 140000,
      costMax: 150000,
      createdAt: '2026-06-01T09:30:00.000Z',
      updatedAt: '2026-06-01T09:30:00.000Z',
    };
  }

  test('different cell types → different roots even with structurally identical payloads', () => {
    // An invoice and a quote could share the amount + customerId values
    // by coincidence. The typeHash binding means their field-tree roots
    // are still distinct, so a verifier can't be fooled by replaying a
    // quote-tree proof against an invoice context.
    const inv = sampleInvoice();
    const qte = sampleQuote();
    const invTree = buildCellFieldTree(invoiceCellType, inv);
    const qteTree = buildCellFieldTree(quoteCellType, qte);
    expect(hex(invTree.root)).not.toBe(hex(qteTree.root));
    expect(hex(invTree.schemaFingerprint)).not.toBe(hex(qteTree.schemaFingerprint));
  });
});

describe('oddjobz × L8: customer cell (PII selective disclosure)', () => {
  test('build + disclose a customer field without leaking other fields', () => {
    // Customer cells carry PII (email, phone, name). The typical use case
    // is disclosing just the name to a third-party verifier without
    // exposing email/phone.
    const cust: OddjobzCustomer = {
      customerId: '55555555-5555-4555-8555-555555555555',
      name: 'Hannah Burke',
      email: 'hannah@example.invalid',
      phone: '+61400000000',
      createdAt: '2026-06-01T08:00:00.000Z',
      updatedAt: '2026-06-01T08:00:00.000Z',
    };
    const tree = buildCellFieldTree(customerCellType, cust);
    const proof = discloseCellField(customerCellType, cust, 'name');
    expect(verifyCellFieldDisclosure(customerCellType, proof, tree.root)).toBe(true);

    // Disclosed value IS present in proof.value (canonical-JSON bytes of "Hannah Burke")
    const disclosedJson = JSON.parse(new TextDecoder().decode(proof.value));
    expect(disclosedJson).toBe('Hannah Burke');

    // email + phone NOT in the proof body — they're only sibling hashes,
    // never plaintext or hex-encoded UTF-8. Check both the literal and
    // the hex-encoded forms of the undisclosed PII.
    const proofSerialised = JSON.stringify(proof, (_k, v) =>
      v instanceof Uint8Array ? hex(v) : v,
    );
    const emailHex = Buffer.from('hannah@example.invalid').toString('hex');
    const phoneHex = Buffer.from('+61400000000').toString('hex');
    expect(proofSerialised).not.toContain('hannah@example.invalid');
    expect(proofSerialised).not.toContain('+61400000000');
    expect(proofSerialised).not.toContain(emailHex);
    expect(proofSerialised).not.toContain(phoneHex);
  });
});

```
