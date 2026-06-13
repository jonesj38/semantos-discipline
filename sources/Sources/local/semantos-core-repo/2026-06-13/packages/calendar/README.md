---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/calendar/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.390008+00:00
---

# @semantos/calendar-ext

Calendar as a semantic object. **One schedule aggregate owns a single append-only patch stream.** Every hold / book / release / cancel is a patch on that schedule. State = fold the stream.

## Why one stream?

You are one physical person. Even though you run a handyman bot and a risk-assessment bot off the same semantos node, they both need to avoid stepping on your 4th-dimension (time). One physical schedule is one linear resource. If the handyman bot books 10:00 AM, the advisor bot is physically blocked — not because their hat ancestry overlaps, but because there's only one of you.

So: bots are **producers** writing to the same schedule stream. The UI is a **consumer** folding it. Hat attribution stays on each patch as metadata (`facetId` on the patch), but no hat owns its own stream.

This is different from A3 v0.2.0, which modeled the calendar as three bespoke tables with patch-emission as a hook. The rewrite (v0.3.0) makes the patch stream the source of truth.

## The model

- **One `sem_objects` row** — `object_kind: 'schedule'`, id defaults to `'schedule-primary'` (env-configurable via `CAL_SCHEDULE_OBJECT_ID`).
- **N hat rows** — each hat is a `sem_objects` row with `object_kind: 'hat'`, `parent_id` for the display tree, `payload: { displayName, timezone, weekendsEnabled, ownerCertId }`.
- **Schedule patches** with deltas:
  ```ts
  type SchedulePatchDelta =
    | { op: 'hold';    holdId; hatId; startAt; endAt; subjectKind; subjectId; heldByCertId; expiresAt }
    | { op: 'book';    bookingId; hatId; startAt; endAt; subjectKind; subjectId; bookedByCertId; notes?; fromHoldId? }
    | { op: 'release'; holdId }
    | { op: 'cancel';  bookingId; reason };
  ```
- **Folded state**: `{ holds: Map, bookings: Map }` with `releasedAt` / `cancelledAt` on records.
- **Conflict detection**: fold → filter by range overlap. No hat-ancestry walk — any active commitment on the stream conflicts with any overlapping window.

## Installation

Both `@semantos/semantic-objects` and `@semantos/calendar-ext` must be installed:

```bash
pnpm add @semantos/calendar-ext @semantos/semantic-objects
```

`.npmrc`:
```
@semantos:registry=https://npm.pkg.github.com
//npm.pkg.github.com/:_authToken=${GITHUB_TOKEN}
```

## Migrations

```bash
# Canonical substrate first.
psql $CALENDAR_DATABASE_URL -f node_modules/@semantos/semantic-objects/migrations/0000_init.sql
# Calendar-ext's migration is a no-op (contributes no new tables).
```

## Seed at deploy time

```ts
import { seedAll } from '@semantos/calendar-ext';
await seedAll(db, {
  ownerCertId: 'cert-todd',
  timezone: 'Australia/Brisbane',
  scheduleObjectId: 'schedule-primary',
  operatorHatId: 'todd-operator',
  operatorDisplayName: 'Todd (operator)',
  childHats: [
    { id: 'todd-handyman', displayName: 'Todd (handyman)' },
    { id: 'todd-advisor',  displayName: 'Todd (advisor)'  },
  ],
});
```

Or env-driven via `readSeedEnv()`:
```
CAL_OWNER_CERT_ID=cert-todd
CAL_TIMEZONE=Australia/Brisbane
CAL_SCHEDULE_OBJECT_ID=schedule-primary
CAL_OPERATOR_HAT_ID=todd-operator
CAL_OPERATOR_DISPLAY_NAME="Todd (operator)"
CAL_CHILD_HATS=[{"id":"todd-handyman","displayName":"Todd (handyman)"},{"id":"todd-advisor","displayName":"Todd (advisor)"}]
```

## Hold, book, conflict check

```ts
import { holdSlot, bookSlot, findConflicts, CalendarConflictError } from '@semantos/calendar-ext';

const hold = await holdSlot(db, {
  hatId: 'todd-handyman',       // attribution
  startAt: new Date('2026-07-01T14:00Z'),
  endAt:   new Date('2026-07-01T16:00Z'),
  subjectKind: 'ojt-job',
  subjectId: 'job-1001',
  heldByCertId: 'cert-todd',
  conversationId: 'ojt-conv-42', // optional: emits a calendar ConversationPatch
});

try {
  const booking = await bookSlot(db, {
    hatId: 'todd-handyman',
    startAt: new Date('2026-07-01T14:00Z'),
    endAt:   new Date('2026-07-01T16:00Z'),
    subjectKind: 'ojt-job',
    subjectId: 'job-1001',
    bookedByCertId: 'cert-todd',
    holdId: hold.id, // atomic hold → booking conversion
  });
} catch (e) {
  if (e instanceof CalendarConflictError) {
    console.error('Conflict:', e.conflictingBookings);
  }
  throw e;
}
```

## Find free windows

```ts
import { findFreeWindows } from '@semantos/calendar-ext';

const candidates = await findFreeWindows(db, {
  hatId: 'todd-handyman', // used for timezone + working-hours preferences
  fromAt: new Date(),
  toAt:   new Date(Date.now() + 14 * 86400_000),
  durationMinutes: 60,
  limit: 5,
});
// Conflict-scoping is STILL global (one schedule). `hatId` here picks
// which hat's working hours + timezone to use.
```

## PlateView

```tsx
import { PlateView } from '@semantos/calendar-ext/ui';
import { listBookings, listHolds } from '@semantos/calendar-ext';

const bookings = await listBookings(db);
const holds    = await listHolds(db);

<PlateView
  hatIds={['todd-handyman', 'todd-advisor']}
  bookings={bookings}
  holds={holds}
  onSelect={(item) => console.log(item)}
/>
```

Pure component: you fetch, it renders. Tailwind utility classes, self-contained.

## Conversation patches

The calendar emits `CalendarPatchEvent`s via a registered writer whenever a mutation includes `conversationId`:

```ts
import { setConversationPatchWriter } from '@semantos/calendar-ext';
setConversationPatchWriter(async (event) => {
  // Forward to whatever patch substrate the consuming bot uses.
});
```

Writer errors are logged but do not fail the calendar operation.

## Optimistic concurrency

Every mutation goes through `@semantos/semantic-objects.appendPatch`, which enforces `current_state_hash` + `current_version` via a guarded UPDATE. Two concurrent `bookSlot` calls contending for the same schedule will see one succeed and the other throw `StaleStateHashError`; the loser can retry with fresh state.

## Multi-user sharing (substrate ready, wiring later)

- `sem_participants` rows on the schedule list who can author patches (`admin | writer | reader`)
- Multiple certs can be writers on the same schedule — your two bots' certs, or a team member's cert on a shared team schedule
- Federation: a signed bundle of schedule patches replays cleanly on a peer node

## Performance

Fold is O(patches) per query. For single-operator scale (thousands of commitments over years), microseconds. If it becomes hot: checkpoint via `sem_object_states` or add a materialized projection table. Not required for A3.

## Not yet wired

- OJT / BRAP integration — **A5**.
- RRULE / recurring events — later.
- Google / iCal sync — later.
- Lens/redaction for privacy when sharing — substrate (`sem_participants` + `participant_role`) exists; no concrete lens API yet.
