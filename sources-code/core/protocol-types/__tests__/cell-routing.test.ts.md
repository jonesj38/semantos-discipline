---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/__tests__/cell-routing.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.856184+00:00
---

# core/protocol-types/__tests__/cell-routing.test.ts

```ts
/**
 * Cell-routing region accessor tests.
 *
 * Spec source: `docs/prd/MNCA-LAYER-COLLAPSE-BRIEF.md` §2.1–§2.4.
 *
 * Pins the wire-format layout (offsets + endianness + checksum coverage)
 * because the routing region is going to be read and written from
 * multiple code paths (mesh-dispatcher, cell-relay, originator-side
 * pathfinder, on-chain anchorer). A drift here is hard to debug from
 * any one consumer.
 */
import { describe, expect, test } from 'bun:test';
import {
  HeaderOffsets,
  HEADER_SIZE,
} from '../src/constants';
import {
  ROUTING_REGION_START,
  ROUTING_REGION_END,
  ROUTING_REGION_SIZE,
  ROUTING_CHECKSUM_COVERAGE_START,
  ROUTING_CHECKSUM_COVERAGE_END,
  ROUTING_VERSION_V1,
  RoutingMode,
  RoutingFlag,
  RoutingRegionOffsets,
  readRoutingRegion,
  writeRoutingRegion,
  computeRoutingChecksum,
  setRoutingChecksum,
  verifyRoutingChecksum,
  isRouted,
  readRoutingMode,
  readPriority,
  hasRoutingFlag,
  crc32,
  type RoutingRegion,
} from '../src/cell-routing';

function emptyRegion(over: Partial<RoutingRegion> = {}): RoutingRegion {
  return {
    routingMode: RoutingMode.SOURCE_ROUTED,
    priority: 0,
    routingVersion: ROUTING_VERSION_V1,
    routingFlags: 0,
    segmentsLeft: 0,
    hopCountBudget: 0,
    flowLabel: 0n,
    nextHopBca: new Uint8Array(16),
    finalDestBca: new Uint8Array(16),
    routingChecksum: 0,
    ...over,
  };
}

describe('cell-routing region layout', () => {
  test('the 64-byte region ends exactly where domainPayloadRoot begins', () => {
    // Routing region is bytes 160..223 (64 bytes); domainPayloadRoot
    // starts at offset 224. If anyone ever moves domainPayloadRoot,
    // this test wedges that conversation.
    expect(ROUTING_REGION_START).toBe(160);
    expect(ROUTING_REGION_END).toBe(224);
    expect(ROUTING_REGION_SIZE).toBe(64);
    expect(HeaderOffsets.domainPayloadRoot).toBe(ROUTING_REGION_END);
  });

  test('all field offsets sit inside the 64-byte region', () => {
    for (const [name, off] of Object.entries(RoutingRegionOffsets)) {
      if (name.endsWith('Size')) continue;
      if (name === 'routingMode' || name === 'priority') {
        // These two live in the 2-byte gap at offset 94-95.
        expect(off).toBeGreaterThanOrEqual(94);
        expect(off).toBeLessThan(96);
        continue;
      }
      expect(off).toBeGreaterThanOrEqual(ROUTING_REGION_START);
      expect(off).toBeLessThan(ROUTING_REGION_END);
    }
  });

  test('field offsets match §2.1 of the brief exactly', () => {
    expect(RoutingRegionOffsets.routingVersion).toBe(160);
    expect(RoutingRegionOffsets.routingFlags).toBe(164);
    expect(RoutingRegionOffsets.segmentsLeft).toBe(168);
    expect(RoutingRegionOffsets.hopCountBudget).toBe(172);
    expect(RoutingRegionOffsets.flowLabel).toBe(176);
    expect(RoutingRegionOffsets.nextHopBca).toBe(184);
    expect(RoutingRegionOffsets.finalDestBca).toBe(200);
    expect(RoutingRegionOffsets.routingChecksum).toBe(216);
    expect(RoutingRegionOffsets.routingReserved).toBe(220);
  });

  test('field sizes sum to the 64-byte region', () => {
    const sum =
      RoutingRegionOffsets.routingVersionSize +
      RoutingRegionOffsets.routingFlagsSize +
      RoutingRegionOffsets.segmentsLeftSize +
      RoutingRegionOffsets.hopCountBudgetSize +
      RoutingRegionOffsets.flowLabelSize +
      RoutingRegionOffsets.nextHopBcaSize +
      RoutingRegionOffsets.finalDestBcaSize +
      RoutingRegionOffsets.routingChecksumSize +
      RoutingRegionOffsets.routingReservedSize;
    expect(sum).toBe(ROUTING_REGION_SIZE);
  });

  test('ROUTING_CHECKSUM covers bytes [160..216) — everything except the checksum + reserved trailer', () => {
    expect(ROUTING_CHECKSUM_COVERAGE_START).toBe(160);
    expect(ROUTING_CHECKSUM_COVERAGE_END).toBe(216);
    expect(ROUTING_CHECKSUM_COVERAGE_END - ROUTING_CHECKSUM_COVERAGE_START).toBe(56);
  });
});

describe('cell-routing read/write round-trip', () => {
  test('write → read preserves every field bit-exact', () => {
    const buf = new Uint8Array(HEADER_SIZE);
    const next = new Uint8Array(16);
    for (let i = 0; i < 16; i++) next[i] = i + 1;
    const final = new Uint8Array(16);
    for (let i = 0; i < 16; i++) final[i] = (i * 3 + 5) & 0xff;

    const region: RoutingRegion = {
      routingMode: RoutingMode.SOURCE_ROUTED,
      priority: 42,
      routingVersion: ROUTING_VERSION_V1,
      routingFlags: RoutingFlag.PRIORITY | RoutingFlag.USES_PUSHDROP_PAYMENT,
      segmentsLeft: 7,
      hopCountBudget: 16,
      flowLabel: 0x0123456789abcdefn,
      nextHopBca: next,
      finalDestBca: final,
      routingChecksum: 0xdeadbeef,
    };
    writeRoutingRegion(buf, region);
    const decoded = readRoutingRegion(buf);

    expect(decoded.routingMode).toBe(RoutingMode.SOURCE_ROUTED);
    expect(decoded.priority).toBe(42);
    expect(decoded.routingVersion).toBe(ROUTING_VERSION_V1);
    expect(decoded.routingFlags).toBe(
      RoutingFlag.PRIORITY | RoutingFlag.USES_PUSHDROP_PAYMENT,
    );
    expect(decoded.segmentsLeft).toBe(7);
    expect(decoded.hopCountBudget).toBe(16);
    expect(decoded.flowLabel).toBe(0x0123456789abcdefn);
    expect(Array.from(decoded.nextHopBca)).toEqual(Array.from(next));
    expect(Array.from(decoded.finalDestBca)).toEqual(Array.from(final));
    expect(decoded.routingChecksum).toBe(0xdeadbeef);
  });

  test('write rejects BCAs that are not 16 bytes', () => {
    const buf = new Uint8Array(HEADER_SIZE);
    expect(() =>
      writeRoutingRegion(buf, emptyRegion({ nextHopBca: new Uint8Array(15) })),
    ).toThrow();
    expect(() =>
      writeRoutingRegion(buf, emptyRegion({ finalDestBca: new Uint8Array(17) })),
    ).toThrow();
  });

  test('read rejects buffers smaller than the routing region end', () => {
    expect(() => readRoutingRegion(new Uint8Array(100))).toThrow();
    expect(() => readRoutingRegion(new Uint8Array(223))).toThrow();
    expect(() => readRoutingRegion(new Uint8Array(224))).not.toThrow();
  });

  test('unrouted cells (ROUTING_MODE = 0) still read cleanly', () => {
    const buf = new Uint8Array(HEADER_SIZE);
    expect(isRouted(buf)).toBe(false);
    expect(readRoutingMode(buf)).toBe(RoutingMode.UNROUTED);
    expect(readPriority(buf)).toBe(0);
    const decoded = readRoutingRegion(buf);
    expect(decoded.routingMode).toBe(RoutingMode.UNROUTED);
    expect(decoded.routingVersion).toBe(0);
  });

  test('writing routing region does NOT touch bytes outside [94, 95] ∪ [160, 224)', () => {
    const buf = new Uint8Array(HEADER_SIZE);
    // Pre-fill with sentinel so we can detect any out-of-region writes.
    for (let i = 0; i < HEADER_SIZE; i++) buf[i] = 0xaa;
    writeRoutingRegion(buf, emptyRegion({ priority: 5 }));

    for (let i = 0; i < HEADER_SIZE; i++) {
      if (i === 94 || i === 95) continue;
      if (i >= 160 && i < 224) continue;
      expect(buf[i]).toBe(0xaa);
    }
  });
});

describe('cell-routing checksum (CRC-32)', () => {
  test('CRC-32 of empty input is 0 (per IEEE 802.3)', () => {
    expect(crc32(new Uint8Array(0))).toBe(0);
  });

  test('CRC-32 of "123456789" is 0xCBF43926 (canonical test vector)', () => {
    // The IEEE 802.3 / zlib / PNG canonical vector — guards against
    // table-init or polynomial drift.
    const bytes = new Uint8Array([0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39]);
    expect(crc32(bytes)).toBe(0xcbf43926);
  });

  test('setRoutingChecksum + verifyRoutingChecksum round-trip', () => {
    const buf = new Uint8Array(HEADER_SIZE);
    writeRoutingRegion(
      buf,
      emptyRegion({
        segmentsLeft: 3,
        hopCountBudget: 5,
        flowLabel: 0xcafebabedeadbeefn,
        priority: 13,
      }),
    );
    const c = setRoutingChecksum(buf);
    expect(verifyRoutingChecksum(buf)).toBe(true);

    // Tamper with the next-hop BCA — checksum must reject.
    buf[RoutingRegionOffsets.nextHopBca]! ^= 0x01;
    expect(verifyRoutingChecksum(buf)).toBe(false);

    // Restore — checksum returns clean.
    buf[RoutingRegionOffsets.nextHopBca]! ^= 0x01;
    expect(verifyRoutingChecksum(buf)).toBe(true);
    expect(computeRoutingChecksum(buf)).toBe(c);
  });

  test('checksum changes when any covered field changes', () => {
    const buf = new Uint8Array(HEADER_SIZE);
    writeRoutingRegion(buf, emptyRegion());
    setRoutingChecksum(buf);
    const a = computeRoutingChecksum(buf);

    buf[RoutingRegionOffsets.segmentsLeft]! = 1;
    const b = computeRoutingChecksum(buf);
    expect(a).not.toBe(b);

    buf[RoutingRegionOffsets.segmentsLeft]! = 0;
    expect(computeRoutingChecksum(buf)).toBe(a);
  });

  test('checksum is unaffected by bytes outside the coverage window', () => {
    const buf = new Uint8Array(HEADER_SIZE);
    writeRoutingRegion(buf, emptyRegion());
    setRoutingChecksum(buf);
    const stable = computeRoutingChecksum(buf);

    // Reserved trailer (bytes 220..224) — not covered.
    buf[220]! = 0xff;
    expect(computeRoutingChecksum(buf)).toBe(stable);

    // domainPayloadRoot region (offset 224..256) — not covered.
    buf[230]! = 0xff;
    expect(computeRoutingChecksum(buf)).toBe(stable);
  });
});

describe('cell-routing flag helpers', () => {
  test('hasRoutingFlag returns true only for set bits', () => {
    const region = emptyRegion({
      routingFlags: RoutingFlag.PRIORITY | RoutingFlag.PATH_MERKLE_OVERLOAD,
    });
    expect(hasRoutingFlag(region, RoutingFlag.PRIORITY)).toBe(true);
    expect(hasRoutingFlag(region, RoutingFlag.PATH_MERKLE_OVERLOAD)).toBe(true);
    expect(hasRoutingFlag(region, RoutingFlag.ANCHOR_ON_ARRIVAL)).toBe(false);
    expect(hasRoutingFlag(region, RoutingFlag.BATCHABLE)).toBe(false);
    expect(hasRoutingFlag(region, RoutingFlag.USES_PUSHDROP_PAYMENT)).toBe(false);
  });

  test('RoutingFlag bits are distinct and stable', () => {
    expect(RoutingFlag.PRIORITY).toBe(1);
    expect(RoutingFlag.ANCHOR_ON_ARRIVAL).toBe(2);
    expect(RoutingFlag.BATCHABLE).toBe(4);
    expect(RoutingFlag.USES_PUSHDROP_PAYMENT).toBe(8);
    expect(RoutingFlag.PATH_MERKLE_OVERLOAD).toBe(16);
  });
});

```
