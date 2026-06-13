---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prds/apps/ALIGNMENT-PHASE-A5-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.788392+00:00
---

# Phase A5 — Inter-Hat Booking Guard: Wire the Calendar into Both Bots' Chat Flows

**Companion of**: `REPO-TOPOLOGY.md`, `ALIGNMENT-MASTER.md` §5/§7
**Prerequisites**: A1 v2, A2, A3 complete. Both bot repos exist and route chat through `handleMessage`; `@semantos/calendar-ext` is published and seeded.
**Estimated size**: 2 focused days.

> **Topology note (post-v2 revision)**: the `CalendarGuard` interface lives in `@semantos/intent` (PR to `semantos-core`); the implementation lives in `@semantos/calendar-ext`. Both bot repos `import { handleMessage } from '@semantos/intent'` and `import { createCalendarGuard } from '@semantos/calendar-ext'`. The cross-bot E2E test is best run against both bots as **separate HTTP servers** spun up from their published artifacts (or a local link), not as imported modules — keeps `semantos-core`'s CI free of any business code.

---

## Objective

Before either bot confirms a time-bound commitment, it asks `extensions/calendar` whether the slot is free on the relevant hat set, and either books the slot (on success) or surfaces the conflict to the user in the chat (on failure). After A5:
- OJT's handyman-intake flow will NOT confirm a "I'll see you Thursday 2pm" if `todd-advisor` already has a consult at that time.
- BRAP's advisory-consult flow will NOT confirm a Sonnet session time if `todd-handyman` has a job then.
- The conflict is visible to the end user ("Sorry, Todd isn't free Thursday 2pm — he's committed to another job. Some free slots: Thursday 4pm, Friday 10am…") rather than silently dropped.
- An E2E test proves the cross-bot guard works with real HTTP, real DB, real LLM (cassette replay is acceptable for deterministic CI).

---

## Architectural choice: guard lives in `handleMessage`

Because both bots (post-A2) route through `runtime/intent.handleMessage`, the cleanest place for the booking guard is inside the intent pipeline, not in per-bot chat routes. A calendar-aware triage step runs after the base triage and before the LLM is called.

Concretely, add to `runtime/intent/src/handle-message.ts`:

```
handleMessage(input)
  1. base triage (existing)
  2. if PROPOSES or RATIFIES:
       extract proposed slot (if any) from the patch delta
       if slot detected AND hatId is set:
         conflicts = calendarExt.findConflicts({ hatId, startAt, endAt })
         if conflicts: return { triageHint: 'REJECT_CONFLICT', conflicts, freeWindows: calendarExt.findFreeWindows(...) }
  3. hand back to caller with the conflict annotation
```

The caller (each bot's chat route) reads the annotation, pre-formats a conflict notice, and either short-circuits the LLM or passes the conflict into the LLM's context so the model can phrase the response in its own voice.

---

## Tasks

### 1. Runtime-intent extension point

- [ ] Add a `CalendarGuard` interface in `runtime/intent/src/calendar-guard.ts`:
  ```ts
  export interface CalendarGuard {
    findConflicts(input: ProposedSlot): Promise<ConflictReport>;
    findFreeWindows(input: FreeWindowsQuery): Promise<Slot[]>;
  }
  ```
- [ ] `handleMessage` accepts an optional `calendarGuard` injected at construction time. If not provided, the guard step is skipped (preserves existing semantos tests).
- [ ] Add a `TriageHint.REJECT_CONFLICT` variant to the existing enum.
- [ ] Add `ConflictAnnotation` to the return shape: `{ conflictingBookings, conflictingHolds, freeWindows }`.

### 2. Calendar-ext guard adapter

- [ ] In `extensions/calendar/src/index.ts`, export a factory `createCalendarGuard(db): CalendarGuard` that conforms to the intent-side interface. This is the only place the interface and the calendar-ext implementation meet.
- [ ] Include a default "look-ahead" window of 21 days and a default buffer (from A3's buffer config) per subject kind.

### 3. Slot extraction from patches

- [ ] Define `extractProposedSlot(patch): ProposedSlot | null` in `runtime/intent/src/slot-extraction.ts`:
  - Looks for `patch.delta.proposedSlot: { startAt, endAt, hatId, subjectKind, subjectId }` — a canonical shape both bots will write.
  - Returns null if absent or malformed.
- [ ] Both bots' LLM prompts (updated in step 5) are instructed to emit this shape when proposing a time; otherwise the guard is a no-op.

### 4. OJT chat integration

- [ ] In `apps/ojt/src/app/api/v3/chat/route.ts` (the v3 route produced by OJT-PHASE-4):
  - Construct `handleMessage` with the calendar guard injected.
  - After the call, inspect the returned `triageHint`.
  - If `REJECT_CONFLICT`: write a `ConversationPatch { lexicon: 'calendar', verb: 'conflict', delta: { conflictingBookings, freeWindows } }`, then either:
    - Short-circuit: synthesize a reply ("Sorry, Todd isn't free at that time. How about: <list free windows>?") — simplest, safest.
    - Delegate: pass the conflict annotation into the LLM context ("SYSTEM: the user asked for X but there's a conflict; propose one of the free windows in your own voice") — more natural but a second LLM call per message.
  - Default: **short-circuit** on first landing; switch to delegate-to-LLM once soak looks clean.
- [ ] If `handleMessage` returns normally and the patch encoded a booking (verb `book` on subject_kind `ojt-job`), call `calendarExt.bookSlot(...)` in the same DB transaction as writing the patch. Failure to book is a hard failure; the chat turn is rolled back.

### 5. BRAP chat integration

- [ ] Mirror the OJT wiring in `apps/brap/src/app/api/chat/route.ts`:
  - Guard injected into `handleMessage`.
  - REJECT_CONFLICT → short-circuit (or LLM-delegate after soak).
  - On successful booking patch, call `calendarExt.bookSlot({ subjectKind: 'brap-consult', ... })`.
- [ ] BRAP's "consult" flow differs from OJT's "job" flow: BRAP consults are typically shorter (30–60 min) and often paid. The subject kind is `brap-consult`; the buffer config in the calendar extension handles the duration sanity checks.

### 6. Prompt updates (minimal)

- [ ] OJT system prompt (`apps/ojt/src/lib/ai/prompts/systemPrompt.ts`): append a short section:
  > "When proposing a specific date and time, always emit a `proposedSlot` object with ISO-8601 `startAt`, `endAt`, and `hatId: 'todd-handyman'`. The runtime will check availability and may refuse or suggest alternatives; always respect the runtime's response."
- [ ] BRAP chat prompt (`apps/brap/src/lib/brem/chat-prompt.ts`): append the equivalent with `hatId: 'todd-advisor'`.
- [ ] No other prompt changes. Both bots retain their existing voice and scripting.

### 7. UI: "your bookings" plate

- [ ] Mount `extensions/calendar`'s `PlateView` in a small admin-only page inside each bot:
  - OJT: `/app/admin/calendar` (operator-only; gated by `certId === OPERATOR_CERT_ID`).
  - BRAP: `/app/admin/calendar` (same gate).
- [ ] Both views query the same calendar DB and show all hats Todd owns (both `todd-handyman` and `todd-advisor`), so he can see his aggregate week from either app.
- [ ] End-user views of end-users' own slots are out of scope for A5.

### 8. Tests

- [ ] Unit: slot-extraction recognizes a variety of valid patches and rejects malformed ones.
- [ ] Unit: `handleMessage` with a mock guard that always returns a conflict yields `REJECT_CONFLICT` and a populated annotation.
- [ ] Integration (OJT only): chat turn proposing Thursday 2pm while a BRAP booking exists at Thursday 1:30–2:30pm on `todd-advisor` returns a short-circuit message listing free windows.
- [ ] Integration (BRAP only): mirror of the above.
- [ ] **E2E cross-bot** (the key one): spin up both bots in memory, run a 4-turn script:
  1. OJT user says "can Todd come Thursday at 2pm?"
  2. OJT agent proposes, guard says free, books on `todd-handyman`.
  3. BRAP user says "I'd like a 30-min consult Thursday 2pm".
  4. BRAP agent attempts to propose, guard says conflict, short-circuits with free windows.
- [ ] Gate count: ≥ 15 E2E gates mirroring the OJT-PHASE-7 style (real LLM optional, cassette replay acceptable for CI determinism).

### 9. Observability hooks

- [ ] Each booking write emits a metric `calendar.bookings.created{hat=<hatId>, subject_kind=<kind>}`.
- [ ] Each conflict rejection emits `calendar.conflicts.detected{hat=<hatId>}`.
- [ ] Surface these in the minimal ops dashboard from A4.

### 10. Docs

- [ ] Update `ALIGNMENT-MASTER.md` §7 acceptance criterion 6 from "call findConflicts" to "verified by the cross-bot E2E test in A5".
- [ ] Short README at `apps/ojt/docs/calendar-guard.md` and `apps/brap/docs/calendar-guard.md` explaining the wiring for future maintainers.

---

## Acceptance Criteria

1. `runtime/intent/src/handle-message.ts` accepts a `CalendarGuard` injection and runs the guard step when a `proposedSlot` is present.
2. `TriageHint` enum includes `REJECT_CONFLICT`.
3. `apps/ojt/src/app/api/v3/chat/route.ts` and `apps/brap/src/app/api/chat/route.ts` both pass a guard into `handleMessage`.
4. Both bots' chat routes, on REJECT_CONFLICT, emit a user-visible message listing at least 3 free windows pulled from `findFreeWindows`.
5. Successful bookings appear in `cal_bookings` with the correct `subject_kind` (`ojt-job` or `brap-consult`) and with `booked_by_cert_id` equal to the operator or end-user cert (per bot).
6. The cross-bot E2E test passes with ≥ 15 gates; a slot booked in one bot reliably blocks the other.
7. Ops dashboard shows non-zero `calendar.bookings.created` after the test run.
8. Both bots' existing non-calendar E2E tests still pass (no regression).
9. `/app/admin/calendar` in each bot renders `PlateView` and shows bookings made by either bot.
10. Prompt additions to OJT and BRAP each fit in ≤ 5 lines; no other prompt surgery performed in this phase.

---

## Out of Scope

- Multi-operator conflict modeling (future).
- Recurring bookings (future).
- Canceling a booked slot via chat on one bot that was created on the other — deferred; for now the admin plate handles cancellations.
- Sending calendar invites to end users (iCal / Google Calendar sync) — deferred.
- Charging-for-consult integration beyond what BRAP already does — Stripe flows stay as-is.

---

## Rollback

- A feature flag `CALENDAR_GUARD_ENABLED` on each bot. If disabled, `handleMessage` is constructed without the guard and both bots behave as they did at the end of A2 (no booking, no conflict detection).
- If a bad booking lands in `cal_bookings`, cancel via the PlateView's cancel action or a direct SQL update (`cancelled_at = now()`); no data migration required.
