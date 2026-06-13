---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/identity-adapters/__tests__/cartridge-license.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.913924+00:00
---

# core/protocol-types/src/identity-adapters/__tests__/cartridge-license.test.ts

```ts
/**
 * Wave Cap-Substrate — Decision-A cartridge-license gate conformance.
 *
 * Ref: docs/design/CARTRIDGE-MARKETPLACE-OWNERSHIP.md (RATIFIED) §2/§4.
 *
 * The license is an affine PushDrop UTXO collapsed onto the proven
 * BRC-108 capability-UTXO model: every positive/negative branch here
 * routes through the SHIPPED CapabilityTokenValidator.checkCapability
 * (K15a–e, proven-against-impl) — the gate adds no new crypto. Also
 * exercises the non-breaking ExtensionLoader opt-in hook.
 */

import { describe, test, expect } from 'bun:test';
import {
  CapabilityTokenValidator,
  MonotoneSpendOracle,
  PERMISSION_GRANT_DERIVATION,
} from '../CapabilityTokenValidator';
import type { CertChainStore, CertData } from '../CertChainStore';
import { verifyCartridgeLicense } from '../cartridge-license';
import { ExtensionLoader, ExtensionLoadError } from '../../extension-loader';
import type { ExtensionManifest } from '../../extension-manifest';
import { ODDJOBZ_PAGE } from '../../constants';

const LOADER_PUBKEY = '-----BEGIN PUBLIC KEY-----\nLOADER\n-----END PUBLIC KEY-----';
const PAGE = ODDJOBZ_PAGE | 0x01; // registered capability-page flag
const SIGNING_KEY = new Uint8Array(32).fill(7);
const TXID = 'a'.repeat(64);

const holderCert: CertData = {
  certId: 'loader-1',
  publicKey: LOADER_PUBKEY,
  domainFlags: [],
  created: 0,
  revoked: false,
};

function store(): CertChainStore {
  return { get: async (id: string) => (id === 'loader-1' ? holderCert : null) } as unknown as CertChainStore;
}

const aliveVerifier = { verifyBeef: async () => true, verifyBump: async () => true };

function licenseToken(v: CapabilityTokenValidator, vout = 0): Uint8Array {
  return v.createBrc108Token(
    {
      outpoint: { txid: TXID, vout },
      issuerCertId: 'issuer-1',
      holderCertId: 'loader-1',
      domainFlag: PAGE,
      issuerDerivationDomain: PERMISSION_GRANT_DERIVATION, // SW4: a grant
      expiry: Date.now() + 60_000,
    },
    SIGNING_KEY,
  );
}

function manifest(over: Partial<ExtensionManifest> = {}): ExtensionManifest {
  return {
    id: 'oddjobz',
    name: 'Oddjobz',
    version: '0.1.0',
    taxonomyPath: 't.json',
    flowsDir: 'f',
    promptsDir: 'p',
    licenseOutpointRef: `${TXID}:0`,
    licenseLinearity: 'AFFINE',
    ...over,
  };
}

describe('Decision-A cartridge-license gate (K15 reuse)', () => {
  test('licensed: unspent license UTXO, holder-bound, page-scoped ⇒ licensed', async () => {
    const v = new CapabilityTokenValidator(store());
    const spv = new MonotoneSpendOracle().spvContext(aliveVerifier, 'beef');
    const r = await verifyCartridgeLicense(manifest(), {
      validator: v,
      licenseToken: licenseToken(v),
      loaderPubKey: LOADER_PUBKEY,
      cartridgePageFlag: PAGE,
      spv,
    });
    expect(r.licensed).toBe(true);
  });

  test('K15b: a spent license UTXO ⇒ rejected', async () => {
    const v = new CapabilityTokenValidator(store());
    const oracle = new MonotoneSpendOracle();
    oracle.markSpent({ txid: TXID, vout: 0 });
    const r = await verifyCartridgeLicense(manifest(), {
      validator: v,
      licenseToken: licenseToken(v),
      loaderPubKey: LOADER_PUBKEY,
      cartridgePageFlag: PAGE,
      spv: oracle.spvContext(aliveVerifier, 'beef'),
    });
    expect(r.licensed).toBe(false);
    if (!r.licensed) expect(r.reason).toContain('K15');
  });

  test('binding: token outpoint ≠ manifest.licenseOutpointRef ⇒ rejected', async () => {
    const v = new CapabilityTokenValidator(store());
    const spv = new MonotoneSpendOracle().spvContext(aliveVerifier, 'beef');
    const r = await verifyCartridgeLicense(manifest({ licenseOutpointRef: `${TXID}:9` }), {
      validator: v,
      licenseToken: licenseToken(v, 0), // bound to :0, manifest claims :9
      loaderPubKey: LOADER_PUBKEY,
      cartridgePageFlag: PAGE,
      spv,
    });
    expect(r.licensed).toBe(false);
  });

  test('K15d: wrong loader pubkey (≠ holder subject) ⇒ rejected', async () => {
    const v = new CapabilityTokenValidator(store());
    const spv = new MonotoneSpendOracle().spvContext(aliveVerifier, 'beef');
    const r = await verifyCartridgeLicense(manifest(), {
      validator: v,
      licenseToken: licenseToken(v),
      loaderPubKey: '-----BEGIN PUBLIC KEY-----\nATTACKER\n-----END PUBLIC KEY-----',
      cartridgePageFlag: PAGE,
      spv,
    });
    expect(r.licensed).toBe(false);
  });

  test('fail-closed: no licenseOutpointRef ⇒ unlicensed (rejected)', async () => {
    const v = new CapabilityTokenValidator(store());
    const r = await verifyCartridgeLicense(manifest({ licenseOutpointRef: undefined }), {
      validator: v,
      loaderPubKey: LOADER_PUBKEY,
      cartridgePageFlag: PAGE,
    });
    expect(r.licensed).toBe(false);
    if (!r.licensed) expect(r.reason).toContain('unlicensed');
  });

  test('escape hatch: no licenseOutpointRef + allowUnlicensed ⇒ admitted', async () => {
    const v = new CapabilityTokenValidator(store());
    const r = await verifyCartridgeLicense(manifest({ licenseOutpointRef: undefined }), {
      validator: v,
      loaderPubKey: LOADER_PUBKEY,
      cartridgePageFlag: PAGE,
      allowUnlicensed: true,
    });
    expect(r.licensed).toBe(true);
  });

  test('non-AFFINE licenseLinearity ⇒ rejected', async () => {
    const v = new CapabilityTokenValidator(store());
    const spv = new MonotoneSpendOracle().spvContext(aliveVerifier, 'beef');
    const r = await verifyCartridgeLicense(
      manifest({ licenseLinearity: 'RELEVANT' as unknown as 'AFFINE' }),
      {
        validator: v,
        licenseToken: licenseToken(v),
        loaderPubKey: LOADER_PUBKEY,
        cartridgePageFlag: PAGE,
        spv,
      },
    );
    expect(r.licensed).toBe(false);
  });
});

describe('ExtensionLoader opt-in license hook (non-breaking)', () => {
  function fakeStorage(manifestJson: string) {
    return {
      read: async (k: string) =>
        k.endsWith('config.json') ? new TextEncoder().encode(manifestJson) : null,
    } as unknown as ConstructorParameters<typeof ExtensionLoader>[0];
  }

  test('gate unset ⇒ loader behaviour unchanged (license not enforced)', async () => {
    const loader = new ExtensionLoader(fakeStorage(JSON.stringify(manifest())));
    // No gate set: loadExtension proceeds past 1.5 (fails later on the
    // missing taxonomy, NOT on licensing) — proves the hook is opt-in.
    await expect(loader.loadExtension('ext/oddjobz')).rejects.toThrow(ExtensionLoadError);
    try {
      await loader.loadExtension('ext/oddjobz');
    } catch (e) {
      expect((e as ExtensionLoadError).message).not.toContain('license');
    }
  });

  test('gate set + throws ⇒ loadExtension rejects with ExtensionLoadError before taxonomy', async () => {
    const loader = new ExtensionLoader(fakeStorage(JSON.stringify(manifest())));
    loader.setLicenseGate(async () => {
      throw new ExtensionLoadError('unlicensed cartridge', 'MANIFEST_INVALID', 'ext/oddjobz');
    });
    await expect(loader.loadExtension('ext/oddjobz')).rejects.toThrow('unlicensed cartridge');
  });
});

```
