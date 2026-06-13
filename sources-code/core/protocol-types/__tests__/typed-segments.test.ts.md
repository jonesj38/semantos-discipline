---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/__tests__/typed-segments.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.855628+00:00
---

# core/protocol-types/__tests__/typed-segments.test.ts

```ts
/**
 * Typed-segments codec + originator path-builder tests.
 *
 * Spec source: `docs/prd/MNCA-LAYER-COLLAPSE-BRIEF.md` §13.2 + §4.1.
 */
import { describe, expect, test } from 'bun:test';
import { CELL_SIZE, HEADER_SIZE, PAYLOAD_SIZE, HeaderOffsets } from '../src/constants';
import {
  SEGMENT_TUPLE_SIZE,
  TYPED_SEGMENTS_HEADER_SIZE,
  maxSegments,
  encodeTypedSegments,
  decodeTypedSegments,
  buildRoutedCell,
  type TypedSegment,
} from '../src/mnca/typed-segments';
import {
  RoutingMode,
  RoutingFlag,
  readRoutingRegion,
  verifyRoutingChecksum,
  isRouted,
} from '../src/cell-routing';

function seg(bcaSeed: number, typeSeed: number): TypedSegment {
  const bca = new Uint8Array(16);
  for (let i = 0; i < 16; i++) bca[i] = (i + bcaSeed) & 0xff;
  const typeHash = new Uint8Array(32);
  for (let i = 0; i < 32; i++) typeHash[i] = (i * 2 + typeSeed) & 0xff;
  return { bca, typeHash };
}

describe('typed-segments layout constants', () => {
  test('each tuple is 48 bytes (16 BCA + 32 type-hash)', () => {
    expect(SEGMENT_TUPLE_SIZE).toBe(48);
    expect(TYPED_SEGMENTS_HEADER_SIZE).toBe(4);
  });

  test('maxSegments fits within the 768-byte payload', () => {
    // (768 - 4) / 48 = 15.9 → 15 segments with no data reserve.
    expect(maxSegments(0)).toBe(15);
    // With 256 bytes reserved for data: (768 - 4 - 256) / 48 = 10.5 → 10.
    expect(maxSegments(256)).toBe(10);
  });
});

describe('typed-segments encode/decode round-trip', () => {
  test('encode → decode preserves segments + data bit-exact', () => {
    const segments = [seg(1, 10), seg(2, 20), seg(3, 30)];
    const data = new Uint8Array([0xde, 0xad, 0xbe, 0xef, 0x01, 0x02]);
    const payload = encodeTypedSegments(segments, data);
    expect(payload.length).toBe(PAYLOAD_SIZE);

    const decoded = decodeTypedSegments(payload);
    expect(decoded.segments.length).toBe(3);
    for (let i = 0; i < 3; i++) {
      expect(Array.from(decoded.segments[i]!.bca)).toEqual(Array.from(segments[i]!.bca));
      expect(Array.from(decoded.segments[i]!.typeHash)).toEqual(Array.from(segments[i]!.typeHash));
    }
    // payloadStartsAt = 4 + 3*48 = 148.
    expect(decoded.payloadStartsAt).toBe(148);
    expect(Array.from(decoded.payloadData.subarray(0, data.length))).toEqual(Array.from(data));
  });

  test('round-trips with empty payload data', () => {
    const segments = [seg(1, 10), seg(2, 20)];
    const payload = encodeTypedSegments(segments);
    const decoded = decodeTypedSegments(payload);
    expect(decoded.segments.length).toBe(2);
    expect(decoded.payloadStartsAt).toBe(4 + 2 * 48);
  });

  test('rejects empty segment list', () => {
    expect(() => encodeTypedSegments([])).toThrow();
  });

  test('rejects wrong-sized segment fields', () => {
    const bad: TypedSegment = { bca: new Uint8Array(15), typeHash: new Uint8Array(32) };
    expect(() => encodeTypedSegments([bad])).toThrow();
    const bad2: TypedSegment = { bca: new Uint8Array(16), typeHash: new Uint8Array(31) };
    expect(() => encodeTypedSegments([bad2])).toThrow();
  });

  test('rejects segments + data that overflow the payload', () => {
    const segments = Array.from({ length: 15 }, (_, i) => seg(i, i));
    // 15 segments = 4 + 720 = 724 bytes, leaving 44 for data. 100 bytes overflows.
    expect(() => encodeTypedSegments(segments, new Uint8Array(100))).toThrow();
    // 44 bytes exactly fits.
    expect(() => encodeTypedSegments(segments, new Uint8Array(44))).not.toThrow();
  });

  test('decode rejects payloadStartsAt that overlaps the segments', () => {
    const payload = encodeTypedSegments([seg(1, 1), seg(2, 2)]);
    // Corrupt payloadStartsAt to point inside the segments region.
    const dv = new DataView(payload.buffer);
    dv.setUint16(2, 10, true); // less than 4 + 2*48 = 100
    expect(() => decodeTypedSegments(payload)).toThrow();
  });
});

describe('buildRoutedCell — originator path-builder', () => {
  test('produces a complete source-routed cell wiring header + payload', () => {
    const cell = new Uint8Array(CELL_SIZE);
    // Set a typeHash so we can assert it survives.
    const typeHash = new Uint8Array(32).fill(0x5a);
    cell.set(typeHash, HeaderOffsets.typeHash);

    const segments = [seg(1, 11), seg(2, 22), seg(3, 33)];
    const finalDest = new Uint8Array(16).fill(0x99);
    const data = new Uint8Array([1, 2, 3, 4]);

    const out = buildRoutedCell({
      cell,
      segments,
      finalDestBca: finalDest,
      payloadData: data,
      flowLabel: 0xabcd1234n,
      priority: 7,
      extraFlags: RoutingFlag.USES_PUSHDROP_PAYMENT,
    });
    expect(out).toBe(cell); // mutated in place

    // Routing region wired correctly.
    expect(isRouted(out)).toBe(true);
    expect(verifyRoutingChecksum(out)).toBe(true);
    const region = readRoutingRegion(out);
    expect(region.routingMode).toBe(RoutingMode.SOURCE_ROUTED);
    expect(region.segmentsLeft).toBe(3);
    expect(region.priority).toBe(7);
    expect(region.flowLabel).toBe(0xabcd1234n);
    expect(region.hopCountBudget).toBe(5); // default = N + 2
    // PATH_IN_PAYLOAD + USES_PUSHDROP_PAYMENT flags both set.
    expect((region.routingFlags & RoutingFlag.PATH_IN_PAYLOAD) !== 0).toBe(true);
    expect((region.routingFlags & RoutingFlag.USES_PUSHDROP_PAYMENT) !== 0).toBe(true);
    // NEXT_HOP_BCA = first segment, FINAL_DEST_BCA = finalDest.
    expect(Array.from(region.nextHopBca)).toEqual(Array.from(segments[0]!.bca));
    expect(Array.from(region.finalDestBca)).toEqual(Array.from(finalDest));

    // typeHash header field untouched.
    expect(Array.from(out.subarray(HeaderOffsets.typeHash, HeaderOffsets.typeHash + 32))).toEqual(
      Array.from(typeHash),
    );

    // Payload carries the segments + data, decodable.
    const payloadRegion = out.subarray(HEADER_SIZE, CELL_SIZE);
    const decoded = decodeTypedSegments(payloadRegion);
    expect(decoded.segments.length).toBe(3);
    expect(Array.from(decoded.segments[2]!.typeHash)).toEqual(Array.from(segments[2]!.typeHash));
    expect(Array.from(decoded.payloadData.subarray(0, 4))).toEqual([1, 2, 3, 4]);
  });

  test('hopCountBudget override is honoured', () => {
    const cell = new Uint8Array(CELL_SIZE);
    const out = buildRoutedCell({
      cell,
      segments: [seg(1, 1)],
      finalDestBca: new Uint8Array(16),
      hopCountBudget: 42,
    });
    expect(readRoutingRegion(out).hopCountBudget).toBe(42);
  });

  test('rejects bad inputs', () => {
    expect(() =>
      buildRoutedCell({ cell: new Uint8Array(100), segments: [seg(1, 1)], finalDestBca: new Uint8Array(16) }),
    ).toThrow();
    expect(() =>
      buildRoutedCell({ cell: new Uint8Array(CELL_SIZE), segments: [], finalDestBca: new Uint8Array(16) }),
    ).toThrow();
    expect(() =>
      buildRoutedCell({ cell: new Uint8Array(CELL_SIZE), segments: [seg(1, 1)], finalDestBca: new Uint8Array(15) }),
    ).toThrow();
  });
});

```
