---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/__tests__/hop-processing.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.858923+00:00
---

# core/protocol-types/__tests__/hop-processing.test.ts

```ts
/**
 * Relay hop-processing tests — the consume-half of source routing.
 *
 * Spec source: `docs/prd/MNCA-LAYER-COLLAPSE-BRIEF.md` §4.2 + §13.3.
 *
 * Exercises a full build → forward → … → deliver round-trip (pairing
 * buildRoutedCell from typed-segments.ts with processHop here), plus each
 * typed rejection reason and the invariant that payload + typeHash survive
 * forwarding untouched.
 */
import { describe, expect, test } from 'bun:test';
import { CELL_SIZE, HEADER_SIZE, HeaderOffsets } from '../src/constants';
import { buildRoutedCell, decodeTypedSegments, type TypedSegment } from '../src/mnca/typed-segments';
import { processHop } from '../src/mnca/hop-processing';
import {
  RoutingMode,
  RoutingRegionOffsets,
  readRoutingRegion,
  verifyRoutingChecksum,
} from '../src/cell-routing';

function bca(seed: number): Uint8Array {
  const b = new Uint8Array(16);
  for (let i = 0; i < 16; i++) b[i] = (i + seed * 31) & 0xff;
  return b;
}
function typeHash(seed: number): Uint8Array {
  const h = new Uint8Array(32);
  for (let i = 0; i < 32; i++) h[i] = (i * 5 + seed) & 0xff;
  return h;
}
function setCellType(cell: Uint8Array, h: Uint8Array): void {
  cell.set(h, HeaderOffsets.typeHash);
}

/** Build a 3-hop routed cell. segments[i] = (hop_i bca, type-on-arrival_i). */
function build3HopCell(): {
  cell: Uint8Array;
  segments: TypedSegment[];
  finalDest: Uint8Array;
  data: Uint8Array;
} {
  const segments: TypedSegment[] = [
    { bca: bca(1), typeHash: typeHash(10) },
    { bca: bca(2), typeHash: typeHash(20) },
    { bca: bca(3), typeHash: typeHash(30) },
  ];
  const finalDest = bca(99);
  const data = new Uint8Array([0xaa, 0xbb, 0xcc, 0xdd]);
  const cell = new Uint8Array(CELL_SIZE);
  // The cell arrives at hop 0 carrying segments[0].typeHash.
  setCellType(cell, segments[0]!.typeHash);
  buildRoutedCell({ cell, segments, finalDestBca: finalDest, payloadData: data, hopCountBudget: 8 });
  return { cell, segments, finalDest, data };
}

describe('processHop — happy path single forward', () => {
  test('first hop forwards, advances routing, names the segment to spend', () => {
    const { cell, segments, finalDest } = build3HopCell();
    const res = processHop(cell, segments[0]!.bca);
    expect(res.ok).toBe(true);
    if (!res.ok || res.kind !== 'forward') throw new Error('expected forward');

    expect(res.spendSegmentIndex).toBe(0);
    expect(Array.from(res.expectedOutputTypeHash!)).toEqual(Array.from(segments[1]!.typeHash));

    const region = readRoutingRegion(res.forwarded);
    expect(region.segmentsLeft).toBe(2);
    expect(region.hopCountBudget).toBe(7);
    expect(Array.from(region.nextHopBca)).toEqual(Array.from(segments[1]!.bca));
    expect(Array.from(region.finalDestBca)).toEqual(Array.from(finalDest));
    expect(verifyRoutingChecksum(res.forwarded)).toBe(true);
  });

  test('forwarding leaves payload + typeHash untouched (transform is external)', () => {
    const { cell, segments } = build3HopCell();
    const beforeType = cell.slice(HeaderOffsets.typeHash, HeaderOffsets.typeHash + 32);
    const beforePayload = cell.slice(HEADER_SIZE, CELL_SIZE);

    const res = processHop(cell, segments[0]!.bca);
    if (!res.ok || res.kind !== 'forward') throw new Error('expected forward');

    // typeHash unchanged — processHop returns intent, doesn't run the transform.
    expect(Array.from(res.forwarded.slice(HeaderOffsets.typeHash, HeaderOffsets.typeHash + 32))).toEqual(
      Array.from(beforeType),
    );
    // payload (inline segments + data) unchanged.
    expect(Array.from(res.forwarded.slice(HEADER_SIZE, CELL_SIZE))).toEqual(Array.from(beforePayload));
    // The inline segments still decode.
    const decoded = decodeTypedSegments(res.forwarded.subarray(HEADER_SIZE));
    expect(decoded.segments.length).toBe(3);
  });
});

describe('processHop — full multi-hop walk to final destination', () => {
  test('3-hop cell traverses hop0 → hop1 → hop2 → final destination', () => {
    const { cell, segments, finalDest } = build3HopCell();
    let current = cell;

    // Hop 0
    let res = processHop(current, segments[0]!.bca);
    if (!res.ok || res.kind !== 'forward') throw new Error('hop0 expected forward');
    expect(res.spendSegmentIndex).toBe(0);
    current = res.forwarded;
    // Simulate the cell-engine transform: set the cell's type to the next hop's expected type.
    setCellType(current, res.expectedOutputTypeHash!);

    // Hop 1
    res = processHop(current, segments[1]!.bca);
    if (!res.ok || res.kind !== 'forward') throw new Error('hop1 expected forward');
    expect(res.spendSegmentIndex).toBe(1);
    expect(readRoutingRegion(res.forwarded).segmentsLeft).toBe(1);
    current = res.forwarded;
    setCellType(current, res.expectedOutputTypeHash!);

    // Hop 2 (last forwarding hop) — points the cell at the final destination.
    res = processHop(current, segments[2]!.bca);
    if (!res.ok || res.kind !== 'forward') throw new Error('hop2 expected forward');
    expect(res.spendSegmentIndex).toBe(2);
    const afterHop2 = readRoutingRegion(res.forwarded);
    expect(afterHop2.segmentsLeft).toBe(0);
    expect(Array.from(afterHop2.nextHopBca)).toEqual(Array.from(finalDest));
    expect(res.expectedOutputTypeHash).toBeUndefined(); // no inline next-type past the last hop
    current = res.forwarded;

    // Final destination
    const final = processHop(current, finalDest);
    expect(final.ok).toBe(true);
    if (!final.ok) throw new Error('unreachable');
    expect(final.kind).toBe('final-destination');
  });

  test('hop budget decrements once per hop across the walk', () => {
    const { cell, segments } = build3HopCell(); // budget 8
    let current = cell;
    const budgets: number[] = [];
    for (let i = 0; i < 3; i++) {
      const res = processHop(current, segments[i]!.bca);
      if (!res.ok || res.kind !== 'forward') throw new Error('expected forward');
      budgets.push(readRoutingRegion(res.forwarded).hopCountBudget);
      current = res.forwarded;
      if (res.expectedOutputTypeHash) setCellType(current, res.expectedOutputTypeHash);
    }
    expect(budgets).toEqual([7, 6, 5]);
  });
});

describe('processHop — typed rejections', () => {
  test('not-source-routed when ROUTING_MODE != SOURCE_ROUTED', () => {
    const { cell, segments } = build3HopCell();
    // ROUTING_MODE byte (offset 94) is outside the CRC coverage window, so
    // clobbering it does not invalidate the checksum — exactly the case
    // the mode check guards.
    cell[RoutingRegionOffsets.routingMode] = RoutingMode.UNROUTED;
    const res = processHop(cell, segments[0]!.bca);
    expect(res).toEqual({ ok: false, reason: 'not-source-routed' });
  });

  test('checksum rejection when a covered routing byte is tampered', () => {
    const { cell, segments } = build3HopCell();
    // Flip a byte inside NEXT_HOP_BCA (covered by the CRC window).
    cell[RoutingRegionOffsets.nextHopBca] ^= 0xff;
    const res = processHop(cell, segments[0]!.bca);
    expect(res).toEqual({ ok: false, reason: 'checksum' });
  });

  test('not-my-hop when NEXT_HOP_BCA is someone else', () => {
    const { cell } = build3HopCell();
    const res = processHop(cell, bca(777)); // not hop 0
    expect(res).toEqual({ ok: false, reason: 'not-my-hop' });
  });

  test('type-mismatch when the cell carries the wrong type for this segment', () => {
    const { cell, segments } = build3HopCell();
    // The cell should carry segments[0].typeHash; give it a different one.
    setCellType(cell, typeHash(222));
    const res = processHop(cell, segments[0]!.bca);
    expect(res).toEqual({ ok: false, reason: 'type-mismatch' });
  });

  test('type check can be disabled via opts.validateType', () => {
    const { cell, segments } = build3HopCell();
    setCellType(cell, typeHash(222)); // wrong type
    const res = processHop(cell, segments[0]!.bca, { validateType: false });
    expect(res.ok).toBe(true);
    if (!res.ok || res.kind !== 'forward') throw new Error('expected forward');
    expect(res.spendSegmentIndex).toBe(0);
  });

  test('budget-exhausted when HOP_COUNT_BUDGET is 0', () => {
    const segments: TypedSegment[] = [{ bca: bca(1), typeHash: typeHash(10) }];
    const cell = new Uint8Array(CELL_SIZE);
    setCellType(cell, segments[0]!.typeHash);
    buildRoutedCell({ cell, segments, finalDestBca: bca(99), hopCountBudget: 0 });
    const res = processHop(cell, segments[0]!.bca);
    expect(res).toEqual({ ok: false, reason: 'budget-exhausted' });
  });
});

describe('processHop — single-hop path reaches final destination', () => {
  test('one segment: hop0 forwards to final dest, which then delivers', () => {
    const segments: TypedSegment[] = [{ bca: bca(1), typeHash: typeHash(10) }];
    const finalDest = bca(99);
    const cell = new Uint8Array(CELL_SIZE);
    setCellType(cell, segments[0]!.typeHash);
    buildRoutedCell({ cell, segments, finalDestBca: finalDest, hopCountBudget: 4 });

    const res = processHop(cell, segments[0]!.bca);
    if (!res.ok || res.kind !== 'forward') throw new Error('expected forward');
    expect(res.spendSegmentIndex).toBe(0);
    expect(readRoutingRegion(res.forwarded).segmentsLeft).toBe(0);
    expect(Array.from(readRoutingRegion(res.forwarded).nextHopBca)).toEqual(Array.from(finalDest));

    const final = processHop(res.forwarded, finalDest);
    expect(final.ok).toBe(true);
    if (!final.ok) throw new Error('unreachable');
    expect(final.kind).toBe('final-destination');
  });
});

describe('processHop — misuse throws', () => {
  test('wrong-sized ownBca throws', () => {
    const { cell } = build3HopCell();
    expect(() => processHop(cell, new Uint8Array(15))).toThrow();
  });
});

```
