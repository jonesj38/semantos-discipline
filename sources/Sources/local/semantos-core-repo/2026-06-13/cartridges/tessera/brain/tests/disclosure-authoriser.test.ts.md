---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/tessera/brain/tests/disclosure-authoriser.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.636280+00:00
---

# cartridges/tessera/brain/tests/disclosure-authoriser.test.ts

```ts
/**
 * Tessera × L9 consumer-scan flow tests.
 *
 * Reference: docs/canon/cw-lift-matrix.yml L8 + L9.
 *
 * Realistic care-chain scenario: a wine producer mints a bottle cell;
 * a consumer scans the QR; the producer's backend issues a
 * SignedDisclosureEnvelope authorising the consumer to see
 * `origin`, `vintage`, `certifications` — NOT `costBasisCents`,
 * `internalSku`, `distributorMarginPct`. The consumer app verifies
 * envelope + L8 field-tree proof end-to-end.
 *
 * The test seam uses a minimal mock DisclosureSigner (not a real
 * @bsv/sdk signer) because tessera tests must respect the
 * adapter-consumption gate. Real production uses a brain-side signer
 * backed by an issuer's @bsv/sdk PrivateKey.
 */

import { describe, expect, test } from 'bun:test';
import PrivateKey from '@bsv/sdk/primitives/PrivateKey';
import { sha256 } from '@bsv/sdk/primitives/Hash';
import {
  authoriseTesseraDisclosure,
  buildFullAuthorisedTesseraDisclosure,
  buildTesseraFieldTree,
  discloseTesseraField,
  verifyAuthorisedTesseraDisclosure,
  type DisclosureSigner,
} from '../src/index.js';

// ── Test seam: a @bsv/sdk-backed DisclosureSigner ────────────────
//
// In production, this signer would be wired at the brain boundary
// (the brain holds the issuer's private key; tessera only sees the
// callback). For tests we build one inline.

function makeSigner(issuerPriv: PrivateKey): DisclosureSigner {
  const pubHex = issuerPriv.toPublicKey().toDER('hex') as string;
  return async (preimage: Uint8Array) => {
    const digest = sha256(Array.from(preimage)) as number[];
    const sig = issuerPriv.sign(digest);
    return {
      signature: Uint8Array.from(sig.toDER() as number[]),
      issuerPubKeyHex: pubHex,
    };
  };
}

const ISSUER_PRIV_HEX =
  'e9873d79c6d87dc0fb6a5778633389f4453213303da61f20bd67fc233aa33262';
const SCANNER_PRIV_HEX =
  'aa873d79c6d87dc0fb6a5778633389f4453213303da61f20bd67fc233aa33262';

function bytes(n: number, fill = 0): Uint8Array {
  const b = new Uint8Array(n);
  if (fill) b.fill(fill);
  return b;
}

function scannerKeys() {
  const priv = PrivateKey.fromString(SCANNER_PRIV_HEX, 'hex');
  return {
    pubHex: priv.toPublicKey().toDER('hex') as string,
    pubBytes: Uint8Array.from(priv.toPublicKey().toDER() as number[]),
  };
}

function sampleBottle() {
  return {
    bottleId: 'btl-11111111-1111-4111-8111-111111111111',
    lotId: 'lot-bla-2024-shiraz-bin-29',
    batchId: 'btl-batch-2024-09-A',
    origin: 'Barossa Valley, SA, AU',
    vintage: 2024,
    varietal: 'Shiraz',
    certifications: ['BWS-organic', 'GI-Barossa'],
    // sensitive:
    costBasisCents: 850,
    internalSku: 'PROD-SHZ-29-2024',
    distributorMarginPct: 18,
  };
}

const FUTURE_EXPIRY = 9_999_999_999_999n;

describe('tessera × L9 — consumer-scan happy path', () => {
  test("producer authorises consumer for bottle.origin; consumer verifies", async () => {
    const issuerPriv = PrivateKey.fromString(ISSUER_PRIV_HEX, 'hex');
    const scanner = scannerKeys();
    const body = sampleBottle();
    const tree = buildTesseraFieldTree('tessera.bottle', body);

    const envelope = await authoriseTesseraDisclosure(
      {
        cellType: 'tessera.bottle',
        body,
        noteId: bytes(32, 0xA1),
        fieldLabel: 'origin',
        verifierId: scanner.pubBytes,
        engagementId: bytes(32, 0xB1),
        purpose: 'consumer-scan',
        expiry: FUTURE_EXPIRY,
        nonce: bytes(16, 0xC1),
      },
      makeSigner(issuerPriv),
    );

    const proof = discloseTesseraField('tessera.bottle', body, 'origin');

    const result = verifyAuthorisedTesseraDisclosure({
      cellType: 'tessera.bottle',
      envelope,
      proof,
      trustedRoot: tree.root,
      verifierPubKeyHex: scanner.pubHex,
      nowMs: 0n,
    });
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.envelope.fieldLabel).toBe('origin');
      expect(result.envelope.purpose).toBe('consumer-scan');
    }
  });

  test('consumer can verify origin + vintage + certs separately, NOT margin/sku', async () => {
    const issuerPriv = PrivateKey.fromString(ISSUER_PRIV_HEX, 'hex');
    const scanner = scannerKeys();
    const body = sampleBottle();
    const tree = buildTesseraFieldTree('tessera.bottle', body);
    const signer = makeSigner(issuerPriv);

    // Producer issues three envelopes — one per disclosed field
    for (const fieldLabel of ['origin', 'vintage', 'certifications']) {
      const envelope = await authoriseTesseraDisclosure(
        {
          cellType: 'tessera.bottle',
          body,
          noteId: bytes(32, 0xA1),
          fieldLabel,
          verifierId: scanner.pubBytes,
          engagementId: bytes(32, 0xB1),
          purpose: 'consumer-scan',
          expiry: FUTURE_EXPIRY,
          nonce: bytes(16, 0xC1),
        },
        signer,
      );
      const proof = discloseTesseraField('tessera.bottle', body, fieldLabel);
      const result = verifyAuthorisedTesseraDisclosure({
        cellType: 'tessera.bottle',
        envelope,
        proof,
        trustedRoot: tree.root,
        verifierPubKeyHex: scanner.pubHex,
        nowMs: 0n,
      });
      expect(result.ok).toBe(true);
    }

    // Producer does NOT issue envelopes for cost/sku/margin — the
    // consumer has no envelope authorising them for those fields.
    // Even if the consumer somehow got a proof of `costBasisCents`,
    // they have no envelope to authorise it. That's the L9 contract:
    // no envelope, no verification.
  });

  test("consumer-app cannot use a vintage proof under an origin envelope (LEAF_COMMITMENT_MISMATCH)", async () => {
    const issuerPriv = PrivateKey.fromString(ISSUER_PRIV_HEX, 'hex');
    const scanner = scannerKeys();
    const body = sampleBottle();
    const tree = buildTesseraFieldTree('tessera.bottle', body);

    // Envelope authorises `origin`
    const envelope = await authoriseTesseraDisclosure(
      {
        cellType: 'tessera.bottle',
        body,
        noteId: bytes(32, 0xA1),
        fieldLabel: 'origin',
        verifierId: scanner.pubBytes,
        engagementId: bytes(32, 0xB1),
        purpose: 'consumer-scan',
        expiry: FUTURE_EXPIRY,
        nonce: bytes(16, 0xC1),
      },
      makeSigner(issuerPriv),
    );

    // Consumer-app tries to present a `vintage` proof under the
    // `origin` envelope. The leaf-commitment pin rejects this.
    const wrongProof = discloseTesseraField('tessera.bottle', body, 'vintage');
    const result = verifyAuthorisedTesseraDisclosure({
      cellType: 'tessera.bottle',
      envelope,
      proof: wrongProof,
      trustedRoot: tree.root,
      verifierPubKeyHex: scanner.pubHex,
      nowMs: 0n,
    });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.stage).toBe('leaf_pin');
      expect(result.code).toBe('LEAF_COMMITMENT_MISMATCH');
    }
  });
});

describe('tessera × L9 — fail-closed paths', () => {
  test('wrong scanner pubkey → stage envelope, code VERIFIER_MISMATCH', async () => {
    const issuerPriv = PrivateKey.fromString(ISSUER_PRIV_HEX, 'hex');
    const scanner = scannerKeys();
    const otherPub = PrivateKey.fromString(
      '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
      'hex',
    ).toPublicKey().toDER('hex') as string;
    const body = sampleBottle();
    const tree = buildTesseraFieldTree('tessera.bottle', body);
    const envelope = await authoriseTesseraDisclosure(
      {
        cellType: 'tessera.bottle',
        body,
        noteId: bytes(32, 0xA1),
        fieldLabel: 'origin',
        verifierId: scanner.pubBytes,
        engagementId: bytes(32, 0xB1),
        purpose: 'consumer-scan',
        expiry: FUTURE_EXPIRY,
        nonce: bytes(16, 0xC1),
      },
      makeSigner(issuerPriv),
    );
    const proof = discloseTesseraField('tessera.bottle', body, 'origin');
    const result = verifyAuthorisedTesseraDisclosure({
      cellType: 'tessera.bottle',
      envelope,
      proof,
      trustedRoot: tree.root,
      verifierPubKeyHex: otherPub,
      nowMs: 0n,
    });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.stage).toBe('envelope');
      expect(result.code).toBe('VERIFIER_MISMATCH');
    }
  });

  test('expired QR envelope → stage envelope, code EXPIRED', async () => {
    const issuerPriv = PrivateKey.fromString(ISSUER_PRIV_HEX, 'hex');
    const scanner = scannerKeys();
    const body = sampleBottle();
    const tree = buildTesseraFieldTree('tessera.bottle', body);
    const envelope = await authoriseTesseraDisclosure(
      {
        cellType: 'tessera.bottle',
        body,
        noteId: bytes(32, 0xA1),
        fieldLabel: 'origin',
        verifierId: scanner.pubBytes,
        engagementId: bytes(32, 0xB1),
        purpose: 'consumer-scan',
        expiry: 1_000n, // short expiry — modelling a one-shot scan envelope
        nonce: bytes(16, 0xC1),
      },
      makeSigner(issuerPriv),
    );
    const proof = discloseTesseraField('tessera.bottle', body, 'origin');
    const result = verifyAuthorisedTesseraDisclosure({
      cellType: 'tessera.bottle',
      envelope,
      proof,
      trustedRoot: tree.root,
      verifierPubKeyHex: scanner.pubHex,
      nowMs: 2_000n,
    });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.stage).toBe('envelope');
      expect(result.code).toBe('EXPIRED');
    }
  });
});

describe('tessera × L9 — buildFullAuthorisedTesseraDisclosure', () => {
  test('returns envelope + proof + tree root for QR-scan packet', async () => {
    const issuerPriv = PrivateKey.fromString(ISSUER_PRIV_HEX, 'hex');
    const scanner = scannerKeys();
    const body = sampleBottle();
    const bundle = await buildFullAuthorisedTesseraDisclosure(
      {
        cellType: 'tessera.bottle',
        body,
        noteId: bytes(32, 0xA1),
        fieldLabel: 'origin',
        verifierId: scanner.pubBytes,
        engagementId: bytes(32, 0xB1),
        purpose: 'consumer-scan',
        expiry: FUTURE_EXPIRY,
        nonce: bytes(16, 0xC1),
      },
      makeSigner(issuerPriv),
    );
    expect(bundle.envelope.envelope.fieldLabel).toBe('origin');
    expect(bundle.proof.label).toBe('origin');
    expect(bundle.treeRoot.byteLength).toBe(32);

    const result = verifyAuthorisedTesseraDisclosure({
      cellType: 'tessera.bottle',
      envelope: bundle.envelope,
      proof: bundle.proof,
      trustedRoot: bundle.treeRoot,
      verifierPubKeyHex: scanner.pubHex,
      nowMs: 0n,
    });
    expect(result.ok).toBe(true);
  });
});

```
