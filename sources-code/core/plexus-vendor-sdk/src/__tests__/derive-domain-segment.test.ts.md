---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/plexus-vendor-sdk/src/__tests__/derive-domain-segment.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.019658+00:00
---

# core/plexus-vendor-sdk/src/__tests__/derive-domain-segment.test.ts

```ts
/**
 * CW Lift L11.5 — domain-separated EP3259724B1 derivation (kdf-v3).
 *
 * Proves `deriveDomainSegment` folds the canonical u32 domain flag into the
 * derivation tweak as `SHA-256(u32_be(domainFlag) ‖ segment)`, matching
 * prof-faustus/bsv-universal-sdk pay-to-contract `H(tag ‖ m)`. These KAT
 * vectors are the cross-language pin shared with `derive_segment.zig`
 * (`deriveDomainSegment` / `deriveDomainSegmentPub`).
 *
 * Reference: docs/canon/domainflag-tag-unification.md; cw-lift-matrix.yml L11.
 */

import { describe, expect, test } from 'bun:test';
import PrivateKey from '@bsv/sdk/primitives/PrivateKey';
import {
  KDF_VERSION_DOMAIN,
  deriveDomainSegment,
  deriveDomainSegmentPub,
  deriveSegment,
} from '../crypto';

// Same deterministic parent as the L11 KAT, for continuity.
const PARENT_HEX = 'e9873d79c6d87dc0fb6a5778633389f4453213303da61f20bd67fc233aa33262';

// Cross-language KAT — flag is a canonical u32 from constants.json.
// Mirrored verbatim in runtime/semantos-brain/src/derive_segment.zig.
const KATS = [
  {
    flag: 0x0001fe02, // DOMAIN_FLAG_ANCHOR_ATTESTATION_V1
    seg: 'cell-anchor:proto:0',
    priv: '516161dcf39159f3a623ebf8f407bf41fba035659ab5abe3f43c0387fbeab001',
    pub: '02845fdac3eb00a50701436ec29b59d76d44e34257918c5bef0c89777b27117bcc',
  },
  {
    flag: 0x00000002, // DOMAIN_FLAG_SIGNING
    seg: 'hat/work/key/0',
    priv: 'b19514d3fb750ab7beb418ae18e414862248cfbd480922b1094ae20921a8e64b',
    pub: '03ed612f2956a557a6dd15854f48e02e605af3647558848588f05bf0243f1127cb',
  },
  {
    flag: 0x0001fe03, // DOMAIN_FLAG_SCG_RELATION_V1
    seg: 'scg:rel:42',
    priv: '118d5b01a891d8f266eb5a9184ce6b38f1b2f77fc7b4f3f5ff9210d16b73802a',
    pub: '027d197769b53b3b68588015395a2082d3e69ab6d8ad8952bf0c379b94ef06b95d',
  },
];

describe('CW Lift L11.5: deriveDomainSegment (kdf-v3)', () => {
  test('version marker is plexus-kdf-v3', () => {
    expect(KDF_VERSION_DOMAIN).toBe('plexus-kdf-v3');
  });

  test('KAT — private side is pinned (cross-language vector)', () => {
    const parent = PrivateKey.fromString(PARENT_HEX, 'hex');
    for (const k of KATS) {
      const child = deriveDomainSegment(parent, k.flag, k.seg);
      expect(child.toString('hex')).toBe(k.priv);
    }
  });

  test('KAT — public side matches private side and the pinned compressed pub', () => {
    const parent = PrivateKey.fromString(PARENT_HEX, 'hex');
    const parentPub = parent.toPublicKey();
    for (const k of KATS) {
      const fromPriv = deriveDomainSegment(parent, k.flag, k.seg).toPublicKey();
      const fromPub = deriveDomainSegmentPub(parentPub, k.flag, k.seg);
      expect(fromPriv.toString('hex')).toBe(fromPub.toString('hex')); // priv↔pub symmetry
      expect(fromPub.toString('hex')).toBe(k.pub);
    }
  });

  test('domain-sensitive — same segment, different flag → different key', () => {
    const parent = PrivateKey.fromString(PARENT_HEX, 'hex');
    const a = deriveDomainSegment(parent, 1, 'same');
    const b = deriveDomainSegment(parent, 2, 'same');
    expect(a.toString('hex')).not.toBe(b.toString('hex'));
  });

  test('v3 differs from v2 deriveSegment for the same segment', () => {
    const parent = PrivateKey.fromString(PARENT_HEX, 'hex');
    const v2 = deriveSegment(parent, 'hat/work/key/0');
    const v3 = deriveDomainSegment(parent, 0x00000002, 'hat/work/key/0');
    expect(v2.toString('hex')).not.toBe(v3.toString('hex'));
  });

  test('deterministic — same inputs → same child', () => {
    const parent = PrivateKey.fromString(PARENT_HEX, 'hex');
    const a = deriveDomainSegment(parent, 0x0001fe02, 'x');
    const b = deriveDomainSegment(parent, 0x0001fe02, 'x');
    expect(a.toString('hex')).toBe(b.toString('hex'));
  });

  test('rejects non-u32 domainFlag', () => {
    const parent = PrivateKey.fromString(PARENT_HEX, 'hex');
    expect(() => deriveDomainSegment(parent, -1, 'x')).toThrow(RangeError);
    expect(() => deriveDomainSegment(parent, 0x1_0000_0000, 'x')).toThrow(RangeError);
    expect(() => deriveDomainSegment(parent, 1.5, 'x')).toThrow(RangeError);
  });
});

```
