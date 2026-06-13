---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/calendar/src/policy/conflict.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.482248+00:00
---

# packages/calendar/src/policy/conflict.ts

```ts
/**
 * Conflict detection against the folded schedule state.
 *
 * One physical schedule → one stream → one fold. Any active commitment
 * (hold or booking) that overlaps the requested window is a conflict,
 * regardless of which hat authored it. This is the "physical time is a
 * single resource" insight: if the handyman books 2–4pm, the advisor
 * CAN'T book 3–5pm, because Todd is one person.
 *
 * Hat-ancestry walks (from A3 v0.2.0) are gone — not needed in this
 * model.
 */
import type { Database } from '@semantos/semantic-objects';
import {
  loadScheduleState,
  activeHolds,
  activeBookings,
  resolveScheduleObjectId,
  type BookingRecord,
  type HoldRecord,
} from '../domain/schedule.js';

export interface ConflictQuery {
  startAt: Date;
  endAt: Date;
  ignoreHoldId?: string;
  ignoreBookingId?: string;
  now?: Date;
  /** Override the default schedule object id (env-driven). */
  scheduleObjectId?: string;
}

export interface ConflictReport {
  conflictingBookings: BookingRecord[];
  conflictingHolds: HoldRecord[];
}

/**
 * Half-open interval overlap on UTC instants.
 *
 *   [aStart, aEnd) overlaps [bStart, bEnd)  iff  aStart < bEnd && bStart < aEnd
 *
 * Adjacency (aEnd === bStart) is NOT a conflict.
 */
export function rangesOverlap(
  a: { startAt: Date; endAt: Date },
  b: { startAt: Date; endAt: Date },
): boolean {
  return a.startAt.getTime() < b.endAt.getTime() && b.startAt.getTime() < a.endAt.getTime();
}

/**
 * Find all active bookings + holds on the schedule that overlap the
 * requested window.
 */
export async function findConflicts(
  db: Database,
  query: ConflictQuery,
): Promise<ConflictReport> {
  const scheduleId = query.scheduleObjectId ?? resolveScheduleObjectId();
  const state = await loadScheduleState(db, scheduleId);
  const now = query.now ?? new Date();

  const conflictingBookings = activeBookings(state).filter(
    (b) =>
      b.id !== query.ignoreBookingId &&
      rangesOverlap({ startAt: b.startAt, endAt: b.endAt }, query),
  );
  const conflictingHolds = activeHolds(state, now).filter(
    (h) =>
      h.id !== query.ignoreHoldId &&
      rangesOverlap({ startAt: h.startAt, endAt: h.endAt }, query),
  );
  return { conflictingBookings, conflictingHolds };
}

export async function hasConflict(db: Database, query: ConflictQuery): Promise<boolean> {
  const report = await findConflicts(db, query);
  return report.conflictingBookings.length > 0 || report.conflictingHolds.length > 0;
}

```
