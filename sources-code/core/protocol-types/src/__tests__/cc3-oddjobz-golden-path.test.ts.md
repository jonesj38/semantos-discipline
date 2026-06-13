---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/__tests__/cc3-oddjobz-golden-path.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.883591+00:00
---

# core/protocol-types/src/__tests__/cc3-oddjobz-golden-path.test.ts

```ts
/**
 * CC3 — oddjobz golden path (Wave Canonical-Cartridge acceptance gate).
 *
 * Ref: docs/canon/commissions/wave-canonical-cartridge.md CC3.
 *
 * Proves the canonical cartridge model holds end-to-end across BOTH
 * shells for the first cartridge, against the REAL composed seams (no
 * stubs):
 *
 *  1. Brain-shell load order: the resolver (CC2a) orders the
 *     wallet/headers INFRA cartridge before the oddjobz EXPERIENCE
 *     cartridge, from their REAL manifests.
 *  2. C3 binding: oddjobz's real manifest validates with
 *     role=experience + experience.flutterPackage.
 *  3. License gate consumes CC1's REAL SpvVerifier: verifyCartridgeLicense
 *     authorizes oddjobz when its license UTXO is unspent (HeadersSpvVerifier
 *     over the canonical BRC-62 vector — the same one Phase-1 proved in
 *     Zig) and rejects when spent (kill-switch) — NOT a stub.
 *  4. Cross-shell contract: the id the Brain serves == the id the PWA
 *     CartridgeRegistry routes (the seam; the Dart half asserts the
 *     registry — see apps/semantos test).
 *
 * Honest boundary: a literal live Zig-brain ⇄ Flutter HTTP round-trip
 * is a manual/e2e step (cannot boot the daemon + app + network in a
 * unit). This conformance proves the *composition is consistently
 * wired across both shells via the shared contract* — the unit-level
 * acceptance gate; the live round-trip is documented, not faked.
 */

import { describe, test, expect } from 'bun:test';
import { readFileSync } from 'fs';
import { join } from 'path';
import { ExtensionLoader } from '../extension-loader';
import { validateExtensionManifest } from '../extension-manifest';
import { verifyCartridgeLicense } from '../identity-adapters/cartridge-license';
import {
  CapabilityTokenValidator,
  MonotoneSpendOracle,
  PERMISSION_GRANT_DERIVATION,
} from '../identity-adapters/CapabilityTokenValidator';
import type { CertChainStore, CertData } from '../identity-adapters/CertChainStore';
import {
  parseBeef,
  computeMerkleRoot,
  hexFromBytes,
  bytesFromHex,
  reverseTxid,
} from '../../../../cartridges/wallet-headers/brain/src/beef-codec';
import { HeadersSpvVerifier } from '../../../../cartridges/wallet-headers/brain/src/spv-verifier';

const REPO = join(import.meta.dir, '..', '..', '..', '..');

function readManifest(p: string): Record<string, unknown> {
  return JSON.parse(readFileSync(join(REPO, p), 'utf-8'));
}

/** Canonical BRC-62 vector (verbatim from the Phase-1 fixture) + its
 *  mined txid / computed BUMP root — the real SPV inputs. */
function brc62() {
  const src = readFileSync(
    join(REPO, 'runtime/semantos-brain/tests/k15a_positive_conformance.zig'),
    'utf-8',
  );
  const hex = src.match(/"(0100beef[0-9a-f]+)"/)![1];
  const parsed = parseBeef(bytesFromHex(hex));
  const tx = parsed.txs.find((t) => t.bumpIndex !== null)!;
  const root = computeMerkleRoot(parsed.bumps[tx.bumpIndex!]!, tx.txid);
  return {
    hex,
    rootHex: hexFromBytes(root),
    displayTxid: hexFromBytes(reverseTxid(tx.txid)),
  };
}

describe('CC3 — oddjobz golden path (both shells, real seams)', () => {
  const oddjobz = readManifest('cartridges/oddjobz/cartridge.json');
  const walletHeaders = readManifest('cartridges/wallet-headers/cartridge.json');

  test('1. Brain-shell resolver orders infra(wallet-headers) → experience(oddjobz)', () => {
    const { order, providesRegistry } = ExtensionLoader.resolveCartridgeOrder([
      {
        id: oddjobz.id as string,
        role: oddjobz.role as 'experience',
        consumes: oddjobz.consumes as Record<string, unknown>,
      },
      {
        id: walletHeaders.id as string,
        role: walletHeaders.role as 'infra',
        provides: walletHeaders.provides as string[],
      },
    ]);
    expect(order).toEqual(['wallet-headers', 'oddjobz']);
    expect(providesRegistry.size).toBeGreaterThan(0);
  });

  test('2. C3 binding: oddjobz manifest validates with role + experience', () => {
    expect(() => validateExtensionManifest(oddjobz)).not.toThrow();
    expect(oddjobz.role).toBe('experience');
    expect((oddjobz.experience as { flutterPackage: string }).flutterPackage).toBe(
      'packages/oddjobz_experience',
    );
  });

  test('3. license gate consumes CC1 REAL SpvVerifier: unspent ⇒ licensed', async () => {
    const { hex, rootHex, displayTxid } = brc62();
    const HOLDER = '-----BEGIN PUBLIC KEY-----\nOWNER\n-----END PUBLIC KEY-----';
    const holder: CertData = {
      certId: 'oj-owner',
      publicKey: HOLDER,
      domainFlags: [],
      created: 0,
      revoked: false,
    };
    const store = {
      get: async (id: string) => (id === 'oj-owner' ? holder : null),
    } as unknown as CertChainStore;
    const v = new CapabilityTokenValidator(store);
    const PAGE = 0x00010101; // registered ODDJOBZ capability page
    const token = v.createBrc108Token(
      {
        outpoint: { txid: displayTxid, vout: 0 },
        issuerCertId: 'oj-issuer',
        holderCertId: 'oj-owner',
        domainFlag: PAGE,
        issuerDerivationDomain: PERMISSION_GRANT_DERIVATION,
        expiry: Date.now() + 60_000,
      },
      new Uint8Array(32).fill(7),
    );
    const realVerifier = new HeadersSpvVerifier((r) => r === rootHex);
    const manifestWithLicense = {
      ...oddjobz,
      licenseOutpointRef: `${displayTxid}:0`,
    } as unknown as Parameters<typeof verifyCartridgeLicense>[0];

    const ok = await verifyCartridgeLicense(manifestWithLicense, {
      validator: v,
      licenseToken: token,
      loaderPubKey: HOLDER,
      cartridgePageFlag: PAGE,
      spv: { verifier: realVerifier, beef: hex, isOutpointSpent: async () => false },
    });
    expect(ok.licensed).toBe(true);

    // kill-switch: spend the license UTXO ⇒ NOT licensed (real path).
    const oracle = new MonotoneSpendOracle();
    oracle.markSpent({ txid: displayTxid, vout: 0 });
    const killed = await verifyCartridgeLicense(manifestWithLicense, {
      validator: v,
      licenseToken: token,
      loaderPubKey: HOLDER,
      cartridgePageFlag: PAGE,
      spv: { verifier: realVerifier, beef: hex, isOutpointSpent: oracle.isSpent },
    });
    expect(killed.licensed).toBe(false);
  });

  test('3b. first-party oddjobz (no on-chain license yet) loads via escape hatch', async () => {
    const v = new CapabilityTokenValidator({
      get: async () => null,
    } as unknown as CertChainStore);
    const r = await verifyCartridgeLicense(
      oddjobz as unknown as Parameters<typeof verifyCartridgeLicense>[0],
      { validator: v, loaderPubKey: 'x', cartridgePageFlag: 0x00010101, allowUnlicensed: true },
    );
    expect(r.licensed).toBe(true); // unanchored first-party path (marketplace doc §6)
  });

  test('4. cross-shell contract: Brain manifest id == PWA registry id', () => {
    // The Brain serves this id (/api/v1/info cartridges[].id); the PWA
    // CartridgeRegistry routes the SAME id (asserted Dart-side in
    // apps/semantos). The shared constant is the seam.
    expect(oddjobz.id).toBe('oddjobz');
  });
});

```
