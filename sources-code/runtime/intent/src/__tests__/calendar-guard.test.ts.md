---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/__tests__/calendar-guard.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.357328+00:00
---

# runtime/intent/src/__tests__/calendar-guard.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import { extractProposedSlot } from '../calendar-guard';

describe('extractProposedSlot', () => {
  const valid = {
    proposedSlot: {
      startAt: '2026-07-01T14:00:00Z',
      endAt: '2026-07-01T16:00:00Z',
      hatId: 'todd-handyman',
      subjectKind: 'ojt-job',
      subjectId: 'job-1001',
    },
  };

  test('E1 parses a valid proposedSlot delta', () => {
    const slot = extractProposedSlot(valid);
    expect(slot).not.toBeNull();
    expect(slot!.hatId).toBe('todd-handyman');
    expect(slot!.startAt.toISOString()).toBe('2026-07-01T14:00:00.000Z');
    expect(slot!.endAt.toISOString()).toBe('2026-07-01T16:00:00.000Z');
    expect(slot!.subjectKind).toBe('ojt-job');
    expect(slot!.subjectId).toBe('job-1001');
  });

  test('E2 accepts Date objects, numbers, and ISO strings for startAt/endAt', () => {
    const d = new Date('2026-08-01T10:00:00Z');
    const withDate = extractProposedSlot({
      proposedSlot: {
        ...valid.proposedSlot,
        startAt: d,
        endAt: new Date('2026-08-01T11:00:00Z'),
      },
    });
    expect(withDate!.startAt.getTime()).toBe(d.getTime());

    const withNumber = extractProposedSlot({
      proposedSlot: {
        ...valid.proposedSlot,
        startAt: Date.UTC(2026, 7, 1, 10, 0, 0),
        endAt: Date.UTC(2026, 7, 1, 11, 0, 0),
      },
    });
    expect(withNumber).not.toBeNull();
  });

  test('E3 returns null on missing proposedSlot', () => {
    expect(extractProposedSlot({})).toBeNull();
    expect(extractProposedSlot({ other: 'x' })).toBeNull();
  });

  test('E4 returns null on missing fields', () => {
    expect(
      extractProposedSlot({
        proposedSlot: { startAt: '2026-01-01T10:00Z', endAt: '2026-01-01T11:00Z' },
      }),
    ).toBeNull();
    expect(
      extractProposedSlot({
        proposedSlot: {
          ...valid.proposedSlot,
          hatId: undefined,
        },
      }),
    ).toBeNull();
  });

  test('E5 returns null when startAt >= endAt (inverted range)', () => {
    expect(
      extractProposedSlot({
        proposedSlot: {
          ...valid.proposedSlot,
          startAt: '2026-07-01T16:00Z',
          endAt: '2026-07-01T14:00Z',
        },
      }),
    ).toBeNull();
    expect(
      extractProposedSlot({
        proposedSlot: {
          ...valid.proposedSlot,
          startAt: '2026-07-01T14:00Z',
          endAt: '2026-07-01T14:00Z',
        },
      }),
    ).toBeNull();
  });

  test('E6 returns null on invalid date strings', () => {
    expect(
      extractProposedSlot({
        proposedSlot: { ...valid.proposedSlot, startAt: 'tomorrow at tea-time' },
      }),
    ).toBeNull();
  });

  test('E7 returns null when delta is not an object', () => {
    expect(extractProposedSlot(null)).toBeNull();
    expect(extractProposedSlot(undefined)).toBeNull();
    expect(extractProposedSlot('nope')).toBeNull();
    expect(extractProposedSlot(42)).toBeNull();
  });

  test('E8 passes proposedByCertId when present', () => {
    const slot = extractProposedSlot({
      proposedSlot: { ...valid.proposedSlot, proposedByCertId: 'cert-todd' },
    });
    expect(slot!.proposedByCertId).toBe('cert-todd');
  });
});

```
