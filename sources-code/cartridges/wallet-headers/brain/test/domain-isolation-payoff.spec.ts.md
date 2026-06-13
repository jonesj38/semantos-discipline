---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/test/domain-isolation-payoff.spec.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.666698+00:00
---

# cartridges/wallet-headers/brain/test/domain-isolation-payoff.spec.ts

```ts
// L11.5 payoff — cross-domain KEY isolation (docs/canon/domainflag-tag-unification.md §3 step 6).
//
// The cutover's security claim: folding the canonical u32 `domainFlag` into the
// derivation tweak makes `OP_CHECKDOMAINFLAG` transitively gate the *derived
// key*, not just the cell at rest. Concretely: "a key derived for domain X can
// no longer be replayed to authorize a cell flagged domain Y."
//
// The cell-level half (a domain-Y cell rejects a presented domain-X flag) is the
// pre-existing, machine-proven K3 property (proofs/lean/.../DomainIsolationK3.lean;
// modelled in cartridges/oddjobz/brain/tests/capabilities.test.ts). What L11.5
// ADDS — and what this test verifies — is the KEY half: the same parent identity
// key yields *different, non-interchangeable* spending keys per domain, and those
// domains are the SAME u32 the runtime gate checks. The two previously-
// incompatible encodings (derivation segment vs registry u32) now share one
// vocabulary, so the binding is end-to-end.

import { describe, expect, test } from 'bun:test';
import * as secp from '@noble/secp256k1';

import {
  deriveCellAnchorSk,
  domainFlagFromTypeHash,
} from '../src/cell-anchor';
import { deriveChangeSk, CHANGE_DOMAIN_FLAG } from '../src/ecdh42';
import { pubkeyToHash160, buildP2pkhLock } from '../src/tx-builder';

const hex = (b: Uint8Array): string =>
  Array.from(b).map((x) => x.toString(16).padStart(2, '0')).join('');

/**
 * Faithful model of the cell-engine `OP_CHECKDOMAINFLAG` opcode
 * (core/cell-engine/src/opcodes/plexus.zig `opCheckDomainFlag`): the cell's
 * header `domainFlag` must equal the flag presented on the stack. This is the
 * K3 gate; reproduced here only to tie the derivation tag to the runtime check.
 */
function opCheckDomainFlag(cellDomainFlag: number, presentedFlag: number): boolean {
  return cellDomainFlag === presentedFlag;
}

describe('L11.5 payoff — key↔domain binding (cross-domain replay fails)', () => {
  // One operator identity; two distinct cell-type domains, X and Y.
  const identitySk = secp.utils.randomPrivateKey();
  const typeHashX = secp.utils.randomPrivateKey(); // 32 random bytes as a type_hash
  const typeHashY = secp.utils.randomPrivateKey();
  const anchorIndex = 0;

  const flagX = domainFlagFromTypeHash(typeHashX);
  const flagY = domainFlagFromTypeHash(typeHashY);

  test('the two domains map to distinct canonical u32 flags', () => {
    expect(flagX).not.toBe(flagY);
    // Both sit in the client-defined sovereign band (0x00010000+).
    expect(flagX).toBeGreaterThanOrEqual(0x00010000);
    expect(flagY).toBeGreaterThanOrEqual(0x00010000);
  });

  test('cell gate (K3): a domain-Y cell rejects domain X’s flag', () => {
    // Pre-existing property — restated here so the payoff is self-contained.
    expect(opCheckDomainFlag(flagY, flagY)).toBe(true); // legitimate
    expect(opCheckDomainFlag(flagY, flagX)).toBe(false); // replay rejected
  });

  test('NEW (L11.5): the anchor key for domain X ≠ the key for domain Y', () => {
    const skX = deriveCellAnchorSk(identitySk, typeHashX, anchorIndex);
    const skY = deriveCellAnchorSk(identitySk, typeHashY, anchorIndex);
    expect(skX).not.toBeNull();
    expect(skY).not.toBeNull();
    // Same parent, same index — different domain ⇒ different key.
    expect(hex(skX!)).not.toBe(hex(skY!));
  });

  test('replay fails at the lock: domain-X key cannot satisfy a domain-Y anchor lock', () => {
    // The Y-cell's anchor output is locked to the Y-domain key.
    const skY = deriveCellAnchorSk(identitySk, typeHashY, anchorIndex)!;
    const lockY = buildP2pkhLock(pubkeyToHash160(secp.getPublicKey(skY, true)));

    // An attacker legitimately holds the X-domain key (derived for a cell they
    // DO control). Its pubkey hashes to a different P2PKH — it cannot satisfy
    // lockY, so the Y-cell's anchor UTXO is unspendable with the X-key.
    const skX = deriveCellAnchorSk(identitySk, typeHashX, anchorIndex)!;
    const lockFromX = buildP2pkhLock(pubkeyToHash160(secp.getPublicKey(skX, true)));

    expect(hex(lockFromX)).not.toBe(hex(lockY));
  });

  test('cross-domain isolation extends to the CHANGE domain (0x0b)', () => {
    // The change key (flag 0x0b) is also non-interchangeable with anchor keys,
    // even at the same index — distinct domains, distinct keys.
    const changeSk = deriveChangeSk(identitySk, anchorIndex)!;
    const anchorSk = deriveCellAnchorSk(identitySk, typeHashX, anchorIndex)!;
    expect(CHANGE_DOMAIN_FLAG).toBe(0x0b);
    expect(flagX).not.toBe(CHANGE_DOMAIN_FLAG);
    expect(hex(changeSk)).not.toBe(hex(anchorSk));
  });
});

```
