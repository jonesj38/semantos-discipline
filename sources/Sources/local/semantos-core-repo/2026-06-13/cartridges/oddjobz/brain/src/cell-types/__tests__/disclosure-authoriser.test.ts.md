---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/cell-types/__tests__/disclosure-authoriser.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.530996+00:00
---

# cartridges/oddjobz/brain/src/cell-types/__tests__/disclosure-authoriser.test.ts

```ts
/**
 * Oddjobz × L9 audit-flow tests — end-to-end producer→auditor disclosure.
 *
 * Reference: docs/canon/cw-lift-matrix.yml L8 + L9.
 *
 * Demonstrates the full real-world flow: operator (invoice owner)
 * authorises an auditor for ONE field of an invoice; auditor receives
 * envelope + L8 proof + tree root; verifyAuthorisedFieldDisclosure
 * composes both checks in ONE call.
 *
 * Covers:
 *   - Happy path (auditor sees amount, NOT customerId/summary)
 *   - Wrong verifier rejected
 *   - Expired envelope rejected
 *   - Wrong-field proof under correct envelope rejected (LEAF_COMMITMENT_MISMATCH)
 *   - Tampered field-tree root rejected at field_tree stage
 *   - buildFullAuthorisedDisclosure produces the complete bundle
 */

import { describe, expect, test } from 'bun:test';
import PrivateKey from '@bsv/sdk/primitives/PrivateKey';
import { invoiceCellType, type OddjobzInvoice } from '../invoice.js';
import {
  authoriseFieldDisclosure,
  buildFullAuthorisedDisclosure,
  discloseCellField,
  buildCellFieldTree,
  verifyAuthorisedFieldDisclosure,
} from '../index.js';

const ISSUER_PRIV_HEX =
  'e9873d79c6d87dc0fb6a5778633389f4453213303da61f20bd67fc233aa33262';
const AUDITOR_PRIV_HEX =
  'aa873d79c6d87dc0fb6a5778633389f4453213303da61f20bd67fc233aa33262';

function issuer() {
  return PrivateKey.fromString(ISSUER_PRIV_HEX, 'hex');
}
function auditor() {
  const priv = PrivateKey.fromString(AUDITOR_PRIV_HEX, 'hex');
  return {
    priv,
    pubHex: priv.toPublicKey().toDER('hex') as string,
    pubBytes: Uint8Array.from(priv.toPublicKey().toDER() as number[]),
  };
}

function bytes(n: number, fill = 0): Uint8Array {
  const b = new Uint8Array(n);
  if (fill) b.fill(fill);
  return b;
}

function sampleInvoice(): OddjobzInvoice {
  return {
    invoiceId: '11111111-1111-4111-8111-111111111111',
    jobId: '22222222-2222-4222-8222-222222222222',
    customerId: '33333333-3333-4333-8333-333333333333',
    status: 'sent',
    externalInvoiceId: 'XERO-INV-7142',
    currency: 'GBP',
    amount: 150_000,
    sentAt: '2026-06-01T10:00:00.000Z',
    dueAt: '2026-06-15T23:59:59.000Z',
    summary: 'Bathroom retile + grout reseal — sensitive job context',
    createdAt: '2026-06-01T09:30:00.000Z',
    updatedAt: '2026-06-01T10:00:00.000Z',
  };
}

const FUTURE_EXPIRY = 9_999_999_999_999n;

describe('oddjobz × L9 audit flow — happy path', () => {
  test('operator authorises auditor for invoice.amount; auditor verifies', () => {
    const inv = sampleInvoice();
    const aud = auditor();
    const tree = buildCellFieldTree(invoiceCellType, inv);

    const envelope = authoriseFieldDisclosure(
      {
        cellType: invoiceCellType,
        value: inv,
        noteId: bytes(32, 0xA1),
        fieldLabel: 'amount',
        verifierId: aud.pubBytes,
        engagementId: bytes(32, 0xB1),
        purpose: 'tax-audit-2026-q2',
        expiry: FUTURE_EXPIRY,
        nonce: bytes(16, 0xC1),
      },
      issuer(),
    );

    const proof = discloseCellField(invoiceCellType, inv, 'amount');

    const result = verifyAuthorisedFieldDisclosure({
      cellType: invoiceCellType,
      envelope,
      proof,
      trustedRoot: tree.root,
      verifierPubKeyHex: aud.pubHex,
      nowMs: 0n,
    });
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.envelope.fieldLabel).toBe('amount');
      expect(result.envelope.purpose).toBe('tax-audit-2026-q2');
    }
  });

  test("auditor's proof body does NOT contain customerId / summary", () => {
    const inv = sampleInvoice();
    const aud = auditor();
    const { envelope, proof } = buildFullAuthorisedDisclosure(
      {
        cellType: invoiceCellType,
        value: inv,
        noteId: bytes(32, 0xA1),
        fieldLabel: 'amount',
        verifierId: aud.pubBytes,
        engagementId: bytes(32, 0xB1),
        purpose: 'audit',
        expiry: FUTURE_EXPIRY,
        nonce: bytes(16, 0xC1),
      },
      issuer(),
    );

    const proofBlob = JSON.stringify(proof, (_k, v) =>
      v instanceof Uint8Array
        ? Buffer.from(v).toString('hex')
        : typeof v === 'bigint'
          ? v.toString()
          : v,
    );
    expect(proofBlob).not.toContain(inv.customerId!);
    expect(proofBlob).not.toContain('Bathroom retile');
    expect(proofBlob).not.toContain(Buffer.from('Bathroom retile').toString('hex'));
    // Envelope itself doesn't carry the customerId either (the binding
    // is over the leaf commitment, not the plaintext)
    const envBlob = JSON.stringify(envelope, (_k, v) =>
      v instanceof Uint8Array
        ? Buffer.from(v).toString('hex')
        : typeof v === 'bigint'
          ? v.toString()
          : v,
    );
    expect(envBlob).not.toContain(inv.customerId!);
  });
});

describe('oddjobz × L9 audit flow — fail-closed paths', () => {
  test('wrong verifier → stage envelope, code VERIFIER_MISMATCH', () => {
    const inv = sampleInvoice();
    const aud = auditor();
    const otherPriv = PrivateKey.fromString(
      '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
      'hex',
    );
    const otherPubHex = otherPriv.toPublicKey().toDER('hex') as string;
    const tree = buildCellFieldTree(invoiceCellType, inv);

    const envelope = authoriseFieldDisclosure(
      {
        cellType: invoiceCellType,
        value: inv,
        noteId: bytes(32, 0xA1),
        fieldLabel: 'amount',
        verifierId: aud.pubBytes,
        engagementId: bytes(32, 0xB1),
        purpose: 'audit',
        expiry: FUTURE_EXPIRY,
        nonce: bytes(16, 0xC1),
      },
      issuer(),
    );
    const proof = discloseCellField(invoiceCellType, inv, 'amount');
    const result = verifyAuthorisedFieldDisclosure({
      cellType: invoiceCellType,
      envelope,
      proof,
      trustedRoot: tree.root,
      verifierPubKeyHex: otherPubHex,
      nowMs: 0n,
    });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.stage).toBe('envelope');
      expect(result.code).toBe('VERIFIER_MISMATCH');
    }
  });

  test('expired envelope → stage envelope, code EXPIRED', () => {
    const inv = sampleInvoice();
    const aud = auditor();
    const tree = buildCellFieldTree(invoiceCellType, inv);
    const envelope = authoriseFieldDisclosure(
      {
        cellType: invoiceCellType,
        value: inv,
        noteId: bytes(32, 0xA1),
        fieldLabel: 'amount',
        verifierId: aud.pubBytes,
        engagementId: bytes(32, 0xB1),
        purpose: 'audit',
        expiry: 1_000n,
        nonce: bytes(16, 0xC1),
      },
      issuer(),
    );
    const proof = discloseCellField(invoiceCellType, inv, 'amount');
    const result = verifyAuthorisedFieldDisclosure({
      cellType: invoiceCellType,
      envelope,
      proof,
      trustedRoot: tree.root,
      verifierPubKeyHex: aud.pubHex,
      nowMs: 2_000n,
    });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.stage).toBe('envelope');
      expect(result.code).toBe('EXPIRED');
    }
  });

  test("wrong-field proof under correct envelope → stage leaf_pin, code LEAF_COMMITMENT_MISMATCH", () => {
    const inv = sampleInvoice();
    const aud = auditor();
    const tree = buildCellFieldTree(invoiceCellType, inv);
    // Envelope authorises `amount`
    const envelope = authoriseFieldDisclosure(
      {
        cellType: invoiceCellType,
        value: inv,
        noteId: bytes(32, 0xA1),
        fieldLabel: 'amount',
        verifierId: aud.pubBytes,
        engagementId: bytes(32, 0xB1),
        purpose: 'audit',
        expiry: FUTURE_EXPIRY,
        nonce: bytes(16, 0xC1),
      },
      issuer(),
    );
    // But auditor presents a proof of `summary` (or `customerId`)
    const wrongProof = discloseCellField(invoiceCellType, inv, 'summary');
    const result = verifyAuthorisedFieldDisclosure({
      cellType: invoiceCellType,
      envelope,
      proof: wrongProof,
      trustedRoot: tree.root,
      verifierPubKeyHex: aud.pubHex,
      nowMs: 0n,
    });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.stage).toBe('leaf_pin');
      expect(result.code).toBe('LEAF_COMMITMENT_MISMATCH');
    }
  });

  test('tampered tree root → stage field_tree, code FIELD_TREE_VERIFY_FAILED', () => {
    const inv = sampleInvoice();
    const aud = auditor();
    const envelope = authoriseFieldDisclosure(
      {
        cellType: invoiceCellType,
        value: inv,
        noteId: bytes(32, 0xA1),
        fieldLabel: 'amount',
        verifierId: aud.pubBytes,
        engagementId: bytes(32, 0xB1),
        purpose: 'audit',
        expiry: FUTURE_EXPIRY,
        nonce: bytes(16, 0xC1),
      },
      issuer(),
    );
    const proof = discloseCellField(invoiceCellType, inv, 'amount');
    const result = verifyAuthorisedFieldDisclosure({
      cellType: invoiceCellType,
      envelope,
      proof,
      trustedRoot: bytes(32, 0xFA), // wrong root
      verifierPubKeyHex: aud.pubHex,
      nowMs: 0n,
    });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.stage).toBe('field_tree');
      expect(result.code).toBe('FIELD_TREE_VERIFY_FAILED');
    }
  });
});

describe('oddjobz × L9 — buildFullAuthorisedDisclosure', () => {
  test('returns envelope + proof + tree root', () => {
    const inv = sampleInvoice();
    const aud = auditor();
    const bundle = buildFullAuthorisedDisclosure(
      {
        cellType: invoiceCellType,
        value: inv,
        noteId: bytes(32, 0xA1),
        fieldLabel: 'amount',
        verifierId: aud.pubBytes,
        engagementId: bytes(32, 0xB1),
        purpose: 'audit',
        expiry: FUTURE_EXPIRY,
        nonce: bytes(16, 0xC1),
      },
      issuer(),
    );

    expect(bundle.envelope.envelope.fieldLabel).toBe('amount');
    expect(bundle.proof.label).toBe('amount');
    expect(bundle.treeRoot.byteLength).toBe(32);
    // Auditor verifies the bundle end-to-end
    const result = verifyAuthorisedFieldDisclosure({
      cellType: invoiceCellType,
      envelope: bundle.envelope,
      proof: bundle.proof,
      trustedRoot: bundle.treeRoot,
      verifierPubKeyHex: aud.pubHex,
      nowMs: 0n,
    });
    expect(result.ok).toBe(true);
  });
});

```
