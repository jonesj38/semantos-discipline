---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/test/popup-flow.spec.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.669744+00:00
---

# cartridges/wallet-headers/brain/test/popup-flow.spec.ts

```ts
// W9 popup flow integration test — drives the popup screens'
// pure-state logic without a real DOM, using fake-indexeddb for storage.
//
// Coverage:
//   • Create flow end-to-end (popup-create.runCreateFlow → wallet-ops.createWallet)
//   • Status formatting (popup-status.formatStatus)
//   • Send flow with Tier-0 amount (no factor required)
//   • Send flow with Tier-1 amount + factor
//   • Policy editor: validation + monotonic update
//   • Initial-screen routing (loadWallet → 'create' or 'status')

import { beforeEach, describe, expect, test } from 'bun:test';
import 'fake-indexeddb/auto';
import * as secp from '@noble/secp256k1';
import { hmac } from '@noble/hashes/hmac';
import { sha256 as nobleSha256 } from '@noble/hashes/sha2';

import { runCreateFlow, fetchRecoveryPriceHint } from '../src/popup-create';
import { renderStatus, formatStatus } from '../src/popup-status';
import { runSendFlow, deriveSpendDigest, receivingPublicKeyHex, formatSendSuccess, formatSendError } from '../src/popup-send';
import { runPolicyUpdate, validatePolicy, buildNextPolicy } from '../src/popup-policy';
import { pickInitialScreen, requestedScreenFromLocation } from '../src/popup';
import {
  _resetRuntimeForTests,
  getStatus,
  getPolicy,
  setRecoveryStatus,
  DEFAULT_POLICY,
} from '../src/wallet-ops';
import { _resetDbForTests } from '../src/storage';
import { MockPlexusOperator } from '../src/plexus';

secp.etc.hmacSha256Sync = (key: Uint8Array, ...msgs: Uint8Array[]): Uint8Array =>
  hmac(nobleSha256, key, secp.etc.concatBytes(...msgs));

function freshFlowInputs() {
  return {
    challengeQuestions: ["Mother's maiden name?", 'City of birth?', 'First pet?'] as [string, string, string],
    challengeAnswers: ['Smith', 'Sydney', 'Rover'] as [string, string, string],
    contactEmail: 'user@example.com',
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

describe('popup-create — runCreateFlow (§7.6)', () => {
  test('creates a wallet end-to-end without DOM', async () => {
    const r = await runCreateFlow({ ...freshFlowInputs(), tier1Pin: '1234', tier2Factor: 'biometric' });
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.value.identity.identityPkHex.length).toBe(33 * 2);
      expect(r.value.policy.policyVersion).toBe(1);
      expect(r.value.recoveryEnvelope.envelopeVersion).toBe(1);
    }
  });

  test('rejects empty PIN', async () => {
    const r = await runCreateFlow({ ...freshFlowInputs(), tier1Pin: '' });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.kind).toBe('BAD_INPUT');
  });

  test('fetchRecoveryPriceHint reads /info from configured operator', async () => {
    const op = new MockPlexusOperator(
      { displayDomain: 'mock.test' },
      { info: { operatorDomain: 'mock.test', annualPriceSats: 50_000, supportedAlgorithmVersions: [1], subscriptionLapsePolicy: 'archive' } },
    );
    const hint = await fetchRecoveryPriceHint(op);
    expect(hint).toBe('50,000 sats / year');
  });

  test('fetchRecoveryPriceHint falls back to "$X" when no operator', async () => {
    const hint = await fetchRecoveryPriceHint(null);
    expect(hint).toBe('$X / year');
  });
});

describe('popup-status — formatStatus', () => {
  test('renders truncated identity, recovery, per-tier ceilings', async () => {
    const created = await runCreateFlow({ ...freshFlowInputs(), tier1Pin: '1234' });
    expect(created.ok).toBe(true);
    const r = await getStatus();
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    const fmt = formatStatus(r.value);
    expect(fmt.identityKeyTruncated).toContain('…');
    expect(fmt.recoveryLabel).toContain('not configured');
    expect(fmt.tier1Label).toContain('1,000,000');
    expect(fmt.tier2Label).toContain('10,000,000');
    expect(fmt.tier3Label).toContain('100,000,000');
    expect(fmt.tier3LastSpendLabel).toContain('(none)');
  });

  test('reflects recovery banner state after enrollment', async () => {
    await runCreateFlow({ ...freshFlowInputs(), tier1Pin: '1234' });
    await setRecoveryStatus({ state: 'ENROLLED', operatorDomain: 'mock.test', enrolledAt: 1700000000 });
    const r = await getStatus();
    expect(r.ok).toBe(true);
    if (r.ok) expect(formatStatus(r.value).recoveryLabel).toContain('mock.test');
  });

  test('renderStatus returns the wallet status result', async () => {
    await runCreateFlow({ ...freshFlowInputs(), tier1Pin: '1234' });
    const r = await renderStatus();
    expect(r.ok).toBe(true);
  });
});

describe('popup-send — runSendFlow', () => {
  test('Tier-0 amount, no factor', async () => {
    await runCreateFlow({ ...freshFlowInputs(), tier1Pin: '1234' });
    const r = await runSendFlow({ recipient: '1abc', amountSats: '500' });
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.value.tier).toBe(0);
  });

  test('successful send UI copy is explicit that broadcast is not implemented', async () => {
    await runCreateFlow({ ...freshFlowInputs(), tier1Pin: '1234' });
    const r = await runSendFlow({ recipient: '1abc', amountSats: '500' });
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(formatSendSuccess(r.value)).toContain('Transaction construction and broadcast are not available');
    }
  });

  test('Tier-1 amount + factor', async () => {
    await runCreateFlow({ ...freshFlowInputs(), tier1Pin: '1234' });
    const r = await runSendFlow({ recipient: '1abc', amountSats: '5000000', factor: '1234' });
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.value.tier).toBe(1);
  });

  test('Tier-1 amount, missing factor → TIER_LOCKED', async () => {
    await runCreateFlow({ ...freshFlowInputs(), tier1Pin: '1234' });
    const r = await runSendFlow({ recipient: '1abc', amountSats: '5000000' });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.kind).toBe('TIER_LOCKED');
    if (!r.ok) expect(formatSendError(r.error)).toContain('requires its factor');
  });

  test('non-numeric amount rejected', async () => {
    await runCreateFlow({ ...freshFlowInputs(), tier1Pin: '1234' });
    const r = await runSendFlow({ recipient: '1abc', amountSats: 'abc' });
    expect(r.ok).toBe(false);
  });

  test('deriveSpendDigest is deterministic', () => {
    const a = deriveSpendDigest('1abc', 100n);
    const b = deriveSpendDigest('1abc', 100n);
    expect(a).toEqual(b);
    const c = deriveSpendDigest('1abc', 101n);
    expect(a).not.toEqual(c);
  });

  test('receivingPublicKeyHex returns identity pk when wallet exists', async () => {
    await runCreateFlow({ ...freshFlowInputs(), tier1Pin: '1234' });
    const pk = receivingPublicKeyHex();
    expect(pk).not.toBeNull();
    if (pk) expect(pk.length).toBe(33 * 2);
  });
});

describe('popup-policy — runPolicyUpdate (§6.3)', () => {
  test('happy path: monotonic version', async () => {
    await runCreateFlow({ ...freshFlowInputs(), tier1Pin: '1234' });
    const r = await runPolicyUpdate({
      tier1CeilingSats: 2_000_000,
      tier2CeilingSats: 20_000_000,
      tier3CeilingSats: 200_000_000,
      tier1FactorKind: 'pin',
      tier2FactorKind: 'webauthn',
      tier3FactorKind: 'passphrase',
      tier3CooldownSeconds: 120,
    });
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.value.policyVersion).toBe(2);
      expect(r.value.tier3CooldownSeconds).toBe(120);
    }
  });

  test('rejects non-monotonic ceilings', () => {
    const v = validatePolicy({
      tier1CeilingSats: 10_000,
      tier2CeilingSats: 5_000, // less than tier1!
      tier3CeilingSats: 100_000,
      tier1FactorKind: 'pin',
      tier2FactorKind: 'pin',
      tier3FactorKind: 'pin',
      tier3CooldownSeconds: 0,
    });
    expect(v.ok).toBe(false);
  });

  test('buildNextPolicy bumps version', () => {
    const next = buildNextPolicy(
      {
        tier1CeilingSats: 1_000_000,
        tier2CeilingSats: 10_000_000,
        tier3CeilingSats: 100_000_000,
        tier1FactorKind: 'pin',
        tier2FactorKind: 'webauthn',
        tier3FactorKind: 'passphrase',
        tier3CooldownSeconds: 60,
      },
      { ...DEFAULT_POLICY, policyVersion: 5 },
    );
    expect(next.policyVersion).toBe(6);
  });
});

describe('popup router — pickInitialScreen', () => {
  test('returns "create" on a fresh device', async () => {
    const screen = await pickInitialScreen();
    expect(screen).toBe('create');
  });

  test('returns "status" after a wallet exists', async () => {
    await runCreateFlow({ ...freshFlowInputs(), tier1Pin: '1234' });
    _resetRuntimeForTests();
    const screen = await pickInitialScreen();
    expect(screen).toBe('status');
  });

  test('plexus signup intent lands on status after wallet creation', () => {
    const originalWindow = (globalThis as Record<string, unknown>).window;
    (globalThis as { window: unknown }).window = {
      location: {
        search: '?intent=plexus-signup',
        hash: '',
      },
    };
    try {
      expect(requestedScreenFromLocation(false)).toBe('create');
      expect(requestedScreenFromLocation(true)).toBe('status');
    } finally {
      if (originalWindow === undefined) {
        delete (globalThis as Record<string, unknown>).window;
      } else {
        (globalThis as Record<string, unknown>).window = originalWindow;
      }
    }
  });
});

describe('popup-flow — full first-time-user walkthrough', () => {
  test('create → status → tier-0 send → status → enroll-mock', async () => {
    // 1. Open popup, no wallet → create screen
    const screen0 = await pickInitialScreen();
    expect(screen0).toBe('create');

    // 2. User creates wallet
    const created = await runCreateFlow({ ...freshFlowInputs(), tier1Pin: '1234' });
    expect(created.ok).toBe(true);

    // 3. Status panel renders
    const status0 = await getStatus();
    expect(status0.ok).toBe(true);
    if (status0.ok) {
      expect(status0.value.policy.policyVersion).toBe(1);
      expect(status0.value.recovery.state).toBe('LOCAL_ONLY');
    }

    // 4. User signs a Tier-0 micropayment
    const send = await runSendFlow({ recipient: 'merchant', amountSats: '42' });
    expect(send.ok).toBe(true);

    // 5. Mock-enroll in Plexus (we don't drive the full enroll flow here —
    //    that's covered in plexus-dispatch.spec — but we do simulate the
    //    "banner clears" effect via setRecoveryStatus).
    await setRecoveryStatus({
      state: 'ENROLLED',
      operatorDomain: 'mock.plexus-keys.test',
      enrolledAt: Math.floor(Date.now() / 1000),
    });

    // 6. Banner clears
    const status1 = await getStatus();
    expect(status1.ok).toBe(true);
    if (status1.ok) expect(status1.value.recovery.state).toBe('ENROLLED');
  });
});

```
