---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/dispatch/dispatch/tests/cell-types/envelope.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.512833+00:00
---

# packages/dispatch/dispatch/tests/cell-types/envelope.test.ts

```ts
/**
 * D-O11 phase O11b — dispatch.envelope.v1 cell-type conformance.
 */

import { describe, expect, test } from 'bun:test';
import {
  dispatchEnvelopeCellType,
  type DispatchEnvelope,
} from '../../src/cell-types/index.js';

const VALID: DispatchEnvelope = {
  envelopeId: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
  fromTenant: 'acme-pm.com.au',
  fromHat: 'pm-alice',
  toTenant: 'oddjobtodd.info',
  toHat: 'tradie-todd',
  payloadType: 're-desk.maintenance-request.v1',
  payload: 'deadbeefcafebabe',
  signedBy: 'cert-id-of-pm-alice-1234567890abcdef',
  createdAt: '2026-05-01T09:00:00.000Z',
};

describe('dispatch.envelope.v1 cell type', () => {
  test('canonical name + LINEAR linearity + 64-char typeHashHex', () => {
    expect(dispatchEnvelopeCellType.name).toBe('dispatch.envelope.v1');
    expect(dispatchEnvelopeCellType.linearity).toBe('LINEAR');
    expect(dispatchEnvelopeCellType.typeHashHex).toHaveLength(64);
  });

  test('round-trip pack/unpack/pack is byte-equal', () => {
    const b1 = dispatchEnvelopeCellType.pack(VALID);
    const back = dispatchEnvelopeCellType.unpack(b1);
    const b2 = dispatchEnvelopeCellType.pack(back);
    expect(b1).toEqual(b2);
    expect(back).toEqual(VALID);
  });

  test('rejects same-hat dispatch (tenant + hat both equal)', () => {
    expect(() =>
      dispatchEnvelopeCellType.pack({
        ...VALID,
        fromTenant: 'me.com',
        toTenant: 'me.com',
        fromHat: 'self',
        toHat: 'self',
      }),
    ).toThrow(/same-hat dispatch is forbidden/);
  });

  test('accepts same-tenant dispatch across different hats (carpenter→musician case)', () => {
    // Chapter 29's hat-isolation example: a single operator can run
    // dispatches between their own hats. Forbidden only when BOTH
    // tenant + hat match.
    const cell: DispatchEnvelope = {
      ...VALID,
      fromTenant: 'me.com',
      toTenant: 'me.com',
      fromHat: 'carpenter',
      toHat: 'musician',
    };
    expect(() => dispatchEnvelopeCellType.pack(cell)).not.toThrow();
  });

  test('rejects malformed envelopeId', () => {
    expect(() =>
      dispatchEnvelopeCellType.pack({ ...VALID, envelopeId: 'not-uuid' }),
    ).toThrow(/envelopeId/);
  });

  test('rejects uppercase tenant domain', () => {
    expect(() =>
      dispatchEnvelopeCellType.pack({ ...VALID, fromTenant: 'AcmePM.com' }),
    ).toThrow(/fromTenant/);
  });

  test('rejects uppercase hat-id', () => {
    expect(() =>
      dispatchEnvelopeCellType.pack({ ...VALID, toHat: 'TradieTodd' }),
    ).toThrow(/toHat/);
  });

  test('rejects odd-length payload hex', () => {
    expect(() =>
      dispatchEnvelopeCellType.pack({ ...VALID, payload: 'abc' }),
    ).toThrow(/payload/);
  });

  test('accepts empty payload (degenerate but legal)', () => {
    expect(() =>
      dispatchEnvelopeCellType.pack({ ...VALID, payload: '' }),
    ).not.toThrow();
  });
});

```
