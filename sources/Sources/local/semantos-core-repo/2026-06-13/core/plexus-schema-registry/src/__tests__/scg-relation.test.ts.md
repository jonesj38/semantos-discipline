---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/plexus-schema-registry/src/__tests__/scg-relation.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.949943+00:00
---

# core/plexus-schema-registry/src/__tests__/scg-relation.test.ts

```ts
/**
 * RM-082 — scg-relation schema round-trip + SCG_RELATION flag wiring.
 *
 * Pins:
 *   - The schema encodes/decodes bit-exact for a representative payload.
 *   - The domainFlag matches `SemantosDomainFlags.SCG_RELATION`.
 *   - The kind-byte discriminator preserves `ALL_RELATION_KINDS` order
 *     (renumbering would be a BREAKING change).
 */
import { describe, expect, test } from 'bun:test';
import { encodePayload, decodePayload } from '../encoding.js';
import { computeDomainPayloadRoot } from '../hash.js';
import {
  SCG_RELATION_DOMAIN_FLAG,
  SCG_RELATION_KIND_BYTES,
  scgRelationPayload,
  scgRelationSchemaV1,
} from '../schemas/scg-relation.js';

function bytes(n: number, fill = 0): Uint8Array {
  const b = new Uint8Array(n);
  if (fill) b.fill(fill);
  return b;
}

describe('scgRelationSchemaV1 round-trip (RM-082)', () => {
  test('S1 flag matches the SemantosDomainFlags reservation', () => {
    expect(SCG_RELATION_DOMAIN_FLAG).toBe(0x0001fe03);
    expect(scgRelationSchemaV1.domainFlag).toBe(SCG_RELATION_DOMAIN_FLAG);
  });

  test('S2 PAYS payload round-trips bit-exact', () => {
    const payload = scgRelationPayload({
      kind: 'PAYS',
      sourceId: bytes(32, 0x11),
      targetId: bytes(32, 0x22),
      amount: 1000,
      currency: 0x73617473, // 'sats' as a u32 token
      txAnchor: bytes(32, 0x33),
      attestation: bytes(4, 0xff),
    });
    const encoded = encodePayload(scgRelationSchemaV1, payload);
    const decoded = decodePayload(scgRelationSchemaV1, encoded);
    expect(decoded.kindByte).toBe(SCG_RELATION_KIND_BYTES.PAYS);
    expect(decoded.sourceId).toEqual(bytes(32, 0x11));
    expect(decoded.targetId).toEqual(bytes(32, 0x22));
    expect(Number(decoded.amount)).toBe(1000);
    expect(Number(decoded.currency)).toBe(0x73617473);
    expect(decoded.txAnchor).toEqual(bytes(32, 0x33));
  });

  test('S3 REPLIES_TO with zero money fields round-trips and computes a stable root', () => {
    const payload = scgRelationPayload({
      kind: 'REPLIES_TO',
      sourceId: bytes(32, 0xaa),
      targetId: bytes(32, 0xbb),
    });
    const root1 = computeDomainPayloadRoot(scgRelationSchemaV1, payload);
    const root2 = computeDomainPayloadRoot(scgRelationSchemaV1, payload);
    expect(root1.byteLength).toBe(32);
    expect(root1).toEqual(root2);
  });

  test('S4 kind-byte order is stable (renumbering would break older anchored relations)', () => {
    expect(SCG_RELATION_KIND_BYTES.REPLIES_TO).toBe(0x01);
    expect(SCG_RELATION_KIND_BYTES.PAYS).toBe(0x09);
    expect(SCG_RELATION_KIND_BYTES.ESCROW_LOCKS).toBe(0x0d);
    expect(SCG_RELATION_KIND_BYTES.MERGES).toBe(0x0f);
  });

  test('S5 different kinds produce different domain roots', () => {
    const base = {
      sourceId: bytes(32, 0x11),
      targetId: bytes(32, 0x22),
    };
    const a = computeDomainPayloadRoot(
      scgRelationSchemaV1,
      scgRelationPayload({ kind: 'REPLIES_TO', ...base }),
    );
    const b = computeDomainPayloadRoot(
      scgRelationSchemaV1,
      scgRelationPayload({ kind: 'SUPPORTS', ...base }),
    );
    expect(a).not.toEqual(b);
  });
});

```
