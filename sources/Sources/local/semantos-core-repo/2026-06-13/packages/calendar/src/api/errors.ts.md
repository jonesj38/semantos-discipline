---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/calendar/src/api/errors.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.483756+00:00
---

# packages/calendar/src/api/errors.ts

```ts
/** Error classes for the calendar API. */
import type { BookingRecord, HoldRecord } from '../domain/schedule.js';

export class CalendarError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'CalendarError';
  }
}

export class CalendarConflictError extends CalendarError {
  readonly code = 'CONFLICT' as const;
  readonly conflictingBookings: BookingRecord[];
  readonly conflictingHolds: HoldRecord[];
  constructor(bookings: BookingRecord[], holds: HoldRecord[]) {
    super(
      `Calendar conflict: ${bookings.length} booking(s), ${holds.length} hold(s) overlap.`,
    );
    this.name = 'CalendarConflictError';
    this.conflictingBookings = bookings;
    this.conflictingHolds = holds;
  }
}

export class HoldExpiredError extends CalendarError {
  readonly code = 'HOLD_EXPIRED' as const;
  constructor(holdId: string) {
    super(`Hold ${holdId} has expired or been released.`);
    this.name = 'HoldExpiredError';
  }
}

export class HoldNotFoundError extends CalendarError {
  readonly code = 'HOLD_NOT_FOUND' as const;
  constructor(holdId: string) {
    super(`Hold ${holdId} not found.`);
    this.name = 'HoldNotFoundError';
  }
}

export class BookingNotFoundError extends CalendarError {
  readonly code = 'BOOKING_NOT_FOUND' as const;
  constructor(bookingId: string) {
    super(`Booking ${bookingId} not found.`);
    this.name = 'BookingNotFoundError';
  }
}

```
