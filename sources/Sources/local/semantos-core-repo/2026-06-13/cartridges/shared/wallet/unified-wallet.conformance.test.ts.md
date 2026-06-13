---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/shared/wallet/unified-wallet.conformance.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.434233+00:00
---

# cartridges/shared/wallet/unified-wallet.conformance.test.ts

```ts
/**
 * unified-wallet.conformance.test.ts — BRC-100 wallet adapter conformance.
 *
 * Per Q9 (canonicalization-decisions.md, 2026-05-28), the wallet contract
 * is BRC-100 (`@bsv/sdk` `WalletInterface`). This module ships TWO
 * conformance entry-points adapters can run:
 *
 *   runBrc100CryptoEquivalence(factoryId, options)
 *     ────────────────────────────────────────────────
 *     STRICTEST. Asserts the adapter's crypto outputs are BYTE-EQUIVALENT
 *     to @bsv/sdk's `ProtoWallet` for the same inputs. Only adapters that
 *     are themselves ProtoWallet-backed (i.e., the local crypto runs
 *     against the SAME deterministic private key) can pass.
 *
 *     Use: headless-unified-wallet (ProtoWallet-backed in-process).
 *     Skip: wallet-headers-unified-wallet (delegates to Metanet Desktop —
 *     the desktop's key is operator-owned, not the test key, so
 *     byte-equivalence is by definition false).
 *
 *   runBrc100InterfaceConformance(factoryId, options)  [C6a tick 4]
 *     ────────────────────────────────────────────────
 *     SHAPE ONLY. Asserts every WalletInterface method is implemented +
 *     each method returns a result with the expected field names + types.
 *     Round-trip operations (HMAC create+verify, encrypt+decrypt,
 *     create+verify signature against the adapter itself) must work, but
 *     no cross-reference against ProtoWallet outputs is performed.
 *
 *     Use: every BRC-100-conformant adapter, regardless of backend.
 *     The headless adapter trivially passes this AS WELL AS crypto-
 *     equivalence; the wallet-headers adapter passes only this.
 *
 *     Mocks: adapters that need external state (Metanet Desktop fetch,
 *     remote signing service, etc.) inject fixtures via options.buildConfig
 *     — the suite itself doesn't know or care.
 *
 * Transaction methods (createAction/signAction etc) remain out of scope
 * — those need real UTXOs + funding and are exercised via integration
 * suites elsewhere.
 *
 * Usage from an adapter test file:
 *   import {
 *     runBrc100CryptoEquivalence,
 *     runBrc100InterfaceConformance,
 *   } from './unified-wallet.conformance.test';
 *   import { registerHeadlessWallet } from './headless-unified-wallet';
 *   registerHeadlessWallet();
 *   runBrc100CryptoEquivalence('headless', { buildConfig: { privKey: TEST_PRIVKEY } });
 *   runBrc100InterfaceConformance('headless', { buildConfig: { privKey: TEST_PRIVKEY } });
 *
 * SUPERSEDES the bespoke runUnifiedWalletConformance from C6a tick 1
 * (commit 975c760) per Q9. The single-entry-point runBrc100Conformance
 * from tick 3 is REMOVED in C6a tick 4 — call sites split into
 * runBrc100CryptoEquivalence (only ProtoWallet-backed adapters) vs
 * runBrc100InterfaceConformance (any adapter) per the architectural
 * split decided 2026-05-28.
 */

import { describe, expect, it, beforeAll } from 'bun:test';
import { ProtoWallet, PrivateKey, type WalletInterface } from '@bsv/sdk';

import {
  getWalletFactory,
} from './unified-wallet';

/** Deterministic test privkey shared across adapters. NOT for production. */
export const TEST_PRIVKEY = new Uint8Array(32);
for (let i = 0; i < 32; i++) TEST_PRIVKEY[i] = (i + 1) & 0xff;

/** Standard test args. The protocolID is BRC-43 (security level + protocol name). */
const TEST_PROTOCOL_ID: [number, string] = [2, 'semantos canonicalization test'];
const TEST_KEY_ID = 'v1_release';
const TEST_DATA = Array.from(
  // The C7 slice's rawText — passing the suite means the wallet handles
  // the slice's actual signing input correctly.
  new TextEncoder().encode(
    "I'm letting go of the pressure to make every interaction perfect.",
  ),
);

/** Construct the reference ProtoWallet from TEST_PRIVKEY for cross-checking. */
function makeReferenceProto(): ProtoWallet {
  const hex = Array.from(TEST_PRIVKEY)
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
  return new ProtoWallet(PrivateKey.fromHex(hex));
}

/**
 * Run the BRC-100 CRYPTO-EQUIVALENCE conformance suite — strictest tier.
 *
 * Adapters PASSING this suite are byte-equivalent to @bsv/sdk's
 * `ProtoWallet` reference for the crypto subset. Only ProtoWallet-backed
 * adapters can pass (the SAME deterministic test key produces the SAME
 * outputs); passthrough adapters (e.g. wallet-headers delegating to
 * Metanet Desktop) cannot pass and should run runBrc100InterfaceConformance
 * instead.
 *
 * @param factoryId  The id used in registerWalletFactory({id, ...}).
 * @param options.buildConfig  Config passed to factory.build(). MUST set
 *   privKey to TEST_PRIVKEY for cross-reference assertions to hold.
 */
export function runBrc100CryptoEquivalence(
  factoryId: string,
  options: { buildConfig?: Record<string, unknown> } = {},
): void {
  describe(`BRC-100 crypto equivalence — ${factoryId}`, () => {
    let wallet: WalletInterface;
    let reference: ProtoWallet;

    beforeAll(async () => {
      const factory = getWalletFactory(factoryId);
      if (!factory) {
        throw new Error(
          `No WalletFactory registered for id '${factoryId}'. ` +
          `Register it via registerWalletFactory() before calling ` +
          `runBrc100Conformance.`,
        );
      }
      wallet = await factory.build(options.buildConfig ?? {});
      reference = makeReferenceProto();
    });

    // ── getPublicKey ──────────────────────────────────────────────────
    it('getPublicKey returns the same key as ProtoWallet reference', async () => {
      const args = {
        protocolID: TEST_PROTOCOL_ID,
        keyID: TEST_KEY_ID,
      } as const;
      const { publicKey: ours } = await wallet.getPublicKey(args);
      const { publicKey: ref } = await reference.getPublicKey(args);
      expect(ours).toBe(ref);
    });

    it('getPublicKey with identityKey:true returns identity pubkey', async () => {
      const { publicKey: ours } = await wallet.getPublicKey({ identityKey: true });
      const { publicKey: ref } = await reference.getPublicKey({ identityKey: true });
      expect(ours).toBe(ref);
    });

    it('getPublicKey with counterparty derives the shared key', async () => {
      // Simulate a counterparty (Bridget). For ProtoWallet self-tests we use
      // 'self' as a sentinel — the real Bridget-payment case uses her cert's
      // subjectPublicKey hex string.
      const args = {
        protocolID: TEST_PROTOCOL_ID,
        keyID: TEST_KEY_ID,
        counterparty: 'self' as const,
      };
      const { publicKey: ours } = await wallet.getPublicKey(args);
      const { publicKey: ref } = await reference.getPublicKey(args);
      expect(ours).toBe(ref);
    });

    // ── createSignature ───────────────────────────────────────────────
    // Note: @bsv/sdk's ProtoWallet has asymmetric default counterparty —
    // createSignature defaults to 'anyone', verifySignature defaults to
    // 'self'. We pass counterparty: 'self' explicitly in both directions
    // to test the symmetric self-signing pattern (which is what the C7
    // slice uses for cell-hash signing).
    const SIGN_ARGS = {
      protocolID: TEST_PROTOCOL_ID,
      keyID: TEST_KEY_ID,
      counterparty: 'self' as const,
      data: TEST_DATA,
    };

    it('createSignature produces a sig that verifies (self → self)', async () => {
      const { signature } = await wallet.createSignature(SIGN_ARGS);
      expect(Array.isArray(signature)).toBe(true);
      expect(signature.length).toBeGreaterThan(0);

      const { valid } = await wallet.verifySignature({
        ...SIGN_ARGS,
        signature,
      });
      expect(valid).toBe(true);
    });

    it('verifySignature accepts the reference ProtoWallet sig', async () => {
      const { signature: refSig } = await reference.createSignature(SIGN_ARGS);
      const { valid } = await wallet.verifySignature({
        ...SIGN_ARGS,
        signature: refSig,
      });
      expect(valid).toBe(true);
    });

    it('reference accepts our adapter sig (interop both ways)', async () => {
      const { signature: oursSig } = await wallet.createSignature(SIGN_ARGS);
      const { valid } = await reference.verifySignature({
        ...SIGN_ARGS,
        signature: oursSig,
      });
      expect(valid).toBe(true);
    });

    // ── HMAC ──────────────────────────────────────────────────────────
    it('createHmac + verifyHmac round-trip', async () => {
      const args = {
        protocolID: TEST_PROTOCOL_ID,
        keyID: TEST_KEY_ID,
        data: TEST_DATA,
      };
      const { hmac } = await wallet.createHmac(args);
      expect(Array.isArray(hmac)).toBe(true);
      expect(hmac.length).toBe(32);

      const { valid } = await wallet.verifyHmac({ ...args, hmac });
      expect(valid).toBe(true);
    });

    // ── encrypt/decrypt ───────────────────────────────────────────────
    it('encrypt + decrypt round-trip recovers plaintext', async () => {
      const args = {
        protocolID: TEST_PROTOCOL_ID,
        keyID: TEST_KEY_ID,
        plaintext: TEST_DATA,
      };
      const { ciphertext } = await wallet.encrypt(args);
      expect(Array.isArray(ciphertext)).toBe(true);

      const { plaintext } = await wallet.decrypt({
        protocolID: TEST_PROTOCOL_ID,
        keyID: TEST_KEY_ID,
        ciphertext,
      });
      expect(plaintext).toEqual(TEST_DATA);
    });

    // ── Network info ──────────────────────────────────────────────────
    it('getNetwork returns mainnet or testnet', async () => {
      const { network } = await wallet.getNetwork();
      expect(network === 'mainnet' || network === 'testnet').toBe(true);
    });

    it('getVersion returns a non-empty version string', async () => {
      const { version } = await wallet.getVersion();
      expect(typeof version).toBe('string');
      expect(version.length).toBeGreaterThan(0);
    });

    it('isAuthenticated returns a boolean result', async () => {
      const result = await wallet.isAuthenticated();
      expect(typeof result.authenticated).toBe('boolean');
    });
  });
}

/**
 * Run the BRC-100 INTERFACE-CONFORMANCE suite — shape only.
 *
 * Asserts the adapter implements all WalletInterface methods + each
 * method returns a result with the expected shape (field names + types).
 * Round-trip operations on the adapter (HMAC create+verify, encrypt+
 * decrypt, sign+verify against the adapter itself) must work.
 *
 * Does NOT cross-reference outputs against ProtoWallet. Passthrough
 * adapters (wallet-headers → Metanet Desktop, remote signing services,
 * etc.) pass this suite if their delegate cooperates.
 *
 * Adapters needing external state inject test fixtures via
 * options.buildConfig — the suite is backend-agnostic.
 *
 * @param factoryId  The id used in registerWalletFactory({id, ...}).
 * @param options.buildConfig  Config passed to factory.build(). Adapter-specific.
 */
export function runBrc100InterfaceConformance(
  factoryId: string,
  options: { buildConfig?: Record<string, unknown> } = {},
): void {
  describe(`BRC-100 interface conformance — ${factoryId}`, () => {
    let wallet: WalletInterface;

    beforeAll(async () => {
      const factory = getWalletFactory(factoryId);
      if (!factory) {
        throw new Error(
          `No WalletFactory registered for id '${factoryId}'. ` +
          `Register it via registerWalletFactory() before calling ` +
          `runBrc100InterfaceConformance.`,
        );
      }
      wallet = await factory.build(options.buildConfig ?? {});
    });

    // ── method-presence smokes ──────────────────────────────────────
    it('implements every WalletInterface method as a function', () => {
      const required = [
        'getPublicKey',
        'createSignature',
        'verifySignature',
        'createHmac',
        'verifyHmac',
        'encrypt',
        'decrypt',
        'createAction',
        'signAction',
        'abortAction',
        'listActions',
        'internalizeAction',
        'listOutputs',
        'relinquishOutput',
        'acquireCertificate',
        'listCertificates',
        'proveCertificate',
        'relinquishCertificate',
        'discoverByIdentityKey',
        'discoverByAttributes',
        'isAuthenticated',
        'waitForAuthentication',
        'getHeight',
        'getHeaderForHeight',
        'getNetwork',
        'getVersion',
      ] as const;
      for (const method of required) {
        expect(typeof (wallet as unknown as Record<string, unknown>)[method])
          .toBe('function');
      }
    });

    // ── crypto round-trips (no cross-reference) ─────────────────────
    // protocolID + keyID must match @bsv/sdk's KeyDeriver constraint:
    // letters, numbers, spaces ONLY (no hyphens, underscores, etc).
    const TEST_PROTO: [number, string] = [2, 'interface conformance probe'];
    const TEST_KEY = 'interface probe';
    const TEST_BYTES = Array.from(new TextEncoder().encode('shape-only test'));

    it('createSignature + verifySignature self round-trip', async () => {
      const args = {
        protocolID: TEST_PROTO,
        keyID: TEST_KEY,
        counterparty: 'self' as const,
        data: TEST_BYTES,
      };
      const { signature } = await wallet.createSignature(args);
      expect(Array.isArray(signature)).toBe(true);
      expect(signature.length).toBeGreaterThan(0);
      const { valid } = await wallet.verifySignature({ ...args, signature });
      expect(valid).toBe(true);
    });

    it('createHmac + verifyHmac round-trip', async () => {
      const args = {
        protocolID: TEST_PROTO,
        keyID: TEST_KEY,
        data: TEST_BYTES,
      };
      const { hmac } = await wallet.createHmac(args);
      expect(Array.isArray(hmac)).toBe(true);
      expect(hmac.length).toBe(32);
      const { valid } = await wallet.verifyHmac({ ...args, hmac });
      expect(valid).toBe(true);
    });

    it('encrypt + decrypt recovers plaintext', async () => {
      const args = {
        protocolID: TEST_PROTO,
        keyID: TEST_KEY,
        plaintext: TEST_BYTES,
      };
      const { ciphertext } = await wallet.encrypt(args);
      expect(Array.isArray(ciphertext)).toBe(true);
      const { plaintext } = await wallet.decrypt({
        protocolID: TEST_PROTO,
        keyID: TEST_KEY,
        ciphertext,
      });
      expect(plaintext).toEqual(TEST_BYTES);
    });

    // ── shape assertions on result envelopes ────────────────────────
    it('getPublicKey returns { publicKey: string }', async () => {
      const result = await wallet.getPublicKey({
        protocolID: TEST_PROTO,
        keyID: TEST_KEY,
      });
      expect(typeof result.publicKey).toBe('string');
      expect(result.publicKey.length).toBeGreaterThan(0);
    });

    it('getNetwork returns { network: "mainnet" | "testnet" }', async () => {
      const { network } = await wallet.getNetwork();
      expect(network === 'mainnet' || network === 'testnet').toBe(true);
    });

    it('getVersion returns { version: string }', async () => {
      const { version } = await wallet.getVersion();
      expect(typeof version).toBe('string');
      expect(version.length).toBeGreaterThan(0);
    });

    it('isAuthenticated returns { authenticated: boolean }', async () => {
      const result = await wallet.isAuthenticated();
      expect(typeof result.authenticated).toBe('boolean');
    });
  });
}

// ── Sentinel test so this file is meaningful when imported standalone ─
describe('BRC-100 conformance suite — module', () => {
  it('exposes runBrc100CryptoEquivalence', () => {
    expect(typeof runBrc100CryptoEquivalence).toBe('function');
  });
  it('exposes runBrc100InterfaceConformance', () => {
    expect(typeof runBrc100InterfaceConformance).toBe('function');
  });
});

```
