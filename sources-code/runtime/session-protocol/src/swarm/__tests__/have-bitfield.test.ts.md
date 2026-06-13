---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/__tests__/have-bitfield.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.076763+00:00
---

# runtime/session-protocol/src/swarm/__tests__/have-bitfield.test.ts

```ts
/**
 * HAVE bitfield + rarest-first selection — M1.
 */
import { describe, expect, test } from 'bun:test';
import {
  bitfieldBytes,
  emptyBitfield,
  setHave,
  hasCell,
  clearHave,
  bitfieldFor,
  haveCount,
  missingCells,
  isComplete,
  mergeBitfields,
  encodeHave,
  decodeHave,
} from '../have-bitfield';
import {
  availabilityMap,
  rarestFirst,
  holdersOf,
  randomFirstPiece,
  isEndgame,
  endgameTargets,
  type SelectionInput,
} from '../piece-selection';

describe('have-bitfield — bit ops', () => {
  test('set / has / clear round-trip, MSB-first', () => {
    const bf = emptyBitfield(10);
    expect(bitfieldBytes(10)).toBe(2);
    setHave(bf, 0);
    setHave(bf, 9);
    expect(hasCell(bf, 0)).toBe(true);
    expect(hasCell(bf, 9)).toBe(true);
    expect(hasCell(bf, 1)).toBe(false);
    // index 0 is the MSB of byte 0
    expect(bf[0]! & 0x80).toBe(0x80);
    clearHave(bf, 0);
    expect(hasCell(bf, 0)).toBe(false);
  });

  test('out-of-range reads are false; set throws', () => {
    const bf = emptyBitfield(8);
    expect(hasCell(bf, -1)).toBe(false);
    expect(hasCell(bf, 8)).toBe(false);
    expect(() => setHave(bf, 8)).toThrow();
  });

  test('bitfieldFor / haveCount / missingCells / isComplete', () => {
    const bf = bitfieldFor([1, 3, 5], 6);
    expect(haveCount(bf, 6)).toBe(3);
    expect(missingCells(bf, 6)).toEqual([0, 2, 4]);
    expect(isComplete(bf, 6)).toBe(false);
    expect(isComplete(bitfieldFor([0, 1, 2, 3, 4, 5], 6), 6)).toBe(true);
  });

  test('mergeBitfields is the union', () => {
    const merged = mergeBitfields(bitfieldFor([0, 2], 8), bitfieldFor([2, 7], 8));
    expect(missingCells(merged, 8)).toEqual([1, 3, 4, 5, 6]);
  });
});

describe('have-bitfield — HAVE payload codec', () => {
  test('encode/decode round-trip', () => {
    const infohash = new Uint8Array(32).fill(0xab);
    const bf = bitfieldFor([0, 17, 49], 50);
    const payload = encodeHave(infohash, 50, bf);
    const decoded = decodeHave(payload);
    expect(decoded.totalCells).toBe(50);
    expect([...decoded.infohash]).toEqual([...infohash]);
    expect(missingCells(decoded.bitfield, 50)).toEqual(missingCells(bf, 50));
  });

  test('decode rejects truncation', () => {
    const payload = encodeHave(new Uint8Array(32), 50, emptyBitfield(50));
    expect(() => decodeHave(payload.subarray(0, 40))).toThrow();
    expect(() => decodeHave(new Uint8Array(10))).toThrow();
  });

  test('encode rejects a bad infohash length', () => {
    expect(() => encodeHave(new Uint8Array(31), 8, emptyBitfield(8))).toThrow();
  });
});

describe('piece-selection — rarest-first', () => {
  const totalCells = 5;
  // peer A holds {0,1,2,3,4}; B holds {0,1}; C holds {0}.
  const peerBitfields = new Map<string, Uint8Array>([
    ['A', bitfieldFor([0, 1, 2, 3, 4], totalCells)],
    ['B', bitfieldFor([0, 1], totalCells)],
    ['C', bitfieldFor([0], totalCells)],
  ]);
  const base: SelectionInput = { totalCells, localBitfield: emptyBitfield(totalCells), peerBitfields };

  test('availability counts holders per missing cell', () => {
    const avail = availabilityMap(base);
    expect(avail.get(0)).toBe(3); // A,B,C
    expect(avail.get(1)).toBe(2); // A,B
    expect(avail.get(2)).toBe(1); // A
    expect(avail.get(4)).toBe(1); // A
  });

  test('orders rarest first, ties by index', () => {
    // counts: 2→1,3→1,4→1 (rarest), 1→2, 0→3. Ties (2,3,4) by index.
    expect(rarestFirst(base)).toEqual([2, 3, 4, 1, 0]);
  });

  test('skips locally-held and in-flight cells', () => {
    const input: SelectionInput = {
      ...base,
      localBitfield: bitfieldFor([2], totalCells),
      inFlight: new Set([3]),
    };
    expect(rarestFirst(input)).toEqual([4, 1, 0]);
  });

  test('omits cells no peer holds', () => {
    const input: SelectionInput = {
      totalCells: 6,
      localBitfield: emptyBitfield(6),
      peerBitfields: new Map([['A', bitfieldFor([0, 1], 6)]]),
    };
    // cells 2..5 have no holder → omitted.
    expect(rarestFirst(input)).toEqual([0, 1]);
  });

  test('holdersOf lists peers for a cell', () => {
    expect(holdersOf(0, peerBitfields).sort()).toEqual(['A', 'B', 'C']);
    expect(holdersOf(4, peerBitfields)).toEqual(['A']);
  });
});

describe('piece-selection — bootstrap + endgame', () => {
  const totalCells = 4;
  const peerBitfields = new Map<string, Uint8Array>([['A', bitfieldFor([0, 1, 2, 3], totalCells)]]);
  const base: SelectionInput = { totalCells, localBitfield: emptyBitfield(totalCells), peerBitfields };

  test('randomFirstPiece picks a fetchable cell deterministically with injected rng', () => {
    expect(randomFirstPiece(base, () => 0)).toBe(rarestFirst(base)[0]);
    // rng→~1 maps to the last candidate (clamped).
    const last = randomFirstPiece(base, () => 0.999);
    expect(typeof last).toBe('number');
    // nothing fetchable → null
    expect(randomFirstPiece({ ...base, localBitfield: bitfieldFor([0, 1, 2, 3], totalCells) })).toBeNull();
  });

  test('isEndgame / endgameTargets', () => {
    const input: SelectionInput = { ...base, localBitfield: bitfieldFor([0, 1], totalCells) };
    expect(isEndgame(input, 2)).toBe(true);
    expect(isEndgame(base, 2)).toBe(false); // 4 missing > 2
    const targets = endgameTargets(input);
    expect(targets.map(t => t.index)).toEqual([2, 3]);
    expect(targets[0]!.holders).toEqual(['A']);
  });
});

```
