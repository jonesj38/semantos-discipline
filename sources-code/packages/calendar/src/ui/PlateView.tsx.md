---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/calendar/src/ui/PlateView.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.484638+00:00
---

# packages/calendar/src/ui/PlateView.tsx

```tsx
/**
 * PlateView — "what's on my plate this week" 7-day grid.
 *
 * Pure component: receives bookings + holds as props. Doesn't fetch.
 * The bot's host app fetches via `listBookings` / `listHolds` and passes
 * the data in.
 *
 * Rendering conventions:
 *   - 7-day × 24-hour grid, vertical hours, horizontal days
 *   - bookings: solid blocks, colored per `subjectKind`
 *   - holds: dashed outline
 *   - cancelled bookings: stricken-through
 *
 * Styling: Tailwind utility classes, self-contained — consumers that
 * don't use Tailwind can wrap in their own component and restyle.
 */
import * as React from 'react';
import type { BookingRecord, HoldRecord } from '../domain/schedule.js';

type SubjectKind = string;
export interface PlateItemBooking extends BookingRecord {}
export interface PlateItemHold extends HoldRecord {}

export interface PlateViewProps {
  /** The hats whose commitments should appear. Bookings on any of these show up. */
  hatIds: string[];
  /** Days to render. Defaults to 7 starting today (operator-local day). */
  rangeDays?: number;
  /** Start date of the grid. Defaults to the current calendar day at 00:00 local. */
  startDate?: Date;
  /** Bookings within the range. The host fetches via listBookings(). */
  bookings: PlateItemBooking[];
  /** Active holds within the range. Host fetches via listHolds(). */
  holds?: PlateItemHold[];
  /** Called when user clicks a block. */
  onSelect?: (item:
    | { kind: 'booking'; value: PlateItemBooking }
    | { kind: 'hold'; value: PlateItemHold }
  ) => void;
  /** Visible hour range. Defaults to 8–18. */
  firstHour?: number;
  lastHour?: number;
}

const SUBJECT_COLORS: Record<string, string> = {
  'ojt-job': 'bg-blue-500/70 border-blue-700 text-white',
  'brap-consult': 'bg-amber-500/70 border-amber-700 text-white',
  manual: 'bg-slate-500/70 border-slate-700 text-white',
};

function subjectColor(kind: SubjectKind | string): string {
  return SUBJECT_COLORS[kind] ?? 'bg-purple-500/70 border-purple-700 text-white';
}

export const PlateView: React.FC<PlateViewProps> = ({
  hatIds,
  rangeDays = 7,
  startDate,
  bookings,
  holds = [],
  onSelect,
  firstHour = 8,
  lastHour = 18,
}) => {
  const gridStart = React.useMemo(() => {
    const d = startDate ? new Date(startDate) : new Date();
    d.setHours(0, 0, 0, 0);
    return d;
  }, [startDate]);

  const days: Date[] = React.useMemo(() => {
    const out: Date[] = [];
    for (let i = 0; i < rangeDays; i++) {
      const d = new Date(gridStart);
      d.setDate(d.getDate() + i);
      out.push(d);
    }
    return out;
  }, [gridStart, rangeDays]);

  const hours: number[] = React.useMemo(() => {
    const out: number[] = [];
    for (let h = firstHour; h < lastHour; h++) out.push(h);
    return out;
  }, [firstHour, lastHour]);

  // Filter items by hat + range.
  const rangeEnd = new Date(gridStart);
  rangeEnd.setDate(rangeEnd.getDate() + rangeDays);
  const hatSet = new Set(hatIds);
  const filteredBookings = bookings.filter(
    (b) =>
      hatSet.has(b.hatId) &&
      b.startAt.getTime() < rangeEnd.getTime() &&
      b.endAt.getTime() > gridStart.getTime(),
  );
  const filteredHolds = holds.filter(
    (h) =>
      hatSet.has(h.hatId) &&
      !h.releasedAt &&
      h.expiresAt.getTime() > Date.now() &&
      h.startAt.getTime() < rangeEnd.getTime() &&
      h.endAt.getTime() > gridStart.getTime(),
  );

  return (
    <div
      className="semantos-calendar-plate-view grid gap-px bg-slate-200"
      style={{
        gridTemplateColumns: `auto repeat(${rangeDays}, minmax(6rem, 1fr))`,
        gridTemplateRows: `auto repeat(${hours.length}, 3rem)`,
      }}
    >
      {/* Top-left corner */}
      <div className="bg-slate-50 p-1 text-xs text-slate-500">time</div>
      {/* Day headers */}
      {days.map((d, i) => (
        <div
          key={`day-${i}`}
          className="bg-slate-50 p-1 text-center text-xs font-semibold text-slate-700"
        >
          {d.toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric' })}
        </div>
      ))}
      {/* Hour rows */}
      {hours.map((h, hi) => (
        <React.Fragment key={`hrow-${hi}`}>
          <div className="bg-slate-50 p-1 text-right text-xs text-slate-500">
            {String(h).padStart(2, '0')}:00
          </div>
          {days.map((d, di) => {
            const cellStart = new Date(d);
            cellStart.setHours(h, 0, 0, 0);
            const cellEnd = new Date(cellStart);
            cellEnd.setHours(h + 1, 0, 0, 0);
            const bookingsInCell = filteredBookings.filter((b) =>
              b.startAt.getTime() < cellEnd.getTime() &&
              b.endAt.getTime() > cellStart.getTime(),
            );
            const holdsInCell = filteredHolds.filter((hold) =>
              hold.startAt.getTime() < cellEnd.getTime() &&
              hold.endAt.getTime() > cellStart.getTime(),
            );
            return (
              <div
                key={`cell-${hi}-${di}`}
                className="relative bg-white hover:bg-slate-50"
              >
                {bookingsInCell.map((b) => (
                  <button
                    key={`b-${b.id}`}
                    type="button"
                    onClick={() => onSelect?.({ kind: 'booking', value: b })}
                    className={`absolute inset-x-0.5 top-0.5 rounded border px-1 text-[10px] leading-tight ${subjectColor(b.subjectKind)} ${b.cancelledAt ? 'line-through opacity-60' : ''}`}
                  >
                    {b.subjectKind} · {b.subjectId}
                  </button>
                ))}
                {holdsInCell.map((hold) => (
                  <button
                    key={`h-${hold.id}`}
                    type="button"
                    onClick={() => onSelect?.({ kind: 'hold', value: hold })}
                    className="absolute inset-x-0.5 bottom-0.5 rounded border border-dashed border-slate-500 bg-slate-100/60 px-1 text-[10px] leading-tight text-slate-700"
                  >
                    hold · {hold.subjectKind}
                  </button>
                ))}
              </div>
            );
          })}
        </React.Fragment>
      ))}
    </div>
  );
};

PlateView.displayName = 'PlateView';

```
