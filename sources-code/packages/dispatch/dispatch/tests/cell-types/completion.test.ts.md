---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/dispatch/dispatch/tests/cell-types/completion.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.513132+00:00
---

# packages/dispatch/dispatch/tests/cell-types/completion.test.ts

```ts
/**
 * D-O11 phase O11b — dispatch.completion.v1 cell-type conformance.
 */

import { describe, expect, test } from 'bun:test';
import {
  dispatchCompletionCellType,
  COMPLETION_KINDS,
  type DispatchCompletion,
} from '../../src/cell-types/index.js';

const VALID_COMPLETED: DispatchCompletion = {
  envelopeId: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
  completionKind: 'completed',
  completedAt: '2026-05-01T11:00:00.000Z',
  completedByHat: 'tradie-todd',
  note: 'HVAC compressor replaced; sensor reads 22°C ambient',
};

const VALID_INVOICED: DispatchCompletion = {
  envelopeId: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
  completionKind: 'invoiced',
  completedAt: '2026-05-01T11:30:00.000Z',
  invoiceAmountCents: 175_000,
  completedByHat: 'tradie-todd',
};

describe('dispatch.completion.v1 cell type', () => {
  test('canonical name + LINEAR + 64-char typeHashHex', () => {
    expect(dispatchCompletionCellType.name).toBe('dispatch.completion.v1');
    expect(dispatchCompletionCellType.linearity).toBe('LINEAR');
    expect(dispatchCompletionCellType.typeHashHex).toHaveLength(64);
  });

  test('round-trip — completed kind', () => {
    const back = dispatchCompletionCellType.unpack(
      dispatchCompletionCellType.pack(VALID_COMPLETED),
    );
    expect(back).toEqual(VALID_COMPLETED);
  });

  test('round-trip — invoiced kind with invoiceAmountCents', () => {
    const back = dispatchCompletionCellType.unpack(
      dispatchCompletionCellType.pack(VALID_INVOICED),
    );
    expect(back).toEqual(VALID_INVOICED);
  });

  test('rejects invoiced kind without invoiceAmountCents', () => {
    expect(() =>
      dispatchCompletionCellType.pack({
        envelopeId: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
        completionKind: 'invoiced',
        completedAt: '2026-05-01T11:30:00.000Z',
        completedByHat: 'tradie-todd',
      }),
    ).toThrow(/invoiceAmountCents/);
  });

  test('rejects unknown completionKind', () => {
    expect(() =>
      dispatchCompletionCellType.pack({
        ...VALID_COMPLETED,
        completionKind: 'frobnicated' as DispatchCompletion['completionKind'],
      }),
    ).toThrow(/completionKind/);
  });

  test('all canonical kinds parse', () => {
    for (const kind of COMPLETION_KINDS) {
      const cell: DispatchCompletion = {
        ...VALID_COMPLETED,
        completionKind: kind,
        ...(kind === 'invoiced' ? { invoiceAmountCents: 100 } : {}),
      };
      const back = dispatchCompletionCellType.unpack(
        dispatchCompletionCellType.pack(cell),
      );
      expect(back.completionKind).toBe(kind);
    }
  });

  test('rejects negative invoiceAmountCents', () => {
    expect(() =>
      dispatchCompletionCellType.pack({
        ...VALID_INVOICED,
        invoiceAmountCents: -1,
      }),
    ).toThrow(/invoiceAmountCents/);
  });
});

```
