---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/plexus-vendor-sdk/src/__tests__/derive-segment.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.019948+00:00
---

# core/plexus-vendor-sdk/src/__tests__/derive-segment.test.ts

```ts
/**
 * CW Lift L11 — EP3259724B1 base derivation primitive.
 *
 * Proves that the foundation primitive `deriveSegment` / `deriveScalar` can
 * express BRC-42 (`deriveChildKey`) as a one-line composition. This anchors
 * the matrix claim that "BRC-42 is the bilateral specialisation of
 * EP3259724B1" — verified by byte-equal output.
 *
 * Reference: docs/canon/cw-lift-matrix.yml L11; docs/prd/CW-LIFT-ROADMAP.md §2.2.
 */

import { describe, expect, test } from 'bun:test';
import PrivateKey from '@bsv/sdk/primitives/PrivateKey';
import { sha256, sha256hmac } from '@bsv/sdk/primitives/Hash';
import {
  deriveChildKey,
  deriveScalar,
  deriveScalarPub,
  deriveSegment,
  deriveSegmentPub,
} from '../crypto';

// Deterministic 32-byte parent scalar for KAT.
const PARENT_HEX = 'e9873d79c6d87dc0fb6a5778633389f4453213303da61f20bd67fc233aa33262';

describe('CW Lift L11: deriveSegment + deriveScalar foundation primitives', () => {
  test('deriveSegment produces a different child for each segment string', () => {
    const parent = PrivateKey.fromString(PARENT_HEX, 'hex');
    const childA = deriveSegment(parent, 'cartridge/oddjobz/account/1');
    const childB = deriveSegment(parent, 'cartridge/oddjobz/account/2');
    expect(childA.toString('hex')).not.toBe(childB.toString('hex'));
    expect(childA.toString('hex')).not.toBe(parent.toString('hex'));
  });

  test('deriveSegment is deterministic (same segment → same child)', () => {
    const parent = PrivateKey.fromString(PARENT_HEX, 'hex');
    const child1 = deriveSegment(parent, 'hat/work/key/0');
    const child2 = deriveSegment(parent, 'hat/work/key/0');
    expect(child1.toString('hex')).toBe(child2.toString('hex'));
  });

  test('deriveSegment accepts Uint8Array segments equivalently to UTF-8 strings', () => {
    const parent = PrivateKey.fromString(PARENT_HEX, 'hex');
    const segmentStr = 'operator/celltree/branch/42';
    const segmentBytes = new TextEncoder().encode(segmentStr);
    const childFromStr = deriveSegment(parent, segmentStr);
    const childFromBytes = deriveSegment(parent, segmentBytes);
    expect(childFromStr.toString('hex')).toBe(childFromBytes.toString('hex'));
  });

  test('deriveScalar with sha256(segment) === deriveSegment(segment)', () => {
    const parent = PrivateKey.fromString(PARENT_HEX, 'hex');
    const segment = 'foundation/composition/check';
    const segmentBytes = Array.from(new TextEncoder().encode(segment));
    const hashBytes = sha256(segmentBytes);
    const childViaScalar = deriveScalar(parent, hashBytes);
    const childViaSegment = deriveSegment(parent, segment);
    expect(childViaScalar.toString('hex')).toBe(childViaSegment.toString('hex'));
  });

  test('BRC-42 deriveChildKey ≡ deriveScalar(parent, sha256hmac(ECDH(parent, parentPub).encode(true), utf8(invoiceNumber)))', () => {
    // This is the canonical claim of L11: BRC-42 is just EP3259724B1 with
    // segment = HMAC(ECDH-shared-secret, data). Verify byte-equal output.
    const parent = PrivateKey.fromString(PARENT_HEX, 'hex');
    const invoiceNumber = 'plexus.identity/cartridge:oddjobz/op:mint/seq:1';

    // Path 1: existing BRC-42 helper (delegates to @bsv/sdk's deriveChild)
    const childViaBrc42 = deriveChildKey(parent, invoiceNumber);

    // Path 2: composition via the foundation primitive
    const parentPub = parent.toPublicKey();
    const sharedPoint = parent.deriveSharedSecret(parentPub);
    const sharedCompressed = sharedPoint.encode(true) as number[];
    const invoiceBytes = Array.from(new TextEncoder().encode(invoiceNumber));
    const segmentBytes = sha256hmac(sharedCompressed, invoiceBytes);
    const childViaComposition = deriveScalar(parent, segmentBytes);

    expect(childViaComposition.toString('hex')).toBe(childViaBrc42.toString('hex'));
  });

  test('multiple invoice numbers compose consistently (KAT spread)', () => {
    const parent = PrivateKey.fromString(PARENT_HEX, 'hex');
    const parentPub = parent.toPublicKey();
    const sharedCompressed = parent.deriveSharedSecret(parentPub).encode(true) as number[];

    for (const inv of [
      'a',
      'plexus.identity/root',
      'cartridge:bsv-anchor-bundle/op:anchor/seq:0',
      'hat:work/account:1/index:0',
      'unicode: ✓ ⚠ ✗ 漢字',
    ]) {
      const childViaBrc42 = deriveChildKey(parent, inv);
      const invBytes = Array.from(new TextEncoder().encode(inv));
      const segmentBytes = sha256hmac(sharedCompressed, invBytes);
      const childViaComposition = deriveScalar(parent, segmentBytes);
      expect(childViaComposition.toString('hex')).toBe(childViaBrc42.toString('hex'));
    }
  });

  test('foundation primitive is curve-order-safe (mod n applied)', () => {
    // A segment whose SHA-256 happens to be very large still produces a
    // valid child in [0, n). The mod-n step inside deriveSegment ensures
    // the result is a canonical scalar.
    const parent = PrivateKey.fromString(PARENT_HEX, 'hex');
    const child = deriveSegment(parent, 'scalar-overflow-stress-test');
    const childHex = child.toString('hex');
    // secp256k1 n in hex (lowercase, 64 chars)
    const N_HEX = 'fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141';
    expect(childHex.length).toBe(64);
    expect(childHex < N_HEX).toBe(true);
  });
});

describe('CW Lift L11: deriveSegmentPub + deriveScalarPub (public-key side)', () => {
  test('deriveSegmentPub byte-equal to deriveSegment(priv).toPublicKey() — priv↔pub symmetry', () => {
    const parent = PrivateKey.fromString(PARENT_HEX, 'hex');
    const parentPub = parent.toPublicKey();
    const segments = [
      'cartridge/oddjobz/account/1',
      'hat/work/key/0',
      'unicode: ✓ ⚠ ✗ 漢字',
      'operator/celltree/branch/42',
    ];
    for (const seg of segments) {
      const childFromPriv = deriveSegment(parent, seg).toPublicKey();
      const childFromPub = deriveSegmentPub(parentPub, seg);
      expect(childFromPub.toDER('hex')).toBe(childFromPriv.toDER('hex'));
    }
  });

  test('deriveScalarPub byte-equal to deriveScalar(priv).toPublicKey() — sha256 segment case', () => {
    const parent = PrivateKey.fromString(PARENT_HEX, 'hex');
    const parentPub = parent.toPublicKey();
    const segment = 'foundation/composition/check';
    const segmentBytes = Array.from(new TextEncoder().encode(segment));
    const hashBytes = sha256(segmentBytes);
    const childFromPriv = deriveScalar(parent, hashBytes).toPublicKey();
    const childFromPub = deriveScalarPub(parentPub, hashBytes);
    expect(childFromPub.toDER('hex')).toBe(childFromPriv.toDER('hex'));
  });

  test('BRC-42 pubkey-side composition: BRC-42-priv.toPub() ≡ deriveScalarPub(parentPub, HMAC(shared, invoice))', () => {
    // The canonical claim: the device-pair flow's pubkey-side derivation
    // is just deriveScalarPub with segment = HMAC(ECDH-shared, invoice).
    const parent = PrivateKey.fromString(PARENT_HEX, 'hex');
    const parentPub = parent.toPublicKey();
    const invoiceNumber = 'plexus.identity/cartridge:oddjobz/op:device-pair/seq:1';

    // Priv-side BRC-42 (existing, unchanged delegate to @bsv/sdk's deriveChild)
    const childViaBrc42Pub = deriveChildKey(parent, invoiceNumber).toPublicKey();

    // Pub-side composition via L11 primitives
    const shared = parent.deriveSharedSecret(parentPub).encode(true) as number[];
    const invoiceBytes = Array.from(new TextEncoder().encode(invoiceNumber));
    const segmentBytes = sha256hmac(shared, invoiceBytes);
    const childViaPubComposition = deriveScalarPub(parentPub, segmentBytes);

    expect(childViaPubComposition.toDER('hex')).toBe(childViaBrc42Pub.toDER('hex'));
  });

  test('two different parents → two different child pubs for the same segment', () => {
    const parent1 = PrivateKey.fromString(PARENT_HEX, 'hex');
    const parent2 = PrivateKey.fromString(
      'aa873d79c6d87dc0fb6a5778633389f4453213303da61f20bd67fc233aa33262',
      'hex',
    );
    const child1 = deriveSegmentPub(parent1.toPublicKey(), 'shared/segment');
    const child2 = deriveSegmentPub(parent2.toPublicKey(), 'shared/segment');
    expect(child1.toDER('hex')).not.toBe(child2.toDER('hex'));
  });

  test('deriveSegmentPub deterministic — same input → same child pub', () => {
    const parent = PrivateKey.fromString(PARENT_HEX, 'hex');
    const parentPub = parent.toPublicKey();
    const a = deriveSegmentPub(parentPub, 'x');
    const b = deriveSegmentPub(parentPub, 'x');
    expect(a.toDER('hex')).toBe(b.toDER('hex'));
  });
});

```
