---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prds/apps/ALIGNMENT-PHASE-A3-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.787011+00:00
---

# Phase A3 — Calendar Extension: Greenfield `extensions/calendar/`

**Companion of**: `REPO-TOPOLOGY.md`, `ALIGNMENT-MASTER.md` §5/§6
**Prerequisites**: A1 v2 complete. Independent of A2 — can run in parallel.
**Estimated size**: 2–3 focused days (schema + policy + API + lexicon + thin UI).

> **Topology note (post-v2 revision)**: this work lands in `semantos-core` under `extensions/calendar/` and is published as `@semantos/calendar-ext` (per `REPO-TOPOLOGY.md`). The bots NEVER reach into `extensions/calendar/` directly — they `import { bookSlot, findConflicts, PlateView } from '@semantos/calendar-ext'`. Migrations ship inside the package as SQL files plus a `calendar-migrate` bin, run on the VPS once per deploy against the shared `calendar_prod` database. Todd's hat topology (`todd-operator`, `todd-handyman`, `todd-advisor`) is **seeded at deploy time from env vars**, not at package install — the package stays domain-neutral.

---

## Objective

Build the shared inter-hat scheduling primitive that both bots consult before confirming any time-bound commitment. After A3:
- A new workspace package `@semantos/calendar-ext` lives at `extensions/calendar/`
- It exposes a clean API: `bookSlot`, `holdSlot`, `releaseSlot`, `listHolds`, `listBookings`, `findConflicts`, `findFreeWindows`
- It owns its own drizzle schema for events, holds, hats, and conflict records
- It defines and exports `CalendarLexicon` for use in semantos-sir
- It ships with a minimal "what's on Todd's plate this week" view that both bots can embed
- It does **not** yet wire into either bot — A5 does that

The pre-flight check (first 30 minutes of work):
- [ ] Search the repo and any feature branches Todd points at for an existing calendar MVP. Locations to grep: `apps/loom-react/src/**`, `apps/navigator/**`, `extensions/**`, every branch matching `*calendar*`, `*schedule*`, `*hat*`. If something exists, this phase becomes "port and harden the existing skeleton" rather than greenfield.

---

## Domain Model

### Concepts

- **Hat**: an identity facet. Todd has at least two: `todd-handyman` (used by OJT) and `todd-advisor` (used by BRAP). The `todd-operator` hat owns both — its commitments block all child hats.
- **Slot**: a half-open `[start, end)` time interval on a specific hat. Slots are quantized to the minute (no sub-minute granularity).
- **Hold**: a soft reservation. Created when a chat is "actively negotiating" a time. Expires after a TTL (default 30 minutes) if not booked.
- **Booking**: a confirmed commitment. Created when the user accepts a proposed time. Owns `hatId`, `slot`, `subjectId` (job id, project id), `subjectKind` (`ojt-job` | `brap-consult` | `manual`), `notes`.
- **Conflict**: a derived entity. Two slots conflict iff they share any hat in their effective hat-set (the hat plus its ancestors via `parentHatId`) AND their time ranges intersect.

### Schema (drizzle, in `extensions/calendar/src/db/schema.ts`)

```ts
export const calHats = pgTable('cal_hats', {
  id: text('id').primaryKey(),               // 'todd-handyman' | 'todd-advisor' | 'todd-operator'
  parentHatId: text('parent_hat_id'),        // FK → cal_hats.id, null = root
  ownerCertId: text('owner_cert_id').notNull(),
  displayName: text('display_name').notNull(),
  timezone: text('timezone').notNull(),      // 'Australia/Brisbane'
  createdAt: timestamp('created_at').defaultNow().notNull(),
});

export const calBookings = pgTable('cal_bookings', {
  id: text('id').primaryKey(),
  hatId: text('hat_id').notNull().references(() => calHats.id),
  startAt: timestamp('start_at', { withTimezone: true }).notNull(),
  endAt: timestamp('end_at', { withTimezone: true }).notNull(),
  subjectKind: text('subject_kind').notNull(),  // 'ojt-job' | 'brap-consult' | 'manual'
  subjectId: text('subject_id').notNull(),      // FK is logical, not enforced (cross-app)
  bookedByCertId: text('booked_by_cert_id').notNull(),
  notes: text('notes'),
  createdAt: timestamp('created_at').defaultNow().notNull(),
  cancelledAt: timestamp('cancelled_at', { withTimezone: true }),
});

export const calHolds = pgTable('cal_holds', {
  id: text('id').primaryKey(),
  hatId: text('hat_id').notNull().references(() => calHats.id),
  startAt: timestamp('start_at', { withTimezone: true }).notNull(),
  endAt: timestamp('end_at', { withTimezone: true }).notNull(),
  subjectKind: text('subject_kind').notNull(),
  subjectId: text('subject_id').notNull(),
  heldByCertId: text('held_by_cert_id').notNull(),
  expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
  createdAt: timestamp('created_at').defaultNow().notNull(),
  releasedAt: timestamp('released_at', { withTimezone: true }),
});

// Indexes:
// - (hat_id, start_at, end_at) on bookings and holds for range queries
// - (subject_kind, subject_id) for app-side joins
// - partial index where cancelled_at IS NULL on bookings
// - partial index where released_at IS NULL AND expires_at > now() on holds
```

---

## Tasks

### 1. Workspace skeleton

- [ ] `mkdir -p extensions/calendar/src/{db,api,policy,lexicon}`
- [ ] `extensions/calendar/package.json`:
  ```json
  {
    "name": "@semantos/calendar-ext",
    "private": true,
    "version": "0.1.0",
    "main": "./src/index.ts",
    "scripts": { "test": "vitest", "build": "tsc -p tsconfig.json" },
    "dependencies": {
      "drizzle-orm": "<aligned with repo>",
      "postgres": "<aligned with repo>",
      "@semantos/protocol-types": "workspace:*"
    }
  }
  ```
- [ ] `extensions/calendar/src/index.ts` — barrel exports the API and lexicon.

### 2. Schema + migrations

- [ ] Implement schema as above.
- [ ] Generate the initial migration with `drizzle-kit generate --name calendar_init`.
- [ ] Seed Todd's three hats on first migration via a `seed.ts`:
  - `todd-operator` (root, owns all commitments)
  - `todd-handyman` (parent: `todd-operator`)
  - `todd-advisor` (parent: `todd-operator`)
- [ ] Migration runs against a separate DB `calendar_dev` (one of three DBs on the VPS Postgres cluster).

### 3. Policy module

- [ ] `extensions/calendar/src/policy/conflict.ts`:
  - `function effectiveHatSet(hatId): hatId[]` — returns hatId plus ancestors via parent chain.
  - `function rangesOverlap(a, b): boolean` — half-open interval intersection on UTC instants.
  - `function findConflicts(input: { hatId, startAt, endAt, ignoreHoldId?, ignoreBookingId? }): { conflictingBookings, conflictingHolds }` — single SQL query that scans bookings + holds for any hat in the effective set whose time range overlaps the requested window.
- [ ] `extensions/calendar/src/policy/buffer.ts`:
  - Configurable per-subject-kind travel/setup buffer (e.g. ojt jobs default to 30-minute buffer before and after; brap consults to 15 minutes).
  - `applyBuffer(slot, subjectKind): {startAt, endAt}` returns expanded window for conflict checks.
- [ ] `extensions/calendar/src/policy/freeness.ts`:
  - `findFreeWindows(input: { hatId, fromAt, toAt, durationMinutes, granularityMinutes? }): Slot[]` — returns up to N candidate windows.
  - Respect operator working-hours config (default Mon–Fri 08:00–18:00 in operator's TZ; weekends opt-in per hat).

### 4. API surface

- [ ] `extensions/calendar/src/api/index.ts` exports:
  - `holdSlot(input): Promise<Hold>` — fails with `CONFLICT` if any conflict exists; succeeds with TTL.
  - `bookSlot(input): Promise<Booking>` — accepts an optional `holdId`; if present, atomically converts hold → booking; else checks conflicts and books.
  - `releaseSlot(holdId): Promise<void>` — soft-releases.
  - `cancelBooking(bookingId, reason): Promise<void>` — sets cancelledAt; emits a `CalendarEvent` (cancellation).
  - `listHolds({ hatId?, subjectKind?, since?, until? }): Promise<Hold[]>`
  - `listBookings({ hatId?, subjectKind?, since?, until?, includeCancelled? }): Promise<Booking[]>`
  - `findConflicts(input): Promise<ConflictReport>`
  - `findFreeWindows(input): Promise<Slot[]>`
- [ ] All API functions accept a `tx` (drizzle transaction) so callers can compose with their own writes (e.g. BRAP creating a project + booking a consult atomically).

### 5. Lexicon + semantos-sir integration

- [ ] `extensions/calendar/src/lexicon/index.ts` exports:
  ```ts
  export const CalendarLexicon = {
    id: 'calendar',
    verbs: ['propose','hold','book','release','reschedule','cancel','find_free'] as const,
    categories: ['slot','window','conflict','hat'] as const,
  };
  ```
- [ ] In `core/semantos-sir/src/lexicons.ts`, register `CalendarLexicon` alongside `JuralLexicon`, `PropertyManagementLexicon`, `BRAPLexicon`.
- [ ] Add a unit test asserting parity of the lexicon shape across all four registries.

### 6. Conversation patches integration

- [ ] When `bookSlot` succeeds, write a `ConversationPatch` (if a `conversationId` is supplied) with:
  - `lexicon: 'calendar'`
  - `verb: 'book'`
  - `objectKind: 'slot'`
  - `objectId: bookingId`
  - `delta: { hatId, startAt, endAt, subjectKind, subjectId }`
- [ ] Same for `hold`, `release`, `cancel`, `reschedule`. This lets the LLM in either bot see "you proposed a time, I held it, you confirmed, I booked it" as a typed history.

### 7. UI: "what's on my plate this week"

- [ ] Build a tiny embeddable React component at `extensions/calendar/src/ui/PlateView.tsx`:
  - Props: `{ hatIds: string[], rangeDays?: number }`
  - Renders a 7-day grid; bookings as colored blocks (color per `subjectKind`); holds as dashed outlines; cancellations stricken-through.
  - Click on a block → open a side panel with the subject details and a deep link (`/ojt/jobs/:id` or `/brap/projects/:id`).
- [ ] Style with whatever the rest of `apps/loom-react` uses (Tailwind likely; check the loom-react package for the convention).
- [ ] Not embedded in a full app yet — A5 wires it in. Just provide the component as a workspace export.

### 8. Tests

- [ ] Unit (≥ 30 cases): conflict detection across hat ancestry, overlap edges (half-open), buffer application, free-window discovery, TTL expiration.
- [ ] Property test: any sequence of `hold/book/release/cancel` on the same hat never produces two simultaneous active bookings.
- [ ] Integration: against a local Postgres, seed 100 random bookings and assert `findConflicts` returns the same set as a brute-force in-memory checker.
- [ ] E2E (with both bots stubbed): OJT books `todd-handyman` 14:00–16:00 → BRAP tries to book `todd-advisor` 15:00–17:00 → conflict reported because both inherit from `todd-operator`.

### 9. Docs

- [ ] `extensions/calendar/README.md` — concepts, schema diagram, API surface, examples in TypeScript.
- [ ] Add to `docs/README.md` extensions table.

---

## Acceptance Criteria

1. `pnpm --filter @semantos/calendar-ext build` succeeds.
2. `pnpm --filter @semantos/calendar-ext test` runs ≥ 30 unit cases + property test + integration; all green.
3. `extensions/calendar/src/db/schema.ts` defines `calHats`, `calBookings`, `calHolds` with the indexes above.
4. `findConflicts({ hatId: 'todd-advisor', ... })` correctly reports conflicts that exist on `todd-handyman` because both share `todd-operator` as ancestor.
5. `holdSlot` enforces TTL: a hold older than its `expiresAt` is treated as released by `findConflicts`.
6. `bookSlot(holdId=h)` atomically deletes the hold and creates the booking; partial failure leaves no orphan.
7. `CalendarLexicon` is exported from `extensions/calendar/src/lexicon/index.ts` AND registered in `core/semantos-sir/src/lexicons.ts`.
8. `PlateView` renders a 7-day grid with seeded bookings + holds + cancellations.
9. No bot code (OJT or BRAP) imports `@semantos/calendar-ext` yet — that wiring is A5's job. CI can grep-check this.
10. The pre-flight existing-skeleton check is documented in the PR — either "ported from <branch>" or "no prior skeleton found, built greenfield".

---

## Out of Scope

- Recurring events / RRULE handling — punt to a later phase.
- Multi-operator support (this is single-operator, multi-hat).
- External calendar sync (Google, iCal) — punt to a later phase.
- Rich notification / reminder system — A5 surfaces conflicts in chat; push notifications and email reminders are out.

---

## Rollback

A3 ships an isolated extension that nothing depends on yet. Rollback is `git revert` — no migrations to undo on production data because the calendar DB is greenfield.
