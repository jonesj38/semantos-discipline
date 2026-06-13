---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/lib/joblist-fetch.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.080196+00:00
---

# apps/loom-svelte/src/lib/joblist-fetch.ts

```ts
// D-DOG.1.0c Phase 3 E.1 — bulk-fetch coordinator for the JobList view.
//
// Reference: docs/prd/D-DOG-1.0c-LAYER-1-PROMOTION-MATRIX.md §4 Phase 3
//   E.1.b — "avoid N+1 customer lookups".  Same pattern applies for
//   sites: one `list_sites` + one `list_customers` for the whole render,
//   then a per-site `find_jobs_at_site` to gather the v2 job rows
//   (since there's no `oddjobz.list_jobs` verb — every v2 job has a
//   siteRef so the union of `find_jobs_at_site` results IS the v2 job
//   universe per the schema validator's REQUIRED-siteRef rule).
//
// The contract: ONE `list_sites` + ONE `list_customers` regardless of
// row count.  Per-site fan-out is bounded by the site count, not the
// job count — for the dogfood operator (~72 jobs across ~few-dozen
// sites) this is well under any meaningful threshold.  When the brain
// grows a `list_jobs_v2` verb a future PR collapses the fan-out into a
// single round-trip; the joiner in lib/joblist-graph.ts won't change.

import type { OddjobzQueryClient } from "./oddjobz-query.js";
import type {
  OddjobzCustomerRow,
  OddjobzJobRow,
  OddjobzSiteRow,
} from "./oddjobz-query.js";

/// Aggregate result of one bulk-fetch round — the three maps
/// [enrichJobs] consumes, plus the raw arrays (kept so a future
/// site-pivot / customer-pivot view can reuse the same fetch).
export interface JobListGraphSnapshot {
  readonly sites: readonly OddjobzSiteRow[];
  readonly customers: readonly OddjobzCustomerRow[];
  readonly v2Jobs: readonly OddjobzJobRow[];
}

/// Fetch the graph-aware enrichment maps in one bulk round.
///
/// Wire pattern:
///   1. parallel:  list_sites()  +  list_customers()
///   2. parallel:  find_jobs_at_site(site.cellId)  for each site
///
/// Returns the raw arrays.  Callers wrap them into Maps via the helpers
/// in `lib/joblist-graph.ts` (siteMap / customerMap / jobV2Map).
///
/// On any error, falls back to empty arrays — v2 enrichment is
/// best-effort.  The REPL `find jobs` path is the source of truth for
/// the row list, so a Semantos Brain that hasn't started its --enable-repl side
/// (no oddjobz query handler) renders a v1-only JobList rather than
/// erroring out.  The caller's responsibility is to surface a banner
/// when [error] is non-null.
export interface FetchGraphSnapshotResult {
  readonly snapshot: JobListGraphSnapshot;
  /// Best-effort failure message — null on full success, populated when
  /// any of the calls failed but enough state was gathered to render
  /// something.  The component degrades to v1-only rendering when this
  /// is set.
  readonly error: string | null;
}

export async function fetchGraphSnapshot(
  client: OddjobzQueryClient,
): Promise<FetchGraphSnapshotResult> {
  let sites: OddjobzSiteRow[] = [];
  let customers: OddjobzCustomerRow[] = [];
  let v2Jobs: OddjobzJobRow[] = [];
  let firstError: string | null = null;

  try {
    const [s, c] = await Promise.all([
      client.listSites(),
      client.listCustomers(),
    ]);
    sites = s;
    customers = c;
  } catch (e) {
    // The brain side returns store_unavailable when --enable-repl wasn't
    // set; surface that to the caller so it can render the legacy view.
    firstError = e instanceof Error ? e.message : String(e);
    return {
      snapshot: { sites: [], customers: [], v2Jobs: [] },
      error: firstError,
    };
  }

  // Parallel fan-out across sites.  Per-site failures are absorbed
  // into firstError; we keep the rows that did come back.
  const jobArrays = await Promise.all(
    sites.map(async (site) => {
      try {
        return await client.findJobsAtSite(site.cellId);
      } catch (e) {
        if (firstError === null) {
          firstError = e instanceof Error ? e.message : String(e);
        }
        return [] as OddjobzJobRow[];
      }
    }),
  );
  for (const arr of jobArrays) {
    for (const j of arr) v2Jobs.push(j);
  }

  return {
    snapshot: { sites, customers, v2Jobs },
    error: firstError,
  };
}

```
