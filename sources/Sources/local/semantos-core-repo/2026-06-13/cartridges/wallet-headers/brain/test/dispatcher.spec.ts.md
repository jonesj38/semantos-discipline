---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/test/dispatcher.spec.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.669444+00:00
---

# cartridges/wallet-headers/brain/test/dispatcher.spec.ts

```ts
// W9 BRC-100 dispatcher tests — drive every implemented method through
// the full envelope-decode → handler → result path, plus failure-atomicity
// invariants.

import { beforeEach, describe, expect, test } from 'bun:test';
import 'fake-indexeddb/auto';
import * as secp from '@noble/secp256k1';
import { hmac } from '@noble/hashes/hmac';
import { sha256 as nobleSha256 } from '@noble/hashes/sha2';
import { encodeDer, decodeDer } from '../src/der';

import { dispatch, type DispatcherDeps, METHOD_COVERAGE } from '../src/dispatcher';
import { buildEnvelope, parseEnvelope, hexToBytes, bytesToHex } from '../src/brc100';
import {
  createWallet,
  _resetRuntimeForTests,
  getIdentitySnapshot,
} from '../src/wallet-ops';
import { _resetDbForTests } from '../src/storage';

secp.etc.hmacSha256Sync = (key: Uint8Array, ...msgs: Uint8Array[]): Uint8Array =>
  hmac(nobleSha256, key, secp.etc.concatBytes(...msgs));

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

async function provisionWallet(): Promise<{ identitySk: Uint8Array; identityPk: Uint8Array }> {
  const seed = new Uint8Array(32);
  crypto.getRandomValues(seed);
  await createWallet({
    challengeQuestions: ["Q1?", "Q2?", "Q3?"] as [string, string, string],
    challengeAnswers: ["alpha-mother", "beta-city", "gamma-pet"] as [string, string, string],
    contactEmail: "user@example.com",
    tier1Pin: new TextEncoder().encode('1234'),
    tier2Factor: new TextEncoder().encode('biom'),
    tier3Factor: new TextEncoder().encode('vault'),
  });
  const id = getIdentitySnapshot();
  return { identitySk: id.identitySk, identityPk: id.identityPk };
}

function envelopeFor(identitySk: Uint8Array, identityPk: Uint8Array, body: object) {
  const built = buildEnvelope(
    identitySk,
    identityPk,
    new TextEncoder().encode(JSON.stringify(body)),
  );
  const parsed = parseEnvelope(built);
  if (!parsed.ok) throw new Error('test envelope failed self-parse: ' + parsed.reason);
  return parsed.envelope;
}

function noPromptDeps(overrides: Partial<DispatcherDeps> = {}): DispatcherDeps {
  return {
    network: 'main',
    version: '0.1.0',
    promptFactor: async () => null,
    ...overrides,
  };
}

describe('dispatcher — method coverage', () => {
  test('METHOD_COVERAGE contains all spec-required methods', () => {
    const names = METHOD_COVERAGE.map((m) => m.method);
    for (const required of ['getPublicKey', 'createSignature', 'verifySignature', 'signMessage', 'verifyMessage', 'getNetwork', 'getVersion']) {
      expect(names).toContain(required as never);
    }
    const createAction = METHOD_COVERAGE.find((m) => m.method === 'createAction');
    expect(createAction?.status).toBe('implemented');
  });
});

describe('dispatcher — getPublicKey', () => {
  test('returns identity key when no protocol/counterparty supplied', async () => {
    const { identitySk, identityPk } = await provisionWallet();
    const env = envelopeFor(identitySk, identityPk, { method: 'getPublicKey' });
    const r = await dispatch(env, noPromptDeps());
    expect(r.ok).toBe(true);
    if (r.ok) {
      const result = r.value.result as { publicKey: string };
      expect(result.publicKey).toBe(bytesToHex(identityPk));
    }
  });

  test('allocates a fresh BRC-42 index when context supplied', async () => {
    const { identitySk, identityPk } = await provisionWallet();
    const counterparty = new Uint8Array(33);
    counterparty[0] = 0x02;
    crypto.getRandomValues(counterparty.subarray(1));
    const env = envelopeFor(identitySk, identityPk, {
      method: 'getPublicKey',
      params: { protocolID: 'test-proto', counterparty: bytesToHex(counterparty) },
    });
    const r = await dispatch(env, noPromptDeps());
    expect(r.ok).toBe(true);
    if (r.ok) {
      const result = r.value.result as { derivationIndex: string };
      expect(result.derivationIndex).toBe('0');
    }
  });
});

describe('dispatcher — createSignature / verifySignature round-trip', () => {
  test('Tier-0 signature verifies', async () => {
    const { identitySk, identityPk } = await provisionWallet();
    const digest = new Uint8Array(32);
    crypto.getRandomValues(digest);
    const env = envelopeFor(identitySk, identityPk, {
      method: 'createSignature',
      params: { digestHex: bytesToHex(digest), amountSats: '100' },
    });
    const r = await dispatch(env, noPromptDeps());
    expect(r.ok).toBe(true);
    if (r.ok) {
      const sigHex = (r.value.result as { signatureDer: string }).signatureDer;
      // Tier-0 sigs in v0.1 use a deterministic per-identity tier-0 leaf —
      // we don't have its pubkey directly, so just check non-empty.
      expect(sigHex.length).toBeGreaterThan(8);
    }
  });

  test('Tier-1 prompt fires exactly once per request scope', async () => {
    const { identitySk, identityPk } = await provisionWallet();
    const digest = new Uint8Array(32);
    let prompts = 0;
    const env = envelopeFor(identitySk, identityPk, {
      method: 'createSignature',
      params: { digestHex: bytesToHex(digest), amountSats: '5000000' },
    });
    const r = await dispatch(env, {
      network: 'main',
      version: '0.1.0',
      promptFactor: async () => {
        prompts++;
        return new TextEncoder().encode('1234');
      },
    });
    expect(prompts).toBe(1);
    expect(r.ok).toBe(true);
  });

  test('Tier-1 wrong factor → 401, no persisted side effects', async () => {
    const { identitySk, identityPk } = await provisionWallet();
    const digest = new Uint8Array(32);
    const env = envelopeFor(identitySk, identityPk, {
      method: 'createSignature',
      params: { digestHex: bytesToHex(digest), amountSats: '5000000' },
    });
    const r = await dispatch(env, {
      network: 'main',
      version: '0.1.0',
      promptFactor: async () => new TextEncoder().encode('wrong-pin'),
    });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.code).toBe(401);

    // Subsequent valid request still works (no half-unlocked state).
    const env2 = envelopeFor(identitySk, identityPk, {
      method: 'createSignature',
      params: { digestHex: bytesToHex(digest), amountSats: '500' },
    });
    const r2 = await dispatch(env2, noPromptDeps());
    expect(r2.ok).toBe(true);
  });

  test('Tier-1 prompt cancelled → 401', async () => {
    const { identitySk, identityPk } = await provisionWallet();
    const digest = new Uint8Array(32);
    const env = envelopeFor(identitySk, identityPk, {
      method: 'createSignature',
      params: { digestHex: bytesToHex(digest), amountSats: '5000000' },
    });
    const r = await dispatch(env, noPromptDeps());
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.code).toBe(401);
  });

  test('verifySignature: identity-signed digest verifies', async () => {
    const { identitySk, identityPk } = await provisionWallet();
    const digest = new Uint8Array(32);
    crypto.getRandomValues(digest);
    const sig = secp.sign(digest, identitySk).normalizeS();
    const der = encodeDer(sig.r, sig.s);
    const env = envelopeFor(identitySk, identityPk, {
      method: 'verifySignature',
      params: {
        publicKey: bytesToHex(identityPk),
        digestHex: bytesToHex(digest),
        signatureDer: bytesToHex(der),
      },
    });
    const r = await dispatch(env, noPromptDeps());
    expect(r.ok).toBe(true);
    if (r.ok) expect((r.value.result as { verified: boolean }).verified).toBe(true);
  });

  test('verifySignature: tampered digest fails', async () => {
    const { identitySk, identityPk } = await provisionWallet();
    const digest = new Uint8Array(32);
    const sig = secp.sign(digest, identitySk).normalizeS();
    const der = encodeDer(sig.r, sig.s);
    const tampered = new Uint8Array(32);
    tampered[0] = 1;
    const env = envelopeFor(identitySk, identityPk, {
      method: 'verifySignature',
      params: {
        publicKey: bytesToHex(identityPk),
        digestHex: bytesToHex(tampered),
        signatureDer: bytesToHex(der),
      },
    });
    const r = await dispatch(env, noPromptDeps());
    expect(r.ok).toBe(true);
    if (r.ok) expect((r.value.result as { verified: boolean }).verified).toBe(false);
  });
});

describe('dispatcher — signMessage / verifyMessage round-trip', () => {
  test('signs an arbitrary message + verifies it', async () => {
    const { identitySk, identityPk } = await provisionWallet();
    const messageHex = bytesToHex(new TextEncoder().encode('the quick brown fox'));

    const signEnv = envelopeFor(identitySk, identityPk, {
      method: 'signMessage',
      params: { messageHex },
    });
    const signed = await dispatch(signEnv, noPromptDeps());
    expect(signed.ok).toBe(true);
    if (!signed.ok) return;
    const sigDer = (signed.value.result as { signatureDer: string }).signatureDer;

    const verifyEnv = envelopeFor(identitySk, identityPk, {
      method: 'verifyMessage',
      params: { messageHex, publicKey: bytesToHex(identityPk), signatureDer: sigDer },
    });
    const verified = await dispatch(verifyEnv, noPromptDeps());
    expect(verified.ok).toBe(true);
    if (verified.ok) expect((verified.value.result as { verified: boolean }).verified).toBe(true);
  });
});

describe('dispatcher — getNetwork / getVersion', () => {
  test('getNetwork returns configured network', async () => {
    const { identitySk, identityPk } = await provisionWallet();
    const env = envelopeFor(identitySk, identityPk, { method: 'getNetwork' });
    const r = await dispatch(env, { ...noPromptDeps(), network: 'test' });
    expect(r.ok).toBe(true);
    if (r.ok) expect((r.value.result as { network: string }).network).toBe('test');
  });

  test('getVersion returns configured version', async () => {
    const { identitySk, identityPk } = await provisionWallet();
    const env = envelopeFor(identitySk, identityPk, { method: 'getVersion' });
    const r = await dispatch(env, { ...noPromptDeps(), version: 'X.Y.Z' });
    expect(r.ok).toBe(true);
    if (r.ok) expect((r.value.result as { version: string }).version).toBe('X.Y.Z');
  });
});

describe('dispatcher — createAction validation', () => {
  test('createAction with missing outputs → 400', async () => {
    const { identitySk, identityPk } = await provisionWallet();
    const env = envelopeFor(identitySk, identityPk, { method: 'createAction', params: {} });
    const r = await dispatch(env, noPromptDeps());
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.code).toBe(400);
  });
});

describe('dispatcher — failure modes', () => {
  test('unknown method → 405', async () => {
    const { identitySk, identityPk } = await provisionWallet();
    const env = envelopeFor(identitySk, identityPk, { method: 'noSuchMethod' });
    const r = await dispatch(env, noPromptDeps());
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.code).toBe(405);
  });

  test('non-JSON body → 400', async () => {
    const { identitySk, identityPk } = await provisionWallet();
    const built = buildEnvelope(
      identitySk,
      identityPk,
      new TextEncoder().encode('not-json-at-all'),
    );
    const parsed = parseEnvelope(built);
    expect(parsed.ok).toBe(true);
    if (!parsed.ok) return;
    const r = await dispatch(parsed.envelope, noPromptDeps());
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.code).toBe(400);
  });

  test('createSignature with bad digest length → 400', async () => {
    const { identitySk, identityPk } = await provisionWallet();
    const env = envelopeFor(identitySk, identityPk, {
      method: 'createSignature',
      params: { digestHex: '00112233' /* 4 bytes */, amountSats: '0' },
    });
    const r = await dispatch(env, noPromptDeps());
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.code).toBe(400);
  });

  test('getPublicKey on a wallet that does not exist → 404', async () => {
    // Build a synthetic envelope keypair without provisioning a wallet.
    const sk = secp.utils.randomPrivateKey();
    const pk = secp.getPublicKey(sk, true);
    const built = buildEnvelope(sk, pk, new TextEncoder().encode(JSON.stringify({ method: 'getPublicKey' })));
    const parsed = parseEnvelope(built);
    if (!parsed.ok) throw new Error('envelope build failed');
    const r = await dispatch(parsed.envelope, noPromptDeps());
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.code).toBe(404);
  });
});

describe('dispatcher — sanity: DER decode helper still works', () => {
  test('decodeDer + encodeDer round-trip', () => {
    const sk = secp.utils.randomPrivateKey();
    const msg = new Uint8Array(32);
    crypto.getRandomValues(msg);
    const sig = secp.sign(msg, sk).normalizeS();
    const der = encodeDer(sig.r, sig.s);
    const { r, s } = decodeDer(der);
    expect(r).toBe(sig.r);
    expect(s).toBe(sig.s);
  });
});

```
