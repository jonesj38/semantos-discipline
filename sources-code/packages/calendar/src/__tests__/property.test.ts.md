---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/calendar/src/__tests__/property.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.480230+00:00
---

# packages/calendar/src/__tests__/property.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import fc from 'fast-check';
import { makeTestDb } from './setup.js';
import {
  holdSlot,
  bookSlot,
  releaseSlot,
  cancelBooking,
  listBookings,
  CalendarConflictError,
  BookingNotFoundError,
} from '../api/index.js';
import { rangesOverlap } from '../policy/conflict.js';

type Op =
  | { kind: 'hold'; startMin: number; endMin: number; hat: 'todd-handyman' | 'todd-advisor' }
  | { kind: 'book'; startMin: number; endMin: number; hat: 'todd-handyman' | 'todd-advisor' }
  | { kind: 'release'; holdIndex: number }
  | { kind: 'cancel'; bookingIndex: number };

const opArb: fc.Arbitrary<Op> = fc.oneof(
  fc.record({
    kind: fc.constant('hold' as const),
    startMin: fc.nat({ max: 2400 }),
    endMin: fc.nat({ max: 2400 }),
    hat: fc.constantFrom('todd-handyman' as const, 'todd-advisor' as const),
  }),
  fc.record({
    kind: fc.constant('book' as const),
    startMin: fc.nat({ max: 2400 }),
    endMin: fc.nat({ max: 2400 }),
    hat: fc.constantFrom('todd-handyman' as const, 'todd-advisor' as const),
  }),
  fc.record({
    kind: fc.constant('release' as const),
    holdIndex: fc.nat({ max: 20 }),
  }),
  fc.record({
    kind: fc.constant('cancel' as const),
    bookingIndex: fc.nat({ max: 20 }),
  }),
);

describe('property — no two active bookings overlap (one-stream invariant)', () => {
  test('P1 random hold/book/release/cancel sequences never violate the invariant', async () => {
    const BASE = new Date('2026-05-01T08:00Z').getTime();
    await fc.assert(
      fc.asyncProperty(fc.array(opArb, { minLength: 5, maxLength: 25 }), async (ops) => {
        const { db, close } = await makeTestDb();
        try {
          const holds: string[] = [];
          const bookings: string[] = [];
          for (const op of ops) {
            if (op.kind === 'hold' && op.endMin > op.startMin) {
              const start = new Date(BASE + op.startMin * 60_000);
              const end = new Date(BASE + op.endMin * 60_000);
              try {
                const h = await holdSlot(db, {
                  hatId: op.hat,
                  startAt: start,
                  endAt: end,
                  subjectKind: 'manual',
                  subjectId: `s-${holds.length}`,
                  heldByCertId: 'cert-todd',
                  ttlMinutes: 120,
                });
                holds.push(h.id);
              } catch (e) {
                if (!(e instanceof CalendarConflictError)) throw e;
              }
            } else if (op.kind === 'book' && op.endMin > op.startMin) {
              const start = new Date(BASE + op.startMin * 60_000);
              const end = new Date(BASE + op.endMin * 60_000);
              try {
                const b = await bookSlot(db, {
                  hatId: op.hat,
                  startAt: start,
                  endAt: end,
                  subjectKind: 'manual',
                  subjectId: `s-${bookings.length}`,
                  bookedByCertId: 'cert-todd',
                });
                bookings.push(b.id);
              } catch (e) {
                if (!(e instanceof CalendarConflictError)) throw e;
              }
            } else if (op.kind === 'release' && holds.length > 0) {
              await releaseSlot(db, holds[op.holdIndex % holds.length]);
            } else if (op.kind === 'cancel' && bookings.length > 0) {
              try {
                await cancelBooking(db, bookings[op.bookingIndex % bookings.length], 'property-test');
              } catch (e) {
                if (!(e instanceof BookingNotFoundError)) throw e;
              }
            }
          }
          const active = await listBookings(db);
          for (let i = 0; i < active.length; i++) {
            for (let j = i + 1; j < active.length; j++) {
              if (
                rangesOverlap(
                  { startAt: active[i].startAt, endAt: active[i].endAt },
                  { startAt: active[j].startAt, endAt: active[j].endAt },
                )
              ) {
                throw new Error(
                  `INVARIANT VIOLATED — two active bookings overlap on the same stream:\n  ${active[i].id} (${active[i].hatId})\n  ${active[j].id} (${active[j].hatId})`,
                );
              }
            }
          }
          return true;
        } finally {
          await close();
        }
      }),
      { numRuns: 10 },
    );
  }, 180_000);
});

```
