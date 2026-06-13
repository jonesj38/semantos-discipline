---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/__tests__/mnca-cell-types.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.860040+00:00
---

# core/protocol-types/__tests__/mnca-cell-types.test.ts

```ts
/**
 * MNCA cell-type registry tests — post-T3.b.
 *
 * Identity (typeHash) is now manifest-driven; this test asserts the
 * MNCA_TRIPLES table → `buildTypeHash` produces the same hex values
 * that `cartridges/mnca/cartridge.json` and
 * `cartridges/mnca/brain/mnca_cell_specs.zig` pin.  Drift in any of
 * the three surfaces surfaces here.
 *
 * Pre-T3.b history: this test pinned 5 known-answer vectors against
 * the legacy `computeMncaTypeHash` (flat SHA256 of dotted name).
 * Those functions were deleted; vectors regenerated under the
 * structured |8|8|8|8| algorithm.  D12 also retired TILE_V0; the
 * 5th type is now TILE (Q13-A — base-tile shape).
 */
import { describe, expect, test } from 'bun:test';
import {
  MNCA_TYPE_HASH_SIZE,
  MncaCellTypeName,
  MNCA_CELL_TYPE_NAMES,
  MNCA_TRIPLES,
  MncaTransformEdges,
  isMncaTransform,
  buildTypeHash,
  typeHashToHex,
} from '../src';

// Known-answer hex vectors under the structured |8|8|8|8| algorithm.
// MUST match `cartridges/mnca/cartridge.json` cellTypes[] hashes and
// `cartridges/mnca/brain/mnca_cell_specs.zig` EXPECTED[].hex values.
//
// All 5 share bytes 0:16 = 09e9fe981010c9b45b565a33b80b75dc
//   (= sha256("mnca")[0:8] ++ sha256("standalone")[0:8])
// The 3 tile-* entries additionally share bytes 0:24 (adding
//   sha256("tile")[0:8] = 8b668b8994aa8451)
const KNOWN: Record<string, string> = {
  'mnca.snapshot':       '09e9fe981010c9b45b565a33b80b75dc16a0eeb0791b6c92e3b0c44298fc1c14',
  'mnca.perturb':        '09e9fe981010c9b45b565a33b80b75dc9dab0a86a717bbbbe3b0c44298fc1c14',
  'mnca.tile.injection': '09e9fe981010c9b45b565a33b80b75dc8b668b8994aa8451545a70019936cf88',
  'mnca.tile.tick':      '09e9fe981010c9b45b565a33b80b75dc8b668b8994aa845155a4bc5be68ea5c3',
  'mnca.tile':           '09e9fe981010c9b45b565a33b80b75dc8b668b8994aa8451e3b0c44298fc1c14',
};

describe('MNCA cell-type names', () => {
  test('all five canonical names are present and stable', () => {
    expect(MncaCellTypeName.SNAPSHOT).toBe('mnca.snapshot');
    expect(MncaCellTypeName.PERTURB).toBe('mnca.perturb');
    expect(MncaCellTypeName.TILE_INJECTION).toBe('mnca.tile.injection');
    expect(MncaCellTypeName.TILE_TICK).toBe('mnca.tile.tick');
    expect(MncaCellTypeName.TILE).toBe('mnca.tile');
    expect(MNCA_CELL_TYPE_NAMES.length).toBe(5);
  });

  test('no name carries a .vN suffix per D12', () => {
    for (const name of MNCA_CELL_TYPE_NAMES) {
      expect(name).not.toMatch(/\.v\d+$/);
    }
  });
});

describe('MNCA_TRIPLES → buildTypeHash matches the manifest hex', () => {
  test('each triple hashes to its frozen known-answer vector', () => {
    for (const name of MNCA_CELL_TYPE_NAMES) {
      const [s1, s2, s3, s4] = MNCA_TRIPLES[name];
      const hash = buildTypeHash(s1, s2, s3, s4);
      expect(hash.length).toBe(MNCA_TYPE_HASH_SIZE);
      expect(typeHashToHex(hash)).toBe(KNOWN[name]);
    }
  });

  test('hashing is deterministic across calls', () => {
    const [s1, s2, s3, s4] = MNCA_TRIPLES[MncaCellTypeName.SNAPSHOT];
    const a = buildTypeHash(s1, s2, s3, s4);
    const b = buildTypeHash(s1, s2, s3, s4);
    expect(Array.from(a)).toEqual(Array.from(b));
  });

  test('distinct names produce distinct hashes', () => {
    const hexes = MNCA_CELL_TYPE_NAMES.map((n) => {
      const [s1, s2, s3, s4] = MNCA_TRIPLES[n];
      return typeHashToHex(buildTypeHash(s1, s2, s3, s4));
    });
    expect(new Set(hexes).size).toBe(hexes.length);
  });
});

describe('routing-prefix property (the whole point of |8|8|8|8|)', () => {
  test('all 5 MNCA types share bytes 0:16 (mnca.standalone namespace)', () => {
    const ns = KNOWN[MncaCellTypeName.SNAPSHOT]!.slice(0, 32); // 16 bytes = 32 hex chars
    for (const name of MNCA_CELL_TYPE_NAMES) {
      expect(KNOWN[name]!.slice(0, 32)).toBe(ns);
    }
  });

  test('all 3 tile.* types share bytes 0:24 (mnca.standalone.tile)', () => {
    const tilePrefix = KNOWN[MncaCellTypeName.TILE]!.slice(0, 48); // 24 bytes
    expect(KNOWN[MncaCellTypeName.TILE_INJECTION]!.slice(0, 48)).toBe(tilePrefix);
    expect(KNOWN[MncaCellTypeName.TILE_TICK]!.slice(0, 48)).toBe(tilePrefix);
  });
});

describe('MNCA transform graph', () => {
  test('the headline perturb → tile.injection edge exists (§13.7)', () => {
    expect(isMncaTransform(MncaCellTypeName.PERTURB, MncaCellTypeName.TILE_INJECTION)).toBe(true);
  });

  test('the full forward pipeline is connected', () => {
    expect(isMncaTransform(MncaCellTypeName.PERTURB, MncaCellTypeName.TILE_INJECTION)).toBe(true);
    expect(isMncaTransform(MncaCellTypeName.TILE_INJECTION, MncaCellTypeName.TILE_TICK)).toBe(true);
    expect(isMncaTransform(MncaCellTypeName.TILE_TICK, MncaCellTypeName.SNAPSHOT)).toBe(true);
  });

  test('non-edges are rejected', () => {
    expect(isMncaTransform(MncaCellTypeName.SNAPSHOT, MncaCellTypeName.PERTURB)).toBe(false);
    expect(isMncaTransform(MncaCellTypeName.PERTURB, MncaCellTypeName.SNAPSHOT)).toBe(false);
  });

  test('every edge references declared cell-type names', () => {
    const valid = new Set<string>(MNCA_CELL_TYPE_NAMES);
    for (const [from, to] of MncaTransformEdges) {
      expect(valid.has(from)).toBe(true);
      expect(valid.has(to)).toBe(true);
    }
  });
});

```
