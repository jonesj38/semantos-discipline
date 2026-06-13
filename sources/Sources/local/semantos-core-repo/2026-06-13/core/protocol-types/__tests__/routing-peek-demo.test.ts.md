---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/__tests__/routing-peek-demo.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.860581+00:00
---

# core/protocol-types/__tests__/routing-peek-demo.test.ts

```ts
/**
 * T5.d — routing peek demo.
 *
 * Demonstrates the load-bearing property of the structured |8|8|8|8|
 * typeHash construction (T5.a): a relay can decide cell ownership by
 * comparing 8 bytes of a 1024-byte cell, without resolving the full
 * triple or reading the payload.
 *
 * Per the cell header wire-format spec (core/protocol-types/src/constants.ts
 * `HeaderOffsets.typeHash = 30`), the typeHash sits at cell bytes 30:62.
 * Under T5.a, bytes 30:38 are `sha256(segment1)[0:8]` — the namespace
 * prefix.  A relay subscribed to all `oddjobz.*` cells holds a single
 * pre-computed `sha256("oddjobz")[0:8]` constant and does an 8-byte
 * memcmp per inbound cell.  No path strings, no JSON, no payload read.
 *
 * Spec: docs/design/STRUCTURED-TYPEHASH-CANONICAL.md §7.2
 */

import { describe, expect, test } from 'bun:test';
import { createHash } from 'crypto';
import {
  buildTypeHash,
  namespacePrefix,
  TYPE_HASH_SEGMENT_BYTES,
} from '../src/type-hash';
import { HeaderOffsets } from '../src/constants';

/** Pre-computed namespace constants — what a relay holds in memory. */
const ODDJOBZ_NS = new Uint8Array(
  createHash('sha256').update('oddjobz', 'utf-8').digest().subarray(0, 8),
);
const MNCA_NS = new Uint8Array(
  createHash('sha256').update('mnca', 'utf-8').digest().subarray(0, 8),
);
const NONPROFIT_NS = new Uint8Array(
  createHash('sha256').update('nonprofit-os', 'utf-8').digest().subarray(0, 8),
);

/** Synthesise a minimal 1024-byte cell with the given typeHash at offset 30. */
function fakeCell(typeHash: Uint8Array): Uint8Array {
  const cell = new Uint8Array(1024);
  cell.set(typeHash, HeaderOffsets.typeHash);
  return cell;
}

/** What a relay actually does on the hot path: 8-byte memcmp on cell[30:38]. */
function relayBelongsToNamespace(
  cell: Uint8Array,
  namespace: Uint8Array,
): boolean {
  // Read the 8-byte namespace prefix directly from the cell header.
  // NO path resolution, NO JSON parse, NO payload touch.
  for (let i = 0; i < TYPE_HASH_SEGMENT_BYTES; i++) {
    if (cell[HeaderOffsets.typeHash + i] !== namespace[i]) return false;
  }
  return true;
}

describe('T5.d — routing peek demo (the whole point of |8|8|8|8|)', () => {
  test('cell.typeHash[0:8] === sha256(segment1)[0:8] — the namespace constant', () => {
    const th = buildTypeHash('oddjobz', 'job', 'worktrack', '');
    const cell = fakeCell(th);
    const peek = cell.subarray(HeaderOffsets.typeHash, HeaderOffsets.typeHash + 8);
    expect(Array.from(peek)).toEqual(Array.from(ODDJOBZ_NS));
  });

  test('oddjobz-subscribed relay accepts every oddjobz.* cell from an 8-byte peek', () => {
    const oddjobzCells = [
      fakeCell(buildTypeHash('oddjobz', 'job', 'worktrack', '')),
      fakeCell(buildTypeHash('oddjobz', 'site', 'locate', '')),
      fakeCell(buildTypeHash('oddjobz', 'attachment', 'capture', '')),
      fakeCell(buildTypeHash('oddjobz', 'mnca', 'tile', 'tick')), // oddjobz-domain MNCA compute
    ];
    for (const cell of oddjobzCells) {
      expect(relayBelongsToNamespace(cell, ODDJOBZ_NS)).toBe(true);
    }
  });

  test('oddjobz-subscribed relay rejects mnca / nonprofit-os cells without further inspection', () => {
    const foreignCells = [
      fakeCell(buildTypeHash('mnca', 'standalone', 'tile', 'tick')),
      fakeCell(buildTypeHash('nonprofit-os', 'fund', 'earmarked_balance', 'v1')),
      fakeCell(buildTypeHash('tessera', 'bottle', 'bottle', '')),
    ];
    for (const cell of foreignCells) {
      expect(relayBelongsToNamespace(cell, ODDJOBZ_NS)).toBe(false);
    }
  });

  test('cross-domain MNCA compute (oddjobz.mnca.tile.tick) routes to oddjobz mesh by namespace prefix', () => {
    // Per decision record §4.2 / D7: MNCA computations over oddjobz data
    // embed "oddjobz" as segment1, so they stay in the oddjobz relay
    // mesh (locality of reference).  This is the per-domain MNCA pattern.
    const cell = fakeCell(buildTypeHash('oddjobz', 'mnca', 'tile', 'tick'));
    expect(relayBelongsToNamespace(cell, ODDJOBZ_NS)).toBe(true);
    expect(relayBelongsToNamespace(cell, MNCA_NS)).toBe(false);
  });

  test('standalone substrate MNCA (mnca.standalone.*) routes to the mnca mesh', () => {
    const cell = fakeCell(buildTypeHash('mnca', 'standalone', 'tile', 'tick'));
    expect(relayBelongsToNamespace(cell, MNCA_NS)).toBe(true);
    expect(relayBelongsToNamespace(cell, ODDJOBZ_NS)).toBe(false);
  });

  test('namespacePrefix() helper extracts the same 8 bytes as the raw peek', () => {
    const th = buildTypeHash('nonprofit-os', 'fund', 'earmarked_balance', 'v1');
    const prefix = namespacePrefix(th);
    expect(prefix.length).toBe(8);
    expect(Array.from(prefix)).toEqual(Array.from(NONPROFIT_NS));
  });

  test('two cellTypes with same namespace+domain share bytes 0..15 (sub-namespace property)', () => {
    // oddjobz.job.v1 vs oddjobz.job.v2: same segment1 + segment2, different segment4.
    // Therefore bytes 0..15 match; bytes 16..31 differ.
    const v1 = buildTypeHash('oddjobz', 'job', 'worktrack', 'v1');
    const v2 = buildTypeHash('oddjobz', 'job', 'worktrack', 'v2');
    expect(Array.from(v1.subarray(0, 16))).toEqual(Array.from(v2.subarray(0, 16)));
    expect(Array.from(v1.subarray(24, 32))).not.toEqual(
      Array.from(v2.subarray(24, 32)),
    );
  });

  test('hot-path cost: a relay needs only 8 byte comparisons per cell', () => {
    // Performance microbenchmark — checks the structural claim, not a
    // wall-clock budget.  10k cells at 8 bytes/cell = 80k bytes of work
    // for namespace routing of 10k 1024-byte cells (10.24 MB raw).
    const cells: Uint8Array[] = [];
    for (let i = 0; i < 10_000; i++) {
      const ns = i % 2 === 0 ? 'oddjobz' : 'mnca';
      cells.push(fakeCell(buildTypeHash(ns, 'x', 'y', String(i))));
    }
    let oddjobzMatches = 0;
    for (const cell of cells) {
      if (relayBelongsToNamespace(cell, ODDJOBZ_NS)) oddjobzMatches++;
    }
    expect(oddjobzMatches).toBe(5_000);
  });
});

```
