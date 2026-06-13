---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/__tests__/cell-header-round-trip.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.853849+00:00
---

# core/protocol-types/__tests__/cell-header-round-trip.test.ts

```ts
/**
 * RM-023 — `domainPayloadRoot` header slot integration test.
 *
 * Acceptance bar (from `docs/SCG-AND-PHASE-H-ROADMAP.md` RM-023):
 *   - Pack + unpack round-trip with a registered schema preserves
 *     `domainPayloadRoot` bit-exact.
 *   - Independent recomputation from payload + schema matches.
 */
import { describe, expect, test } from 'bun:test';
import {
  computeDomainPayloadRoot,
  encodePayload,
  type DomainSchema,
} from '@semantos/plexus-schema-registry';
import {
  CellHeaderLayout,
  deserializeCellHeader,
  serializeCellHeader,
  type CellHeader,
} from '../src/cell-header';
import { HeaderOffsets } from '../src/constants';

const COMMERCE_V1: DomainSchema = {
  domainFlag: 0x0001fe01, // SemantosDomainFlags.COMMERCE (relocated, audit B-1)
  version: 1,
  commitmentMode: 'payload-digest',
  fields: [
    { name: 'phase', offset: 0, size: 1, type: 'u8' },
    { name: 'dimension', offset: 1, size: 1, type: 'u8' },
    { name: 'parentHash', offset: 2, size: 32, type: 'u256' },
    { name: 'prevStateHash', offset: 34, size: 32, type: 'u256' },
  ],
};

function emptyHeader(over: Partial<CellHeader> = {}): CellHeader {
  return {
    magic: new Uint8Array(16),
    linearity: 1,
    version: 1,
    flags: 0,
    refCount: 1,
    typeHash: new Uint8Array(32),
    ownerId: new Uint8Array(16),
    timestamp: 1715000000n,
    cellCount: 1,
    totalSize: 0,
    parentHash: new Uint8Array(32),
    prevStateHash: new Uint8Array(32),
    domainPayloadRoot: new Uint8Array(32),
    ...over,
  };
}

describe('RM-023 domainPayloadRoot header slot', () => {
  test('H1 CellHeaderLayout exposes domainPayloadRoot at offset 224, size 32', () => {
    expect(CellHeaderLayout.domainPayloadRoot.offset).toBe(224);
    expect(CellHeaderLayout.domainPayloadRoot.size).toBe(32);
    expect(HeaderOffsets.domainPayloadRoot).toBe(224);
    expect(HeaderOffsets.domainPayloadRootSize).toBe(32);
  });

  test('H2 serialize → deserialize preserves domainPayloadRoot bit-exact', () => {
    const root = new Uint8Array(32);
    for (let i = 0; i < 32; i++) root[i] = (i * 7 + 1) & 0xff;

    const header = emptyHeader({ domainPayloadRoot: root });
    const buf = serializeCellHeader(header);
    expect(buf.length).toBe(256);

    // The root should sit at bytes 224..255.
    expect(Array.from(buf.slice(224, 256))).toEqual(Array.from(root));

    const decoded = deserializeCellHeader(buf);
    expect(Array.from(decoded.domainPayloadRoot)).toEqual(Array.from(root));
  });

  test('H3 unset domainPayloadRoot serialises as 32 zero bytes', () => {
    const header = emptyHeader();
    const buf = serializeCellHeader(header);
    expect(Array.from(buf.slice(224, 256))).toEqual(Array.from(new Uint8Array(32)));
    const decoded = deserializeCellHeader(buf);
    expect(Array.from(decoded.domainPayloadRoot)).toEqual(Array.from(new Uint8Array(32)));
  });

  test('H4 round-trip with a real schema-computed root', () => {
    const values = {
      phase: 3,
      dimension: 1,
      parentHash: new Uint8Array(32).fill(0xaa),
      prevStateHash: new Uint8Array(32).fill(0xbb),
    };
    const root = computeDomainPayloadRoot(COMMERCE_V1, values);
    expect(root.byteLength).toBe(32);

    const header = emptyHeader({ domainPayloadRoot: root });
    const buf = serializeCellHeader(header);
    const decoded = deserializeCellHeader(buf);

    // Independent recompute matches.
    const recomputed = computeDomainPayloadRoot(COMMERCE_V1, values);
    expect(Array.from(decoded.domainPayloadRoot)).toEqual(Array.from(recomputed));
  });

  test('H5 chain fields + domainPayloadRoot coexist in the same header (post-RM-032b)', () => {
    // RM-032b stripped commerce phase/dimension but kept parentHash +
    // prevStateHash as first-class chain fields. They round-trip
    // alongside domainPayloadRoot.
    const root = new Uint8Array(32).fill(0xcc);
    const header = emptyHeader({
      parentHash: new Uint8Array(32).fill(0xdd),
      prevStateHash: new Uint8Array(32).fill(0xee),
      domainPayloadRoot: root,
    });
    const buf = serializeCellHeader(header);
    const decoded = deserializeCellHeader(buf);

    expect(Array.from(decoded.parentHash)).toEqual(Array.from(new Uint8Array(32).fill(0xdd)));
    expect(Array.from(decoded.prevStateHash)).toEqual(Array.from(new Uint8Array(32).fill(0xee)));
    expect(Array.from(decoded.domainPayloadRoot)).toEqual(Array.from(root));
  });

  test('H6 schema payload bytes pack at the offsets the schema declares', () => {
    const values = {
      phase: 7,
      dimension: 2,
      parentHash: new Uint8Array(32).fill(0xaa),
      prevStateHash: new Uint8Array(32).fill(0xbb),
    };
    const encoded = encodePayload(COMMERCE_V1, values);
    // phase at offset 0, dimension at offset 1, parentHash at offset 2..34, prevStateHash at offset 34..66.
    expect(encoded[0]).toBe(7);
    expect(encoded[1]).toBe(2);
    expect(encoded[2]).toBe(0xaa);
    expect(encoded[33]).toBe(0xaa);
    expect(encoded[34]).toBe(0xbb);
    expect(encoded[65]).toBe(0xbb);
  });
});

```
