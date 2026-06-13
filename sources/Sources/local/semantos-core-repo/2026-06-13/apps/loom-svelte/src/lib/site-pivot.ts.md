---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/lib/site-pivot.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.081062+00:00
---

# apps/loom-svelte/src/lib/site-pivot.ts

```ts
// D-DOG.1.0c Phase 3 E.2 — pure helpers for the site-pivot route.
//
// Reference: docs/prd/D-DOG-1.0c-LAYER-1-PROMOTION-MATRIX.md §4 Phase 3
//   E.2 — "helm site-pivot route — all jobs at this address".  Given a
//   site cellId the operator wants to see (a) the full property header
//   and (b) every job that has ever happened at the address, regardless
//   of which customer commissioned it.  Both bits ride the existing
//   Phase 2B.3 RPC surface — `oddjobz.get_site` for the header and
//   `oddjobz.find_jobs_at_site` for the row list — so this module is
//   purely the joiner + formatters; the IO sits in views/SiteDetail.
//
// Why split this out (mirrors lib/joblist-graph.ts):
//
// The Svelte component file holds the orchestration (props, $state,
// $effect, the [load] async function).  The pure joiners + formatters
// live here so the parser/renderer invariants are testable under
// `node --test` without instantiating a Svelte component.  The brief's
// "extract JobList row into shared component if still inline" hint is
// satisfied by this split — the row shape ([SiteJobRow]) and the
// formatter helpers are reusable from both JobList and SiteDetail
// without depending on either component's internals.

import type {
  OddjobzCustomerRow,
  OddjobzJobRow,
  OddjobzSiteRow,
} from "./oddjobz-query.js";
import {
  formatDueDate,
  formatPrimaryCustomer,
  resolvePrimaryCustomer,
  type PrimaryCustomer,
} from "./joblist-graph.js";

/// Operator-facing address header — the four lines the SiteDetail view
/// renders at the top of the page.  Built from one [OddjobzSiteRow] so
/// callers don't need to know the wire-shape's nullability rules.
export interface SiteAddressHeader {
  /// First line: the operator-supplied display address.  Always set —
  /// the v2 schema requires `fullAddress` on every site cell.
  readonly fullAddress: string;
  /// Second line: "Suburb, STATE postcode" with empty pieces dropped.
  /// Empty string when none of the three fields are populated.
  readonly localityLine: string;
  /// Operator-facing access key suffix (e.g. "key #177").  Null when
  /// the site cell has no `keyNumber`.  Rendered as a small chip beside
  /// the address rather than on its own line.
  readonly keyChip: string | null;
}

/// Build the address header from an [OddjobzSiteRow].
///
/// Locality-line rules:
///   - "Surfers Paradise, QLD 4217"  — all three present
///   - "Surfers Paradise, QLD"        — postcode missing
///   - "Surfers Paradise 4217"        — state missing
///   - "QLD 4217"                     — suburb missing
///   - ""                              — none present
///
/// Whitespace is collapsed and leading/trailing punctuation that would
/// otherwise leak out of the gaps (e.g. ", QLD") is trimmed off.
export function buildSiteAddressHeader(
  site: OddjobzSiteRow,
): SiteAddressHeader {
  const suburb = (site.suburb ?? "").trim();
  const state = (site.state ?? "").trim();
  const postcode = (site.postcode ?? "").trim();

  let localityLine: string;
  // The state+postcode pair reads as one unit visually; if either is
  // present we glue them with a space, then prefix the suburb with ", "
  // when both ends are non-empty.
  const tail =
    state.length > 0 && postcode.length > 0
      ? `${state} ${postcode}`
      : state.length > 0
        ? state
        : postcode;
  if (suburb.length > 0 && tail.length > 0) {
    localityLine = `${suburb}, ${tail}`;
  } else if (suburb.length > 0) {
    localityLine = suburb;
  } else {
    localityLine = tail;
  }

  const keyChip =
    site.keyNumber !== null && site.keyNumber.length > 0
      ? `key ${site.keyNumber.startsWith("#") ? site.keyNumber : `#${site.keyNumber}`}`
      : null;

  return {
    fullAddress: site.fullAddress,
    localityLine,
    keyChip,
  };
}

// ─── Per-site job rows ──────────────────────────────────────────────────

/// One row of the site-pivot job list.  Mirrors [JobListRow] in shape
/// (so a future shared row component can render either with no
/// branching), but drops `propertyAddress` since every row at this
/// pivot is by definition at the same address — the page header
/// renders it once.
export interface SiteJobRow {
  /// UUID — both v1 and v2 jobs at this site.
  readonly id: string;
  /// v1 carry-over flat customer-name string.  Used as the fallback
  /// when `primaryCustomer` is null.
  readonly customer_name: string;
  readonly state: string;
  readonly scheduled_at: string;
  /// True when the row carries v2 graph enrichment.  Per the v2 schema
  /// validator's REQUIRED-siteRef rule, every job returned by
  /// `find_jobs_at_site` IS v2 — but we keep the flag for symmetry
  /// with [JobListRow] and for the (defensive) v1 carry-over case.
  readonly hasV2: boolean;
  /// ISO calendar date (YYYY-MM-DD) the work order is due.  Null for v1.
  readonly dueDate: string | null;
  /// Resolved primary customer — null when the job has no v2 enrichment,
  /// no primary customerRef, or the ref points at a customer the
  /// customers map doesn't know about (orphaned edge).
  readonly primaryCustomer: PrimaryCustomer | null;
  /// True when the linked v2 job has photos in its source PDF.
  readonly hasPhotos: boolean;
  /// Photo count — 0 / null when none / unknown.
  readonly photoCount: number | null;
}

/// Join a per-site `find_jobs_at_site` response with the customers map
/// to produce view-model rows.  Pure — no IO.  The customers map comes
/// from the same `oddjobz.list_customers` round-trip the JobList view
/// already does, so callers can reuse the bulk fetch when they have
/// one (e.g. when navigating from JobList to SiteDetail without
/// remounting).
export function buildSiteJobRows(
  jobs: readonly OddjobzJobRow[],
  customers: Map<string, OddjobzCustomerRow>,
): SiteJobRow[] {
  const out: SiteJobRow[] = [];
  for (const j of jobs) {
    out.push({
      id: j.id,
      customer_name: j.customer_name,
      state: j.state,
      scheduled_at: j.scheduled_at,
      hasV2: j.cellId !== null,
      dueDate: j.dueDate,
      primaryCustomer: resolvePrimaryCustomer(j, customers),
      hasPhotos: j.hasPhotos === true,
      photoCount: j.photoCount,
    });
  }
  return out;
}

// Re-export the shared formatters so SiteDetail.svelte imports both
// from one module.  These are the same helpers JobList uses; sharing
// them keeps the row rendering visually consistent across pivots.
export { formatDueDate, formatPrimaryCustomer };

// ─── Route helpers ──────────────────────────────────────────────────────

/// Parse a site cellId out of `window.location.hash`.  Returns null
/// when the hash doesn't match `#/sites/<64-hex>` — the App.svelte
/// router falls back to the Jobs tab in that case.  Defensive against
/// trailing slashes, query strings, and embedded uppercase (the v2
/// schema validator emits lowercase hex but a hand-typed deep link
/// should still resolve).
export function parseSiteHashRoute(hash: string): string | null {
  // Strip leading `#`.  A bare `""` or `"#"` short-circuits.
  const raw = hash.startsWith("#") ? hash.slice(1) : hash;
  if (raw.length === 0) return null;
  // Drop any query string (`?bearer=...`) or trailing slash.
  const cleaned = raw.split("?")[0]!.replace(/\/+$/, "");
  const m = /^\/?sites\/([0-9a-fA-F]{64})$/.exec(cleaned);
  if (m === null) return null;
  return m[1]!.toLowerCase();
}

/// Build the hash-route fragment for a given site cellId.  Used by the
/// JobList address-cell anchor + by the SiteDetail "back to jobs" link
/// (which navigates to `#/jobs`) — keeping the URL shape in one place
/// here means future SvelteKit migration only has to update this
/// helper's body, not every call site.
export function siteHashRoute(siteRef: string): string {
  return `#/sites/${siteRef}`;
}

```
