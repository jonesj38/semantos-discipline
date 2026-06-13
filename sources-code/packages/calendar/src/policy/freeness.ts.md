---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/calendar/src/policy/freeness.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.482526+00:00
---

# packages/calendar/src/policy/freeness.ts

```ts
/**
 * Free-window discovery against the folded schedule.
 *
 * Walks `[fromAt, toAt)` in `granularityMinutes` increments within the
 * hat's working hours; returns up to `limit` candidate windows of the
 * requested duration that have no conflicts.
 *
 * Since the schedule is ONE stream for ONE physical person, free-ness
 * is hatId-agnostic for conflict purposes. The `hatId` input is used
 * only for working-hours + timezone lookup (per-hat scheduling
 * preferences).
 */
import type { Database } from '@semantos/semantic-objects';
import { getHat } from '../domain/hat.js';
import { findConflicts } from './conflict.js';

export interface WorkingHours {
  /** 0 = Sun, 1 = Mon, ..., 6 = Sat */
  days: number[];
  startMinute: number;
  endMinute: number;
}

export const DEFAULT_WORKING_HOURS: WorkingHours = {
  days: [1, 2, 3, 4, 5],
  startMinute: 8 * 60,
  endMinute: 18 * 60,
};

export interface FindFreeWindowsInput {
  /** Timezone + weekends-enabled come from this hat; conflict scoping is global. */
  hatId: string;
  fromAt: Date;
  toAt: Date;
  durationMinutes: number;
  granularityMinutes?: number;
  limit?: number;
  workingHours?: WorkingHours;
  now?: Date;
  scheduleObjectId?: string;
}

export interface FreeWindow {
  startAt: Date;
  endAt: Date;
}

export async function findFreeWindows(
  db: Database,
  input: FindFreeWindowsInput,
): Promise<FreeWindow[]> {
  const granularity = input.granularityMinutes ?? 15;
  const limit = input.limit ?? 10;
  const duration = input.durationMinutes;
  if (duration <= 0) throw new Error('durationMinutes must be positive');
  if (input.fromAt.getTime() >= input.toAt.getTime()) return [];

  const hat = await getHat(db, input.hatId);
  if (!hat) return [];

  const wh = input.workingHours ?? {
    ...DEFAULT_WORKING_HOURS,
    days: hat.weekendsEnabled ? [0, 1, 2, 3, 4, 5, 6] : DEFAULT_WORKING_HOURS.days,
  };

  const out: FreeWindow[] = [];
  const stepMs = granularity * 60_000;
  const durationMs = duration * 60_000;
  let cursor = new Date(input.fromAt.getTime());
  const end = input.toAt.getTime();

  while (cursor.getTime() + durationMs <= end && out.length < limit) {
    const windowEnd = new Date(cursor.getTime() + durationMs);
    if (isWithinWorkingHours(cursor, windowEnd, hat.timezone, wh)) {
      const report = await findConflicts(db, {
        startAt: cursor,
        endAt: windowEnd,
        now: input.now,
        scheduleObjectId: input.scheduleObjectId,
      });
      if (
        report.conflictingBookings.length === 0 &&
        report.conflictingHolds.length === 0
      ) {
        out.push({ startAt: new Date(cursor.getTime()), endAt: windowEnd });
        cursor = new Date(cursor.getTime() + durationMs);
        continue;
      }
    }
    cursor = new Date(cursor.getTime() + stepMs);
  }
  return out;
}

export function isWithinWorkingHours(
  startAt: Date,
  endAt: Date,
  timezone: string,
  wh: WorkingHours,
): boolean {
  const startMinuteOfDay = minuteOfDayInTz(startAt, timezone);
  const endMinuteOfDay = minuteOfDayInTz(endAt, timezone);
  const startDay = dayOfWeekInTz(startAt, timezone);
  const endDay = dayOfWeekInTz(endAt, timezone);
  if (startDay !== endDay) return false;
  if (!wh.days.includes(startDay)) return false;
  return startMinuteOfDay >= wh.startMinute && endMinuteOfDay <= wh.endMinute;
}

function minuteOfDayInTz(date: Date, timezone: string): number {
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone: timezone,
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).formatToParts(date);
  const hour = parseInt(parts.find((p) => p.type === 'hour')!.value, 10);
  const minute = parseInt(parts.find((p) => p.type === 'minute')!.value, 10);
  return hour * 60 + minute;
}

function dayOfWeekInTz(date: Date, timezone: string): number {
  const weekday = new Intl.DateTimeFormat('en-US', {
    timeZone: timezone,
    weekday: 'short',
  }).format(date);
  const map: Record<string, number> = {
    Sun: 0,
    Mon: 1,
    Tue: 2,
    Wed: 3,
    Thu: 4,
    Fri: 5,
    Sat: 6,
  };
  return map[weekday] ?? 0;
}

```
