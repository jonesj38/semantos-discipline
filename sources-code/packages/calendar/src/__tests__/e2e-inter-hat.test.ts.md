---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/calendar/src/__tests__/e2e-inter-hat.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.479671+00:00
---

# packages/calendar/src/__tests__/e2e-inter-hat.test.ts

```ts
/**
 * E2E — validates the core A3 thesis under the rewrite:
 *
 *   OJT (handyman hat) books 14:00–16:00 → BRAP (advisor hat) attempts
 *   to hold 15:00–17:00 → reports CalendarConflictError because both
 *   patches land on the same schedule stream.
 */
import { describe, expect, test } from 'bun:test';
import { makeTestDb, d } from './setup.js';
import {
  bookSlot,
  holdSlot,
  listBookings,
  CalendarConflictError,
} from '../api/index.js';

describe('e2e — inter-hat booking guard (one stream)', () => {
  test('E1 OJT books handyman → BRAP advisor overlap is rejected', async () => {
    const { db, close } = await makeTestDb();
    try {
      const ojtBooking = await bookSlot(db, {
        hatId: 'todd-handyman',
        startAt: d('2026-07-01T14:00Z'),
        endAt: d('2026-07-01T16:00Z'),
        subjectKind: 'ojt-job',
        subjectId: 'job-1001',
        bookedByCertId: 'cert-todd',
        conversationId: 'ojt-conv',
      });
      expect(ojtBooking.id).toMatch(/^book_/);

      let err: unknown = null;
      try {
        await holdSlot(db, {
          hatId: 'todd-advisor',
          startAt: d('2026-07-01T15:00Z'),
          endAt: d('2026-07-01T17:00Z'),
          subjectKind: 'brap-consult',
          subjectId: 'consult-5001',
          heldByCertId: 'cert-todd',
        });
      } catch (e) { err = e; }
      expect(err).toBeInstanceOf(CalendarConflictError);
      const cerr = err as CalendarConflictError;
      expect(cerr.conflictingBookings.length).toBe(1);
      expect(cerr.conflictingBookings[0].hatId).toBe('todd-handyman');

      const laterHold = await holdSlot(db, {
        hatId: 'todd-advisor',
        startAt: d('2026-07-01T17:00Z'),
        endAt: d('2026-07-01T18:00Z'),
        subjectKind: 'brap-consult',
        subjectId: 'consult-5002',
        heldByCertId: 'cert-todd',
      });
      expect(laterHold.id).toMatch(/^hold_/);

      const bookings = await listBookings(db);
      expect(bookings.length).toBe(1);
      expect(bookings[0].id).toBe(ojtBooking.id);
    } finally {
      await close();
    }
  });
});

```
