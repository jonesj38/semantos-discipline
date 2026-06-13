---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/calendar/src/domain/schedule.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.478734+00:00
---

# packages/calendar/src/domain/schedule.ts

```ts
/**
 * Schedule domain model.
 *
 * The calendar is ONE `sem_objects` row (`object_kind: 'schedule'`) that
 * owns an append-only patch stream. Every hold/book/release/cancel is a
 * patch on that schedule. State = fold the stream.
 *
 * This module defines the patch delta shape, the folded state shape, and
 * the reducer.
 */
import type { ObjectPatch } from '@semantos/semantic-objects';
import { listPatches, foldState } from '@semantos/semantic-objects';
import type { Database } from '@semantos/semantic-objects';

/** Default id for the single-operator deployment. Override via env. */
export const DEFAULT_SCHEDULE_OBJECT_ID = 'schedule-primary';

export function resolveScheduleObjectId(
  env: Record<string, string | undefined> = process.env as Record<string, string | undefined>,
): string {
  return env.CAL_SCHEDULE_OBJECT_ID ?? DEFAULT_SCHEDULE_OBJECT_ID;
}

// ────────────────────────────────────────────────────────────
// Patch kinds ("verbs" on the schedule)
// ────────────────────────────────────────────────────────────

export type SchedulePatchKind = 'hold' | 'book' | 'release' | 'cancel';

export interface HoldDelta {
  op: 'hold';
  holdId: string;
  hatId: string;
  startAt: string; // ISO
  endAt: string; // ISO
  subjectKind: string;
  subjectId: string;
  heldByCertId: string;
  expiresAt: string; // ISO
  notes?: string;
}

export interface BookDelta {
  op: 'book';
  bookingId: string;
  hatId: string;
  startAt: string;
  endAt: string;
  subjectKind: string;
  subjectId: string;
  bookedByCertId: string;
  notes?: string;
  /** If present, this booking converted a hold (which is released in the same txn). */
  fromHoldId?: string;
}

export interface ReleaseDelta {
  op: 'release';
  holdId: string;
}

export interface CancelDelta {
  op: 'cancel';
  bookingId: string;
  reason: string;
}

export type SchedulePatchDelta = HoldDelta | BookDelta | ReleaseDelta | CancelDelta;
export type SchedulePatch = ObjectPatch<SchedulePatchDelta>;

// ────────────────────────────────────────────────────────────
// Folded state
// ────────────────────────────────────────────────────────────

export interface HoldRecord {
  id: string;
  hatId: string;
  startAt: Date;
  endAt: Date;
  subjectKind: string;
  subjectId: string;
  heldByCertId: string;
  expiresAt: Date;
  createdAt: Date;
  /** When released; absent on active holds. */
  releasedAt: Date | null;
}

export interface BookingRecord {
  id: string;
  hatId: string;
  startAt: Date;
  endAt: Date;
  subjectKind: string;
  subjectId: string;
  bookedByCertId: string;
  notes: string | null;
  createdAt: Date;
  /** When cancelled; absent on active bookings. */
  cancelledAt: Date | null;
  cancelReason: string | null;
  /** If this booking converted a hold, the hold's id. */
  fromHoldId: string | null;
}

export interface ScheduleState {
  holds: Map<string, HoldRecord>;
  bookings: Map<string, BookingRecord>;
}

export function initialScheduleState(): ScheduleState {
  return { holds: new Map(), bookings: new Map() };
}

// ────────────────────────────────────────────────────────────
// Reducer
// ────────────────────────────────────────────────────────────

/** Fold a single patch into the state. Pure; returns a new state. */
export function applyPatch(state: ScheduleState, patch: SchedulePatch): ScheduleState {
  const holds = new Map(state.holds);
  const bookings = new Map(state.bookings);
  const ts = patch.createdAt;

  switch (patch.delta.op) {
    case 'hold': {
      const d = patch.delta;
      holds.set(d.holdId, {
        id: d.holdId,
        hatId: d.hatId,
        startAt: new Date(d.startAt),
        endAt: new Date(d.endAt),
        subjectKind: d.subjectKind,
        subjectId: d.subjectId,
        heldByCertId: d.heldByCertId,
        expiresAt: new Date(d.expiresAt),
        createdAt: ts,
        releasedAt: null,
      });
      break;
    }
    case 'book': {
      const d = patch.delta;
      if (d.fromHoldId) {
        // Release the converted hold in-place.
        const prev = holds.get(d.fromHoldId);
        if (prev && prev.releasedAt === null) {
          holds.set(d.fromHoldId, { ...prev, releasedAt: ts });
        }
      }
      bookings.set(d.bookingId, {
        id: d.bookingId,
        hatId: d.hatId,
        startAt: new Date(d.startAt),
        endAt: new Date(d.endAt),
        subjectKind: d.subjectKind,
        subjectId: d.subjectId,
        bookedByCertId: d.bookedByCertId,
        notes: d.notes ?? null,
        createdAt: ts,
        cancelledAt: null,
        cancelReason: null,
        fromHoldId: d.fromHoldId ?? null,
      });
      break;
    }
    case 'release': {
      const d = patch.delta;
      const prev = holds.get(d.holdId);
      if (prev && prev.releasedAt === null) {
        holds.set(d.holdId, { ...prev, releasedAt: ts });
      }
      break;
    }
    case 'cancel': {
      const d = patch.delta;
      const prev = bookings.get(d.bookingId);
      if (prev && prev.cancelledAt === null) {
        bookings.set(d.bookingId, { ...prev, cancelledAt: ts, cancelReason: d.reason });
      }
      break;
    }
  }
  return { holds, bookings };
}

/** Fold an entire patch stream. */
export function fold(patches: SchedulePatch[]): ScheduleState {
  return foldState<ScheduleState, SchedulePatchDelta>({
    patches,
    initial: initialScheduleState(),
    reducer: applyPatch,
  });
}

/** Load patches from the DB and fold to current state. */
export async function loadScheduleState(
  db: Database,
  scheduleObjectId: string,
): Promise<ScheduleState> {
  const patches = await listPatches<SchedulePatchDelta>(db, {
    objectId: scheduleObjectId,
  });
  return fold(patches as SchedulePatch[]);
}

// ────────────────────────────────────────────────────────────
// Active-only helpers
// ────────────────────────────────────────────────────────────

/** Holds that are not released AND not expired at `now`. */
export function activeHolds(state: ScheduleState, now: Date = new Date()): HoldRecord[] {
  const out: HoldRecord[] = [];
  for (const h of state.holds.values()) {
    if (h.releasedAt !== null) continue;
    if (h.expiresAt.getTime() <= now.getTime()) continue;
    out.push(h);
  }
  return out;
}

/** Bookings that are not cancelled. */
export function activeBookings(state: ScheduleState): BookingRecord[] {
  return [...state.bookings.values()].filter((b) => b.cancelledAt === null);
}

/** All bookings including cancelled, for reporting. */
export function allBookings(state: ScheduleState): BookingRecord[] {
  return [...state.bookings.values()];
}

```
