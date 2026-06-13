---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/test/wallet-ops.spec.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.665176+00:00
---

# cartridges/wallet-headers/brain/test/wallet-ops.spec.ts

```ts
// W9 wallet-ops tests — exercise the popup-side wallet API directly.
//
// Coverage per the W9 acceptance list:
//   • createWallet — happy path + idempotency (second call returns
//     ALREADY_CREATED rather than overwriting).
//   • signSpend — Tier-0 happy path, Tier-1 happy path with factor,
//     Tier-1 wrong factor surfaces WRONG_FACTOR with no side effects.
//   • updatePolicy — identity-signed, monotonic version, stale-version
//     rejected.
//   • getStatus — shape contains identityKey + recovery + per-tier ceilings.

import { beforeEach, describe, expect, test } from 'bun:test';
import 'fake-indexeddb/auto';
import * as secp from '@noble/secp256k1';
import { hmac } from '@noble/hashes/hmac';
import { sha256 as nobleSha256 } from '@noble/hashes/sha2';

import {
  createWallet,
  loadWallet,
  recoverWallet,
  unlockIdentity,
  unlockIdentityFromCache,
  signSpend,
  signMessage,
  updatePolicy,
  getStatus,
  getPolicy,
  classifyTier,
  DEFAULT_POLICY,
  _resetRuntimeForTests,
} from '../src/wallet-ops';
import { _resetDbForTests } from '../src/storage';

secp.etc.hmacSha256Sync = (key: Uint8Array, ...msgs: Uint8Array[]): Uint8Array =>
  hmac(nobleSha256, key, secp.etc.concatBytes(...msgs));

function freshSeed(): Uint8Array {
  const seed = new Uint8Array(32);
  crypto.getRandomValues(seed);
  return seed;
}

/** v0.4 createWallet inputs — challenges + email mandatory.
 *  `tier1Pin` defaults to '1234' but is overridable. */
function freshCreateInputs(opts?: { tier1Pin?: Uint8Array; tier2Factor?: Uint8Array; tier3Factor?: Uint8Array }) {
  return {
    challengeQuestions: ["Mother's maiden name?", 'City of birth?', 'First pet?'] as [string, string, string],
    challengeAnswers: ['Smith', 'Sydney', 'Rover'] as [string, string, string],
    contactEmail: 'user@example.com',
    tier1Pin: opts?.tier1Pin ?? new TextEncoder().encode('1234'),
    tier2Factor: opts?.tier2Factor ?? new TextEncoder().encode('passphrase'),
    tier3Factor: opts?.tier3Factor ?? new TextEncoder().encode('vault'),
  };
}

beforeEach(() => {
  _resetRuntimeForTests();
  _resetDbForTests();
  return new Promise<void>((resolve) => {
    const req = indexedDB.deleteDatabase('semantos-wallet');
    req.onsuccess = () => resolve();
    req.onerror = () => resolve();
    req.onblocked = () => resolve();
  });
});

describe('createWallet — first-time flow (§7.6)', () => {
  test('happy path: creates identity + policy + tier blobs + recovery envelope', async () => {
    const r = await createWallet(freshCreateInputs());
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.value.identity.identityPkHex.length).toBe(33 * 2);
      expect(r.value.identity.certIdHex.length).toBe(32 * 2);
      expect(r.value.policy.policyVersion).toBe(1);

      // v0.4: every wallet has a dispatch envelope built at creation
      // (§7.6 step 7), regardless of any future Plexus enrollment.
      expect(r.value.recoveryEnvelope).toBeDefined();
      expect(r.value.recoveryEnvelope.envelopeVersion).toBe(1);
      expect(r.value.recoveryEnvelope.identityKey).toBe(r.value.identity.identityPkHex);
      expect(r.value.recoveryEnvelope.contactEmail).toBe('user@example.com');
      expect(r.value.recoveryEnvelope.challengeBundle.questions).toHaveLength(3);
      expect(r.value.recoveryEnvelope.challengeBundle.answerHashes).toHaveLength(3);
      expect(r.value.recoveryEnvelope.challengeBundle.kdfIterations).toBe(100_000);
      expect(r.value.recoveryEnvelope.encryptedRecoverySeed.ciphertext.length).toBeGreaterThan(0);

      // No mnemonic in the result — challenge answers are the user's
      // recovery knowledge per §4.0.
      expect((r.value as unknown as Record<string, unknown>).mnemonicHex).toBeUndefined();
    }
  });

  test('v0.4 §7.6: rejects creation without challenge questions', async () => {
    const inputs = freshCreateInputs();
    inputs.challengeQuestions = ['', 'City of birth?', 'First pet?'] as [string, string, string];
    const r = await createWallet(inputs);
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.kind).toBe('BAD_INPUT');
  });

  test('v0.4 §7.6: rejects creation without challenge answers', async () => {
    const inputs = freshCreateInputs();
    inputs.challengeAnswers = ['Smith', '', 'Rover'] as [string, string, string];
    const r = await createWallet(inputs);
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.kind).toBe('BAD_INPUT');
  });

  test('v0.4 §7.6: rejects creation without contactEmail', async () => {
    const inputs = freshCreateInputs();
    inputs.contactEmail = 'not-an-email';
    const r = await createWallet(inputs);
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.kind).toBe('BAD_INPUT');
  });

  test('v0.4 §7.6: identityKey from envelope matches the identity record', async () => {
    const r = await createWallet(freshCreateInputs());
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.value.recoveryEnvelope.identityKey).toBe(r.value.identity.identityPkHex);
    }
  });

  test('idempotency: second call returns ALREADY_CREATED, no overwrite', async () => {
    const seedA = freshSeed();
    const r1 = await createWallet(freshCreateInputs({ tier1Pin: new TextEncoder().encode('1234'), tier2Factor: new TextEncoder().encode('A'), tier3Factor: new TextEncoder().encode('A') }));
    expect(r1.ok).toBe(true);
    const pkA = (r1 as { ok: true; value: { identity: { identityPkHex: string } } }).value.identity.identityPkHex;

    // Reset runtime cache (simulates a tab reload) — IndexedDB persists.
    _resetRuntimeForTests();
    const seedB = freshSeed();
    const r2 = await createWallet(freshCreateInputs({ tier1Pin: new TextEncoder().encode('5678'), tier2Factor: new TextEncoder().encode('B'), tier3Factor: new TextEncoder().encode('B') }));
    expect(r2.ok).toBe(false);
    if (!r2.ok) {
      expect(r2.error.kind).toBe('ALREADY_CREATED');
    }

    // Verify the original identity survived.
    const status = await getStatus();
    expect(status.ok).toBe(true);
    if (status.ok) expect(status.value.identityKeyHex).toBe(pkA);
  });

  test('rejects empty PIN', async () => {
    const r = await createWallet(freshCreateInputs({ tier1Pin: new Uint8Array(0), tier2Factor: new Uint8Array(0), tier3Factor: new Uint8Array(0) }));
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.kind).toBe('BAD_INPUT');
  });
});

describe('signSpend — tiered signing flow (§7.1–7.4)', () => {
  test('Tier-0: no factor required, succeeds', async () => {
    const seed = freshSeed();
    await createWallet(freshCreateInputs({ tier1Pin: new TextEncoder().encode('1234'), tier2Factor: new Uint8Array(0), tier3Factor: new Uint8Array(0) }));
    const digest = new Uint8Array(32);
    crypto.getRandomValues(digest);
    const r = await signSpend({ digest, amountSats: 500n });
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.value.tier).toBe(0);
      expect(r.value.signatureDer.length).toBeGreaterThan(8);
    }
  });

  test('Tier-1: requires factor, succeeds with correct PIN', async () => {
    const seed = freshSeed();
    await createWallet(freshCreateInputs({ tier1Pin: new TextEncoder().encode('1234'), tier2Factor: new Uint8Array(0), tier3Factor: new Uint8Array(0) }));
    const digest = new Uint8Array(32);
    crypto.getRandomValues(digest);
    const r = await signSpend({
      digest,
      amountSats: 5_000_000n, // > tier1 ceiling (1M) → tier 1
      factor: new TextEncoder().encode('1234'),
    });
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.value.tier).toBe(1);
  });

  test('Tier-1: wrong PIN → WRONG_FACTOR, no side effects on persistence', async () => {
    const seed = freshSeed();
    await createWallet(freshCreateInputs({ tier1Pin: new TextEncoder().encode('1234'), tier2Factor: new Uint8Array(0), tier3Factor: new Uint8Array(0) }));
    const digest = new Uint8Array(32);
    const r = await signSpend({
      digest,
      amountSats: 5_000_000n,
      factor: new TextEncoder().encode('wrong'),
    });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.kind).toBe('WRONG_FACTOR');

    // After the failure: a status read still works.  The identity sk and
    // identity record are intact.
    const status = await getStatus();
    expect(status.ok).toBe(true);
    if (status.ok) expect(status.value.policy.policyVersion).toBe(1);
  });

  test('Tier-1: missing factor → TIER_LOCKED', async () => {
    const seed = freshSeed();
    await createWallet(freshCreateInputs({ tier1Pin: new TextEncoder().encode('1234'), tier2Factor: new Uint8Array(0), tier3Factor: new Uint8Array(0) }));
    const digest = new Uint8Array(32);
    const r = await signSpend({ digest, amountSats: 5_000_000n });
    expect(r.ok).toBe(false);
    if (!r.ok) {
      expect(r.error.kind).toBe('TIER_LOCKED');
      if (r.error.kind === 'TIER_LOCKED') expect(r.error.tier).toBe(1);
    }
  });

  test('signMessage: identity-signed digest', async () => {
    await createWallet(freshCreateInputs({ tier1Pin: new TextEncoder().encode('1234'), tier2Factor: new Uint8Array(0), tier3Factor: new Uint8Array(0) }));
    const r = await signMessage(new TextEncoder().encode('hello'));
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.value.length).toBeGreaterThan(8);
  });
});

describe('updatePolicy — identity-signed monotonic (§6.3)', () => {
  test('happy path: bumps version', async () => {
    await createWallet(freshCreateInputs({ tier1Pin: new TextEncoder().encode('1234'), tier2Factor: new Uint8Array(0), tier3Factor: new Uint8Array(0) }));
    const cur = getPolicy();
    expect(cur.policyVersion).toBe(1);
    const r = await updatePolicy({
      next: { ...cur, policyVersion: 2, tier1CeilingSats: 2_000_000 },
    });
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.value.policyVersion).toBe(2);
      expect(r.value.tier1CeilingSats).toBe(2_000_000);
    }
  });

  test('stale version is rejected', async () => {
    await createWallet(freshCreateInputs({ tier1Pin: new TextEncoder().encode('1234'), tier2Factor: new Uint8Array(0), tier3Factor: new Uint8Array(0) }));
    const r = await updatePolicy({
      next: { ...DEFAULT_POLICY, policyVersion: 1 }, // same as current
    });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.kind).toBe('STALE_POLICY');
  });
});

describe('getStatus — shape (§10.3)', () => {
  test('returns identity + recovery + policy + tier enrollment', async () => {
    await createWallet(freshCreateInputs({ tier1Pin: new TextEncoder().encode('1234'), tier2Factor: new TextEncoder().encode('A'), tier3Factor: new Uint8Array(0) }));
    const r = await getStatus();
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.value.identityKeyHex.length).toBe(33 * 2);
      expect(r.value.recovery.state).toBe('LOCAL_ONLY');
      expect(r.value.policy.tier1CeilingSats).toBe(1_000_000);
      expect(r.value.tierEnrolled.tier1).toBe(true);
      expect(r.value.tierEnrolled.tier2).toBe(true);
      expect(r.value.tierEnrolled.tier3).toBe(false);
    }
  });

  test('NOT_CREATED before createWallet runs', async () => {
    const r = await getStatus();
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.kind).toBe('NOT_CREATED');
  });
});

describe('classifyTier (§3 schedule)', () => {
  test('classifies amounts against default policy', () => {
    expect(classifyTier(0n)).toBe(0);
    expect(classifyTier(999_999n)).toBe(0);
    expect(classifyTier(1_000_000n)).toBe(1);
    expect(classifyTier(9_999_999n)).toBe(1);
    expect(classifyTier(10_000_000n)).toBe(2);
    expect(classifyTier(99_999_999n)).toBe(2);
    expect(classifyTier(100_000_000n)).toBe(3);
  });
});

describe('recoverWallet (W10 unit-level coverage of the new public export)', () => {
  test('rejects when a wallet already exists locally (ALREADY_CREATED)', async () => {
    // Create a wallet, then try to "recover" on top of it. v0.4 forbids
    // clobbering — the recovery flow is meant for fresh-device boot.
    const created = await createWallet(freshCreateInputs());
    expect(created.ok).toBe(true);
    if (!created.ok) return;
    const r = await recoverWallet({
      envelope: created.value.recoveryEnvelope,
      challengeAnswers: ['Smith', 'Sydney', 'Rover'],
      tier1Pin: new TextEncoder().encode('5678'),
      tier2Factor: new TextEncoder().encode('B'),
      tier3Factor: new TextEncoder().encode('B'),
    });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.kind).toBe('ALREADY_CREATED');
  });

  test('rejects malformed envelope (envelopeVersion != 1)', async () => {
    const created = await createWallet(freshCreateInputs());
    if (!created.ok) throw new Error('setup');
    const env = JSON.parse(JSON.stringify(created.value.recoveryEnvelope));
    env.envelopeVersion = 2;
    _resetRuntimeForTests();
    _resetDbForTests();
    await new Promise<void>((resolve) => {
      const req = indexedDB.deleteDatabase('semantos-wallet');
      req.onsuccess = () => resolve();
      req.onerror = () => resolve();
      req.onblocked = () => resolve();
    });
    const r = await recoverWallet({
      envelope: env,
      challengeAnswers: ['Smith', 'Sydney', 'Rover'],
      tier1Pin: new TextEncoder().encode('5678'),
      tier2Factor: new TextEncoder().encode('B'),
      tier3Factor: new TextEncoder().encode('B'),
    });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.kind).toBe('BAD_INPUT');
  });
});

describe('loadWallet (cross-process simulation, v0.4)', () => {
  test('hydrates identity record + policy from IndexedDB after runtime reset', async () => {
    const r1 = await createWallet(freshCreateInputs({ tier1Pin: new TextEncoder().encode('1234'), tier2Factor: new Uint8Array(0), tier3Factor: new Uint8Array(0) }));
    expect(r1.ok).toBe(true);
    if (!r1.ok) return;
    const originalPk = r1.value.identity.identityPkHex;

    _resetRuntimeForTests(); // simulate tab reload — process state cleared

    // v0.4: loadWallet rehydrates the identity record + policy from
    // IndexedDB without needing the seed (which was wiped at creation
    // per §7.6 step 11). Signing operations on a freshly-loaded wallet
    // require either the recovery flow (challenge answers) OR an explicit
    // unlock — neither is exercised here, just the load.
    const loaded = await loadWallet();
    expect(loaded.ok).toBe(true);
    if (loaded.ok) {
      expect(loaded.value.identity.identityPkHex).toBe(originalPk);
      expect(loaded.value.policy.policyVersion).toBe(1);
      expect(loaded.value.recovery.state).toBe('LOCAL_ONLY');
    }

    // The recovery envelope is also persisted and recoverable post-reload.
    const status = await getStatus();
    expect(status.ok).toBe(true);
    if (status.ok) {
      expect(status.value.identityKeyHex).toBe(originalPk);
    }
  });

  test('returning-device boot loads identity sk from cache without re-entering answers', async () => {
    // Create a wallet, then simulate tab reload (runtime cleared, IndexedDB
    // persists). v0.4 §7.9 boot path: loadWallet hydrates identity record +
    // policy; unlockIdentityFromCache rehydrates identity sk from the
    // deterministic-from-identityPk encrypted blob without challenge
    // answers, seed, or any UI prompt.
    const r1 = await createWallet(freshCreateInputs({ tier1Pin: new TextEncoder().encode('1234'), tier2Factor: new Uint8Array(0), tier3Factor: new Uint8Array(0) }));
    expect(r1.ok).toBe(true);
    if (!r1.ok) return;
    const originalPk = r1.value.identity.identityPkHex;

    _resetRuntimeForTests();

    const loaded = await loadWallet();
    expect(loaded.ok).toBe(true);

    // Before unlockIdentityFromCache, identity-keyed signing fails because
    // identitySk isn't in runtime memory.
    const sigBefore = await signMessage(new TextEncoder().encode('hello'));
    expect(sigBefore.ok).toBe(false);

    // v0.4 §7.9: rehydrate identity sk from the boot cache.
    const unlocked = await unlockIdentityFromCache();
    expect(unlocked.ok).toBe(true);

    // Now identity signing works — proves identitySk really is in runtime.
    const sigAfter = await signMessage(new TextEncoder().encode('hello'));
    expect(sigAfter.ok).toBe(true);

    // Identity public key still matches the original creation.
    const status = await getStatus();
    expect(status.ok).toBe(true);
    if (status.ok) expect(status.value.identityKeyHex).toBe(originalPk);
  });
});

```
