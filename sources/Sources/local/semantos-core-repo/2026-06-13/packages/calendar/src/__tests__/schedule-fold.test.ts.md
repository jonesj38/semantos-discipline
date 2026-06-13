---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/calendar/src/__tests__/schedule-fold.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.479383+00:00
---

# packages/calendar/src/__tests__/schedule-fold.test.ts

```ts
/**
 * Pure unit tests for the fold. No DB — construct patches by hand and
 * verify state reduction.
 */
import { describe, expect, test } from 'bun:test';
import { fold, type SchedulePatch } from '../domain/schedule.js';

function mkPatch(
  kind: SchedulePatch['kind'],
  delta: SchedulePatch['delta'],
  createdAt = new Date('2026-05-01T10:00Z'),
): SchedulePatch {
  return {
    id: `patch_${Math.random().toString(36).slice(2, 8)}`,
    objectId: 'schedule-primary',
    kind,
    timestamp: createdAt.getTime(),
    delta,
    facetId: null,
    facetCapabilities: null,
    lexicon: 'calendar',
    prevStateHash: null,
    newStateHash: 'h',
    authorObjectId: null,
    linearity: 'LINEAR',
    consumed: true,
    createdAt,
  };
}

describe('domain/schedule — fold', () => {
  test('S1 empty stream yields empty state', () => {
    const state = fold([]);
    expect(state.holds.size).toBe(0);
    expect(state.bookings.size).toBe(0);
  });

  test('S2 hold patch adds a hold', () => {
    const state = fold([
      mkPatch('hold', {
        op: 'hold',
        holdId: 'h1',
        hatId: 'todd-handyman',
        startAt: '2026-05-10T14:00Z',
        endAt: '2026-05-10T15:00Z',
        subjectKind: 'manual',
        subjectId: 's1',
        heldByCertId: 'cert-todd',
        expiresAt: '2026-05-10T14:30Z',
      }),
    ]);
    expect(state.holds.size).toBe(1);
    const h = state.holds.get('h1')!;
    expect(h.hatId).toBe('todd-handyman');
    expect(h.releasedAt).toBeNull();
  });

  test('S3 book patch adds a booking', () => {
    const state = fold([
      mkPatch('book', {
        op: 'book',
        bookingId: 'b1',
        hatId: 'todd-handyman',
        startAt: '2026-05-10T14:00Z',
        endAt: '2026-05-10T15:00Z',
        subjectKind: 'manual',
        subjectId: 's1',
        bookedByCertId: 'cert-todd',
      }),
    ]);
    expect(state.bookings.size).toBe(1);
    expect(state.bookings.get('b1')!.cancelledAt).toBeNull();
  });

  test('S4 hold → book with fromHoldId releases the hold', () => {
    const state = fold([
      mkPatch('hold', {
        op: 'hold',
        holdId: 'h1',
        hatId: 'todd-handyman',
        startAt: '2026-05-10T14:00Z',
        endAt: '2026-05-10T15:00Z',
        subjectKind: 'manual',
        subjectId: 's1',
        heldByCertId: 'cert-todd',
        expiresAt: '2026-05-10T14:30Z',
      }),
      mkPatch(
        'book',
        {
          op: 'book',
          bookingId: 'b1',
          hatId: 'todd-handyman',
          startAt: '2026-05-10T14:00Z',
          endAt: '2026-05-10T15:00Z',
          subjectKind: 'manual',
          subjectId: 's1',
          bookedByCertId: 'cert-todd',
          fromHoldId: 'h1',
        },
        new Date('2026-05-01T10:01Z'),
      ),
    ]);
    expect(state.bookings.size).toBe(1);
    const h = state.holds.get('h1')!;
    expect(h.releasedAt).not.toBeNull();
    expect(state.bookings.get('b1')!.fromHoldId).toBe('h1');
  });

  test('S5 release patch releases an active hold', () => {
    const state = fold([
      mkPatch('hold', {
        op: 'hold',
        holdId: 'h1',
        hatId: 'todd-advisor',
        startAt: '2026-05-10T14:00Z',
        endAt: '2026-05-10T15:00Z',
        subjectKind: 'manual',
        subjectId: 's1',
        heldByCertId: 'cert-todd',
        expiresAt: '2026-05-10T14:30Z',
      }),
      mkPatch('release', { op: 'release', holdId: 'h1' }, new Date('2026-05-01T10:01Z')),
    ]);
    expect(state.holds.get('h1')!.releasedAt).not.toBeNull();
  });

  test('S6 cancel patch marks booking cancelled', () => {
    const state = fold([
      mkPatch('book', {
        op: 'book',
        bookingId: 'b1',
        hatId: 'todd-handyman',
        startAt: '2026-05-10T14:00Z',
        endAt: '2026-05-10T15:00Z',
        subjectKind: 'manual',
        subjectId: 's1',
        bookedByCertId: 'cert-todd',
      }),
      mkPatch('cancel', { op: 'cancel', bookingId: 'b1', reason: 'rain' }, new Date('2026-05-01T11:00Z')),
    ]);
    const b = state.bookings.get('b1')!;
    expect(b.cancelledAt).not.toBeNull();
    expect(b.cancelReason).toBe('rain');
  });

  test('S7 release on unknown hold is a no-op', () => {
    const state = fold([mkPatch('release', { op: 'release', holdId: 'nope' })]);
    expect(state.holds.size).toBe(0);
  });

  test('S8 cancel on unknown booking is a no-op', () => {
    const state = fold([mkPatch('cancel', { op: 'cancel', bookingId: 'nope', reason: 'x' })]);
    expect(state.bookings.size).toBe(0);
  });

  test('S9 double release is idempotent (releasedAt stays at first)', () => {
    const t0 = new Date('2026-05-01T10:00Z');
    const t1 = new Date('2026-05-01T10:05Z');
    const t2 = new Date('2026-05-01T10:10Z');
    const state = fold([
      mkPatch('hold', {
        op: 'hold',
        holdId: 'h1',
        hatId: 'h',
        startAt: '2026-05-10T14:00Z',
        endAt: '2026-05-10T15:00Z',
        subjectKind: 'manual',
        subjectId: 's1',
        heldByCertId: 'c',
        expiresAt: '2026-05-10T15:30Z',
      }, t0),
      mkPatch('release', { op: 'release', holdId: 'h1' }, t1),
      mkPatch('release', { op: 'release', holdId: 'h1' }, t2),
    ]);
    expect(state.holds.get('h1')!.releasedAt!.toISOString()).toBe(t1.toISOString());
  });

  test('S10 multi-hat patches all land in the same schedule stream', () => {
    const state = fold([
      mkPatch('book', {
        op: 'book',
        bookingId: 'b-hand',
        hatId: 'todd-handyman',
        startAt: '2026-05-10T10:00Z',
        endAt: '2026-05-10T11:00Z',
        subjectKind: 'ojt-job',
        subjectId: 'j-1',
        bookedByCertId: 'cert-todd',
      }),
      mkPatch('book', {
        op: 'book',
        bookingId: 'b-adv',
        hatId: 'todd-advisor',
        startAt: '2026-05-10T13:00Z',
        endAt: '2026-05-10T14:00Z',
        subjectKind: 'brap-consult',
        subjectId: 'c-1',
        bookedByCertId: 'cert-todd',
      }),
    ]);
    expect(state.bookings.size).toBe(2);
    expect(new Set([...state.bookings.values()].map((b) => b.hatId))).toEqual(
      new Set(['todd-handyman', 'todd-advisor']),
    );
  });
});

```
