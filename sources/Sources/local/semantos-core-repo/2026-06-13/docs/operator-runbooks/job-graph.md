---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/operator-runbooks/job-graph.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.639314+00:00
---

# Job-graph navigation — operator guide

D-DOG.1.0c Phase 3 promoted oddjobz from "one flat job row per ratify"
to a connected cell-DAG: every ratified proposal mints a graph of
site / customer / job / attachment cells linked by typed edges.
This guide walks an operator through how to use that graph on the
helm SPA and on mobile.

## What changed for you

Pre-Phase-3 a `legacy ratify` produced one flat row in
`jobs.jsonl` with six columns: id / customer / state / scheduled /
created / etc. 95% of the proposal data — owner names, secondary
contacts, billing party, work-order number, due date, photo count —
was thrown away.

Post-Phase-3 the same ratify mints:

```
              site.v2                 ← WHERE
                │
         ┌──────┼─────────┐
         ▼      ▼         ▼
     customer customer customer       ← WHO (tenant + agent + owner + ...)
         │      │         │
         └──────┼─────────┘
                ▼
              job.v2                  ← WHAT (FSM + workOrderNumber +
                │                       dueDate + billingParty + photos
                ▼                       boolean)
            attachment.v2             ← HOW (source PDF + photos)
```

Edges between cells answer the WHO / WHAT / WHERE / WHY questions
without piling fields into one row. Concretely: "all jobs at
13 Orealla Cr" is a graph walk from one site cell, not a string-search
across `jobs.jsonl`.

## Helm SPA — graph-aware views

### JobList (Phase 3 E.1, PR #389-era)

Open `/helm/` after pairing. The job list now renders four columns
instead of two:

- **Property** — pulled from the linked v2 site cell. Click to go to
  the site-pivot view (all jobs at this address).
- **Customer (role)** — the primary customerRef on the v2 job, e.g.
  "Sarah Liu (tenant)". Click to go to the customer-pivot view (all
  jobs for this person).
- **State + photo badge** — the standard FSM state chip, plus a
  camera icon when the source PDF embedded photos. Hover the icon for
  the count.
- **Due** — the workOrderNumber's due date, formatted relative to
  today ("Due tomorrow", "Overdue 3 days", "Due 24 Mar").

Pre-Phase-1 v1 cells (the operator's first 72 dogfood cells) still
render — their property + customer columns show "—" placeholders and
they're slightly faded. After running `legacy migrate-to-graph` (Phase
5 G.1) the rows that match a source proposal are re-ratified into
graph cells; rows that don't match get a small "legacy" pill next to
the state chip (Phase 5 G.2) so you can pick them out.

### Site-pivot route (Phase 3 E.2, PR #380)

Click any property address in the JobList → `/helm/sites/<cellId>`.

Renders:

- The full normalised address + key number if present.
- Every job ever ratified for this site, sorted by `dueDate` then
  `created_at`. Includes completed and closed jobs — the site is the
  long-lived stable identity, jobs come and go.
- Every customer ever associated with this site (with their roles).

Use this when a tenant calls about "the leaking tap at 47 Hygieta" —
the site pivot shows all open + recent jobs without manual searching.

### Customer-pivot route (Phase 3 E.3, PR #379)

Click any customer name in the JobList → `/helm/customers/<cellId>`.

Renders:

- The customer's display name + canonical phone + email.
- Every job they've ever been on, with their role on that job
  (tenant on one job, agent on another — roles live on the
  job→customer edge, not the customer cell).

Use this when an agent calls about a job — looking them up reveals
every other job they're routing to you. Useful for "did Zoe ever
mention X" questions that previously required scrolling.

### Job-detail with attachments (Phase 3 E.4, PR #389)

Click a job row's body → `/helm/jobs/<id>`.

Renders:

- The full v2 job cell payload (workOrderNumber, dueDate,
  issuanceDate, billingParty, propertyKey, ...).
- The full primary + secondary customer list (with roles).
- Linked site (full address + key number).
- **Attachments view** — source PDF download link, plus thumbnails
  for any embedded photos detected by the Vision pass. Click a
  thumbnail to open a lightbox.

This is the "everything about this job" surface — the operator's
single screen for the FSM transitions (`quoted` → `scheduled` →
`in_progress` → ...) without losing the source PDF context.

## Mobile (Flutter, oddjobz-mobile)

Same four navigation surfaces as the helm — phase-3 F.1-F.4 (PRs #378
#386 #388 #387):

### JobList screen (F.1)

The 5-tab Find pivot's Jobs tab now renders the rich row:

- Title: property address (key #N badge alongside)
- Line 2: primary customer (tenant) — tappable, opens customer pivot
- Line 3: due date + camera icon when photos present

v1 carry-over rows fall back to the v1 layout (customer name as
title, "—" placeholders). Phase 5 G.2 adds a small "legacy" pill on
the title row when the row is `legacy_unsigned` (un-migratable v1).

### Site pivot (F.2)

Tap the property address → push `SiteScreen`. Same content as the
helm route: every job at this address, every customer linked.

### Customer pivot (F.3)

Tap the customer-name line → push `CustomerScreen`. Every job this
person has been on, sorted by recency.

### Attachment screen (F.4)

Tap the camera icon → push `AttachmentScreen`. Inline PDF viewer
(via `pdfx`) for the source PDF; photo carousel for embedded photos.

## RPC contract (for tooling builders)

The graph-aware views read the Semantos Brain-side query handler:

| Verb | Returns | Files |
|---|---|---|
| `oddjobz.list_sites()` | All v2 site cells, paginated | `runtime/semantos-brain/src/oddjobz_query_handler.zig` |
| `oddjobz.list_customers()` | All v2 customer cells | (same) |
| `oddjobz.list_jobs()` | All v2 job cells (no v1 carry-over) | (same) |
| `oddjobz.find_jobs_at_site(siteId)` | Site-pivot view backing | (same) |
| `oddjobz.find_jobs_for_customer(customerId)` | Customer-pivot view backing | (same) |
| `oddjobz.get_job(id)` | Single job + linked refs | (same) |

The verbs are stable as of Phase 2B and tested via the cross-store
parity oracle at `runtime/semantos-brain/tests/cross_store_query_oracle.zig`.
The TS join + N+1 prevention contract for the helm lives at
`apps/loom-svelte/src/lib/joblist-fetch.ts`.

## Migration from pre-Phase-3 cells

Run `legacy migrate-to-graph` once (Phase 5 G.1):

```sh
ssh rbs bun run --cwd /opt/semantos legacy-cli -- migrate-to-graph
```

Add `--dry-run` first to see the plan without writing anything. The
verb walks `~/.semantos/data/oddjobz/jobs.jsonl` for v1 (flat-shape)
rows, looks each one up via the receipt store's cellId index, finds
the source proposal in the proposal store, and re-ratifies through
the Phase 2A.4 graph-walk handler.

Outcomes:

- Matched + re-ratified → new graph cell with the same source-PDF
  attachments. Original v1 row stays in `jobs.jsonl` (the helm
  joblist treats it as superseded by the new graph row).
- Un-matched (proposal pruned, receipt missing, no proposal-store
  match) → flagged in `~/.semantos/data/oddjobz/legacy-unsigned.jsonl`.
  The helm + mobile JobList renders these with the "legacy" pill.

Best-effort. Per matrix R5 the operator's first dogfood produced 72
v1 cells, some of which may not have proposal-store entries — those
stay flat with the badge. Re-ratify them manually via
`legacy correct <provider>:<proposal-id>` if they do still have a
proposal, or accept them as legacy artefacts.

Re-running `legacy migrate-to-graph` is idempotent — the verb tracks
already-migrated proposals via the graph-shaped receipt and skips
them on subsequent runs.

## What's NOT in the graph yet

Phase 3 covered jobs / sites / customers / attachments. Things still
on the flat path:

- Quotes (D-O7 follow-up adds quote.v2 cells)
- Visits (D-O5.followup-3 calendar feeds; cell promotion deferred)
- Invoices (`invoice.v2` is sketched but not yet minted by the
  ratify handler — Stripe integration is the trigger)
- Messages (`message.v1` exists but isn't graph-linked to jobs;
  Phase 6 deliverable)

The matrix tracks these as out-of-scope for D-DOG.1.0c proper.

## See also

- `docs/operator-runbooks/cell-signing-bkds.md` — how the graph
  cells are signed.
- `docs/canon/unification-matrix.yml` — the canonical roster of
  cell types (jobs / sites / customers / attachments) post-D-DOG.1.0c.
- `docs/prd/D-DOG-1.0c-LAYER-1-PROMOTION-MATRIX.md` — the full PRD,
  references for every PR landed in Phases 1-5.
- PRs #380, #379, #389 (helm), #378, #386, #388, #387 (mobile) —
  the graph-navigation work this guide describes.
