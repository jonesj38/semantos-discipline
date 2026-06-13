---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/calendar-guard.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.344658+00:00
---

# runtime/intent/src/calendar-guard.ts

```ts
/**
 * CalendarGuard — pluggable time-bound-commitment arbiter for the
 * intent pipeline.
 *
 * Both OJT and BRAP route through `handleMessage` (post-A2). Before
 * either bot runs a full pipeline turn on a message that proposes a
 * time-bound commitment, `handleMessage` asks the guard whether the
 * slot is free on the relevant hat set.
 *
 * The guard interface lives here (in @semantos/intent) so the intent
 * orchestrator can call into the calendar without importing from
 * @semantos/calendar-ext (which would create a circular dep). Calendar-
 * ext supplies `createCalendarGuard(db)` that returns a value matching
 * this interface; bots wire it in at construction.
 *
 * Types are structurally compatible with calendar-ext's `BookingRecord`
 * / `HoldRecord` / `FreeWindow` but kept minimal here — we only
 * name what the guard interface actually needs.
 */

/** A proposed time slot extracted from an Intent's delta. */
export interface ProposedSlot {
  /** ISO-8601 UTC instant (string or Date — normalised by the guard). */
  startAt: Date;
  endAt: Date;
  /** The hat making the commitment (e.g. 'todd-handyman', 'todd-advisor'). */
  hatId: string;
  /** Application tag: 'ojt-job' | 'brap-consult' | 'manual' | ... */
  subjectKind: string;
  /** Logical id (job id, project id, consult id). */
  subjectId: string;
  /** Optional: who's proposing the booking (cert id). */
  proposedByCertId?: string;
}

/** Minimal shape of a conflicting active commitment reported by the guard. */
export interface CalendarConflictRecord {
  id: string;
  hatId: string;
  startAt: Date;
  endAt: Date;
  subjectKind: string;
  subjectId: string;
  /** 'booking' | 'hold' — flags which kind of commitment conflicts. */
  recordKind: 'booking' | 'hold';
}

/** A candidate free window returned by findFreeWindows. */
export interface FreeWindow {
  startAt: Date;
  endAt: Date;
}

export interface ConflictReport {
  conflictingBookings: CalendarConflictRecord[];
  conflictingHolds: CalendarConflictRecord[];
}

export interface FreeWindowsQuery {
  hatId: string;
  fromAt: Date;
  toAt: Date;
  durationMinutes: number;
  limit?: number;
}

/**
 * The guard interface. `handleMessage` calls `findConflicts` when a
 * `ProposedSlot` is detected in the classifier's Intent; if conflicts
 * exist, `findFreeWindows` is called to surface alternatives.
 *
 * Implementations must be async and read-only (no side effects). The
 * actual `bookSlot` call happens downstream, in the bot's chat route,
 * inside the same transaction that writes the confirming patch.
 */
export interface CalendarGuard {
  findConflicts(slot: ProposedSlot): Promise<ConflictReport>;
  findFreeWindows(query: FreeWindowsQuery): Promise<FreeWindow[]>;
}

// ── Slot extraction ─────────────────────────────────────────

/**
 * Extract a `ProposedSlot` from an Intent's delta. Returns `null` if
 * the intent doesn't propose a specific time or the payload is
 * malformed. The bot's classifier (or its LLM prompt) is responsible
 * for writing the `proposedSlot` field into `intent.delta`.
 *
 * Shape expected in `intent.delta`:
 * ```
 * {
 *   proposedSlot: {
 *     startAt: <ISO-8601 string or Date>,
 *     endAt:   <ISO-8601 string or Date>,
 *     hatId:   'todd-handyman' | 'todd-advisor' | ...,
 *     subjectKind: 'ojt-job' | 'brap-consult' | 'manual',
 *     subjectId:   string,
 *     proposedByCertId?: string,
 *   }
 * }
 * ```
 */
export function extractProposedSlot(delta: unknown): ProposedSlot | null {
  if (!delta || typeof delta !== 'object') return null;
  const d = delta as Record<string, unknown>;
  const slot = d.proposedSlot as Record<string, unknown> | undefined;
  if (!slot || typeof slot !== 'object') return null;

  const startAt = normalizeInstant(slot.startAt);
  const endAt = normalizeInstant(slot.endAt);
  if (!startAt || !endAt) return null;
  if (startAt.getTime() >= endAt.getTime()) return null;

  const hatId = typeof slot.hatId === 'string' ? slot.hatId : null;
  const subjectKind = typeof slot.subjectKind === 'string' ? slot.subjectKind : null;
  const subjectId = typeof slot.subjectId === 'string' ? slot.subjectId : null;
  if (!hatId || !subjectKind || !subjectId) return null;

  const proposedByCertId =
    typeof slot.proposedByCertId === 'string' ? slot.proposedByCertId : undefined;

  return { startAt, endAt, hatId, subjectKind, subjectId, proposedByCertId };
}

function normalizeInstant(v: unknown): Date | null {
  if (v instanceof Date) return Number.isNaN(v.getTime()) ? null : v;
  if (typeof v === 'string') {
    const d = new Date(v);
    return Number.isNaN(d.getTime()) ? null : d;
  }
  if (typeof v === 'number') {
    const d = new Date(v);
    return Number.isNaN(d.getTime()) ? null : d;
  }
  return null;
}

```
