---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/calendar/src/__tests__/conflict.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.480517+00:00
---

# packages/calendar/src/__tests__/conflict.test.ts

```ts
import { describe, expect, test, beforeEach, afterEach } from 'bun:test';
import { makeTestDb, d } from './setup.js';
import type { Database } from '@semantos/semantic-objects';
import { findConflicts, rangesOverlap } from '../policy/conflict.js';
import { bookSlot, holdSlot, cancelBooking } from '../api/index.js';

describe('policy/conflict — rangesOverlap', () => {
  test('C1 adjacent ranges do not conflict (half-open)', () => {
    expect(
      rangesOverlap(
        { startAt: d('2026-01-01T10:00Z'), endAt: d('2026-01-01T11:00Z') },
        { startAt: d('2026-01-01T11:00Z'), endAt: d('2026-01-01T12:00Z') },
      ),
    ).toBe(false);
  });
  test('C2 overlapping ranges conflict', () => {
    expect(
      rangesOverlap(
        { startAt: d('2026-01-01T10:00Z'), endAt: d('2026-01-01T12:00Z') },
        { startAt: d('2026-01-01T11:00Z'), endAt: d('2026-01-01T13:00Z') },
      ),
    ).toBe(true);
  });
});

describe('policy/conflict — findConflicts on the shared schedule', () => {
  let db: Database;
  let close: () => Promise<void>;
  beforeEach(async () => { ({ db, close } = await makeTestDb()); });
  afterEach(async () => { await close(); });

  test('C3 two bookings on different hats on the same stream conflict when overlapping', async () => {
    await bookSlot(db, {
      hatId: 'todd-handyman',
      startAt: d('2026-03-10T14:00Z'),
      endAt: d('2026-03-10T16:00Z'),
      subjectKind: 'manual',
      subjectId: 'j1',
      bookedByCertId: 'cert-todd',
    });
    const report = await findConflicts(db, {
      startAt: d('2026-03-10T15:00Z'),
      endAt: d('2026-03-10T17:00Z'),
    });
    expect(report.conflictingBookings.length).toBe(1);
    expect(report.conflictingBookings[0].hatId).toBe('todd-handyman');
  });

  test('C4 non-overlapping booking on different hat does not conflict', async () => {
    await bookSlot(db, {
      hatId: 'todd-handyman',
      startAt: d('2026-03-10T14:00Z'),
      endAt: d('2026-03-10T15:00Z'),
      subjectKind: 'manual',
      subjectId: 'j2',
      bookedByCertId: 'cert-todd',
    });
    const report = await findConflicts(db, {
      startAt: d('2026-03-10T16:00Z'),
      endAt: d('2026-03-10T17:00Z'),
    });
    expect(report.conflictingBookings.length).toBe(0);
  });

  test('C5 ignoreBookingId excludes a specific booking', async () => {
    const b = await bookSlot(db, {
      hatId: 'todd-handyman',
      startAt: d('2026-03-10T14:00Z'),
      endAt: d('2026-03-10T16:00Z'),
      subjectKind: 'manual',
      subjectId: 'j3',
      bookedByCertId: 'cert-todd',
    });
    const report = await findConflicts(db, {
      startAt: d('2026-03-10T14:00Z'),
      endAt: d('2026-03-10T16:00Z'),
      ignoreBookingId: b.id,
    });
    expect(report.conflictingBookings.length).toBe(0);
  });

  test('C6 active hold blocks a conflict check', async () => {
    await holdSlot(db, {
      hatId: 'todd-advisor',
      startAt: d('2026-03-10T14:00Z'),
      endAt: d('2026-03-10T16:00Z'),
      subjectKind: 'manual',
      subjectId: 'c1',
      heldByCertId: 'cert-todd',
    });
    const report = await findConflicts(db, {
      startAt: d('2026-03-10T15:00Z'),
      endAt: d('2026-03-10T17:00Z'),
    });
    expect(report.conflictingHolds.length).toBe(1);
  });

  test('C7 expired hold is NOT reported as conflict', async () => {
    const past = d('2026-02-01T10:00Z');
    await holdSlot(db, {
      hatId: 'todd-advisor',
      startAt: d('2026-04-01T14:00Z'),
      endAt: d('2026-04-01T16:00Z'),
      subjectKind: 'manual',
      subjectId: 'c2',
      heldByCertId: 'cert-todd',
      ttlMinutes: 30,
      now: past,
    });
    const report = await findConflicts(db, {
      startAt: d('2026-04-01T15:00Z'),
      endAt: d('2026-04-01T17:00Z'),
      now: d('2026-03-01T10:00Z'),
    });
    expect(report.conflictingHolds.length).toBe(0);
  });

  test('C8 cancelled booking is NOT reported as conflict', async () => {
    const b = await bookSlot(db, {
      hatId: 'todd-handyman',
      startAt: d('2026-03-10T14:00Z'),
      endAt: d('2026-03-10T16:00Z'),
      subjectKind: 'manual',
      subjectId: 'j8',
      bookedByCertId: 'cert-todd',
    });
    await cancelBooking(db, b.id, 'test');
    const report = await findConflicts(db, {
      startAt: d('2026-03-10T14:00Z'),
      endAt: d('2026-03-10T16:00Z'),
    });
    expect(report.conflictingBookings.length).toBe(0);
  });
});

```
