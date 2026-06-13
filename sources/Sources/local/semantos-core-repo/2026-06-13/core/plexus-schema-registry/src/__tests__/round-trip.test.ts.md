---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/plexus-schema-registry/src/__tests__/round-trip.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.950507+00:00
---

# core/plexus-schema-registry/src/__tests__/round-trip.test.ts

```ts
/**
 * RM-012 — encode/decode round-trip + domainPayloadRoot determinism.
 */
import { describe, expect, test } from 'bun:test';
import { encodePayload, decodePayload, encodeSchema } from '../encoding.js';
import { computeDomainPayloadRoot } from '../hash.js';
import type { DomainSchema } from '../types.js';

const COMMERCE_V1: DomainSchema = {
  domainFlag: 0x0001fe01, // SemantosDomainFlags.COMMERCE per RM-004 (relocated, audit B-1)
  version: 1,
  commitmentMode: 'payload-digest',
  fields: [
    { name: 'phase', offset: 0, size: 1, type: 'u8' },
    { name: 'dimension', offset: 1, size: 1, type: 'u8' },
    { name: 'parentHash', offset: 2, size: 32, type: 'u256' },
    { name: 'prevStateHash', offset: 34, size: 32, type: 'u256' },
  ],
};

function bytes(n: number, fill = 0): Uint8Array {
  const b = new Uint8Array(n);
  if (fill) b.fill(fill);
  return b;
}

describe('encodePayload / decodePayload round-trip', () => {
  test('E1 commerce v1 round-trips bit-exact', () => {
    const values = {
      phase: 3,
      dimension: 1,
      parentHash: bytes(32, 0xaa),
      prevStateHash: bytes(32, 0xbb),
    };
    const encoded = encodePayload(COMMERCE_V1, values);
    expect(encoded.byteLength).toBe(72); // 66 bytes laid out, padded to 72 (next /8)
    const decoded = decodePayload(COMMERCE_V1, encoded);
    expect(decoded.phase).toBe(3);
    expect(decoded.dimension).toBe(1);
    expect(decoded.parentHash).toEqual(bytes(32, 0xaa));
    expect(decoded.prevStateHash).toEqual(bytes(32, 0xbb));
  });

  test('E2 hex-string bytes input is accepted', () => {
    const values = {
      phase: 0,
      dimension: 0,
      parentHash: '0x' + 'aa'.repeat(32),
      prevStateHash: '0x' + 'bb'.repeat(32),
    };
    const encoded = encodePayload(COMMERCE_V1, values);
    const decoded = decodePayload(COMMERCE_V1, encoded);
    expect(decoded.parentHash).toEqual(bytes(32, 0xaa));
  });

  test('E3 missing field throws', () => {
    expect(() =>
      encodePayload(COMMERCE_V1, {
        phase: 1,
        dimension: 0,
        parentHash: bytes(32),
        // prevStateHash missing
      }),
    ).toThrow(/'prevStateHash'/);
  });

  test('E4 u256 with wrong length throws', () => {
    expect(() =>
      encodePayload(COMMERCE_V1, {
        phase: 1,
        dimension: 0,
        parentHash: bytes(16), // wrong length
        prevStateHash: bytes(32),
      }),
    ).toThrow(/expected 32 bytes/);
  });

  test('E5 u16 / u32 / u64 little-endian', () => {
    const schema: DomainSchema = {
      domainFlag: 99,
      version: 1,
      commitmentMode: 'payload-digest',
      fields: [
        { name: 'a', offset: 0, size: 2, type: 'u16' },
        { name: 'b', offset: 2, size: 4, type: 'u32' },
        { name: 'c', offset: 8, size: 8, type: 'u64' },
      ],
    };
    const enc = encodePayload(schema, { a: 0x1234, b: 0xdeadbeef, c: 0x0123456789abcdefn });
    // Little-endian: a = 34 12, b = ef be ad de, c = ef cd ab 89 67 45 23 01
    expect(enc[0]).toBe(0x34);
    expect(enc[1]).toBe(0x12);
    expect(enc[2]).toBe(0xef);
    expect(enc[3]).toBe(0xbe);
    expect(enc[4]).toBe(0xad);
    expect(enc[5]).toBe(0xde);
    const dec = decodePayload(schema, enc);
    expect(dec.a).toBe(0x1234);
    expect(dec.b).toBe(0xdeadbeef);
    expect(dec.c).toBe(0x0123456789abcdefn);
  });
});

describe('computeDomainPayloadRoot', () => {
  test('H1 deterministic across calls', () => {
    const values = {
      phase: 1,
      dimension: 2,
      parentHash: bytes(32, 0xaa),
      prevStateHash: bytes(32, 0xbb),
    };
    const r1 = computeDomainPayloadRoot(COMMERCE_V1, values);
    const r2 = computeDomainPayloadRoot(COMMERCE_V1, values);
    expect(r1).toEqual(r2);
    expect(r1.byteLength).toBe(32);
  });

  test('H2 different inputs → different roots', () => {
    const a = computeDomainPayloadRoot(COMMERCE_V1, {
      phase: 1,
      dimension: 0,
      parentHash: bytes(32),
      prevStateHash: bytes(32),
    });
    const b = computeDomainPayloadRoot(COMMERCE_V1, {
      phase: 2,
      dimension: 0,
      parentHash: bytes(32),
      prevStateHash: bytes(32),
    });
    expect(a).not.toEqual(b);
  });
});

describe('encodeSchema canonical form', () => {
  test('S1 stable JSON regardless of field insertion order', () => {
    const a: DomainSchema = {
      domainFlag: 1,
      version: 1,
      commitmentMode: 'payload-digest',
      fields: [
        { name: 'a', offset: 0, size: 1, type: 'u8' },
        { name: 'b', offset: 1, size: 1, type: 'u8' },
      ],
    };
    const b: DomainSchema = {
      commitmentMode: 'payload-digest',
      fields: [
        { name: 'a', offset: 0, size: 1, type: 'u8' },
        { name: 'b', offset: 1, size: 1, type: 'u8' },
      ],
      domainFlag: 1,
      version: 1,
    } as DomainSchema; // keys in different declaration order
    expect(encodeSchema(a)).toEqual(encodeSchema(b));
  });

  test('S2 authority is excluded from canonical bytes', () => {
    const base: DomainSchema = {
      domainFlag: 1,
      version: 1,
      commitmentMode: 'payload-digest',
      fields: [{ name: 'x', offset: 0, size: 1, type: 'u8' }],
    };
    const signed: DomainSchema = {
      ...base,
      authority: {
        cert: { certId: 'cert-x', subjectPublicKey: '02'.padEnd(66, 'a') },
        schemaSignature: 'sig-deadbeef',
        schemaBytes: new Uint8Array([1, 2, 3]),
      },
    };
    expect(encodeSchema(base)).toEqual(encodeSchema(signed));
  });
});

```
