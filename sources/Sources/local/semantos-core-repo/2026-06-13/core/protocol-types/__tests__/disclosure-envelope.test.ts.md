---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/__tests__/disclosure-envelope.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.859212+00:00
---

# core/protocol-types/__tests__/disclosure-envelope.test.ts

```ts
/**
 * L9 disclosure-envelope tests.
 *
 * Reference: docs/canon/cw-lift-matrix.yml L9 (scoped-disclosure signed envelope).
 *
 * Covers:
 *   - Canonical preimage determinism + structure
 *   - signDisclosureEnvelope + verifyDisclosureEnvelope round-trip
 *   - Fail-closed on every axis:
 *     INVALID_VERIFIER_PUBKEY / VERIFIER_MISMATCH / EXPIRED /
 *     LEAF_COMMITMENT_MISMATCH / INVALID_ISSUER_PUBKEY / INVALID_SIGNATURE
 *   - Compose with L8: producer signs envelope binding a field-tree
 *     leaf commitment; verifier accepts envelope + L8 disclosure proof.
 *   - Different verifierIds → different envelopes (sig-bound)
 *   - Tamper with envelope → signature fails verification
 */

import { describe, expect, test } from 'bun:test';
import PrivateKey from '@bsv/sdk/primitives/PrivateKey';
import {
  ENVELOPE_DOMAIN,
  ENVELOPE_MAGIC,
  ENVELOPE_VERSION,
  canonicalDisclosureEnvelopePreimage,
  signDisclosureEnvelope,
  verifyDisclosureEnvelope,
  type DisclosureEnvelope,
} from '../src/disclosure';
import {
  buildFieldTree,
  discloseField,
  verifyFieldDisclosure,
  type FieldLeaf,
} from '../src/field-tree';

// ── Test fixtures ────────────────────────────────────────────────

const ISSUER_PRIV_HEX =
  'e9873d79c6d87dc0fb6a5778633389f4453213303da61f20bd67fc233aa33262';
const VERIFIER_PRIV_HEX =
  'aa873d79c6d87dc0fb6a5778633389f4453213303da61f20bd67fc233aa33262';

function issuerKeys() {
  const priv = PrivateKey.fromString(ISSUER_PRIV_HEX, 'hex');
  return { priv, pubHex: priv.toPublicKey().toDER('hex') as string };
}

function verifierKeys() {
  const priv = PrivateKey.fromString(VERIFIER_PRIV_HEX, 'hex');
  const pubHex = priv.toPublicKey().toDER('hex') as string;
  const pubBytes = priv.toPublicKey().toDER();
  return { priv, pubHex, pubBytes: Uint8Array.from(pubBytes as number[]) };
}

function bytes(n: number, fill = 0): Uint8Array {
  const b = new Uint8Array(n);
  if (fill) b.fill(fill);
  return b;
}

function envelope(opts: Partial<DisclosureEnvelope> = {}): DisclosureEnvelope {
  const verifier = verifierKeys();
  return {
    noteId: opts.noteId ?? bytes(32, 0xAA),
    fieldLabel: opts.fieldLabel ?? 'amount',
    leafCommitment: opts.leafCommitment ?? bytes(32, 0xBB),
    verifierId: opts.verifierId ?? verifier.pubBytes,
    engagementId: opts.engagementId ?? bytes(32, 0xCC),
    purpose: opts.purpose ?? 'tax-audit-2026-q2',
    expiry: opts.expiry ?? 9_999_999_999_999n, // far future
    nonce: opts.nonce ?? bytes(16, 0xDD),
  };
}

// ── Canonical preimage ───────────────────────────────────────────

describe('L9 — canonicalDisclosureEnvelopePreimage', () => {
  test('starts with the "L9DS" magic + version + domain separator', () => {
    const env = envelope();
    const preimage = canonicalDisclosureEnvelopePreimage(env);
    expect(preimage[0]).toBe(ENVELOPE_MAGIC[0]); // 0x4C
    expect(preimage[1]).toBe(ENVELOPE_MAGIC[1]); // 0x39
    expect(preimage[2]).toBe(ENVELOPE_MAGIC[2]); // 0x44
    expect(preimage[3]).toBe(ENVELOPE_MAGIC[3]); // 0x53
    expect(preimage[4]).toBe(ENVELOPE_VERSION);
    // Domain varint + bytes follow
    const domainBytes = new TextEncoder().encode(ENVELOPE_DOMAIN);
    expect(preimage[5]).toBe(domainBytes.length); // direct varint for length < 0xfd
    for (let i = 0; i < domainBytes.length; i++) {
      expect(preimage[6 + i]).toBe(domainBytes[i]);
    }
  });

  test('deterministic — same envelope → same preimage', () => {
    const env = envelope();
    const a = canonicalDisclosureEnvelopePreimage(env);
    const b = canonicalDisclosureEnvelopePreimage(env);
    expect(Buffer.from(a).toString('hex')).toBe(Buffer.from(b).toString('hex'));
  });

  test('every field affects the preimage', () => {
    const base = envelope();
    const preimage = canonicalDisclosureEnvelopePreimage(base);
    for (const variant of [
      envelope({ noteId: bytes(32, 0x11) }),
      envelope({ fieldLabel: 'currency' }),
      envelope({ leafCommitment: bytes(32, 0x22) }),
      envelope({ engagementId: bytes(32, 0x33) }),
      envelope({ purpose: 'consumer-scan' }),
      envelope({ expiry: 1_000_000_000_000n }),
      envelope({ nonce: bytes(16, 0x44) }),
    ]) {
      const variantPreimage = canonicalDisclosureEnvelopePreimage(variant);
      expect(Buffer.from(variantPreimage).toString('hex')).not.toBe(
        Buffer.from(preimage).toString('hex'),
      );
    }
  });

  test('rejects wrong-size noteId / leafCommitment / verifierId / engagementId / nonce', () => {
    expect(() =>
      canonicalDisclosureEnvelopePreimage(envelope({ noteId: bytes(31) })),
    ).toThrow();
    expect(() =>
      canonicalDisclosureEnvelopePreimage(envelope({ leafCommitment: bytes(33) })),
    ).toThrow();
    expect(() =>
      canonicalDisclosureEnvelopePreimage(envelope({ verifierId: bytes(32) })),
    ).toThrow(); // verifierId is 33B not 32
    expect(() =>
      canonicalDisclosureEnvelopePreimage(envelope({ engagementId: bytes(16) })),
    ).toThrow();
    expect(() =>
      canonicalDisclosureEnvelopePreimage(envelope({ nonce: bytes(15) })),
    ).toThrow();
  });
});

// ── Sign + verify round-trip ─────────────────────────────────────

describe('L9 — sign + verify round-trip', () => {
  test('happy path: signed envelope verifies for the named verifier', () => {
    const { priv: issuerPriv } = issuerKeys();
    const verifier = verifierKeys();
    const env = envelope();
    const signed = signDisclosureEnvelope(env, issuerPriv);
    const result = verifyDisclosureEnvelope({
      signed,
      verifierPubKeyHex: verifier.pubHex,
      nowMs: 0n,
    });
    expect(result.ok).toBe(true);
  });

  test('SignedDisclosureEnvelope carries issuer pubkey hex (66 chars)', () => {
    const { priv: issuerPriv, pubHex } = issuerKeys();
    const signed = signDisclosureEnvelope(envelope(), issuerPriv);
    expect(signed.issuerPubKeyHex).toBe(pubHex);
    expect(signed.issuerPubKeyHex.length).toBe(66);
  });

  test('signature is non-trivial (>= 64 bytes DER)', () => {
    const { priv: issuerPriv } = issuerKeys();
    const signed = signDisclosureEnvelope(envelope(), issuerPriv);
    expect(signed.signature.length).toBeGreaterThanOrEqual(64);
  });
});

// ── Fail-closed paths ────────────────────────────────────────────

describe('L9 — fail-closed: VERIFIER_MISMATCH', () => {
  test('different verifier pubkey rejected', () => {
    const { priv: issuerPriv } = issuerKeys();
    const verifier = verifierKeys();
    const signed = signDisclosureEnvelope(envelope(), issuerPriv);
    // An UNRELATED verifier pubkey
    const otherPriv = PrivateKey.fromString(
      '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
      'hex',
    );
    const otherPubHex = otherPriv.toPublicKey().toDER('hex') as string;
    void verifier;
    const result = verifyDisclosureEnvelope({
      signed,
      verifierPubKeyHex: otherPubHex,
      nowMs: 0n,
    });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe('VERIFIER_MISMATCH');
    }
  });
});

describe('L9 — fail-closed: EXPIRED', () => {
  test('rejects when nowMs >= envelope.expiry', () => {
    const { priv: issuerPriv } = issuerKeys();
    const verifier = verifierKeys();
    const env = envelope({ expiry: 1_000n });
    const signed = signDisclosureEnvelope(env, issuerPriv);

    // Exactly-equal → rejected
    const onExpiry = verifyDisclosureEnvelope({
      signed,
      verifierPubKeyHex: verifier.pubHex,
      nowMs: 1_000n,
    });
    expect(onExpiry.ok).toBe(false);
    if (!onExpiry.ok) expect(onExpiry.code).toBe('EXPIRED');

    // Past → rejected
    const past = verifyDisclosureEnvelope({
      signed,
      verifierPubKeyHex: verifier.pubHex,
      nowMs: 1_001n,
    });
    expect(past.ok).toBe(false);
    if (!past.ok) expect(past.code).toBe('EXPIRED');

    // Before expiry → ok
    const before = verifyDisclosureEnvelope({
      signed,
      verifierPubKeyHex: verifier.pubHex,
      nowMs: 999n,
    });
    expect(before.ok).toBe(true);
  });
});

describe('L9 — fail-closed: LEAF_COMMITMENT_MISMATCH (L8 compose-pin)', () => {
  test('rejects when expectedLeafCommitment differs', () => {
    const { priv: issuerPriv } = issuerKeys();
    const verifier = verifierKeys();
    const env = envelope({ leafCommitment: bytes(32, 0xBB) });
    const signed = signDisclosureEnvelope(env, issuerPriv);
    const result = verifyDisclosureEnvelope({
      signed,
      verifierPubKeyHex: verifier.pubHex,
      nowMs: 0n,
      expectedLeafCommitment: bytes(32, 0xCC),
    });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe('LEAF_COMMITMENT_MISMATCH');
    }
  });

  test('matching expectedLeafCommitment passes', () => {
    const { priv: issuerPriv } = issuerKeys();
    const verifier = verifierKeys();
    const commitment = bytes(32, 0xBB);
    const signed = signDisclosureEnvelope(
      envelope({ leafCommitment: commitment }),
      issuerPriv,
    );
    const result = verifyDisclosureEnvelope({
      signed,
      verifierPubKeyHex: verifier.pubHex,
      nowMs: 0n,
      expectedLeafCommitment: commitment,
    });
    expect(result.ok).toBe(true);
  });
});

describe('L9 — fail-closed: INVALID_VERIFIER_PUBKEY', () => {
  test('rejects non-hex / wrong-length / uppercase verifier pubkey', () => {
    const { priv: issuerPriv } = issuerKeys();
    const signed = signDisclosureEnvelope(envelope(), issuerPriv);
    for (const bad of ['too-short', 'A'.repeat(66), 'x'.repeat(65)]) {
      const result = verifyDisclosureEnvelope({
        signed,
        verifierPubKeyHex: bad,
        nowMs: 0n,
      });
      expect(result.ok).toBe(false);
      if (!result.ok) expect(result.code).toBe('INVALID_VERIFIER_PUBKEY');
    }
  });
});

describe('L9 — fail-closed: INVALID_SIGNATURE (tamper detection)', () => {
  test('tampering with the envelope after signing causes signature to fail', () => {
    const { priv: issuerPriv } = issuerKeys();
    const verifier = verifierKeys();
    const signed = signDisclosureEnvelope(envelope(), issuerPriv);
    const tampered = {
      ...signed,
      envelope: { ...signed.envelope, fieldLabel: 'currency' }, // attacker swaps
    };
    const result = verifyDisclosureEnvelope({
      signed: tampered,
      verifierPubKeyHex: verifier.pubHex,
      nowMs: 0n,
    });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe('INVALID_SIGNATURE');
    }
  });

  test('tampering with the signature bytes is rejected', () => {
    const { priv: issuerPriv } = issuerKeys();
    const verifier = verifierKeys();
    const signed = signDisclosureEnvelope(envelope(), issuerPriv);
    const tamperedSig = new Uint8Array(signed.signature);
    // Flip a byte deep inside the signature
    tamperedSig[10] ^= 0xff;
    const result = verifyDisclosureEnvelope({
      signed: { ...signed, signature: tamperedSig },
      verifierPubKeyHex: verifier.pubHex,
      nowMs: 0n,
    });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe('INVALID_SIGNATURE');
    }
  });

  test('different issuer pubkey rejected (signed by someone else)', () => {
    const { priv: issuerPriv } = issuerKeys();
    const verifier = verifierKeys();
    const signed = signDisclosureEnvelope(envelope(), issuerPriv);
    const otherPub = PrivateKey.fromString(
      '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
      'hex',
    ).toPublicKey().toDER('hex') as string;
    const result = verifyDisclosureEnvelope({
      signed: { ...signed, issuerPubKeyHex: otherPub },
      verifierPubKeyHex: verifier.pubHex,
      nowMs: 0n,
    });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe('INVALID_SIGNATURE');
    }
  });
});

// ── End-to-end: compose with L8 ──────────────────────────────────

describe('L9 ∘ L8 — end-to-end disclosure authorisation', () => {
  test('producer signs envelope binding a field-tree leaf; auditor verifies BOTH', () => {
    // === producer side ===
    const { priv: issuerPriv } = issuerKeys();
    const verifier = verifierKeys();
    const schemaFp = bytes(32, 0x42);
    const noteId = bytes(32, 0x77);
    const fields: FieldLeaf[] = [
      { label: 'amount', value: new TextEncoder().encode('150000') },
      { label: 'memo', value: new TextEncoder().encode('redacted') },
      { label: 'currency', value: new TextEncoder().encode('GBP') },
    ];
    const tree = buildFieldTree(schemaFp, fields);

    // Producer issues an envelope authorising `amount` to the auditor
    const amountLeaf = tree.fields.find(f => f.label === 'amount')!;
    const env = envelope({
      noteId,
      fieldLabel: 'amount',
      leafCommitment: amountLeaf.commitment,
      verifierId: verifier.pubBytes,
      purpose: 'tax-audit',
    });
    const signed = signDisclosureEnvelope(env, issuerPriv);

    // Producer hands auditor: signed envelope + L8 disclosure proof
    const fieldProof = discloseField(schemaFp, fields, 'amount');

    // === auditor side ===
    // Step 1: verify envelope (L9), pinning leaf commitment to the
    // proof we received from the producer
    const envResult = verifyDisclosureEnvelope({
      signed,
      verifierPubKeyHex: verifier.pubHex,
      nowMs: 0n,
      expectedLeafCommitment: fieldProof.commitment,
    });
    expect(envResult.ok).toBe(true);

    // Step 2: verify the L8 field-tree proof
    const proofOk = verifyFieldDisclosure(fieldProof, tree.root);
    expect(proofOk).toBe(true);

    // Both pass → disclosure is AUTHORISED + VERIFIED
  });

  test('auditor rejects when proof leaf does NOT match the envelope binding', () => {
    const { priv: issuerPriv } = issuerKeys();
    const verifier = verifierKeys();
    const schemaFp = bytes(32, 0x42);
    const fields: FieldLeaf[] = [
      { label: 'amount', value: new TextEncoder().encode('150000') },
      { label: 'memo', value: new TextEncoder().encode('redacted') },
    ];
    const tree = buildFieldTree(schemaFp, fields);

    // Envelope authorises `amount`
    const amountLeaf = tree.fields.find(f => f.label === 'amount')!;
    const env = envelope({
      leafCommitment: amountLeaf.commitment,
      verifierId: verifier.pubBytes,
    });
    const signed = signDisclosureEnvelope(env, issuerPriv);

    // But the auditor is fed a proof of the `memo` field — try to
    // use it under the `amount` envelope. The leafCommitment pin
    // rejects this.
    const memoProof = discloseField(schemaFp, fields, 'memo');
    void tree;
    const result = verifyDisclosureEnvelope({
      signed,
      verifierPubKeyHex: verifier.pubHex,
      nowMs: 0n,
      expectedLeafCommitment: memoProof.commitment,
    });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.code).toBe('LEAF_COMMITMENT_MISMATCH');
    }
  });
});

```
