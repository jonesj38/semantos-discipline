---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/anchor-attestation/src/__tests__/round-trip.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.940880+00:00
---

# core/anchor-attestation/src/__tests__/round-trip.test.ts

```ts
/**
 * RM-042 anchor-attestation round-trip tests.
 *
 * Acceptance (from `docs/SCG-AND-PHASE-H-ROADMAP.md` RM-042):
 *   - An `AnchorAttestation` cell can be constructed, persisted, and
 *     verified end-to-end. The original cell is anchored not by
 *     mutating its header but by pointing an attestation cell at it.
 *   - No header path writes binding fields.
 *
 * Schema v2 (this file): `bumpHash` retired (BRC-74 BUMP mismatch;
 * zombie field never read outside test scaffolding), `anchor_height: u64`
 * promoted to a first-class queryable field for the brain reorg substrate.
 */
import { describe, expect, test } from 'bun:test';
import { createAnchorAttestation, verifyAnchor } from '../operations.js';
import {
  ANCHOR_ATTESTATION_DOMAIN_FLAG,
  anchorAttestationSchemaV2,
  decodePayload,
} from '@semantos/plexus-schema-registry';

function bytes(n: number, fill = 0): Uint8Array {
  const b = new Uint8Array(n);
  if (fill) b.fill(fill);
  return b;
}

describe('createAnchorAttestation (schema v2)', () => {
  test('A1 produces a structured record + encoded payload + 32B root', () => {
    const out = createAnchorAttestation({
      targetCellId: bytes(32, 0xaa),
      txid: bytes(32, 0xbb),
      anchorHeight: 850_000n,
      vout: 1,
      derivationIndex: 7,
    });
    expect(out.attestation.targetCellId.byteLength).toBe(32);
    expect(out.attestation.txid.byteLength).toBe(32);
    expect(out.attestation.anchorHeight).toBe(850_000n);
    expect(out.attestation.vout).toBe(1);
    expect(out.attestation.derivationIndex).toBe(7);
    expect(out.payload).toBeInstanceOf(Uint8Array);
    // v2 payload is 80B tight (targetCellId 32 + txid 32 + height 8 +
    // vout 4 + derivationIndex 4); the encoder rounds up to the next
    // 8B boundary, which 80 already is.
    expect(out.payload.byteLength).toBe(80);
    expect(out.domainPayloadRoot.byteLength).toBe(32);
  });

  test('A2 encoded payload decodes back via the schema', () => {
    const created = createAnchorAttestation({
      targetCellId: bytes(32, 0x11),
      txid: bytes(32, 0x22),
      anchorHeight: 12_345_678_901n,
      vout: 3,
      derivationIndex: 42,
    });
    const decoded = decodePayload(anchorAttestationSchemaV2, created.payload);
    expect(decoded.targetCellId).toEqual(bytes(32, 0x11));
    expect(decoded.txid).toEqual(bytes(32, 0x22));
    expect(decoded.anchor_height).toBe(12_345_678_901n);
    expect(decoded.vout).toBe(3);
    expect(decoded.derivationIndex).toBe(42);
  });

  test('A2b anchor_height encodes little-endian at payload offset 64', () => {
    // Use a recognisable value: 0x00000000_DEADBEEF. Stored LE at
    // bytes 64..72 reads as: EF BE AD DE 00 00 00 00.
    const created = createAnchorAttestation({
      targetCellId: bytes(32, 0x00),
      txid: bytes(32, 0x00),
      anchorHeight: 0xdeadbeefn,
      vout: 0,
      derivationIndex: 0,
    });
    expect(created.payload[64]).toBe(0xef);
    expect(created.payload[65]).toBe(0xbe);
    expect(created.payload[66]).toBe(0xad);
    expect(created.payload[67]).toBe(0xde);
    expect(created.payload[68]).toBe(0x00);
    expect(created.payload[69]).toBe(0x00);
    expect(created.payload[70]).toBe(0x00);
    expect(created.payload[71]).toBe(0x00);
  });

  test('A3 rejects wrong field lengths', () => {
    expect(() =>
      createAnchorAttestation({
        targetCellId: bytes(16),
        txid: bytes(32),
        anchorHeight: 0n,
        vout: 0,
        derivationIndex: 0,
      }),
    ).toThrow(/targetCellId/);
    expect(() =>
      createAnchorAttestation({
        targetCellId: bytes(32),
        txid: bytes(31),
        anchorHeight: 0n,
        vout: 0,
        derivationIndex: 0,
      }),
    ).toThrow(/txid/);
  });

  test('A3b rejects anchorHeight outside the u64 range', () => {
    expect(() =>
      createAnchorAttestation({
        targetCellId: bytes(32),
        txid: bytes(32),
        anchorHeight: -1n,
        vout: 0,
        derivationIndex: 0,
      }),
    ).toThrow(/anchorHeight/);
    expect(() =>
      createAnchorAttestation({
        targetCellId: bytes(32),
        txid: bytes(32),
        anchorHeight: 1n << 64n,
        vout: 0,
        derivationIndex: 0,
      }),
    ).toThrow(/anchorHeight/);
    expect(() =>
      createAnchorAttestation({
        targetCellId: bytes(32),
        txid: bytes(32),
        // bigint required; a plain number must be rejected.
        anchorHeight: 100 as unknown as bigint,
        vout: 0,
        derivationIndex: 0,
      }),
    ).toThrow(/anchorHeight/);
  });

  test('A4 rejects negative vout / derivationIndex', () => {
    expect(() =>
      createAnchorAttestation({
        targetCellId: bytes(32),
        txid: bytes(32),
        anchorHeight: 0n,
        vout: -1,
        derivationIndex: 0,
      }),
    ).toThrow(/vout/);
    expect(() =>
      createAnchorAttestation({
        targetCellId: bytes(32),
        txid: bytes(32),
        anchorHeight: 0n,
        vout: 0,
        derivationIndex: -5,
      }),
    ).toThrow(/derivationIndex/);
  });

  test('A5 defensive-copies the input byte buffers', () => {
    const target = bytes(32, 0xaa);
    const created = createAnchorAttestation({
      targetCellId: target,
      txid: bytes(32, 0xbb),
      anchorHeight: 0n,
      vout: 0,
      derivationIndex: 0,
    });
    target.fill(0xff);
    expect(created.attestation.targetCellId[0]).toBe(0xaa);
  });
});

describe('verifyAnchor (schema v2)', () => {
  test('V1 accepts a well-formed attestation pointing at the expected cell', () => {
    const targetCellId = bytes(32, 0x11);
    const created = createAnchorAttestation({
      targetCellId,
      txid: bytes(32, 0x22),
      anchorHeight: 900_000n,
      vout: 4,
      derivationIndex: 8,
    });
    const result = verifyAnchor({
      expectedTargetCellId: targetCellId,
      payload: created.payload,
      domainPayloadRoot: created.domainPayloadRoot,
    });
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.attestation.vout).toBe(4);
    expect(result.attestation.anchorHeight).toBe(900_000n);
  });

  test('V2 rejects attestation pointing at a different cell', () => {
    const created = createAnchorAttestation({
      targetCellId: bytes(32, 0x11),
      txid: bytes(32, 0x22),
      anchorHeight: 1n,
      vout: 0,
      derivationIndex: 0,
    });
    const result = verifyAnchor({
      expectedTargetCellId: bytes(32, 0xff),
      payload: created.payload,
      domainPayloadRoot: created.domainPayloadRoot,
    });
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe('TARGET_MISMATCH');
  });

  test('V3 rejects payload/root mismatch (tampered root)', () => {
    const targetCellId = bytes(32, 0x11);
    const created = createAnchorAttestation({
      targetCellId,
      txid: bytes(32, 0x22),
      anchorHeight: 0n,
      vout: 0,
      derivationIndex: 0,
    });
    const tamperedRoot = bytes(32, 0xee);
    const result = verifyAnchor({
      expectedTargetCellId: targetCellId,
      payload: created.payload,
      domainPayloadRoot: tamperedRoot,
    });
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe('PAYLOAD_ROOT_MISMATCH');
  });

  test('V4 ANCHOR_ATTESTATION_DOMAIN_FLAG matches RM-004 allocation', () => {
    expect(ANCHOR_ATTESTATION_DOMAIN_FLAG).toBe(0x0001fe02);
  });
});

```
