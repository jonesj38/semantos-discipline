---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/test/plexus-dispatch.spec.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.672859+00:00
---

# cartridges/wallet-headers/brain/test/plexus-dispatch.spec.ts

```ts
// W7 Plexus dispatcher tests — drive the full enroll / recover flows
// against the in-process MockPlexusOperator. No real network calls.
//
// Coverage per the W7 acceptance list:
//   • happy-path enrollment (build → POST → OTP → confirm → enrolled)
//   • OTP timeout
//   • wrong OTP code → lockout after 5 attempts
//   • network failure mid-dispatch → cached envelope returned for retry
//   • happy-path recovery (pre-seeded enrollment → seed reconstructed)
//   • wrong-answer recovery → CHALLENGE_FAILED, no seed leaked

import { beforeEach, describe, expect, test } from 'bun:test';
import * as secp from '@noble/secp256k1';
import { hmac } from '@noble/hashes/hmac';
import { sha256 as nobleSha256 } from '@noble/hashes/sha2';

import { buildEnvelope } from '../src/plexus/envelope';
import { enroll, enrollCachedEnvelope, recover } from '../src/plexus/dispatch';
import { MockPlexusOperator } from '../src/plexus/operator';
import type { DerivationContext, DerivationStateSnapshot } from '../src/plexus/envelope';

secp.etc.hmacSha256Sync = (key: Uint8Array, ...msgs: Uint8Array[]): Uint8Array =>
  hmac(nobleSha256, key, secp.etc.concatBytes(...msgs));

// ── Fixtures ──────────────────────────────────────────────────────────

const QUESTIONS = ["Mother's maiden name?", 'First pet?'];
const ANSWERS = ['Smith', 'Fluffy'];
const CONTEXTS: DerivationContext[] = [
  {
    tier: 1,
    brc43InvoiceString: '1-tier-key-1',
    domainFlag: '0x10000003',
    recoveryPolicy: 'BACKUP_ON_CREATE',
  },
];
const STATE_SNAPSHOT: DerivationStateSnapshot = {
  records: [],
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

let operator: MockPlexusOperator;
let kp: { sk: Uint8Array; pk: Uint8Array };
let seed: Uint8Array;
let certId: Uint8Array;

beforeEach(() => {
  operator = new MockPlexusOperator(
    { displayDomain: 'mock.plexus-keys.test' },
    { otpExpiryMs: 10 * 60 * 1000 },
  );
  kp = freshKeypair();
  seed = freshSeed();
  certId = freshCertId();
});

// ── Tests ─────────────────────────────────────────────────────────────

describe('Plexus dispatch — enrollment', () => {
  test('happy-path: dispatch → OTP → confirm → enrolled', async () => {
    const result = await enroll(operator, {
      identitySk: kp.sk,
      identityPk: kp.pk,
      certId,
      contactEmail: 'alice@example.com',
      questions: QUESTIONS,
      answers: ANSWERS.slice(),
      recoverySeed: seed,
      derivationContexts: CONTEXTS,
      derivationStateSnapshot: STATE_SNAPSHOT,
      requestOtp: async () => {
        // The mock pushes the OTP into operator.issuedOtps. The popup UI
        // would normally show a prompt here — in tests we read it back.
        return operator.lastOtpFor('alice@example.com');
      },
    });
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.value.envelope.contactEmail).toBe('alice@example.com');
      expect(result.value.operatorDomain).toBe('mock.plexus-keys.test');
      expect(operator.enrollments.size).toBe(1);
    }
  });

  test('OTP timeout: 10-minute window expires → OTP_EXPIRED', async () => {
    let nowMs = 1_700_000_000_000;
    operator.now = () => nowMs;
    const result = await enroll(operator, {
      identitySk: kp.sk,
      identityPk: kp.pk,
      certId,
      contactEmail: 'alice@example.com',
      questions: QUESTIONS,
      answers: ANSWERS.slice(),
      recoverySeed: seed,
      derivationContexts: CONTEXTS,
      derivationStateSnapshot: STATE_SNAPSHOT,
      requestOtp: async () => {
        // Fast-forward 11 minutes between dispatch and confirm.
        nowMs += 11 * 60 * 1000;
        return operator.lastOtpFor('alice@example.com');
      },
    });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.kind).toBe('OTP_EXPIRED');
    }
    expect(operator.enrollments.size).toBe(0);
  });

  test('wrong OTP: 5 attempts → OTP_LOCKED', async () => {
    // First wrong attempt via the full enroll() path — confirms the
    // dispatcher correctly maps a 401 OTP_WRONG into the typed error.
    const dispatchResult = await enroll(operator, {
      identitySk: kp.sk,
      identityPk: kp.pk,
      certId,
      contactEmail: 'alice@example.com',
      questions: QUESTIONS,
      answers: ANSWERS.slice(),
      recoverySeed: freshSeed(),
      derivationContexts: CONTEXTS,
      derivationStateSnapshot: STATE_SNAPSHOT,
      requestOtp: async () => '000000', // wrong code
    });
    expect(dispatchResult.ok).toBe(false);
    if (!dispatchResult.ok) {
      expect(dispatchResult.error.kind).toBe('OTP_WRONG');
    }

    // Drive 4 more wrong confirms against the same pending enrollment.
    // Each enroll() retry would burn a per-hour dispatch quota slot, so
    // we hit the operator's confirm endpoint directly — same envelope is
    // already pending at this point.
    const ikHex = Array.from(operator.pendingEnrollments.keys())[0]!;
    let lockHit = false;
    for (let i = 0; i < 4; i++) {
      const wire = {
        headers: {
          'x-brc100-identitykey': ikHex,
          'x-brc100-nonce': '00'.repeat(32),
          'x-brc100-timestamp': '0',
          'x-brc100-signature': '00',
        },
        body: JSON.stringify({ identityKey: ikHex, otp: '000000' }),
      };
      const r = await operator.enrollmentConfirm(wire);
      if (r.status === 423) {
        lockHit = true;
        break;
      }
    }
    expect(lockHit).toBe(true);
  });

  test('network failure: NETWORK_FAILURE returned with cachedEnvelope for retry', async () => {
    operator.failNextDispatch = true;
    const result = await enroll(operator, {
      identitySk: kp.sk,
      identityPk: kp.pk,
      certId,
      contactEmail: 'alice@example.com',
      questions: QUESTIONS,
      answers: ANSWERS.slice(),
      recoverySeed: seed,
      derivationContexts: CONTEXTS,
      derivationStateSnapshot: STATE_SNAPSHOT,
      requestOtp: async () => '000000',
    });
    expect(result.ok).toBe(false);
    if (!result.ok && result.error.kind === 'NETWORK_FAILURE') {
      expect(result.error.cachedEnvelope.identityKey).toBeDefined();
      expect(result.error.cachedEnvelope.encryptedRecoverySeed.ciphertext).toBeDefined();
    } else {
      throw new Error(`expected NETWORK_FAILURE, got ${JSON.stringify(result)}`);
    }
  });

  test('cached envelope enrollment mirrors createWallet envelope without seed or answers', async () => {
    const built = await buildEnvelope({
      identitySk: kp.sk,
      identityPk: kp.pk,
      certId,
      contactEmail: 'alice@example.com',
      questions: QUESTIONS,
      answers: ANSWERS.slice(),
      recoverySeed: seed,
      derivationContexts: CONTEXTS,
      derivationStateSnapshot: STATE_SNAPSHOT,
    });
    expect(built.ok).toBe(true);
    if (!built.ok) return;

    seed.fill(0);
    const result = await enrollCachedEnvelope(operator, {
      identitySk: kp.sk,
      identityPk: kp.pk,
      envelope: built.envelope,
      requestOtp: async () => operator.lastOtpFor('alice@example.com'),
    });

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.value.envelope).toEqual(built.envelope);
      expect(operator.enrollments.size).toBe(1);
    }
  });

  test('rate limit: 4th dispatch within an hour → RATE_LIMITED', async () => {
    // policy.enrollmentDispatchPerHour = 3
    for (let i = 0; i < 3; i++) {
      const r = await enroll(operator, {
        identitySk: kp.sk,
        identityPk: kp.pk,
        certId,
        contactEmail: 'alice@example.com',
        questions: QUESTIONS,
        answers: ANSWERS.slice(),
        recoverySeed: freshSeed(),
        derivationContexts: CONTEXTS,
        derivationStateSnapshot: STATE_SNAPSHOT,
        requestOtp: async () => null, // cancel each attempt to keep state clean
      });
      // First 3 dispatches succeed (200 from the operator); the user cancels OTP.
      void r;
    }
    const fourth = await enroll(operator, {
      identitySk: kp.sk,
      identityPk: kp.pk,
      certId,
      contactEmail: 'alice@example.com',
      questions: QUESTIONS,
      answers: ANSWERS.slice(),
      recoverySeed: freshSeed(),
      derivationContexts: CONTEXTS,
      derivationStateSnapshot: STATE_SNAPSHOT,
      requestOtp: async () => null,
    });
    expect(fourth.ok).toBe(false);
    if (!fourth.ok) {
      expect(fourth.error.kind).toBe('RATE_LIMITED');
    }
  });
});

describe('Plexus dispatch — recovery', () => {
  test('happy-path: pre-seeded → recovered seed bytes match', async () => {
    // Pre-seed with a built envelope.
    const built = await buildEnvelope({
      identitySk: kp.sk,
      identityPk: kp.pk,
      certId,
      contactEmail: 'alice@example.com',
      questions: QUESTIONS,
      answers: ANSWERS.slice(),
      recoverySeed: seed,
      derivationContexts: CONTEXTS,
      derivationStateSnapshot: STATE_SNAPSHOT,
    });
    expect(built.ok).toBe(true);
    if (!built.ok) return;
    operator.seedEnrollment(built.envelope);

    const result = await recover(operator, {
      contactEmail: 'alice@example.com',
      requestOtp: async () => operator.lastOtpFor('alice@example.com'),
      requestAnswers: async () => ANSWERS.slice(),
    });
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.value.recoveredSeed).toEqual(seed);
      expect(result.value.tierContexts).toEqual(CONTEXTS);
    }
  });

  test('wrong answers: CHALLENGE_FAILED, no seed leaked', async () => {
    const built = await buildEnvelope({
      identitySk: kp.sk,
      identityPk: kp.pk,
      certId,
      contactEmail: 'alice@example.com',
      questions: QUESTIONS,
      answers: ANSWERS.slice(),
      recoverySeed: seed,
      derivationContexts: CONTEXTS,
      derivationStateSnapshot: STATE_SNAPSHOT,
    });
    expect(built.ok).toBe(true);
    if (!built.ok) return;
    operator.seedEnrollment(built.envelope);

    const result = await recover(operator, {
      contactEmail: 'alice@example.com',
      requestOtp: async () => operator.lastOtpFor('alice@example.com'),
      requestAnswers: async () => ['Wrong', 'Wrong'],
    });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.kind).toBe('CHALLENGE_FAILED');
    }
  });

  test('user cancels OTP: OTP_CANCELLED', async () => {
    const built = await buildEnvelope({
      identitySk: kp.sk,
      identityPk: kp.pk,
      certId,
      contactEmail: 'alice@example.com',
      questions: QUESTIONS,
      answers: ANSWERS.slice(),
      recoverySeed: seed,
      derivationContexts: CONTEXTS,
      derivationStateSnapshot: STATE_SNAPSHOT,
    });
    if (!built.ok) throw new Error('build failed');
    operator.seedEnrollment(built.envelope);

    const result = await recover(operator, {
      contactEmail: 'alice@example.com',
      requestOtp: async () => null,
      requestAnswers: async () => ANSWERS.slice(),
    });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error.kind).toBe('OTP_CANCELLED');
    }
  });

  test('unknown email: opaque OTP-delivered response (no enumeration leak), then NO_ENROLLMENT', async () => {
    const result = await recover(operator, {
      contactEmail: 'unknown@example.com',
      requestOtp: async () => '000000',
      requestAnswers: async () => ['anything'],
    });
    expect(result.ok).toBe(false);
    // Unknown emails get an opaque 202 from initiate (no enumeration), so
    // the dispatcher proceeds to the challenge fetch which fails with
    // NO_ENROLLMENT.
    if (!result.ok) {
      expect(['NO_ENROLLMENT', 'OPERATOR_REJECTED']).toContain(result.error.kind);
    }
  });
});

describe('Mock operator: pricing info', () => {
  test('GET /info returns pricing + supported algorithm versions', async () => {
    const r = await operator.info();
    expect(r.status).toBe(200);
    const body = r.body as { annualPriceSats: number; supportedAlgorithmVersions: number[] };
    expect(body.annualPriceSats).toBe(100_000);
    expect(body.supportedAlgorithmVersions).toContain(1);
  });
});

```
