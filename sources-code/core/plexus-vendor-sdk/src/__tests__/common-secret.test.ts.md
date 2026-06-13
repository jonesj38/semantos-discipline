---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/plexus-vendor-sdk/src/__tests__/common-secret.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.020300+00:00
---

# core/plexus-vendor-sdk/src/__tests__/common-secret.test.ts

```ts
/**
 * L12 computeCommonSecret tests.
 *
 * Asserts:
 *   - Symmetry: Alice (myPriv, theirPub, gv) == Bob (theirPriv, myPub, gv)
 *     i.e. the va-chain "common secret" is commutative in the ECDH sense.
 *   - String + raw-scalar overloads produce the same secret as their
 *     deriveSegment / deriveScalar twins.
 *   - Different gv → different secret.
 *   - Different counterparty → different secret.
 */

import { describe, expect, test } from 'bun:test';
import PrivateKey from '@bsv/sdk/primitives/PrivateKey';
import {
  computeCommonSecret,
  computeSharedSecret,
  deriveScalar,
  deriveScalarPub,
  deriveSegment,
  deriveSegmentPub,
} from '../crypto.js';

const ALICE_HEX =
  'e9873d79c6d87dc0fb6a5778633389f4453213303da61f20bd67fc233aa33262';
const BOB_HEX =
  'aa873d79c6d87dc0fb6a5778633389f4453213303da61f20bd67fc233aa33262';
const CARLA_HEX =
  '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef';

function k(hex: string) {
  return PrivateKey.fromString(hex, 'hex');
}

describe('L12 computeCommonSecret — symmetry (Alice vs Bob)', () => {
  test('string-gv: Alice and Bob compute the same secret', () => {
    const alice = k(ALICE_HEX);
    const bob = k(BOB_HEX);
    const gv = 'tx/0042/audit-link';
    const aliceSecret = computeCommonSecret(alice, bob.toPublicKey(), gv);
    const bobSecret = computeCommonSecret(bob, alice.toPublicKey(), gv);
    expect(aliceSecret).toBe(bobSecret);
    expect(aliceSecret.length).toBe(64); // SHA-256 hex
  });

  test('raw 32-byte gv: Alice and Bob compute the same secret', () => {
    const alice = k(ALICE_HEX);
    const bob = k(BOB_HEX);
    const gv = new Uint8Array(32);
    for (let i = 0; i < 32; i++) gv[i] = (i * 7 + 3) & 0xff;
    const aliceSecret = computeCommonSecret(alice, bob.toPublicKey(), gv);
    const bobSecret = computeCommonSecret(bob, alice.toPublicKey(), gv);
    expect(aliceSecret).toBe(bobSecret);
  });
});

describe('L12 computeCommonSecret — composition equivalence', () => {
  test('string overload === computeSharedSecret(deriveSegment, deriveSegmentPub)', () => {
    const alice = k(ALICE_HEX);
    const bob = k(BOB_HEX);
    const gv = 'engagement-7';
    const direct = computeCommonSecret(alice, bob.toPublicKey(), gv);
    const composed = computeSharedSecret(
      deriveSegment(alice, gv),
      deriveSegmentPub(bob.toPublicKey(), gv),
    );
    expect(direct).toBe(composed);
  });

  test('raw-scalar overload === computeSharedSecret(deriveScalar, deriveScalarPub)', () => {
    const alice = k(ALICE_HEX);
    const bob = k(BOB_HEX);
    const gv = new Uint8Array(32);
    for (let i = 0; i < 32; i++) gv[i] = (i + 1) & 0xff;
    const direct = computeCommonSecret(alice, bob.toPublicKey(), gv);
    const composed = computeSharedSecret(
      deriveScalar(alice, gv),
      deriveScalarPub(bob.toPublicKey(), gv),
    );
    expect(direct).toBe(composed);
  });
});

describe('L12 computeCommonSecret — distinct domains', () => {
  test('different gv → different secret (same parties)', () => {
    const alice = k(ALICE_HEX);
    const bob = k(BOB_HEX);
    const s1 = computeCommonSecret(alice, bob.toPublicKey(), 'gv-A');
    const s2 = computeCommonSecret(alice, bob.toPublicKey(), 'gv-B');
    expect(s1).not.toBe(s2);
  });

  test('different counterparty → different secret (same gv)', () => {
    const alice = k(ALICE_HEX);
    const bob = k(BOB_HEX);
    const carla = k(CARLA_HEX);
    const gv = 'shared';
    const aliceBob = computeCommonSecret(alice, bob.toPublicKey(), gv);
    const aliceCarla = computeCommonSecret(alice, carla.toPublicKey(), gv);
    expect(aliceBob).not.toBe(aliceCarla);
  });
});

```
