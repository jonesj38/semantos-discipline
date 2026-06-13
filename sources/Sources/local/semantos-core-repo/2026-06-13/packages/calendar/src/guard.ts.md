---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/calendar/src/guard.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.477714+00:00
---

# packages/calendar/src/guard.ts

```ts
/**
 * A5 CalendarGuard factory — makes the calendar extension's
 * `findConflicts` + `findFreeWindows` available to `@semantos/intent`'s
 * handleMessage orchestrator.
 *
 * The guard interface is defined in @semantos/intent (to avoid a
 * circular dep); this factory returns a value that matches that shape.
 * Consumers wire it at construction:
 *
 * ```ts
 * import { handleMessage } from '@semantos/intent';
 * import { createCalendarGuard } from '@semantos/calendar-ext';
 *
 * const guard = createCalendarGuard(db);
 * const result = await handleMessage(input, { ..., calendarGuard: guard });
 * ```
 */
import type {
  CalendarGuard,
  ProposedSlot,
  ConflictReport,
  CalendarConflictRecord,
  FreeWindowsQuery,
  FreeWindow,
} from '@semantos/intent';
import type { Database } from '@semantos/semantic-objects';
import { findConflicts } from './policy/conflict.js';
import { findFreeWindows } from './policy/freeness.js';

export interface CalendarGuardOptions {
  /** Override the schedule object id. Defaults to env / 'schedule-primary'. */
  scheduleObjectId?: string;
}

/**
 * Create a CalendarGuard bound to a drizzle `Database` and the
 * deployment's schedule sem_objects row. The returned value plugs
 * directly into `@semantos/intent.handleMessage` via `deps.calendarGuard`.
 */
export function createCalendarGuard(
  db: Database,
  opts: CalendarGuardOptions = {},
): CalendarGuard {
  const scheduleObjectId = opts.scheduleObjectId;

  return {
    async findConflicts(slot: ProposedSlot): Promise<ConflictReport> {
      const report = await findConflicts(db, {
        startAt: slot.startAt,
        endAt: slot.endAt,
        scheduleObjectId,
      });
      const conflictingBookings: CalendarConflictRecord[] = report.conflictingBookings.map(
        (b) => ({
          id: b.id,
          hatId: b.hatId,
          startAt: b.startAt,
          endAt: b.endAt,
          subjectKind: b.subjectKind,
          subjectId: b.subjectId,
          recordKind: 'booking',
        }),
      );
      const conflictingHolds: CalendarConflictRecord[] = report.conflictingHolds.map(
        (h) => ({
          id: h.id,
          hatId: h.hatId,
          startAt: h.startAt,
          endAt: h.endAt,
          subjectKind: h.subjectKind,
          subjectId: h.subjectId,
          recordKind: 'hold',
        }),
      );
      return { conflictingBookings, conflictingHolds };
    },

    async findFreeWindows(query: FreeWindowsQuery): Promise<FreeWindow[]> {
      const windows = await findFreeWindows(db, {
        hatId: query.hatId,
        fromAt: query.fromAt,
        toAt: query.toAt,
        durationMinutes: query.durationMinutes,
        limit: query.limit,
        scheduleObjectId,
      });
      return windows.map((w) => ({ startAt: w.startAt, endAt: w.endAt }));
    },
  };
}

```
