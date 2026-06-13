---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/calendar/src/__tests__/api.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.480796+00:00
---

# packages/calendar/src/__tests__/api.test.ts

```ts
import { describe, expect, test, beforeEach, afterEach } from 'bun:test';
import { makeTestDb, d } from './setup.js';
import type { Database } from '@semantos/semantic-objects';
import {
  holdSlot,
  bookSlot,
  releaseSlot,
  cancelBooking,
  listBookings,
  listHolds,
  CalendarConflictError,
  HoldExpiredError,
  HoldNotFoundError,
  BookingNotFoundError,
  setConversationPatchWriter,
  type CalendarPatchEvent,
} from '../api/index.js';

describe('api — holdSlot', () => {
  let db: Database;
  let close: () => Promise<void>;
  beforeEach(async () => { ({ db, close } = await makeTestDb()); });
  afterEach(async () => {
    await close();
    setConversationPatchWriter(null);
  });

  test('A1 happy path', async () => {
    const hold = await holdSlot(db, {
      hatId: 'todd-handyman',
      startAt: d('2026-04-01T14:00Z'),
      endAt: d('2026-04-01T15:00Z'),
      subjectKind: 'manual',
      subjectId: 'j1',
      heldByCertId: 'cert-todd',
    });
    expect(hold.id).toMatch(/^hold_/);
    expect(hold.expiresAt.getTime()).toBeGreaterThan(Date.now());
  });

  test('A2 hold conflicts with existing booking on different hat', async () => {
    await bookSlot(db, {
      hatId: 'todd-handyman',
      startAt: d('2026-04-01T14:00Z'),
      endAt: d('2026-04-01T16:00Z'),
      subjectKind: 'manual',
      subjectId: 'j2',
      bookedByCertId: 'cert-todd',
    });
    await expect(
      holdSlot(db, {
        hatId: 'todd-advisor', // different hat, same stream, overlapping → conflict
        startAt: d('2026-04-01T15:00Z'),
        endAt: d('2026-04-01T17:00Z'),
        subjectKind: 'manual',
        subjectId: 'c1',
        heldByCertId: 'cert-todd',
      }),
    ).rejects.toBeInstanceOf(CalendarConflictError);
  });
});

describe('api — bookSlot', () => {
  let db: Database;
  let close: () => Promise<void>;
  beforeEach(async () => { ({ db, close } = await makeTestDb()); });
  afterEach(async () => {
    await close();
    setConversationPatchWriter(null);
  });

  test('A3 book without hold', async () => {
    const b = await bookSlot(db, {
      hatId: 'todd-handyman',
      startAt: d('2026-04-01T14:00Z'),
      endAt: d('2026-04-01T15:00Z'),
      subjectKind: 'manual',
      subjectId: 'j3',
      bookedByCertId: 'cert-todd',
    });
    expect(b.id).toMatch(/^book_/);
    expect(b.cancelledAt).toBeNull();
  });

  test('A4 hold → book converts hold (released) + creates booking with fromHoldId', async () => {
    const hold = await holdSlot(db, {
      hatId: 'todd-handyman',
      startAt: d('2026-04-01T14:00Z'),
      endAt: d('2026-04-01T15:00Z'),
      subjectKind: 'manual',
      subjectId: 'j4',
      heldByCertId: 'cert-todd',
    });
    const booking = await bookSlot(db, {
      hatId: 'todd-handyman',
      startAt: d('2026-04-01T14:00Z'),
      endAt: d('2026-04-01T15:00Z'),
      subjectKind: 'manual',
      subjectId: 'j4',
      bookedByCertId: 'cert-todd',
      holdId: hold.id,
    });
    expect(booking.fromHoldId).toBe(hold.id);
    const heldIncluding = await listHolds(db, { includeReleased: true });
    expect(heldIncluding[0].releasedAt).not.toBeNull();
  });

  test('A5 bookSlot with unknown holdId throws HoldNotFoundError', async () => {
    await expect(
      bookSlot(db, {
        hatId: 'todd-handyman',
        startAt: d('2026-04-01T14:00Z'),
        endAt: d('2026-04-01T15:00Z'),
        subjectKind: 'manual',
        subjectId: 'j5',
        bookedByCertId: 'cert-todd',
        holdId: 'hold_nope',
      }),
    ).rejects.toBeInstanceOf(HoldNotFoundError);
  });

  test('A6 bookSlot with expired hold throws HoldExpiredError', async () => {
    const hold = await holdSlot(db, {
      hatId: 'todd-handyman',
      startAt: d('2026-04-01T14:00Z'),
      endAt: d('2026-04-01T15:00Z'),
      subjectKind: 'manual',
      subjectId: 'j6',
      heldByCertId: 'cert-todd',
      ttlMinutes: 1,
      now: d('2026-03-01T12:00Z'),
    });
    await expect(
      bookSlot(db, {
        hatId: 'todd-handyman',
        startAt: d('2026-04-01T14:00Z'),
        endAt: d('2026-04-01T15:00Z'),
        subjectKind: 'manual',
        subjectId: 'j6',
        bookedByCertId: 'cert-todd',
        holdId: hold.id,
        now: d('2026-03-01T13:00Z'),
      }),
    ).rejects.toBeInstanceOf(HoldExpiredError);
  });

  test('A7 inverted range rejected', async () => {
    await expect(
      bookSlot(db, {
        hatId: 'todd-handyman',
        startAt: d('2026-04-01T15:00Z'),
        endAt: d('2026-04-01T14:00Z'),
        subjectKind: 'manual',
        subjectId: 'j7',
        bookedByCertId: 'cert-todd',
      }),
    ).rejects.toThrow(/before endAt/);
  });
});

describe('api — releaseSlot + cancelBooking', () => {
  let db: Database;
  let close: () => Promise<void>;
  beforeEach(async () => { ({ db, close } = await makeTestDb()); });
  afterEach(async () => {
    await close();
    setConversationPatchWriter(null);
  });

  test('A8 releaseSlot releases hold', async () => {
    const h = await holdSlot(db, {
      hatId: 'todd-handyman',
      startAt: d('2026-04-01T14:00Z'),
      endAt: d('2026-04-01T15:00Z'),
      subjectKind: 'manual',
      subjectId: 'j8',
      heldByCertId: 'cert-todd',
    });
    await releaseSlot(db, h.id);
    const all = await listHolds(db, { includeReleased: true });
    expect(all[0].releasedAt).not.toBeNull();
  });

  test('A9 releaseSlot on unknown hold is a no-op', async () => {
    await releaseSlot(db, 'hold_unknown');
    // Did not throw — OK.
  });

  test('A10 cancelBooking sets cancelledAt + reason', async () => {
    const b = await bookSlot(db, {
      hatId: 'todd-handyman',
      startAt: d('2026-04-01T14:00Z'),
      endAt: d('2026-04-01T15:00Z'),
      subjectKind: 'manual',
      subjectId: 'j10',
      bookedByCertId: 'cert-todd',
    });
    await cancelBooking(db, b.id, 'user reschedule');
    const all = await listBookings(db, { includeCancelled: true });
    expect(all[0].cancelledAt).not.toBeNull();
    expect(all[0].cancelReason).toBe('user reschedule');
  });

  test('A11 cancelBooking on unknown throws BookingNotFoundError', async () => {
    await expect(cancelBooking(db, 'book_nope', 'x')).rejects.toBeInstanceOf(BookingNotFoundError);
  });
});

describe('api — conversation patch hook', () => {
  let db: Database;
  let close: () => Promise<void>;
  beforeEach(async () => { ({ db, close } = await makeTestDb()); });
  afterEach(async () => {
    await close();
    setConversationPatchWriter(null);
  });

  test('A12 hold + book emit calendar patches when conversationId set', async () => {
    const emitted: CalendarPatchEvent[] = [];
    setConversationPatchWriter((e) => { emitted.push(e); });
    const hold = await holdSlot(db, {
      hatId: 'todd-handyman',
      startAt: d('2026-04-01T14:00Z'),
      endAt: d('2026-04-01T15:00Z'),
      subjectKind: 'manual',
      subjectId: 'j12',
      heldByCertId: 'cert-todd',
      conversationId: 'conv-1',
    });
    await bookSlot(db, {
      hatId: 'todd-handyman',
      startAt: d('2026-04-01T14:00Z'),
      endAt: d('2026-04-01T15:00Z'),
      subjectKind: 'manual',
      subjectId: 'j12',
      bookedByCertId: 'cert-todd',
      holdId: hold.id,
      conversationId: 'conv-1',
    });
    expect(emitted.length).toBe(2);
    expect(emitted.map((e) => e.verb)).toEqual(['hold', 'book']);
  });

  test('A13 writer throwing does not fail the booking', async () => {
    setConversationPatchWriter(() => { throw new Error('boom'); });
    const b = await bookSlot(db, {
      hatId: 'todd-handyman',
      startAt: d('2026-04-01T14:00Z'),
      endAt: d('2026-04-01T15:00Z'),
      subjectKind: 'manual',
      subjectId: 'j13',
      bookedByCertId: 'cert-todd',
      conversationId: 'conv-2',
    });
    expect(b.id).toMatch(/^book_/);
  });
});

describe('api — listHolds + listBookings filters', () => {
  let db: Database;
  let close: () => Promise<void>;
  beforeEach(async () => { ({ db, close } = await makeTestDb()); });
  afterEach(async () => { await close(); });

  test('A14 listBookings filters by hatId', async () => {
    await bookSlot(db, {
      hatId: 'todd-handyman',
      startAt: d('2026-04-01T10:00Z'),
      endAt: d('2026-04-01T11:00Z'),
      subjectKind: 'ojt-job',
      subjectId: 'j',
      bookedByCertId: 'cert-todd',
    });
    await bookSlot(db, {
      hatId: 'todd-advisor',
      startAt: d('2026-04-02T10:00Z'),
      endAt: d('2026-04-02T11:00Z'),
      subjectKind: 'brap-consult',
      subjectId: 'c',
      bookedByCertId: 'cert-todd',
    });
    const hand = await listBookings(db, { hatId: 'todd-handyman' });
    expect(hand.length).toBe(1);
    expect(hand[0].hatId).toBe('todd-handyman');
  });

  test('A15 listBookings default excludes cancelled', async () => {
    const b = await bookSlot(db, {
      hatId: 'todd-handyman',
      startAt: d('2026-04-01T14:00Z'),
      endAt: d('2026-04-01T15:00Z'),
      subjectKind: 'manual',
      subjectId: 'x',
      bookedByCertId: 'cert-todd',
    });
    await cancelBooking(db, b.id, 'test');
    expect((await listBookings(db)).length).toBe(0);
    expect((await listBookings(db, { includeCancelled: true })).length).toBe(1);
  });
});

```
