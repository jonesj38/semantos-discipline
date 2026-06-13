---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/calendar/src/api/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.483154+00:00
---

# packages/calendar/src/api/index.ts

```ts
/**
 * Public API for @semantos/calendar-ext.
 *
 * Every mutation is an `appendPatch` on the one schedule object.
 * `listHolds` / `listBookings` fold the stream and filter.
 */
import { appendPatch, type Database } from '@semantos/semantic-objects';
import {
  loadScheduleState,
  activeHolds,
  activeBookings,
  allBookings,
  resolveScheduleObjectId,
  type SchedulePatchDelta,
  type BookingRecord,
  type HoldRecord,
} from '../domain/schedule.js';
import {
  BookingNotFoundError,
  CalendarConflictError,
  HoldExpiredError,
  HoldNotFoundError,
} from './errors.js';
import { newBookingId, newHoldId } from './ids.js';
import { applyBuffer, type BufferMinutes } from '../policy/buffer.js';
import { findConflicts } from '../policy/conflict.js';
import { emitPatch } from './hooks.js';

export * from './errors.js';
export { applyBuffer, getBuffer, DEFAULT_BUFFERS } from '../policy/buffer.js';
export type { BufferMinutes } from '../policy/buffer.js';
export { findConflicts, hasConflict, rangesOverlap } from '../policy/conflict.js';
export type { ConflictQuery, ConflictReport } from '../policy/conflict.js';
export { findFreeWindows, DEFAULT_WORKING_HOURS, isWithinWorkingHours } from '../policy/freeness.js';
export type { WorkingHours, FindFreeWindowsInput, FreeWindow } from '../policy/freeness.js';
export {
  DEFAULT_SCHEDULE_OBJECT_ID,
  resolveScheduleObjectId,
  fold,
  applyPatch,
  loadScheduleState,
  initialScheduleState,
  activeHolds,
  activeBookings,
  allBookings,
} from '../domain/schedule.js';
export type {
  SchedulePatch,
  SchedulePatchDelta,
  SchedulePatchKind,
  ScheduleState,
  HoldRecord,
  BookingRecord,
  HoldDelta,
  BookDelta,
  ReleaseDelta,
  CancelDelta,
} from '../domain/schedule.js';
export {
  setConversationPatchWriter,
  type CalendarPatchEvent,
  type ConversationPatchWriter,
} from './hooks.js';

export const DEFAULT_HOLD_TTL_MINUTES = 30;

// ────────────────────────────────────────────────────────────
// holdSlot
// ────────────────────────────────────────────────────────────

export interface HoldSlotInput {
  hatId: string;
  startAt: Date;
  endAt: Date;
  subjectKind: string;
  subjectId: string;
  heldByCertId: string;
  ttlMinutes?: number;
  conversationId?: string;
  bufferOverrides?: Record<string, BufferMinutes>;
  now?: Date;
  scheduleObjectId?: string;
}

export async function holdSlot(db: Database, input: HoldSlotInput): Promise<HoldRecord> {
  validateRange(input.startAt, input.endAt);
  const scheduleId = input.scheduleObjectId ?? resolveScheduleObjectId();
  const now = input.now ?? new Date();
  const buffered = applyBuffer(
    { startAt: input.startAt, endAt: input.endAt },
    input.subjectKind,
    input.bufferOverrides,
  );

  const report = await findConflicts(db, {
    startAt: buffered.startAt,
    endAt: buffered.endAt,
    now,
    scheduleObjectId: scheduleId,
  });
  if (report.conflictingBookings.length > 0 || report.conflictingHolds.length > 0) {
    throw new CalendarConflictError(report.conflictingBookings, report.conflictingHolds);
  }

  const holdId = newHoldId();
  const expiresAt = new Date(now.getTime() + (input.ttlMinutes ?? DEFAULT_HOLD_TTL_MINUTES) * 60_000);

  const delta: SchedulePatchDelta = {
    op: 'hold',
    holdId,
    hatId: input.hatId,
    startAt: input.startAt.toISOString(),
    endAt: input.endAt.toISOString(),
    subjectKind: input.subjectKind,
    subjectId: input.subjectId,
    heldByCertId: input.heldByCertId,
    expiresAt: expiresAt.toISOString(),
  };

  await appendPatch<SchedulePatchDelta>(db, {
    objectId: scheduleId,
    kind: 'hold',
    delta,
    facetId: input.hatId,
    lexicon: 'calendar',
  });

  const record: HoldRecord = {
    id: holdId,
    hatId: input.hatId,
    startAt: input.startAt,
    endAt: input.endAt,
    subjectKind: input.subjectKind,
    subjectId: input.subjectId,
    heldByCertId: input.heldByCertId,
    expiresAt,
    createdAt: now,
    releasedAt: null,
  };

  if (input.conversationId) {
    await emitPatch({
      conversationId: input.conversationId,
      lexicon: 'calendar',
      verb: 'hold',
      objectKind: 'slot',
      objectId: holdId,
      delta: {
        hatId: record.hatId,
        startAt: record.startAt.toISOString(),
        endAt: record.endAt.toISOString(),
        subjectKind: record.subjectKind,
        subjectId: record.subjectId,
        expiresAt: record.expiresAt.toISOString(),
      },
    });
  }
  return record;
}

// ────────────────────────────────────────────────────────────
// bookSlot
// ────────────────────────────────────────────────────────────

export interface BookSlotInput {
  hatId: string;
  startAt: Date;
  endAt: Date;
  subjectKind: string;
  subjectId: string;
  bookedByCertId: string;
  notes?: string;
  holdId?: string;
  conversationId?: string;
  bufferOverrides?: Record<string, BufferMinutes>;
  now?: Date;
  scheduleObjectId?: string;
}

export async function bookSlot(db: Database, input: BookSlotInput): Promise<BookingRecord> {
  validateRange(input.startAt, input.endAt);
  const scheduleId = input.scheduleObjectId ?? resolveScheduleObjectId();
  const now = input.now ?? new Date();

  const runWithTx = async (tx: Database): Promise<BookingRecord> => {
    // Validate the hold if provided.
    if (input.holdId) {
      const state = await loadScheduleState(tx, scheduleId);
      const hold = state.holds.get(input.holdId);
      if (!hold) throw new HoldNotFoundError(input.holdId);
      if (hold.releasedAt !== null || hold.expiresAt.getTime() <= now.getTime()) {
        throw new HoldExpiredError(input.holdId);
      }
    }

    const buffered = applyBuffer(
      { startAt: input.startAt, endAt: input.endAt },
      input.subjectKind,
      input.bufferOverrides,
    );
    const report = await findConflicts(tx, {
      startAt: buffered.startAt,
      endAt: buffered.endAt,
      ignoreHoldId: input.holdId,
      now,
      scheduleObjectId: scheduleId,
    });
    if (report.conflictingBookings.length > 0 || report.conflictingHolds.length > 0) {
      throw new CalendarConflictError(report.conflictingBookings, report.conflictingHolds);
    }

    const bookingId = newBookingId();
    const delta: SchedulePatchDelta = {
      op: 'book',
      bookingId,
      hatId: input.hatId,
      startAt: input.startAt.toISOString(),
      endAt: input.endAt.toISOString(),
      subjectKind: input.subjectKind,
      subjectId: input.subjectId,
      bookedByCertId: input.bookedByCertId,
      notes: input.notes,
      fromHoldId: input.holdId,
    };

    await appendPatch<SchedulePatchDelta>(tx, {
      objectId: scheduleId,
      kind: 'book',
      delta,
      facetId: input.hatId,
      lexicon: 'calendar',
    });

    return {
      id: bookingId,
      hatId: input.hatId,
      startAt: input.startAt,
      endAt: input.endAt,
      subjectKind: input.subjectKind,
      subjectId: input.subjectId,
      bookedByCertId: input.bookedByCertId,
      notes: input.notes ?? null,
      createdAt: now,
      cancelledAt: null,
      cancelReason: null,
      fromHoldId: input.holdId ?? null,
    };
  };

  let booking: BookingRecord;
  if (typeof (db as unknown as { transaction?: unknown }).transaction === 'function') {
    booking = await (
      db as unknown as {
        transaction: (fn: (tx: Database) => Promise<BookingRecord>) => Promise<BookingRecord>;
      }
    ).transaction(runWithTx);
  } else {
    booking = await runWithTx(db);
  }

  if (input.conversationId) {
    await emitPatch({
      conversationId: input.conversationId,
      lexicon: 'calendar',
      verb: 'book',
      objectKind: 'slot',
      objectId: booking.id,
      delta: {
        hatId: booking.hatId,
        startAt: booking.startAt.toISOString(),
        endAt: booking.endAt.toISOString(),
        subjectKind: booking.subjectKind,
        subjectId: booking.subjectId,
        holdId: input.holdId ?? null,
      },
    });
  }
  return booking;
}

// ────────────────────────────────────────────────────────────
// releaseSlot
// ────────────────────────────────────────────────────────────

export async function releaseSlot(
  db: Database,
  holdId: string,
  options?: { conversationId?: string; now?: Date; scheduleObjectId?: string },
): Promise<void> {
  const scheduleId = options?.scheduleObjectId ?? resolveScheduleObjectId();
  const state = await loadScheduleState(db, scheduleId);
  const hold = state.holds.get(holdId);
  if (!hold || hold.releasedAt !== null) return; // no-op

  const delta: SchedulePatchDelta = { op: 'release', holdId };
  await appendPatch<SchedulePatchDelta>(db, {
    objectId: scheduleId,
    kind: 'release',
    delta,
    facetId: hold.hatId,
    lexicon: 'calendar',
  });

  if (options?.conversationId) {
    await emitPatch({
      conversationId: options.conversationId,
      lexicon: 'calendar',
      verb: 'release',
      objectKind: 'slot',
      objectId: holdId,
      delta: {
        hatId: hold.hatId,
        startAt: hold.startAt.toISOString(),
        endAt: hold.endAt.toISOString(),
        subjectKind: hold.subjectKind,
        subjectId: hold.subjectId,
      },
    });
  }
}

// ────────────────────────────────────────────────────────────
// cancelBooking
// ────────────────────────────────────────────────────────────

export async function cancelBooking(
  db: Database,
  bookingId: string,
  reason: string,
  options?: { conversationId?: string; now?: Date; scheduleObjectId?: string },
): Promise<void> {
  const scheduleId = options?.scheduleObjectId ?? resolveScheduleObjectId();
  const state = await loadScheduleState(db, scheduleId);
  const booking = state.bookings.get(bookingId);
  if (!booking) throw new BookingNotFoundError(bookingId);
  if (booking.cancelledAt !== null) return; // idempotent

  const delta: SchedulePatchDelta = { op: 'cancel', bookingId, reason };
  await appendPatch<SchedulePatchDelta>(db, {
    objectId: scheduleId,
    kind: 'cancel',
    delta,
    facetId: booking.hatId,
    lexicon: 'calendar',
  });

  if (options?.conversationId) {
    await emitPatch({
      conversationId: options.conversationId,
      lexicon: 'calendar',
      verb: 'cancel',
      objectKind: 'slot',
      objectId: bookingId,
      delta: {
        hatId: booking.hatId,
        startAt: booking.startAt.toISOString(),
        endAt: booking.endAt.toISOString(),
        subjectKind: booking.subjectKind,
        subjectId: booking.subjectId,
        reason,
      },
    });
  }
}

// ────────────────────────────────────────────────────────────
// Listing
// ────────────────────────────────────────────────────────────

export interface ListFilters {
  hatId?: string;
  subjectKind?: string;
  since?: Date;
  until?: Date;
  scheduleObjectId?: string;
}

export async function listHolds(
  db: Database,
  filters: ListFilters & { includeReleased?: boolean; now?: Date } = {},
): Promise<HoldRecord[]> {
  const scheduleId = filters.scheduleObjectId ?? resolveScheduleObjectId();
  const state = await loadScheduleState(db, scheduleId);
  const now = filters.now ?? new Date();
  const source = filters.includeReleased
    ? [...state.holds.values()]
    : activeHolds(state, now);
  return source
    .filter((h) => !filters.hatId || h.hatId === filters.hatId)
    .filter((h) => !filters.subjectKind || h.subjectKind === filters.subjectKind)
    .filter((h) => !filters.since || h.endAt.getTime() >= filters.since.getTime())
    .filter((h) => !filters.until || h.startAt.getTime() <= filters.until.getTime())
    .sort((a, b) => a.startAt.getTime() - b.startAt.getTime());
}

export async function listBookings(
  db: Database,
  filters: ListFilters & { includeCancelled?: boolean } = {},
): Promise<BookingRecord[]> {
  const scheduleId = filters.scheduleObjectId ?? resolveScheduleObjectId();
  const state = await loadScheduleState(db, scheduleId);
  const source = filters.includeCancelled
    ? allBookings(state)
    : activeBookings(state);
  return source
    .filter((b) => !filters.hatId || b.hatId === filters.hatId)
    .filter((b) => !filters.subjectKind || b.subjectKind === filters.subjectKind)
    .filter((b) => !filters.since || b.endAt.getTime() >= filters.since.getTime())
    .filter((b) => !filters.until || b.startAt.getTime() <= filters.until.getTime())
    .sort((a, b) => a.startAt.getTime() - b.startAt.getTime());
}

function validateRange(startAt: Date, endAt: Date): void {
  if (startAt.getTime() >= endAt.getTime()) {
    throw new Error('startAt must be strictly before endAt');
  }
}

```
