---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/test/spv-verifier.conformance.spec.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.664835+00:00
---

# cartridges/wallet-headers/brain/test/spv-verifier.conformance.spec.ts

```ts
/**
 * CC1 conformance — the wallet/headers infra cartridge's real
 * SpvVerifier, and the cap-UTXO path consuming it.
 *
 * Ref: docs/canon/commissions/wave-canonical-cartridge.md CC1 (the
 * keystone). Proves: (a) HeadersSpvVerifier verifies a real BEEF
 * against a trusted PoW root via the local beef-codec path; (b)
 * fail-closed when the root isn't trusted; (c) the SHIPPED
 * CapabilityTokenValidator.checkCapability authorizes an unspent cap
 * when given an SpvContext backed by this REAL verifier — i.e. the
 * documented TS SpvContext stub-debt is retired (the analogue of the
 * Phase-1 K15a-positive Zig proof, now on the TS cap-license path).
 *
 * The BEEF is the SAME canonical BRC-62 vector Phase-1 proved in Zig
 * (read from the Phase-1 fixture — single source, no transcription).
 */

import { describe, test, expect } from 'bun:test';
import { readFileSync } from 'fs';
import { join } from 'path';
import {
  parseBeef,
  computeMerkleRoot,
  hexFromBytes,
  bytesFromHex,
  reverseTxid,
} from '../src/beef-codec';
import { HeadersSpvVerifier } from '../src/spv-verifier';
import {
  CapabilityTokenValidator,
  MonotoneSpendOracle,
  PERMISSION_GRANT_DERIVATION,
} from '../../../core/protocol-types/src/identity-adapters/CapabilityTokenValidator';
import type {
  CertChainStore,
  CertData,
} from '../../../core/protocol-types/src/identity-adapters/CertChainStore';

const REPO = join(import.meta.dir, '..', '..', '..');

/** The canonical BRC-62 BEEF vector, taken verbatim from the Phase-1
 *  K15a-positive fixture (single source of the proven vector). */
function brc62Hex(): string {
  const src = readFileSync(
    join(REPO, 'runtime/semantos-brain/tests/k15a_positive_conformance.zig'),
    'utf-8',
  );
  const m = src.match(/"(0100beef[0-9a-f]+)"/);
  if (!m) throw new Error('BRC-62 vector not found in Phase-1 fixture');
  return m[1];
}

/** Parse the vector → the mined tx (has a BUMP) + its computed root. */
function minedTxAndRoot(hex: string) {
  const parsed = parseBeef(bytesFromHex(hex));
  const tx = parsed.txs.find((t) => t.bumpIndex !== null);
  if (!tx || tx.bumpIndex === null) throw new Error('no mined tx in BEEF');
  const root = computeMerkleRoot(parsed.bumps[tx.bumpIndex]!, tx.txid);
  return {
    rootHex: hexFromBytes(root),
    displayTxid: hexFromBytes(reverseTxid(tx.txid)),
  };
}

describe('CC1 — wallet/headers infra cartridge SpvVerifier', () => {
  const hex = brc62Hex();
  const { rootHex, displayTxid } = minedTxAndRoot(hex);

  test('verifyBeef ⇒ true when the BUMP root is trusted (real beef-codec path)', async () => {
    const v = new HeadersSpvVerifier((r) => r === rootHex);
    expect(await v.verifyBeef(hex, displayTxid)).toBe(true);
  });

  test('fail-closed: root not trusted ⇒ false', async () => {
    const v = new HeadersSpvVerifier(() => false);
    expect(await v.verifyBeef(hex, displayTxid)).toBe(false);
  });

  test('fail-closed: garbage BEEF ⇒ false (no throw)', async () => {
    const v = new HeadersSpvVerifier(() => true);
    expect(await v.verifyBeef('deadbeef', displayTxid)).toBe(false);
    expect(await v.verifyBeef(hex, 'f'.repeat(64))).toBe(false); // txid absent
  });

  test('cap-UTXO path consumes the REAL verifier (TS SpvContext stub-debt retired)', async () => {
    const HOLDER = '-----BEGIN PUBLIC KEY-----\nNODE\n-----END PUBLIC KEY-----';
    const holder: CertData = {
      certId: 'h1',
      publicKey: HOLDER,
      domainFlags: [],
      created: 0,
      revoked: false,
    };
    const store = {
      get: async (id: string) => (id === 'h1' ? holder : null),
    } as unknown as CertChainStore;
    const v = new CapabilityTokenValidator(store);
    const PAGE = 0x00010101; // registered ODDJOBZ capability page | 0x01
    const token = v.createBrc108Token(
      {
        outpoint: { txid: displayTxid, vout: 0 },
        issuerCertId: 'i1',
        holderCertId: 'h1',
        domainFlag: PAGE,
        issuerDerivationDomain: PERMISSION_GRANT_DERIVATION,
        expiry: Date.now() + 60_000,
      },
      new Uint8Array(32).fill(7),
    );
    const real = new HeadersSpvVerifier((r) => r === rootHex);
    const spv = {
      verifier: real,
      beef: hex,
      isOutpointSpent: async () => false,
    };
    const r = await v.checkCapability(token, HOLDER, PAGE, spv);
    // Authorized ONLY because the real HeadersSpvVerifier verified the
    // BEEF against the trusted root — not a stub.
    expect(r.authorized).toBe(true);

    // And spent ⇒ revoked (kill path still holds with the real verifier).
    const oracle = new MonotoneSpendOracle();
    oracle.markSpent({ txid: displayTxid, vout: 0 });
    const r2 = await v.checkCapability(token, HOLDER, PAGE, {
      verifier: real,
      beef: hex,
      isOutpointSpent: oracle.isSpent,
    });
    expect(r2.authorized).toBe(false);
  });
});

```
