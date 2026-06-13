---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/TIER-2-BACKLOG-KANBAN.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.665621+00:00
---

# Tier 2 — Backlog Kanban PRD

**Status**: scoped, awaiting operator go-signal.
**Pre-requisite**: D-DOG.1.0c shipped (#367–#391). Graph data model + helm/mobile graph-aware UI in place. Operator has run §6 of `SESSION-HANDOFF-2026-05-06.md` to populate the graph from real Gmail data.

## §1 — Why this matters

Operator (Todd) currently sees jobs as a **list view** — sorted by some default order, with each row showing site/customer/due date/photos. List view is fine for "scan recent leads" but bad for **state-of-the-business**: at any given moment, how many jobs are awaiting quote? Awaiting customer reply? Scheduled for this week? Awaiting payment?

A kanban view answers this at a glance. Each column = one FSM state. Cards (one per `job.v2`) live in the column corresponding to their state. Operator drag-drops a card across columns to advance / regress its state, which fires a state-transition through the existing FSM gate (already validated by `extensions/oddjobz/src/state-machines/job-fsm.ts`).

This is the **operator-execution surface** — it doesn't add new data, it pivots the data we already have onto a different visual primitive. Highest-value-per-day deliverable to ship next.

## §2 — Existing FSM (already in cell schema)

From `extensions/oddjobz/src/cell-types/job.ts` v1 + v2:

```
       ┌─────────────────────────────────────────────────────────┐
       ▼                                                         │
   lead → quoted → scheduled → in_progress → completed → invoiced → paid → closed
       ↑                                                         │
       └────────────── (cancellable from any state) ──────────────┘
```

Plus legacy migration states (`new_lead`, `partial_intake`, etc.) — kept readable but flagged as "needs review" so the kanban can show a "Migration triage" column for operator cleanup.

## §3 — Layout

```
┌──────────┬──────────┬──────────┬───────────┬──────────┬──────────┬──────┬────────┐
│   LEAD   │  QUOTED  │SCHEDULED │IN PROGRESS│COMPLETED │ INVOICED │ PAID │ CLOSED │
├──────────┼──────────┼──────────┼───────────┼──────────┼──────────┼──────┼────────┤
│ ┌──────┐ │ ┌──────┐ │ ┌──────┐ │  ┌──────┐ │ ┌──────┐ │ ┌──────┐ │ ░░░░ │  ░░░░  │
│ │Pohlen│ │ │Tessa │ │ │J.Liu │ │  │ Bob  │ │ │Foeda.│ │ │ Jo-A │ │ ░░░░ │  ░░░░  │
│ │  $300│ │ │ $1k  │ │ │Tue 9a│ │  │WO 47 │ │ │  ✓   │ │ │ inv  │ │ ░░░░ │  ░░░░  │
│ │ 🔵 RJR│ │ │ 🟢 CP│ │ │ 🟢 CP│ │  │ 🔵 RJR│ │ │ 🟢 CP│ │ │ 🟢 CP│ │ ░░░░ │  ░░░░  │
│ └──────┘ │ └──────┘ │ └──────┘ │  └──────┘ │ └──────┘ │ └──────┘ │ ░░░░ │  ░░░░  │
│ ┌──────┐ │          │ ┌──────┐ │           │          │          │ ░░░░ │  ░░░░  │
│ │S.Liu │ │          │ │Smith │ │           │          │          │ ░░░░ │  ░░░░  │
│ │      │ │          │ │ Sat  │ │           │          │          │ ░░░░ │  ░░░░  │
│ └──────┘ │          │ └──────┘ │           │          │          │ ░░░░ │  ░░░░  │
└──────────┴──────────┴──────────┴───────────┴──────────┴──────────┴──────┴────────┘
   3 leads    1 quoted   2 sched.    1 in-prog    1 done     1 inv'd    0 paid   0 closed

  + filter [▾] sender   + sort [▾] due-date asc   + drag-drop to advance state
```

Each card shows: primary customer name, work-order# / amount / due-date (whichever is most informative for the state), agency/source badge (RJR / CP / Bricks), and a photos icon if `hasPhotos`.

Column headers show a count. Click a card → opens job-detail (the route already shipped in PR #389 / #387).

## §4 — Sub-deliverables

Match the D-DOG.1.0c structure so the next session can fire agents with the same pattern.

### Phase A — Helm SPA kanban view

| ID | Title | Files | Effort |
|---|---|---|---|
| A.1 | New route `/kanban` (or replace `/jobs` view-toggle: list ⇄ kanban) | new `apps/loom-svelte/src/routes/kanban/+page.svelte` + view toggle in `JobList.svelte` header | 1d |
| A.2 | Column components — one per FSM state, each fetching `find_jobs_for_state(state)` (new RPC verb — see Phase B) | `apps/loom-svelte/src/lib/kanban/Column.svelte` + `Card.svelte` | 1d |
| A.3 | Drag-drop wiring — `svelte-dnd-action` or similar; on drop, invoke the FSM transition handler | `apps/loom-svelte/src/lib/kanban/dnd.ts` + integration with existing job FSM RPC | 1d |
| A.4 | Filter + sort UI — sender domain pill filter; due-date / WO# / created-at sort modes | `Filter.svelte` + `SortPicker.svelte` | 0.5d |
| A.5 | Tests — pure-function joiner + dnd state machine + per-column filter | new `apps/loom-svelte/tests/kanban-*.test.ts` | 0.5d |

### Phase B — brain `find_jobs_for_state` RPC

| ID | Title | Files | Effort |
|---|---|---|---|
| B.1 | New verb on `oddjobz_query_handler.zig` (PR #375 wired the handler skeleton) — `oddjobz.find_jobs_for_state({state, limit, since})` | extend `oddjobz_query_handler.zig` | 0.5d |
| B.2 | View-store query method — `JobsStore.listForState(state) → []Job` | extend `runtime/semantos-brain/src/jobs_store_fs.zig` | 0.5d |
| B.3 | Tests — verb+store conformance | extend conformance suites | 0.5d |

### Phase C — FSM transition RPC (operator-driven, kanban drag-drop fires this)

The FSM logic exists in `extensions/oddjobz/src/state-machines/job-fsm.ts`. Today it's TS-only (used by helm-side validation pre-Phase-2A). After D-DOG.1.0c, the Semantos Brain-side handler also needs to expose it.

| ID | Title | Files | Effort |
|---|---|---|---|
| C.1 | Brain-side FSM-transition handler — `oddjobz.transition_job({jobId, fromState, toState, hatId})`. Validates per the FSM rule table; mints a successor `job.v2` cell with `prevStateHash` pointing to the current; signs via Phase 4 BKDS; returns the new cellID. | new `runtime/semantos-brain/src/oddjobz_transition_handler.zig` | 1d |
| C.2 | Helm-side wrapper — calls the new RPC, shows error toast on rejection (e.g. invalid transition like `paid → lead`) | `apps/loom-svelte/src/lib/oddjobz-query.ts` | 0.5d |
| C.3 | Mobile-side wrapper for parity (mobile gets kanban Phase D below) | `apps/oddjobz-mobile/lib/src/repl/oddjobz_query_client.dart` | 0.5d |
| C.4 | Tests — transition validation, idempotency, signature chain integrity | extend conformance | 1d |

### Phase D — Mobile kanban (parallel with A)

Same shape as helm-side. Mobile uses the existing `JobListRow` widget but in a horizontal swipeable carousel (one column per state) instead of a vertical list.

| ID | Title | Files | Effort |
|---|---|---|---|
| D.1 | New screen `KanbanScreen` with PageView per FSM state | new `apps/oddjobz-mobile/lib/src/helm/kanban_screen.dart` | 1.5d |
| D.2 | Card swipe-to-advance gesture (long-press + drag to next column header) | gesture detector + navigation | 1d |
| D.3 | Filter sheet (sender domain) | `kanban_filter_sheet.dart` | 0.5d |
| D.4 | Tests | flutter widget tests | 0.5d |

### Phase E — Docs + canon

| ID | Title | Files | Effort |
|---|---|---|---|
| E.1 | Operator runbook for kanban + drag-drop transitions | new `docs/operator-runbooks/job-kanban.md` | 0.5d |
| E.2 | Update `dogfood-gmail.md` to mention kanban view in §11 | edit | 0.25d |
| E.3 | Update `unification-matrix.yml` + `deliverables.yml` for Tier 2 ship | edit | 0.25d |

## §5 — Dependency graph + parallelisation

```
Phase A (helm kanban view) ──┐
                              ├──→ depends on Phase B (find_jobs_for_state RPC)
Phase D (mobile kanban) ─────┘
                              ├──→ depends on Phase C (transition RPC)

Phase B + Phase C — brain-side, file-disjoint (different new handler files), parallel
Phase A + Phase D — UI-side, file-disjoint (Svelte vs Flutter), parallel
Phase E — docs, parallel with everything
```

**Wall-clock with 4-5 parallel agents at peak: ~5 days. Sequential: ~12 dev-days.**

## §6 — Risks & open questions

| # | Risk | Mitigation |
|---|---|---|
| R1 | Drag-drop UX on mobile is finicky (long-press + drag is the wrong primitive on touch) | Use a "swipe right to advance / left to regress" or a "tap-to-show-menu" instead. Decide during Phase D after testing on the simulator. |
| R2 | FSM transitions for legacy v1 cells (the 72 first-dogfood ones) — they don't have `prevStateHash`, so transitioning them produces a v2 successor with no prev. Acceptable? Or require migration first? | Default: transition v1 cell mints a v2 successor with `prevStateHash: null` and `legacy_unsigned: true` lineage marker. Operator sees the legacy pill on the new cell too. |
| R3 | Operator may want to bulk-transition (e.g. "mark all 'completed' jobs from last month as 'invoiced'") | Add a bulk-select mode to Phase A.4 (multi-select cards + apply transition). Treat as a stretch goal; minimal kanban ships without it. |
| R4 | The `job-fsm.ts` validator currently only knows v1 type hash | Phase C.1 routes via `cellTypeByHashHex` (already proven in Phase 2A.3). Same FSM rules apply to v1 and v2. |
| R5 | Helm path-matcher unification (open follow-up §5.6) blocks the new `/kanban` route from working alongside `/sites/[id]` etc. cleanly | Either fix the path-matcher first (small) or piggyback on the existing hash router for `/kanban` too. |

## §7 — Decision points (operator input needed before firing)

1. **Drag-drop on desktop, swipe on mobile** — recommend default, but operator can specify a different mobile gesture (long-press menu, separate "advance" button, etc.). Defaults are fine for first pass.
2. **Bulk-transition stretch goal** — yes/no for v0? Recommend NO; ship single-card-at-a-time first.
3. **Legacy v1 transitions** — produce v2 successors with `legacy_unsigned: true` lineage? (Recommend yes.)
4. **Phase 5 helm path-matcher unification before Phase A.1?** — recommend YES (small follow-up, ~½ day, makes the `/kanban` route + existing pivot routes coexist cleanly).

If operator says "go with defaults," fire all 5 phases in serial-with-parallel-fan-out per the §5 dep graph.

## §8 — Acceptance criteria

- [ ] Operator opens helm `/kanban` (or toggles JobList → kanban): sees 8-column board with their real jobs distributed across FSM states
- [ ] Drag a card from `lead` → `quoted` succeeds, card moves, new v2 cell minted + signed
- [ ] Drag a card from `lead` → `paid` (invalid transition) shows an error toast; cell unchanged
- [ ] Filter by sender domain (CP / RJR / Bricks) works
- [ ] Sort by due-date asc / desc + WO# / created-at works
- [ ] Mobile: open `KanbanScreen`, swipe across PageView columns, swipe-card-right-to-advance works
- [ ] All v1 cells display as cards but with a `legacy_unsigned` pill (carried from PR #391)
- [ ] Click a card opens job-detail (existing route)
- [ ] Operator can run a real day's work entirely from the kanban view
