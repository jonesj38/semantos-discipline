---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/calendar/src/__tests__/integration.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.481640+00:00
---

# packages/calendar/src/__tests__/integration.test.ts

```ts
/**
 * Integration: seed many random bookings on the schedule stream; verify
 * findConflicts matches a brute-force in-memory check.
 */
import { describe, expect, test } from 'bun:test';
import { makeTestDb } from './setup.js';
import { bookSlot, findConflicts } from '../api/index.js';
import { rangesOverlap } from '../policy/conflict.js';
import type { BookingRecord } from '../domain/schedule.js';

describe('integration — findConflicts vs in-memory brute force', () => {
  test('I1 100 random bookings, 50 queries, all agree', async () => {
    const { db, close } = await makeTestDb();
    try {
      const BASE = new Date('2026-06-01T00:00Z').getTime();
      const random = seededRandom(42);
      const seeded: BookingRecord[] = [];

      for (let i = 0; i < 100; i++) {
        const dayOffset = Math.floor(random() * 30);
        const hourStart = 8 + Math.floor(random() * 9);
        const duration = 1 + Math.floor(random() * 3);
        const start = new Date(BASE + dayOffset * 86400_000 + hourStart * 3600_000);
        const end = new Date(start.getTime() + duration * 3600_000);
        const hat = random() < 0.5 ? 'todd-handyman' : 'todd-advisor';
        try {
          const b = await bookSlot(db, {
            hatId: hat,
            startAt: start,
            endAt: end,
            subjectKind: 'manual',
            subjectId: `s${i}`,
            bookedByCertId: 'cert-todd',
          });
          seeded.push(b);
        } catch {
          // conflict during seeding — skip
        }
      }
      expect(seeded.length).toBeGreaterThan(50);

      for (let i = 0; i < 50; i++) {
        const dayOffset = Math.floor(random() * 30);
        const hourStart = 8 + Math.floor(random() * 9);
        const duration = 1 + Math.floor(random() * 3);
        const start = new Date(BASE + dayOffset * 86400_000 + hourStart * 3600_000);
        const end = new Date(start.getTime() + duration * 3600_000);

        const report = await findConflicts(db, { startAt: start, endAt: end });
        // In the one-stream model, ANY overlapping active booking conflicts
        // regardless of hat.
        const expected = seeded
          .filter((b) => !b.cancelledAt)
          .filter((b) => rangesOverlap({ startAt: b.startAt, endAt: b.endAt }, { startAt: start, endAt: end }))
          .map((b) => b.id)
          .sort();
        const actual = report.conflictingBookings.map((b) => b.id).sort();
        expect(actual).toEqual(expected);
      }
    } finally {
      await close();
    }
  }, 120_000);
});

function seededRandom(seed: number): () => number {
  let s = seed;
  return () => {
    s = (s * 9301 + 49297) % 233280;
    return s / 233280;
  };
}

```
