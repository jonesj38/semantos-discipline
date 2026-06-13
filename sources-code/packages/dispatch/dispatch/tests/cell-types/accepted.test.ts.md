---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/dispatch/dispatch/tests/cell-types/accepted.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.512544+00:00
---

# packages/dispatch/dispatch/tests/cell-types/accepted.test.ts

```ts
/**
 * D-O11 phase O11b — dispatch.accepted.v1 cell-type conformance.
 */

import { describe, expect, test } from 'bun:test';
import {
  dispatchAcceptedCellType,
  type DispatchAccepted,
} from '../../src/cell-types/index.js';

const VALID: DispatchAccepted = {
  envelopeId: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
  localCellId: '11111111-2222-3333-4444-555555555555',
  localCellType: 'oddjobz.job.v1',
  acceptedAt: '2026-05-01T09:05:00.000Z',
  acceptedByHat: 'tradie-todd',
};

describe('dispatch.accepted.v1 cell type', () => {
  test('canonical name + LINEAR + 64-char typeHashHex', () => {
    expect(dispatchAcceptedCellType.name).toBe('dispatch.accepted.v1');
    expect(dispatchAcceptedCellType.linearity).toBe('LINEAR');
    expect(dispatchAcceptedCellType.typeHashHex).toHaveLength(64);
  });

  test('round-trip pack/unpack', () => {
    const back = dispatchAcceptedCellType.unpack(
      dispatchAcceptedCellType.pack(VALID),
    );
    expect(back).toEqual(VALID);
  });

  test('rejects malformed envelopeId', () => {
    expect(() =>
      dispatchAcceptedCellType.pack({ ...VALID, envelopeId: 'nope' }),
    ).toThrow(/envelopeId/);
  });

  test('rejects empty localCellId', () => {
    expect(() =>
      dispatchAcceptedCellType.pack({ ...VALID, localCellId: '' }),
    ).toThrow(/localCellId/);
  });
});

```
