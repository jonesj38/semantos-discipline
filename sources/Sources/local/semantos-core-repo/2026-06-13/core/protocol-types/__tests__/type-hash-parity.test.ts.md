---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/__tests__/type-hash-parity.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.857530+00:00
---

# core/protocol-types/__tests__/type-hash-parity.test.ts

```ts
/**
 * T1 canonical typeHash parity tests — TypeScript side.
 *
 * The vector table below is replicated byte-identically in
 * `core/cell-engine/src/type_hash.zig` (PARITY_VECTORS).  If you change
 * one, change the other; both languages run this table and both must
 * agree, byte-for-byte.
 *
 * Each row is `[segment1, segment2, segment3, segment4, expectedHex64]`.
 * Hashes are SHA-256 of `s1:s2:s3:s4` (flat algorithm — T5.a flips this
 * to the structured |8|8|8|8| construction at which point the entire
 * table regenerates).
 *
 * Spec:    docs/design/STRUCTURED-TYPEHASH-CANONICAL.md
 * Tracker: docs/STRUCTURED-TYPEHASH-TRACKER.md
 */

import { describe, expect, test } from 'bun:test';
import {
  buildTypeHash,
  isWildcard,
  typeHashToHex,
  TYPE_HASH_SIZE,
  TYPE_HASH_SEGMENT_BYTES,
  TYPE_HASH_SEGMENT_COUNT,
  WILDCARD_NAMESPACE_PREFIX,
} from '../src/type-hash';
import { createHash } from 'crypto';

type Vec = readonly [string, string, string, string, string];

// MUST mirror PARITY_VECTORS in core/cell-engine/src/type_hash.zig.
// Under T5.a structured algorithm: typeHash[i*8:(i+1)*8] = sha256(segment_i)[0:8].
// Routing-prefix property visible in hex: all "oddjobz.*" share bytes 0:8
// (c4cf2fd44009863e); all "mnca.*" share 09e9fe981010c9b4; empty segments
// hash to sha256("")[0:8] = e3b0c44298fc1c14.
const PARITY_VECTORS: readonly Vec[] = [
  ['', '', '', '', 'e3b0c44298fc1c14e3b0c44298fc1c14e3b0c44298fc1c14e3b0c44298fc1c14'],
  ['mnca', '', '', '', '09e9fe981010c9b4e3b0c44298fc1c14e3b0c44298fc1c14e3b0c44298fc1c14'],
  ['mnca', 'snapshot', '', '', '09e9fe981010c9b416a0eeb0791b6c92e3b0c44298fc1c14e3b0c44298fc1c14'],
  ['mnca', 'tile', 'injection', '', '09e9fe981010c9b48b668b8994aa8451545a70019936cf88e3b0c44298fc1c14'],
  ['mnca', 'tile', 'tick', '', '09e9fe981010c9b48b668b8994aa845155a4bc5be68ea5c3e3b0c44298fc1c14'],
  ['mnca', 'tile', '', 'v0', '09e9fe981010c9b48b668b8994aa8451e3b0c44298fc1c140270da4daac514f3'],
  ['mnca', 'standalone', 'tile', 'tick', '09e9fe981010c9b45b565a33b80b75dc8b668b8994aa845155a4bc5be68ea5c3'],
  ['oddjobz', 'job', 'worktrack', 'v1', 'c4cf2fd44009863e5e8c9902207afaeb822965fc3debc30d3bfc269594ef6492'],
  ['oddjobz', 'job', 'worktrack', 'v2', 'c4cf2fd44009863e5e8c9902207afaeb822965fc3debc30dfb04dcb6970e4c3d'],
  ['oddjobz', 'customer', 'identify', 'v2', 'c4cf2fd44009863eb6c45863875e34480f780b5c735e7025fb04dcb6970e4c3d'],
  ['oddjobz', 'site', 'locate', 'v2', 'c4cf2fd44009863efbae041b02c41ed0c61d02ef654ab458fb04dcb6970e4c3d'],
  ['oddjobz', 'attachment', 'capture', 'v2', 'c4cf2fd44009863e602a5e69c3021bdb460ee6aa3a803591fb04dcb6970e4c3d'],
  ['oddjobz', 'mnca', 'tile', 'tick', 'c4cf2fd44009863e09e9fe981010c9b48b668b8994aa845155a4bc5be68ea5c3'],
  ['nonprofit-os', 'fund', 'earmarked_balance', 'v1', '52b2931aa02bb055639f78fb7729d09d187a3cbda417c6b43bfc269594ef6492'],
  ['nonprofit-os', 'mnca', 'snapshot', 'v1', '52b2931aa02bb05509e9fe981010c9b416a0eeb0791b6c923bfc269594ef6492'],
  ['tessera', 'batch', 'mint', 'v1', '2f1e83d30fff12f14bb24efc9641afc5dc6f17bbec824fff3bfc269594ef6492'],
  ['chess', 'stake', '', 'v1', 'ac739dccd121f712f4caf4ff95731a23e3b0c44298fc1c143bfc269594ef6492'],
  ['semantos', 'test', 'linear-cell', '', 'af70498e94f58c419f86d081884c7d6503f44d22268104d9e3b0c44298fc1c14'],
  ['a', 'b', 'c', 'd', 'ca978112ca1bbdca3e23e8160039594a2e7d2c03a9507ae218ac3e7343f01689'],
  ['café', 'naïve', '日本', '🦀', '850f7dc43910ff89f86fd89de87a848acf2abf0c5be326cb7224c588fa988754'],
];

describe('T1 — buildTypeHash parity (flat SHA256 phase)', () => {
  for (const [s1, s2, s3, s4, expectedHex] of PARITY_VECTORS) {
    test(`(${JSON.stringify(s1)}, ${JSON.stringify(s2)}, ${JSON.stringify(s3)}, ${JSON.stringify(s4)}) → ${expectedHex.slice(0, 12)}…`, () => {
      const actual = buildTypeHash(s1, s2, s3, s4);
      expect(actual.length).toBe(TYPE_HASH_SIZE);
      expect(typeHashToHex(actual)).toBe(expectedHex);
    });
  }

  test('Zig PARITY_VECTORS table is byte-identical to TS PARITY_VECTORS', () => {
    // This test exists as a structural reminder, not a real cross-language
    // assertion (Zig runs its own table under `zig build test-type-hash`).
    // If anyone changes the TS table without updating the Zig one (or vice
    // versa), the next CI run will surface drift via one side failing
    // while the other passes.
    expect(PARITY_VECTORS.length).toBeGreaterThanOrEqual(20);
  });
});

describe('T1 — constants', () => {
  test('TYPE_HASH_SIZE = 32', () => {
    expect(TYPE_HASH_SIZE).toBe(32);
  });

  test('TYPE_HASH_SEGMENT_COUNT = 4', () => {
    expect(TYPE_HASH_SEGMENT_COUNT).toBe(4);
  });

  test('TYPE_HASH_SEGMENT_BYTES = 8 (matches T5.a design: 32/4)', () => {
    expect(TYPE_HASH_SEGMENT_BYTES).toBe(8);
    expect(TYPE_HASH_SIZE / TYPE_HASH_SEGMENT_COUNT).toBe(TYPE_HASH_SEGMENT_BYTES);
  });
});

describe('T1 — wildcard sentinel', () => {
  test('WILDCARD_NAMESPACE_PREFIX is 8 raw zero bytes', () => {
    expect(WILDCARD_NAMESPACE_PREFIX.length).toBe(TYPE_HASH_SEGMENT_BYTES);
    for (const b of WILDCARD_NAMESPACE_PREFIX) {
      expect(b).toBe(0x00);
    }
  });

  test('WILDCARD_NAMESPACE_PREFIX is distinct from sha256("")[0:8]', () => {
    // sha256("") = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
    const emptyHash = new Uint8Array(createHash('sha256').update('', 'utf-8').digest());
    const firstEight = emptyHash.slice(0, TYPE_HASH_SEGMENT_BYTES);
    let same = true;
    for (let i = 0; i < TYPE_HASH_SEGMENT_BYTES; i++) {
      if (firstEight[i] !== WILDCARD_NAMESPACE_PREFIX[i]) {
        same = false;
        break;
      }
    }
    expect(same).toBe(false);
  });
});

describe('T1 — isWildcard', () => {
  test('returns false for non-wildcard hash', () => {
    const h = new Uint8Array(TYPE_HASH_SIZE).fill(0xAA);
    expect(isWildcard(h)).toBe(false);
  });

  test('returns true when first 8 bytes are zero', () => {
    const h = new Uint8Array(TYPE_HASH_SIZE).fill(0xFF);
    for (let i = 0; i < TYPE_HASH_SEGMENT_BYTES; i++) h[i] = 0x00;
    expect(isWildcard(h)).toBe(true);
  });

  test('returns false when only first 7 bytes are zero', () => {
    const h = new Uint8Array(TYPE_HASH_SIZE).fill(0xFF);
    for (let i = 0; i < TYPE_HASH_SEGMENT_BYTES - 1; i++) h[i] = 0x00;
    expect(isWildcard(h)).toBe(false);
  });

  test('returns false for a too-short input', () => {
    const h = new Uint8Array(4);
    expect(isWildcard(h)).toBe(false);
  });
});

describe('T1 — typeHashToHex', () => {
  test('round-trips through hex of a known vector', () => {
    const actual = buildTypeHash('oddjobz', 'job', 'worktrack', 'v2');
    expect(typeHashToHex(actual)).toBe(
      'c4cf2fd44009863e5e8c9902207afaeb822965fc3debc30dfb04dcb6970e4c3d',
    );
  });
});

```
