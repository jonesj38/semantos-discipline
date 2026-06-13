---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/TIER-3-EXECUTION-PROPOSAL-ENGINE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.682274+00:00
---

# Tier 3 — Execution Proposal Engine PRD

**Status**: scoped, awaiting operator go-signal.
**Pre-requisite**: Tier 1.7 shipped (PR #366). `dueDate` field on `job.v2` is populated. Operator's working hours are 7am-7pm per `DOGFOOD-READINESS-MATRIX.md` §6.3.

## §1 — Why this matters

Operator sees the graph of jobs (lead, quoted, scheduled, etc.). What they DON'T see today: **"what should I do tomorrow?"** The kanban (Tier 2) shows state-of-the-business; the execution engine **proposes a plan**.

For each new day at 7am:
- "You have 3 quote requests due this week. Quote Pohlen by EOD Tuesday."
- "Wednesday is the deadline for the Foedera Cres ceiling work — visit booked for Tuesday morning at 9am."
- "Friday's open: schedule Sarah Liu's screen-door rollers (quote sent 4 days ago)."

The engine is a **proposal**, not a hard schedule. Operator reviews + accepts / amends / rejects each entry. Approved entries become `visit.v1` cells (the cell type already exists in `extensions/oddjobz/src/cell-types/visit.ts`).

## §2 — Inputs

The graph already has everything we need:

| Input | Source |
|---|---|
| Working day envelope | Operator config: 7am-7pm (default) — stored as a single hat-config cell or a global setting JSONL |
| Jobs needing action | `oddjobz.find_jobs_for_state` filtered to {lead, quoted, scheduled, in_progress} |
| Due dates | `job.v2.dueDate` (Tier 1.7 shipped this) |
| Property addresses | `job.v2.siteRef → site.v2.fullAddress` (Phase 2A wired the ref + the lookup) |
| Estimated travel time between sites | Geocoding service (Mapbox / Google Maps / OSM Nominatim) — pick one + cache results in a `geocode_cache.jsonl` view-store |
| Estimated job duration | Per-job-type heuristic table OR operator-tagged on the job cell. Default: 1.5h for quotes (assess + measure + photo); 4h for work orders (default — but obviously varies wildly). Operator can override in job-detail. |
| Already-scheduled visits | `visit.v1` cells where `scheduled_at >= today` |
| Operator's calendar (optional) | Read from external calendar (Google Cal, Apple Cal) via existing OAuth flows; treat as blackout slots |

## §3 — Output: a daily proposal

For "tomorrow" (operator can request any future day):

```
Tomorrow, Wed 2026-05-07 (7:00am – 7:00pm)
─────────────────────────────────────────────────────────────────

 7:00  ☕  prep + drive to first site
 8:30  📍  29 Foedera Cres, Tewantin (key #177) — Pohlen ceiling quote
        → measure damage, photo, estimate; ~1.5h
        → 1 prior message in thread (operator may want to read first)
10:00  🚗  → drive (12min) →
10:15  📍  4/5 Hygieta St, Noosaville — Stevenson screen-door quote
        → ~1h
11:30  🚗  → drive (15min) →
11:45  🍽   lunch buffer (45min)  ← built-in default; operator-tunable
12:30  📍  13 Orealla Cr, Sunrise Beach — RJR deck rail repair (work order)
        → confirmed scope, $1000 fixed; ~3h
 3:30  🚗  → drive (10min) → home or next site
 ────  END proposed schedule  ────
 [3 jobs / ~6h scheduled / 2h drive / 45m lunch / 4h slack]

Open quotes (NOT scheduled):
 - Sarah Liu screen rollers — quote sent 4d ago, no reply
 - Tessa Herbert bar fitout — invoice phase, no visit needed

[Approve all] [Amend...] [Reject...] [Move to another day]
```

Each row is a **proposed** `visit.v1` cell. Operator approves → cell mints + signs + appears on tomorrow's calendar.

## §4 — Algorithm (heuristic, deterministic)

```
inputs:
  day             = target date (default: tomorrow)
  envelope        = (07:00, 19:00) or operator's config
  candidate_jobs  = jobs in state {lead, quoted, scheduled, in_progress}
                    sorted by (dueDate asc, then by created_at asc)
  travel_matrix   = geocode + drive-time between operator home + each candidate site
  duration_table  = job_type → estimated minutes
  buffers         = lunch (45m) + per-job admin (10m setup + 10m cleanup) + travel padding (20%)

algorithm:
  1. Greedy-fill the envelope:
     a. start at envelope[0] (7am) at operator home
     b. pick the candidate with earliest dueDate that fits remaining envelope including travel + duration + buffers
     c. for each selected job: append to schedule, advance "current location" + "current time"
     d. insert a lunch slot when crossing noon-1pm boundary
     e. stop when no remaining candidate fits OR envelope[1] reached
  2. For unscheduled candidates that are "due tomorrow / overdue":
     surface as "URGENT — should be on tomorrow's plan but didn't fit" warnings
  3. For scheduled candidates not picked (later due dates):
     surface as "deferred to a later day" hints
  4. Operator approves/amends → minting visit.v1 cells
```

This is a SIMPLE greedy first-pass. A future iteration could use an actual TSP solver (we have ~5–15 candidate jobs at most, so brute-force optimal is feasible). For v0 the greedy heuristic is correct enough — operator's local knowledge (e.g. "Pohlen wants morning visits only") gets layered on via per-job tags.

## §5 — Sub-deliverables

### Phase A — Brain-side proposal engine

| ID | Files | Effort |
|---|---|---|
| A.1 — Geocode cache + drive-time matrix builder | new `runtime/semantos-brain/src/geocode_cache_fs.zig` (view store) + `geocode_handler.zig` (RPC verb `oddjobz.geocode_address`) | 1.5d |
| A.2 — Scheduler core (greedy fill) | new `runtime/semantos-brain/src/oddjobz_scheduler.zig` — pure-function module, takes (jobs, travel_matrix, day, envelope) → (schedule, deferred[], urgent[]) | 1.5d |
| A.3 — RPC verb `oddjobz.propose_schedule({day})` | new `oddjobz_scheduler_handler.zig` wired into `wss_wallet.zig` | 0.5d |
| A.4 — Tests | conformance for scheduler greedy fill + edge cases (no candidates / overflow / lunch boundary) | 1d |

### Phase B — Geocoding provider

Pick ONE — operator preference. **Recommend OSM Nominatim** (free, sovereign-friendly, no API key, no rate-limit-fee surprise). Use Google Maps as fallback for ambiguous Aussie addresses (Nominatim's Australia coverage is patchy).

| ID | Files | Effort |
|---|---|---|
| B.1 — Nominatim client | extend Phase A.1 — HTTP GET `https://nominatim.openstreetmap.org/search` with `format=json&countrycodes=au&limit=1` | 0.5d |
| B.2 — Drive-time provider | OSRM public server (`https://router.project-osrm.org/route/v1/driving/...`) — free, sovereign, returns duration in seconds | 0.5d |
| B.3 — Operator override | Operator can manually edit drive times in the geocode cache (a tagged JSONL) when OSRM is wrong (e.g. wrong route around a closed bridge) | 0.25d |

### Phase C — Helm SPA proposal view

| ID | Files | Effort |
|---|---|---|
| C.1 — `/proposal/[date]` route showing the day's plan | new `apps/loom-svelte/src/routes/proposal/[date]/+page.svelte` + `ProposalDetail.svelte` view | 1d |
| C.2 — Approve/Amend/Reject UI | per-row buttons; bulk-approve at top; amend-row opens a small editor (different time / different duration / link a different job) | 1d |
| C.3 — Drag-reorder schedule | `svelte-dnd-action` again — drag a row up/down to reorder; engine recalculates travel times + total envelope on each drop | 0.5d |
| C.4 — Tests | pure-function joiner + amend/reject logic | 0.5d |

### Phase D — Mobile proposal screen

Same as C, ported to Flutter.

| ID | Files | Effort |
|---|---|---|
| D.1 — `ProposalScreen` widget | new `apps/oddjobz-mobile/lib/src/helm/proposal_screen.dart` — vertical scroll list, swipe-to-approve | 1.5d |
| D.2 — Drag-reorder + amend bottom sheet | `proposal_amend_sheet.dart` | 1d |
| D.3 — Tests | flutter widget tests | 0.5d |

### Phase E — Tier-3-specific docs

| ID | Files | Effort |
|---|---|---|
| E.1 — Operator runbook: how the engine builds a day's plan + how to override | new `docs/operator-runbooks/execution-proposals.md` | 0.5d |
| E.2 — Geocoding sovereignty doc — what data leaves the operator's machine when Nominatim/OSRM is hit | new `docs/canon/sovereignty-geocoding.md` | 0.25d |
| E.3 — Update `unification-matrix.yml` + `deliverables.yml` | edit | 0.25d |

## §6 — Dependency graph

```
Phase A (scheduler) ──┐
                       ├─→ Phase C (helm UI)
                       │     ‖
                       │   Phase D (mobile UI)
                       │
Phase B (geocoding) ───┴─→ feeds Phase A.1's matrix builder

Phase E (docs) — parallel with everything
```

**Wall-clock with 3-4 parallel agents: ~5 days. Sequential: ~12 dev-days.**

## §7 — Risks & open questions

| # | Risk | Mitigation |
|---|---|---|
| R1 | Nominatim rate-limits hobbyist free-tier (1 req/sec). Operator might have 50+ unique addresses. | Cache aggressively in `geocode_cache.jsonl`; one-time backfill on first run; never re-geocode an address that's already cached. |
| R2 | OSRM public server has no SLA. Could be down. | Fall back to a flat-rate-per-km estimate (e.g. 1km = 90s avg in Noosa traffic). |
| R3 | Aussie addresses with units (4/5 Hygieta St) sometimes confuse Nominatim — returns the wrong building | Operator-override path in B.3 + a "geocode confidence" field — show a warning when confidence is low and ask operator to confirm. |
| R4 | The 7am-7pm envelope is per-day; but operator might want different envelopes for different days (Mon-Fri vs Sat) | v0 ships single envelope; v1 adds per-weekday + per-date overrides via operator config. |
| R5 | Operator has hard preferences ("never schedule Pohlen mornings") that aren't in the data | Per-job tags: `{morning_only: true, after_3pm: true, ...}`. Operator adds via job-detail amend; scheduler respects them as constraints. v0 may not have UI to set these — operator can manually edit the JSONL row. |
| R6 | Geocode + drive-time involves outbound HTTPS — operator may want to opt out for sovereignty | Provider config allows an `offline` mode that uses a flat-rate per-km estimate from cached coordinates only. Document in Phase E.2. |

## §8 — Decision points

1. **Geocoding provider** — recommend OSM Nominatim + OSRM. Operator can override.
2. **Default working hours** — recommend 7am-7pm per existing matrix. Operator can override per-day later.
3. **Default job durations** — recommend `quote_request: 1.5h, work_order: 4h, maintenance_order: 2h`. Operator tunes via per-job tag.
4. **Lunch window** — recommend 45m floating between 12pm-1:30pm. Operator can disable.
5. **Approval semantics** — recommend "approve = mint visit.v1 cell signed under operator hat; reject = noop; amend = edit then approve."

## §9 — Acceptance criteria

- [ ] Operator opens `/proposal/2026-05-07`: sees a coherent 7am-7pm plan with 2-5 visits, lunch slot, drive times, and slack
- [ ] Each row links back to the originating `job.v2` (so operator can drill into the source PDF / customer / site)
- [ ] Approve-all mints visit.v1 cells; they appear on tomorrow's calendar in helm + mobile
- [ ] Amend-row UI lets operator change time / duration / which job
- [ ] Drag-reorder recalculates travel + envelope correctly
- [ ] Mobile parity: same UI on Flutter
- [ ] First-time geocode populates the cache; subsequent days re-use cached coords
- [ ] Operator can run a real day's planning entirely from the proposal screen
