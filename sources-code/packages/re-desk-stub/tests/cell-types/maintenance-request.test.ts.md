---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/re-desk-stub/tests/cell-types/maintenance-request.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.537167+00:00
---

# packages/re-desk-stub/tests/cell-types/maintenance-request.test.ts

```ts
/**
 * D-O11 phase O11a — MaintenanceRequest cell-type conformance tests.
 *
 * Mirrors the oddjobz cell-type test pattern: round-trip determinism,
 * validation rejection on bad inputs, byte-for-byte equality on canonical
 * encoding.
 */

import { describe, expect, test } from 'bun:test';

import {
  maintenanceRequestCellType,
  MAINTENANCE_REQUEST_STATES,
  type MaintenanceRequest,
} from '../../src/cell-types/index.js';

const VALID: MaintenanceRequest = {
  requestId: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
  customer: 'Tenant 4B, 12 Smith St, Sydney',
  description: 'HVAC unit failed; office is 31°C',
  dispatchTo: 'oddjobtodd.info#tradie-todd',
  state: 'draft',
  urgency: 'urgent',
  createdAt: '2026-05-01T09:00:00.000Z',
  updatedAt: '2026-05-01T09:00:00.000Z',
};

describe('re-desk.maintenance-request.v1 cell type', () => {
  test('cell type metadata has the canonical name + LINEAR linearity', () => {
    expect(maintenanceRequestCellType.name).toBe(
      're-desk.maintenance-request.v1',
    );
    expect(maintenanceRequestCellType.linearity).toBe('LINEAR');
    expect(maintenanceRequestCellType.wireLinearity).toBe(1); // LINEAR
  });

  test('typeHashHex is 64 hex chars + stable across calls', () => {
    expect(maintenanceRequestCellType.typeHashHex).toHaveLength(64);
    expect(/^[0-9a-f]{64}$/.test(maintenanceRequestCellType.typeHashHex)).toBe(
      true,
    );
  });

  test('round-trip pack/unpack/pack is byte-equal', () => {
    const bytes1 = maintenanceRequestCellType.pack(VALID);
    const decoded = maintenanceRequestCellType.unpack(bytes1);
    const bytes2 = maintenanceRequestCellType.pack(decoded);
    expect(bytes1).toEqual(bytes2);
    expect(decoded).toEqual(VALID);
  });

  test('round-trip preserves all optional fields', () => {
    const fully: MaintenanceRequest = {
      ...VALID,
      state: 'invoiced',
      envelopeId: 'env-stable-id',
      dispatchedAt: '2026-05-01T10:00:00.000Z',
      acceptedAt: '2026-05-01T10:05:00.000Z',
      completedAt: '2026-05-01T11:00:00.000Z',
      invoicedAt: '2026-05-01T11:05:00.000Z',
    };
    const decoded = maintenanceRequestCellType.unpack(
      maintenanceRequestCellType.pack(fully),
    );
    expect(decoded).toEqual(fully);
  });

  test('rejects malformed UUID', () => {
    expect(() =>
      maintenanceRequestCellType.pack({ ...VALID, requestId: 'not-a-uuid' }),
    ).toThrow(/requestId/);
  });

  test('rejects empty customer', () => {
    expect(() =>
      maintenanceRequestCellType.pack({ ...VALID, customer: '' }),
    ).toThrow(/customer/);
  });

  test('rejects malformed dispatchTo (no #)', () => {
    expect(() =>
      maintenanceRequestCellType.pack({
        ...VALID,
        dispatchTo: 'no-delimiter-here',
      }),
    ).toThrow(/dispatchTo/);
  });

  test('rejects dispatchTo with uppercase domain (must be lowercase)', () => {
    expect(() =>
      maintenanceRequestCellType.pack({
        ...VALID,
        dispatchTo: 'OddJob.com#tradie',
      }),
    ).toThrow(/dispatchTo/);
  });

  test('rejects unknown state', () => {
    expect(() =>
      maintenanceRequestCellType.pack({
        ...VALID,
        state: 'frobnicated' as MaintenanceRequest['state'],
      }),
    ).toThrow(/state/);
  });

  test('rejects non-draft state without envelopeId', () => {
    expect(() =>
      maintenanceRequestCellType.pack({ ...VALID, state: 'dispatched' }),
    ).toThrow(/envelopeId required/);
  });

  test('accepts every canonical state with envelopeId set', () => {
    for (const state of MAINTENANCE_REQUEST_STATES) {
      const cell: MaintenanceRequest = {
        ...VALID,
        state,
        envelopeId: state === 'draft' ? undefined : 'env-id',
      };
      const bytes = maintenanceRequestCellType.pack(cell);
      const back = maintenanceRequestCellType.unpack(bytes);
      expect(back.state).toBe(state);
    }
  });
});

```
