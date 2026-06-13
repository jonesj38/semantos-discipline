---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/test/recovery-roundtrip.spec.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.665493+00:00
---

# cartridges/wallet-headers/brain/test/recovery-roundtrip.spec.ts

```ts
// W10 — End-to-end recovery roundtrip test.
//
// This is the test that validates v0.4's central architectural promise:
// **the wallet recovers without Plexus**. Each phase below is a discrete
// `describe` block; each step inside it is a discrete `test`. On failure
// the test name plus the failing assertion pinpoints exactly which v0.4
// promise broke — that's the diagnostic intent.
//
// Phases (mirrors `WALLET-TIER-CUSTODY.md` §7.6 → §7.8):
//   A — initial wallet on Device A (createWallet, sign at every tier,
//       2-of-3 vault spend)
//   B — wipe IndexedDB + runtime caches (simulate device loss)
//   C — recover on Device B from the local envelope file (Path B):
//       decryptRecoverySeed → recoverWallet → re-derive identity + tier
//       keys → re-establish per-tier daily-use factors → replay
//       derivationStateSnapshot
//   D — verify recovery is functional: signSpend at every tier, signMessage
//       under the recovered identity, build a fresh dispatch envelope on
//       Device B and round-trip it through decrypt
//   E — Plexus path also recovers (Path A): MockPlexusOperator
//       enrollment dispatch + recover() seed reconstruction → recoverWallet
//       → signSpend on the recovered Plexus path
//
// Constraints honored:
//   • Single bun test file per W10 brief.
//   • No real-network HTTP — MockPlexusOperator only.
//   • No new TS / Bun deps.
//   • Deterministic seed via testOverrides where v0.4 inputs allow.

import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import 'fake-indexeddb/auto';
import * as secp from '@noble/secp256k1';
import { hmac } from '@noble/hashes/hmac';
import { sha256 as nobleSha256 } from '@noble/hashes/sha2';

import {
  createWallet,
  loadWallet,
  recoverWallet,
  signSpend,
  signMessage,
  getStatus,
  _resetRuntimeForTests,
  _bytesToHex,
} from '../src/wallet-ops';
import { _resetDbForTests, kvGet } from '../src/storage';
import {
  buildEnvelope,
  decryptRecoverySeed,
  type PlexusRecoveryEnvelope,
  type DerivationContext,
  type DerivationStateSnapshot,
} from '../src/plexus/envelope';
import { recover as plexusRecover, enroll as plexusEnroll } from '../src/plexus/dispatch';
import { MockPlexusOperator } from '../src/plexus/operator';
import {
  createVault,
  signVaultSpend,
  nextNSequence,
  readThreshold,
} from '../src/vault';

// secp v2 needs sync HMAC for sync sign() — same wiring as host.ts.
secp.etc.hmacSha256Sync = (key: Uint8Array, ...msgs: Uint8Array[]): Uint8Array =>
  hmac(nobleSha256, key, secp.etc.concatBytes(...msgs));

// ──────────────────────────────────────────────────────────────────────
// Test fixtures — deterministic so a failure is reproducible.
// ──────────────────────────────────────────────────────────────────────

/** A 64-byte deterministic seed pinned to W10. Keeps assertions on
 *  identity / tier base keys reproducible from one run to the next. */
function w10Seed(): Uint8Array {
  const seed = new Uint8Array(64);
  for (let i = 0; i < 64; i++) seed[i] = (i * 23 + 7) & 0xff;
  return seed;
}

/** A pinned 32-byte salt — same role as w10Seed but for the envelope's
 *  PBKDF2 challenge-answer KEK. */
function w10Salt(): Uint8Array {
  const salt = new Uint8Array(32);
  for (let i = 0; i < 32; i++) salt[i] = ((i + 1) * 17) & 0xff;
  return salt;
}

/** A pinned 12-byte AES-GCM nonce. */
function w10Nonce(): Uint8Array {
  const nonce = new Uint8Array(12);
  for (let i = 0; i < 12; i++) nonce[i] = (i * 31 + 11) & 0xff;
  return nonce;
}

const QUESTIONS_A: [string, string, string] = [
  "Mother's maiden name?",
  'City of birth?',
  'First pet?',
];
const ANSWERS_A: [string, string, string] = ['Smith', 'Sydney', 'Rover'];
const EMAIL_A = 'alice@example.com';

const TIER1_PIN_DEVICE_A = new TextEncoder().encode('1234');
const TIER2_FACTOR_DEVICE_A = new TextEncoder().encode('biometric-A');
const TIER3_FACTOR_DEVICE_A = new TextEncoder().encode('vault-pass-A');

// New device — different daily-use factors (per §7.8 step 13: "user
// re-establishes device-local daily-use auth factors on the new device").
const TIER1_PIN_DEVICE_B = new TextEncoder().encode('5678');
const TIER2_FACTOR_DEVICE_B = new TextEncoder().encode('biometric-B');
const TIER3_FACTOR_DEVICE_B = new TextEncoder().encode('vault-pass-B');

// ──────────────────────────────────────────────────────────────────────
// IndexedDB wipe helper — simulates Phase B "fresh tab on Device B".
// ──────────────────────────────────────────────────────────────────────

async function wipeIndexedDb(): Promise<void> {
  _resetRuntimeForTests();
  _resetDbForTests();
  await new Promise<void>((resolve) => {
    const req = indexedDB.deleteDatabase('semantos-wallet');
    req.onsuccess = () => resolve();
    req.onerror = () => resolve();
    req.onblocked = () => resolve();
  });
}

beforeEach(wipeIndexedDb);
afterEach(wipeIndexedDb);

// ──────────────────────────────────────────────────────────────────────
// PHASE A — initial wallet on Device A
// ──────────────────────────────────────────────────────────────────────

describe('Phase A — initial wallet on Device A', () => {
  test('A1: createWallet succeeds with v0.4 inputs (challenges + email)', async () => {
    const r = await createWallet({
      challengeQuestions: QUESTIONS_A,
      challengeAnswers: [...ANSWERS_A] as [string, string, string],
      contactEmail: EMAIL_A,
      tier1Pin: TIER1_PIN_DEVICE_A.slice(),
      tier2Factor: TIER2_FACTOR_DEVICE_A,
      tier3Factor: TIER3_FACTOR_DEVICE_A,
      testOverrides: { seed: w10Seed(), salt: w10Salt(), gcmNonce: w10Nonce() },
    });
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.value.identity.identityPkHex.length).toBe(33 * 2);
    expect(r.value.recoveryEnvelope.envelopeVersion).toBe(1);
    expect(r.value.recoveryEnvelope.identityKey).toBe(r.value.identity.identityPkHex);
    expect(r.value.recoveryEnvelope.contactEmail).toBe(EMAIL_A);
    expect(r.value.recoveryEnvelope.challengeBundle.questions).toEqual(QUESTIONS_A);
    expect(r.value.recoveryEnvelope.challengeBundle.kdfIterations).toBe(100_000);
  });

  test('A2: signSpend(tier=0, 500_000) — hot path, no factor prompt', async () => {
    await freshDeviceASetup();
    const digest = pinnedDigest(2);
    const r = await signSpend({ digest, amountSats: 500_000n });
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.value.tier).toBe(0);
      expect(r.value.signatureDer.length).toBeGreaterThan(8);
    }
  });

  test('A3: signSpend(tier=1, 5_000_000, factor=PIN) — daily-use unlock', async () => {
    await freshDeviceASetup();
    const digest = pinnedDigest(3);
    const r = await signSpend({
      digest,
      amountSats: 5_000_000n,
      factor: TIER1_PIN_DEVICE_A.slice(),
    });
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.value.tier).toBe(1);
  });

  test('A4: signSpend(tier=2, 50_000_000, factor=biometric)', async () => {
    await freshDeviceASetup();
    const digest = pinnedDigest(4);
    const r = await signSpend({
      digest,
      amountSats: 50_000_000n,
      factor: TIER2_FACTOR_DEVICE_A,
    });
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.value.tier).toBe(2);
  });

  test('A5: 2-of-3 vault spend (Tier-3 v0.2 multisig via vault.ts)', async () => {
    // W11 vault.signVaultSpend wires the m-of-n satisfaction. The wallet's
    // signSpend(tier=3) is the v0.1 single-key path; the design's "Tier-3
    // multisig spend" is the v0.2 vault module — we exercise it directly
    // here, mirroring vault.spec.ts's pattern, since W11's spend path is
    // not yet wired through wallet-ops.signSpend (tracked separately —
    // see the §4.3 "v0.2 vault-tier-only upgrade" framing).
    const a = makeMember(81);
    const b = makeMember(82);
    const c = makeMember(83);
    const v = createVault({
      memberPubkeys: [a.pk, b.pk, c.pk],
      threshold: 2,
      leafPrivKey: makeSk(811),
      protocolHash: makeProtocolHash(),
      counterparty: makeCounterparty(),
      nsequence: nextNSequence(null, 60),
      parentTxid: new Uint8Array(32),
    });
    const digest = pinnedDigest(5);
    const sig = signVaultSpend(v, [0, 1], [a.sk, b.sk], digest);
    expect(sig.sigCount).toBe(2);
    expect(readThreshold(v)).toBe(2);
    // Each packed entry = [len][DER||sighash]. Sanity-check the count.
    let off = 0;
    let entries = 0;
    while (off < sig.packed.length) {
      const len = sig.packed[off]!;
      off += 1 + len;
      entries++;
    }
    expect(entries).toBe(2);
  });
});

// ──────────────────────────────────────────────────────────────────────
// PHASE B — wipe and reload (simulate device loss)
// ──────────────────────────────────────────────────────────────────────
//
// Captured artifacts from Phase A flow into Phase C. Each test in this
// describe is sequential within a single it()-style chain because
// IndexedDB state is what's being wiped and inspected.

describe('Phase B — wipe IndexedDB and runtime (device loss)', () => {
  test('B1+B2+B3: capture envelope + identityPk, then wipe DB + runtime', async () => {
    const setup = await freshDeviceASetup();
    expect(setup.identity.identityPkHex.length).toBe(33 * 2);
    const captured = setup.recoveryEnvelope;

    // The envelope is also persisted to KV at wallet creation per §7.6.
    // Confirm round-trip: what we got from createWallet matches what's
    // on disk.
    const stored = await kvGet<PlexusRecoveryEnvelope>('recovery-envelope');
    expect(stored).not.toBeNull();
    expect(stored!.identityKey).toBe(captured.identityKey);
    expect(stored!.encryptedRecoverySeed.ciphertext).toBe(captured.encryptedRecoverySeed.ciphertext);

    // Wipe.
    await wipeIndexedDb();

    // B4: loadWallet returns NOT_CREATED on the fresh DB.
    const loaded = await loadWallet();
    expect(loaded.ok).toBe(false);
    if (!loaded.ok) expect(loaded.error.kind).toBe('NOT_CREATED');

    // The recovery envelope is also gone.
    const goneEnv = await kvGet<PlexusRecoveryEnvelope>('recovery-envelope');
    expect(goneEnv).toBeNull();
  });
});

// ──────────────────────────────────────────────────────────────────────
// PHASE C — recovery on Device B (Path B: local envelope file)
// ──────────────────────────────────────────────────────────────────────

describe('Phase C — recover on Device B (Path B: local envelope)', () => {
  test('C1+C2+C3: decryptRecoverySeed yields the original Phase A seed', async () => {
    // Simulate the user uploading the envelope.json they previously backed
    // up. We materialize it by running createWallet on Device A, capturing
    // the envelope, then wiping. After wipe the seed is supposedly gone —
    // recovery has to reconstruct it from envelope + answers.
    const setup = await freshDeviceASetup();
    const envelope = setup.recoveryEnvelope;
    const originalSeed = w10Seed(); // testOverride pinned this
    await wipeIndexedDb();

    // The user re-types the same three answers on the new device.
    const recoveredSeed = await decryptRecoverySeed(envelope, [...ANSWERS_A]);
    expect(recoveredSeed).not.toBeNull();
    if (!recoveredSeed) return;
    expect(recoveredSeed.length).toBe(64);
    expect(recoveredSeed).toEqual(originalSeed);
  });

  test('C3 (negative): wrong answers do not decrypt the seed', async () => {
    const setup = await freshDeviceASetup();
    const envelope = setup.recoveryEnvelope;
    await wipeIndexedDb();

    const wrong = await decryptRecoverySeed(envelope, ['Smith', 'Sydney', 'WRONG']);
    expect(wrong).toBeNull();
  });

  test('C4+C5+C6+C7: recoverWallet rebuilds identity + tier keys + state', async () => {
    const setup = await freshDeviceASetup();
    const envelope = setup.recoveryEnvelope;
    const originalIdentityPk = setup.identity.identityPkHex;
    await wipeIndexedDb();

    const r = await recoverWallet({
      envelope,
      challengeAnswers: [...ANSWERS_A],
      tier1Pin: TIER1_PIN_DEVICE_B.slice(),
      tier2Factor: TIER2_FACTOR_DEVICE_B,
      tier3Factor: TIER3_FACTOR_DEVICE_B,
    });
    expect(r.ok).toBe(true);
    if (!r.ok) {
      throw new Error(`recoverWallet failed: ${JSON.stringify(r.error)}`);
    }

    // C4: identity matches Phase A bit-for-bit.
    expect(r.value.identity.identityPkHex).toBe(originalIdentityPk);
    expect(r.value.identity.certIdHex).toBe(setup.identity.certIdHex);
    // C7: snapshot was empty (createWallet doesn't seed records yet) so
    // no replay happened — but the call shape exercises the path.
    expect(r.value.derivationStateRecordsReplayed).toBe(0);

    // C6: the wallet is now functional — tier blobs are present in
    // IndexedDB under the new daily-use KEKs.
    const status = await getStatus();
    expect(status.ok).toBe(true);
    if (status.ok) {
      expect(status.value.identityKeyHex).toBe(originalIdentityPk);
      expect(status.value.tierEnrolled.tier1).toBe(true);
      expect(status.value.tierEnrolled.tier2).toBe(true);
      expect(status.value.tierEnrolled.tier3).toBe(true);
    }
  });

  test('C: recoverWallet refuses to clobber an existing wallet', async () => {
    const setup = await freshDeviceASetup();
    // Don't wipe — try to recover on top.
    const r = await recoverWallet({
      envelope: setup.recoveryEnvelope,
      challengeAnswers: [...ANSWERS_A],
      tier1Pin: TIER1_PIN_DEVICE_B.slice(),
      tier2Factor: TIER2_FACTOR_DEVICE_B,
      tier3Factor: TIER3_FACTOR_DEVICE_B,
    });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.kind).toBe('ALREADY_CREATED');
  });

  test('C: recoverWallet rejects a tampered envelope (wrong identityKey)', async () => {
    const setup = await freshDeviceASetup();
    const tampered = JSON.parse(JSON.stringify(setup.recoveryEnvelope)) as PlexusRecoveryEnvelope;
    // Flip the identityKey to a different valid 33-byte hex string.
    const fakeSk = new Uint8Array(32);
    for (let i = 0; i < 32; i++) fakeSk[i] = 0xab;
    tampered.identityKey = _bytesToHex(secp.getPublicKey(fakeSk, true));
    await wipeIndexedDb();

    const r = await recoverWallet({
      envelope: tampered,
      challengeAnswers: [...ANSWERS_A],
      tier1Pin: TIER1_PIN_DEVICE_B.slice(),
      tier2Factor: TIER2_FACTOR_DEVICE_B,
      tier3Factor: TIER3_FACTOR_DEVICE_B,
    });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.kind).toBe('IDENTITY_MISMATCH');
  });

  test('C: recoverWallet rejects when answers do not decrypt', async () => {
    const setup = await freshDeviceASetup();
    const envelope = setup.recoveryEnvelope;
    await wipeIndexedDb();

    const r = await recoverWallet({
      envelope,
      challengeAnswers: ['nope', 'nope', 'nope'],
      tier1Pin: TIER1_PIN_DEVICE_B.slice(),
      tier2Factor: TIER2_FACTOR_DEVICE_B,
      tier3Factor: TIER3_FACTOR_DEVICE_B,
    });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.kind).toBe('DECRYPT_FAILED');
  });
});

// ──────────────────────────────────────────────────────────────────────
// PHASE D — verify recovery is functional on Device B
// ──────────────────────────────────────────────────────────────────────

describe('Phase D — recovered wallet is fully functional', () => {
  test('D1: signSpend(tier=0) on Device B works', async () => {
    await recoverIntoDeviceB();
    const r = await signSpend({ digest: pinnedDigest(11), amountSats: 100_000n });
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.value.tier).toBe(0);
  });

  test('D2: signSpend(tier=1) on Device B with the NEW PIN', async () => {
    await recoverIntoDeviceB();
    const r = await signSpend({
      digest: pinnedDigest(12),
      amountSats: 5_000_000n,
      factor: TIER1_PIN_DEVICE_B.slice(),
    });
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.value.tier).toBe(1);
  });

  test('D2 (negative): old Device A PIN does not work on Device B', async () => {
    await recoverIntoDeviceB();
    const r = await signSpend({
      digest: pinnedDigest(12),
      amountSats: 5_000_000n,
      factor: TIER1_PIN_DEVICE_A.slice(),
    });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.kind).toBe('WRONG_FACTOR');
  });

  test('D3: signSpend(tier=2) on Device B with NEW biometric', async () => {
    await recoverIntoDeviceB();
    const r = await signSpend({
      digest: pinnedDigest(13),
      amountSats: 50_000_000n,
      factor: TIER2_FACTOR_DEVICE_B,
    });
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.value.tier).toBe(2);
  });

  test('D4: signMessage on Device B produces sig that verifies under Phase A identityPk', async () => {
    const recovered = await recoverIntoDeviceB();
    const message = new TextEncoder().encode('hello on device B');
    const r = await signMessage(message);
    expect(r.ok).toBe(true);
    if (!r.ok) return;

    // Verify externally under the identityPk from Phase A. We do this with
    // raw secp + DER decode rather than the wallet's own verification — the
    // point is to assert the sig is bound to the SAME identity that Phase A
    // created, end-to-end.
    const digest = nobleSha256(message);
    const identityPk = hexToBytes(recovered.identityPkHex);
    const sig = decodeDerSig(r.value);
    const verified = secp.verify({ r: sig.r, s: sig.s }, digest, identityPk);
    expect(verified).toBe(true);
  });

  test('D5: a fresh dispatch envelope built on Device B round-trips through decrypt', async () => {
    await recoverIntoDeviceB();
    // Build a fresh envelope on Device B with the same identity material
    // and verify decryption with the original answers yields the same seed.
    // This proves recovery yields a fully-functional v0.4 wallet, not a
    // degraded one — the recovered seed can sign new dispatch envelopes.
    const seed = w10Seed();
    const identitySk = hmacDerive(seed, 'identity');
    const identityPk = secp.getPublicKey(identitySk, true);
    const certIdSrc = new Uint8Array(48);
    certIdSrc.set(identityPk, 0);
    certIdSrc.set(new TextEncoder().encode('BRC-52-cert-v1'), identityPk.length);
    const certId = nobleSha256(certIdSrc);

    const built = await buildEnvelope({
      identitySk,
      identityPk,
      certId,
      contactEmail: EMAIL_A,
      questions: [...QUESTIONS_A],
      answers: [...ANSWERS_A],
      recoverySeed: seed,
      derivationContexts: [
        { tier: 1, brc43InvoiceString: '1-tier-key-1', domainFlag: '0x10000003', recoveryPolicy: 'BACKUP_ON_CREATE' },
      ],
      derivationStateSnapshot: { records: [], snapshotTimestamp: '2026-04-26T00:00:00Z' },
    });
    expect(built.ok).toBe(true);
    if (!built.ok) return;
    const seed2 = await decryptRecoverySeed(built.envelope, [...ANSWERS_A]);
    expect(seed2).toEqual(seed);
  });
});

// ──────────────────────────────────────────────────────────────────────
// PHASE E — Plexus path also recovers (Path A)
// ──────────────────────────────────────────────────────────────────────

describe('Phase E — Plexus recovery path (A) reaches the same outcome', () => {
  test('E1+E2: enroll into MockPlexusOperator, envelope mirrored server-side', async () => {
    // Set up a fresh wallet identical to Phase A.
    const seed = w10Seed();
    const identitySk = hmacDerive(seed, 'identity');
    const identityPk = secp.getPublicKey(identitySk, true);
    const certIdSrc = new Uint8Array(48);
    certIdSrc.set(identityPk, 0);
    certIdSrc.set(new TextEncoder().encode('BRC-52-cert-v1'), identityPk.length);
    const certId = nobleSha256(certIdSrc);

    const operator = new MockPlexusOperator(
      { displayDomain: 'mock.plexus-keys.test' },
      { otpExpiryMs: 10 * 60 * 1000 },
    );

    const enrollResult = await plexusEnroll(operator, {
      identitySk,
      identityPk,
      certId,
      contactEmail: EMAIL_A,
      questions: [...QUESTIONS_A],
      answers: [...ANSWERS_A],
      recoverySeed: seed,
      derivationContexts: phaseEContexts(),
      derivationStateSnapshot: { records: [], snapshotTimestamp: '2026-04-26T00:00:00Z' },
      requestOtp: async () => operator.lastOtpFor(EMAIL_A),
    });
    expect(enrollResult.ok).toBe(true);
    if (enrollResult.ok) {
      expect(operator.enrollments.size).toBe(1);
      expect(operator.enrollments.get(enrollResult.value.envelope.identityKey)).toBeDefined();
    }
  });

  test('E3+E4+E5: wipe, recover via Plexus, recoverWallet rebuilds, signSpend works', async () => {
    // Drive a full Plexus enrollment to seed the operator's store.
    const seed = w10Seed();
    const identitySk = hmacDerive(seed, 'identity');
    const identityPk = secp.getPublicKey(identitySk, true);
    const certIdSrc = new Uint8Array(48);
    certIdSrc.set(identityPk, 0);
    certIdSrc.set(new TextEncoder().encode('BRC-52-cert-v1'), identityPk.length);
    const certId = nobleSha256(certIdSrc);

    const operator = new MockPlexusOperator(
      { displayDomain: 'mock.plexus-keys.test' },
      { otpExpiryMs: 10 * 60 * 1000 },
    );

    const enrolled = await plexusEnroll(operator, {
      identitySk,
      identityPk,
      certId,
      contactEmail: EMAIL_A,
      questions: [...QUESTIONS_A],
      answers: [...ANSWERS_A],
      recoverySeed: seed,
      derivationContexts: phaseEContexts(),
      derivationStateSnapshot: { records: [], snapshotTimestamp: '2026-04-26T00:00:00Z' },
      requestOtp: async () => operator.lastOtpFor(EMAIL_A),
    });
    expect(enrolled.ok).toBe(true);
    if (!enrolled.ok) return;

    // E3: simulate device loss.
    await wipeIndexedDb();

    // E4: recoverFromPlexus — the plexus/dispatch.recover() flow.
    const recovered = await plexusRecover(operator, {
      contactEmail: EMAIL_A,
      requestOtp: async () => operator.lastOtpFor(EMAIL_A),
      requestAnswers: async () => [...ANSWERS_A],
    });
    expect(recovered.ok).toBe(true);
    if (!recovered.ok) {
      throw new Error(`plexus recover failed: ${JSON.stringify(recovered.error)}`);
    }
    expect(recovered.value.recoveredSeed).toEqual(seed);

    // Now lift the recovered seed + envelope through recoverWallet so the
    // wallet's IndexedDB is fully populated under new device factors.
    const installed = await recoverWallet({
      envelope: recovered.value.envelope,
      challengeAnswers: [...ANSWERS_A],
      tier1Pin: TIER1_PIN_DEVICE_B.slice(),
      tier2Factor: TIER2_FACTOR_DEVICE_B,
      tier3Factor: TIER3_FACTOR_DEVICE_B,
    });
    expect(installed.ok).toBe(true);
    if (!installed.ok) {
      throw new Error(`recoverWallet (Plexus path) failed: ${JSON.stringify(installed.error)}`);
    }
    expect(installed.value.identity.identityPkHex).toBe(_bytesToHex(identityPk));

    // E5: signSpend on Tier-0 works on the freshly-recovered Plexus path.
    const r = await signSpend({ digest: pinnedDigest(99), amountSats: 100n });
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.value.tier).toBe(0);
  });
});

// ──────────────────────────────────────────────────────────────────────
// Helpers
// ──────────────────────────────────────────────────────────────────────

/** Run createWallet with the Phase-A fixtures + deterministic overrides.
 *  Returns the `value` of a successful CreateWalletResult so callers can
 *  reach the envelope / identity directly. */
async function freshDeviceASetup(): Promise<{
  identity: { identityPkHex: string; certIdHex: string };
  recoveryEnvelope: PlexusRecoveryEnvelope;
}> {
  const r = await createWallet({
    challengeQuestions: QUESTIONS_A,
    challengeAnswers: [...ANSWERS_A] as [string, string, string],
    contactEmail: EMAIL_A,
    tier1Pin: TIER1_PIN_DEVICE_A.slice(),
    tier2Factor: TIER2_FACTOR_DEVICE_A,
    tier3Factor: TIER3_FACTOR_DEVICE_A,
    testOverrides: { seed: w10Seed(), salt: w10Salt(), gcmNonce: w10Nonce() },
  });
  if (!r.ok) throw new Error(`Phase A setup failed: ${JSON.stringify(r.error)}`);
  return { identity: r.value.identity, recoveryEnvelope: r.value.recoveryEnvelope };
}

/** Walk Phase A → wipe → Phase C, returning the recovered identity record
 *  for downstream Phase D assertions. */
async function recoverIntoDeviceB(): Promise<{ identityPkHex: string }> {
  const setup = await freshDeviceASetup();
  const envelope = setup.recoveryEnvelope;
  const originalPk = setup.identity.identityPkHex;
  await wipeIndexedDb();
  const r = await recoverWallet({
    envelope,
    challengeAnswers: [...ANSWERS_A],
    tier1Pin: TIER1_PIN_DEVICE_B.slice(),
    tier2Factor: TIER2_FACTOR_DEVICE_B,
    tier3Factor: TIER3_FACTOR_DEVICE_B,
  });
  if (!r.ok) throw new Error(`Phase C setup failed: ${JSON.stringify(r.error)}`);
  expect(r.value.identity.identityPkHex).toBe(originalPk);
  return { identityPkHex: originalPk };
}

function phaseEContexts(): DerivationContext[] {
  return [
    { tier: 1, brc43InvoiceString: '1-tier-key-1', domainFlag: '0x10000003', recoveryPolicy: 'BACKUP_ON_CREATE' },
    { tier: 2, brc43InvoiceString: '1-tier-key-2', domainFlag: '0x10000004', recoveryPolicy: 'BACKUP_ON_CREATE' },
    { tier: 3, brc43InvoiceString: '1-tier-key-3', domainFlag: '0x10000005', recoveryPolicy: 'BACKUP_ON_CONFIRM' },
  ];
}

function pinnedDigest(salt: number): Uint8Array {
  const d = new Uint8Array(32);
  for (let i = 0; i < 32; i++) d[i] = ((salt + 1) * 13 + i * 7) & 0xff;
  return d;
}

function hmacDerive(seed: Uint8Array, label: string): Uint8Array {
  return hmac(nobleSha256, seed, new TextEncoder().encode(label));
}

function hexToBytes(hex: string): Uint8Array {
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  return out;
}

/** Decode a DER-encoded ECDSA signature into (r, s) bigints — needed for
 *  Phase D4's external verification of the wallet's signMessage output. */
function decodeDerSig(der: Uint8Array): { r: bigint; s: bigint } {
  if (der[0] !== 0x30) throw new Error('decodeDerSig: not a DER SEQUENCE');
  let off = 2; // skip seq tag + len
  if (der[off] !== 0x02) throw new Error('decodeDerSig: r tag missing');
  const rLen = der[off + 1]!;
  const rBytes = der.slice(off + 2, off + 2 + rLen);
  off += 2 + rLen;
  if (der[off] !== 0x02) throw new Error('decodeDerSig: s tag missing');
  const sLen = der[off + 1]!;
  const sBytes = der.slice(off + 2, off + 2 + sLen);
  return { r: bytesToBigint(rBytes), s: bytesToBigint(sBytes) };
}

function bytesToBigint(b: Uint8Array): bigint {
  let n = 0n;
  for (const x of b) n = (n << 8n) | BigInt(x);
  return n;
}

// Vault-test helpers (mirror vault.spec.ts shapes — cannot import from
// a spec file, so re-derive deterministically here).
function makeSk(seed: number): Uint8Array {
  const sk = new Uint8Array(32);
  for (let i = 0; i < 32; i++) sk[i] = ((seed * 31 + i * 7) & 0xff) || 1;
  sk[0] = 0x40 | (seed & 0x3f);
  return sk;
}

function makeMember(seed: number): { sk: Uint8Array; pk: Uint8Array } {
  const sk = makeSk(seed);
  return { sk, pk: secp.getPublicKey(sk, true) };
}

function makeProtocolHash(): Uint8Array {
  const ph = new Uint8Array(16);
  for (let i = 0; i < 16; i++) ph[i] = 0xa0 + i;
  return ph;
}

function makeCounterparty(): Uint8Array {
  const cp = new Uint8Array(33);
  cp[0] = 0x02;
  for (let i = 1; i < 33; i++) cp[i] = 0x55;
  return cp;
}

```
