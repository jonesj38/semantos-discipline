---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/test/plexus-envelope.spec.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.666107+00:00
---

# cartridges/wallet-headers/brain/test/plexus-envelope.spec.ts

```ts
// W7 Plexus envelope-builder conformance tests.
//
// Per `WALLET-TIER-CUSTODY.md` §8.2, the wallet must enforce checks 1–5
// before dispatching. Each test below maps to one of those checks plus a
// build → encrypt → ship → decrypt round-trip.

import { beforeEach, describe, expect, test } from 'bun:test';
import * as secp from '@noble/secp256k1';
import { hmac } from '@noble/hashes/hmac';
import { sha256 as nobleSha256 } from '@noble/hashes/sha2';

import {
  buildEnvelope,
  decryptRecoverySeed,
  hashAnswerHex,
  kdfVersionForDomain,
  normalizeAnswer,
  PBKDF2_ITERATIONS,
  type DerivationContext,
  type DerivationStateSnapshot,
} from '../src/plexus/envelope';
import { parseEnvelope, hexToBytes, bytesToHex } from '../src/brc100';

secp.etc.hmacSha256Sync = (key: Uint8Array, ...msgs: Uint8Array[]): Uint8Array =>
  hmac(nobleSha256, key, secp.etc.concatBytes(...msgs));

// ── Fixtures ──────────────────────────────────────────────────────────

const QUESTIONS = ["Mother's maiden name?", 'First pet?', 'City of birth?'];
const ANSWERS = ['Smith', 'Fluffy', 'Sydney'];
const CONTEXTS: DerivationContext[] = [
  {
    tier: 1,
    brc43InvoiceString: '1-tier-key-1',
    domainFlag: '0x10000003',
    recoveryPolicy: 'BACKUP_ON_CREATE',
  },
  {
    tier: 2,
    brc43InvoiceString: '1-tier-key-2',
    domainFlag: '0x10000004',
    recoveryPolicy: 'BACKUP_ON_CREATE',
  },
  {
    tier: 3,
    brc43InvoiceString: '1-tier-key-3',
    domainFlag: '0x10000005',
    recoveryPolicy: 'BACKUP_ON_CONFIRM',
  },
];
const STATE_SNAPSHOT: DerivationStateSnapshot = {
  records: [
    {
      protocolHash: '00112233445566778899aabbccddeeff',
      counterparty: '02' + '11'.repeat(32),
      currentIndex: 7,
      domainFlag: 0x04,
      protocolId: 'BRC-42-edge-creation',
    },
  ],
  snapshotTimestamp: '2026-04-26T00:00:00Z',
};

function freshKeypair(): { sk: Uint8Array; pk: Uint8Array } {
  const sk = secp.utils.randomPrivateKey();
  const pk = secp.getPublicKey(sk, true);
  return { sk, pk };
}

function freshSeed(): Uint8Array {
  const s = new Uint8Array(64);
  crypto.getRandomValues(s);
  return s;
}

function freshCertId(): Uint8Array {
  const c = new Uint8Array(32);
  crypto.getRandomValues(c);
  return c;
}

let kp: { sk: Uint8Array; pk: Uint8Array };
let seed: Uint8Array;
let certId: Uint8Array;

beforeEach(() => {
  kp = freshKeypair();
  seed = freshSeed();
  certId = freshCertId();
});

// ── Tests ─────────────────────────────────────────────────────────────

describe('Plexus dispatch envelope (§8.2)', () => {
  test('happy-path build emits a well-formed envelope', async () => {
    const result = await buildEnvelope({
      identitySk: kp.sk,
      identityPk: kp.pk,
      certId,
      contactEmail: 'alice@example.com',
      questions: QUESTIONS,
      answers: ANSWERS,
      recoverySeed: seed,
      derivationContexts: CONTEXTS,
      derivationStateSnapshot: STATE_SNAPSHOT,
    });
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.envelope.envelopeVersion).toBe(1);
    expect(result.envelope.algorithmVersion).toBe(2);
    expect(result.envelope.identityKey).toBe(bytesToHex(kp.pk));
    expect(result.envelope.challengeBundle.kdfIterations).toBe(PBKDF2_ITERATIONS);
    expect(result.envelope.challengeBundle.questions).toEqual(QUESTIONS);
    expect(result.envelope.challengeBundle.answerHashes.length).toBe(QUESTIONS.length);
    expect(result.envelope.encryptedRecoverySeed.nonce.length).toBe(12 * 2);
    expect(result.envelope.encryptedRecoverySeed.tag.length).toBe(16 * 2);
    expect(result.envelope.derivationContexts).toEqual(CONTEXTS);
    expect(result.envelope.edgeRecipes.length).toBe(1);
    expect(result.envelope.edgeRecipes[0].protocolHash).toBe(
      STATE_SNAPSHOT.records[0].protocolHash,
    );
    expect(result.envelope.edgeRecipes[0].highWaterMark).toBe(7);
    // domainFlag 0x04 (MESSAGING) is bilateral → stays BRC-42 = kdf-v1.
    expect(result.envelope.edgeRecipes[0].kdfVersion).toBe('plexus-kdf-v1');
    expect(result.envelope.derivationStateSnapshot.records.length).toBe(1);
  });

  test('kdfVersionForDomain: bilateral domains → v1, unilateral domains → v2', () => {
    // Bilateral (real counterparty) — BRC-42 unchanged.
    expect(kdfVersionForDomain(0x01)).toBe('plexus-kdf-v1'); // EDGE
    expect(kdfVersionForDomain(0x04)).toBe('plexus-kdf-v1'); // MESSAGING
    // Unilateral (no counterparty) — EP3259724B1 deriveSegment.
    expect(kdfVersionForDomain(0x0b)).toBe('plexus-kdf-v2'); // CHANGE — legacy fallback only
    expect(kdfVersionForDomain(0x00010003)).toBe('plexus-kdf-v2'); // sovereign cell-anchor flag
  });

  test('recovery 2b: a per-record kdfVersion stamp wins over the flag→version map', async () => {
    // L11.5: change keys derive via kdf-v3, stamped on the record at key-creation.
    // The recipe must surface the stamped v3, NOT the flag-map fallback (v2 for 0x0b).
    const result = await buildEnvelope({
      identitySk: kp.sk,
      identityPk: kp.pk,
      certId,
      contactEmail: 'alice@example.com',
      questions: QUESTIONS,
      answers: ANSWERS,
      recoverySeed: seed,
      derivationContexts: CONTEXTS,
      derivationStateSnapshot: {
        records: [
          {
            protocolHash: 'aabbccddeeff00112233445566778899',
            counterparty: 'self',
            currentIndex: 2,
            domainFlag: 0x0b, // CHANGE
            protocolId: 'BRC-42-wallet-change',
            kdfVersion: 'plexus-kdf-v3', // stamped at key-creation (recovery 2b)
          },
          {
            // Un-stamped legacy record → flag→version fallback (bilateral → v1).
            protocolHash: '00112233445566778899aabbccddeeff',
            counterparty: '02' + '11'.repeat(32),
            currentIndex: 0,
            domainFlag: 0x01, // EDGE
            protocolId: 'BRC-42-edge-creation',
          },
        ],
        snapshotTimestamp: '2026-06-06T00:00:00Z',
      },
    });
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const change = result.envelope.edgeRecipes.find((r) => r.domainFlag === 0x0b);
    const edge = result.envelope.edgeRecipes.find((r) => r.domainFlag === 0x01);
    expect(change?.kdfVersion).toBe('plexus-kdf-v3'); // stamp wins
    expect(edge?.kdfVersion).toBe('plexus-kdf-v1'); // fallback for un-stamped
  });

  test('invariant 1: no plaintext private key, mnemonic, seed, or answer in envelope', async () => {
    const result = await buildEnvelope({
      identitySk: kp.sk,
      identityPk: kp.pk,
      certId,
      contactEmail: 'alice@example.com',
      questions: QUESTIONS,
      answers: ANSWERS,
      recoverySeed: seed,
      derivationContexts: CONTEXTS,
      derivationStateSnapshot: STATE_SNAPSHOT,
    });
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const json = JSON.stringify(result.envelope);
    expect(json).not.toContain(bytesToHex(kp.sk));
    expect(json).not.toContain(bytesToHex(seed));
    for (const a of ANSWERS) {
      expect(json).not.toContain(a);
      expect(json).not.toContain(a.toLowerCase());
    }
  });

  test('invariant 2: answerHashes[i] = sha256(salt || normalize(answer_i))', async () => {
    const result = await buildEnvelope({
      identitySk: kp.sk,
      identityPk: kp.pk,
      certId,
      contactEmail: 'alice@example.com',
      questions: QUESTIONS,
      answers: ANSWERS,
      recoverySeed: seed,
      derivationContexts: CONTEXTS,
      derivationStateSnapshot: STATE_SNAPSHOT,
    });
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    for (let i = 0; i < ANSWERS.length; i++) {
      const expected = hashAnswerHex(result.envelope.challengeBundle.salt, ANSWERS[i]!);
      expect(result.envelope.challengeBundle.answerHashes[i]).toBe(expected);
    }
  });

  test('invariant 3: ciphertext decrypts back to seed under the same answers', async () => {
    const result = await buildEnvelope({
      identitySk: kp.sk,
      identityPk: kp.pk,
      certId,
      contactEmail: 'alice@example.com',
      questions: QUESTIONS,
      answers: ANSWERS,
      recoverySeed: seed,
      derivationContexts: CONTEXTS,
      derivationStateSnapshot: STATE_SNAPSHOT,
    });
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const recovered = await decryptRecoverySeed(result.envelope, ANSWERS);
    expect(recovered).not.toBeNull();
    expect(recovered).toEqual(seed);
  });

  test('invariant 3 (negative): wrong answers do not decrypt the seed', async () => {
    const result = await buildEnvelope({
      identitySk: kp.sk,
      identityPk: kp.pk,
      certId,
      contactEmail: 'alice@example.com',
      questions: QUESTIONS,
      answers: ANSWERS,
      recoverySeed: seed,
      derivationContexts: CONTEXTS,
      derivationStateSnapshot: STATE_SNAPSHOT,
    });
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const wrong = await decryptRecoverySeed(result.envelope, ['wrong', 'wrong', 'wrong']);
    expect(wrong).toBeNull();
  });

  test('invariant 4: BRC-100 signature on the envelope verifies under identityKey', async () => {
    const result = await buildEnvelope({
      identitySk: kp.sk,
      identityPk: kp.pk,
      certId,
      contactEmail: 'alice@example.com',
      questions: QUESTIONS,
      answers: ANSWERS,
      recoverySeed: seed,
      derivationContexts: CONTEXTS,
      derivationStateSnapshot: STATE_SNAPSHOT,
    });
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const parsed = parseEnvelope(result.brc100);
    expect(parsed.ok).toBe(true);
    if (parsed.ok) {
      expect(parsed.envelope.identityKey).toEqual(kp.pk);
    }
  });

  test('invariant 4 (input boundary): mismatched sk/pk is rejected', async () => {
    const other = freshKeypair();
    const result = await buildEnvelope({
      identitySk: other.sk,
      identityPk: kp.pk, // mismatched
      certId,
      contactEmail: 'alice@example.com',
      questions: QUESTIONS,
      answers: ANSWERS,
      recoverySeed: seed,
      derivationContexts: CONTEXTS,
      derivationStateSnapshot: STATE_SNAPSHOT,
    });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.kind).toBe('INVARIANT_FAILED');
      if (result.error.kind === 'INVARIANT_FAILED') {
        expect(result.error.check).toBe(4);
      }
    }
  });

  test('invariant 5: certId must be 32 bytes', async () => {
    const shortCert = new Uint8Array(31);
    const result = await buildEnvelope({
      identitySk: kp.sk,
      identityPk: kp.pk,
      certId: shortCert,
      contactEmail: 'alice@example.com',
      questions: QUESTIONS,
      answers: ANSWERS,
      recoverySeed: seed,
      derivationContexts: CONTEXTS,
      derivationStateSnapshot: STATE_SNAPSHOT,
    });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.kind).toBe('INVALID_INPUT');
    }
  });

  test('round-trip: build → ship → decrypt → seed identical', async () => {
    const result = await buildEnvelope({
      identitySk: kp.sk,
      identityPk: kp.pk,
      certId,
      contactEmail: 'alice@example.com',
      questions: QUESTIONS,
      answers: ANSWERS,
      recoverySeed: seed,
      derivationContexts: CONTEXTS,
      derivationStateSnapshot: STATE_SNAPSHOT,
    });
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    // Simulate "shipped" by serialize → deserialize across JSON.
    const wire = JSON.stringify(result.envelope);
    const restored = JSON.parse(wire);
    const recovered = await decryptRecoverySeed(restored, ANSWERS);
    expect(recovered).not.toBeNull();
    expect(recovered).toEqual(seed);
  });

  test('normalizeAnswer is idempotent and case/whitespace insensitive', () => {
    expect(normalizeAnswer('  Smith ')).toBe(normalizeAnswer('smith'));
    expect(normalizeAnswer('Smith   Jones')).toBe('smith jones');
    expect(normalizeAnswer('Café')).toBe(normalizeAnswer('Café'.normalize('NFD')));
  });

  test('rejects empty questions array', async () => {
    const result = await buildEnvelope({
      identitySk: kp.sk,
      identityPk: kp.pk,
      certId,
      contactEmail: 'alice@example.com',
      questions: [],
      answers: [],
      recoverySeed: seed,
      derivationContexts: CONTEXTS,
      derivationStateSnapshot: STATE_SNAPSHOT,
    });
    expect(result.ok).toBe(false);
  });

  test('rejects mismatched question/answer length', async () => {
    const result = await buildEnvelope({
      identitySk: kp.sk,
      identityPk: kp.pk,
      certId,
      contactEmail: 'alice@example.com',
      questions: ['q1', 'q2'],
      answers: ['only-one'],
      recoverySeed: seed,
      derivationContexts: CONTEXTS,
      derivationStateSnapshot: STATE_SNAPSHOT,
    });
    expect(result.ok).toBe(false);
  });

  test('rejects malformed seed length', async () => {
    const tooShort = new Uint8Array(32);
    const result = await buildEnvelope({
      identitySk: kp.sk,
      identityPk: kp.pk,
      certId,
      contactEmail: 'alice@example.com',
      questions: QUESTIONS,
      answers: ANSWERS,
      recoverySeed: tooShort,
      derivationContexts: CONTEXTS,
      derivationStateSnapshot: STATE_SNAPSHOT,
    });
    expect(result.ok).toBe(false);
  });

  test('AAD = identityKey || envelopeVersion (1 byte)', async () => {
    const result = await buildEnvelope({
      identitySk: kp.sk,
      identityPk: kp.pk,
      certId,
      contactEmail: 'alice@example.com',
      questions: QUESTIONS,
      answers: ANSWERS,
      recoverySeed: seed,
      derivationContexts: CONTEXTS,
      derivationStateSnapshot: STATE_SNAPSHOT,
    });
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const aad = hexToBytes(result.envelope.encryptedRecoverySeed.aad);
    expect(aad.length).toBe(34);
    // Compare bytes via index — the Uint8Array<ArrayBufferLike> vs <ArrayBuffer>
    // distinction shipped in lib.dom 5.7+ trips the structural-equality overload.
    for (let i = 0; i < 33; i++) expect(aad[i]).toBe(kp.pk[i]!);
    expect(aad[33]).toBe(1);
  });
});

```
