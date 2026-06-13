---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/lib/customer-pivot.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.077462+00:00
---

# apps/loom-svelte/src/lib/customer-pivot.ts

```ts
// D-DOG.1.0c Phase 3 E.3 — customer-pivot view helpers.
//
// Reference: docs/prd/D-DOG-1.0c-LAYER-1-PROMOTION-MATRIX.md §4 Phase 3
//   E.3 — "operator opens a customer record from JobList → sees the
//   contact card + every job they're listed against".
//
// This module is the pure / testable half of the customer-pivot route
// at `src/routes/customers/[id]/+page.svelte`.  The view itself is a
// thin Svelte shell that:
//   1. Parses the customer cellId out of the URL pathname,
//   2. Calls `oddjobz.get_customer` + `oddjobz.find_jobs_for_customer`
//      via the [OddjobzQueryClient],
//   3. Renders the results through the projections defined here.
//
// Putting the projections in a standalone .ts file means we can test
// them with `node --test` (the SPA's existing test harness) without
// pulling Svelte's compiler in.
//
// The shape mirrors `lib/joblist-graph.ts`'s posture: small, pure,
// type-safe helpers with explicit fallbacks for missing v2 fields.

import type {
  OddjobzCustomerRow,
  OddjobzJobRow,
} from "./oddjobz-query.js";

/// Header card for the customer-pivot view.  Mirrors the v1+v2 mixed
/// shape — `display_name`, `phone`, `email` come from the v1 carry-over
/// fields (always populated for ratified customers), `role` and
/// `siteRef` are v2-only graph extensions.
export interface CustomerPivotHeader {
  /// 64-hex cellID — the canonical v2 identity.
  readonly cellId: string;
  readonly displayName: string;
  readonly phone: string;
  readonly email: string;
  /// Operator-supplied address string from the v1 carry-over field.
  /// Distinct from a linked `site` — a customer can be associated
  /// with N sites; this is the address the customer themselves sits
  /// at, used as a tie-breaker hint when the operator merges duplicate
  /// customer rows.
  readonly address: string;
  /// v2 role (tenant / agent / owner / pm / sub-tradie / other) or
  /// null when the row is a v1 carry-over (no graph metadata).
  readonly role:
    | "tenant"
    | "agent"
    | "owner"
    | "pm"
    | "sub-tradie"
    | "other"
    | null;
}

/// One row in the customer-pivot's "jobs they're contact for" list.
/// Stripped down to what the row renderer actually displays — the full
/// v2 job shape is reachable via the cellId for a future row-click
/// drill-down (D-O5.followup-N / job-detail pivot).
export interface CustomerPivotJobRow {
  /// v1 carry-over UUID — always populated.
  readonly id: string;
  /// 64-hex cellID of the v2 job, or null on v1 rows.
  readonly cellId: string | null;
  /// Customer's role on THIS specific job — comes off the job's
  /// customerRefs (a customer can be `tenant` on one job and `agent`
  /// on another), so it's per-row, not per-customer.
  readonly role: string | null;
  /// True when this customer is marked `primary: true` on the job's
  /// customerRefs.  Renderer surfaces a small badge.
  readonly primary: boolean;
  readonly state: string;
  readonly scheduled_at: string;
  /// ISO calendar date (YYYY-MM-DD) the work order is due, or null
  /// for v1 carry-over rows.
  readonly dueDate: string | null;
  /// Operator-supplied work order number, when present on the v2 row.
  readonly workOrderNumber: string | null;
}

/// Project a single [OddjobzCustomerRow] into the header-card shape.
/// Returns null when the input is null (the view renders a "not found"
/// stub).  v1 rows (`cellId === null`) are unreachable here — the
/// customer-pivot route is keyed by 64-hex cellId, which v1 rows don't
/// carry — but we tolerate them defensively by falling back to the
/// v1 `id` slot, prefixed `v1:` so it's clear in the URL bar / logs.
export function projectHeader(
  row: OddjobzCustomerRow | null,
): CustomerPivotHeader | null {
  if (row === null) return null;
  return {
    cellId: row.cellId ?? `v1:${row.id}`,
    displayName: row.display_name,
    phone: row.phone,
    email: row.email,
    address: row.address,
    role: row.role,
  };
}

/// Project the per-customer job list into the row shape.
///
/// For each [OddjobzJobRow] we look up the matching `customerRef`
/// against the customer cellId we're pivoting on, and pull the role +
/// primary flag off it.  The brain handler guarantees the result set
/// only contains jobs whose `customerRefs` include `customerCellId`
/// (otherwise the brain would have returned the wrong list), but we
/// guard defensively in case a future verb relaxes that contract.
///
/// Sort order: most-recently-scheduled first, then by id (stable
/// tiebreaker).  Operators typically open a customer to glance at
/// "what are we doing for them right now?" — newest jobs at the top
/// match that intent.  Empty `scheduled_at` strings sort last.
export function projectJobs(
  jobs: readonly OddjobzJobRow[],
  customerCellId: string,
): CustomerPivotJobRow[] {
  const rows: CustomerPivotJobRow[] = [];
  for (const j of jobs) {
    const ref = (j.customerRefs ?? []).find(
      (r) => r.cellId === customerCellId,
    );
    rows.push({
      id: j.id,
      cellId: j.cellId,
      role: ref?.role ?? null,
      primary: ref?.primary ?? false,
      state: j.state,
      scheduled_at: j.scheduled_at,
      dueDate: j.dueDate,
      workOrderNumber: j.workOrderNumber,
    });
  }
  rows.sort((a, b) => {
    // Empty scheduled_at sorts last (legacy v1 jobs without a date).
    const aEmpty = a.scheduled_at.length === 0;
    const bEmpty = b.scheduled_at.length === 0;
    if (aEmpty !== bEmpty) return aEmpty ? 1 : -1;
    if (a.scheduled_at !== b.scheduled_at) {
      // Reverse-chronological — newest first.
      return a.scheduled_at < b.scheduled_at ? 1 : -1;
    }
    return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
  });
  return rows;
}

/// Pull the customer cellId out of the helm pathname.
/// Accepts both `/helm/customers/<cellId>` and `/customers/<cellId>`
/// shapes (the SPA mounts under `/helm/` per vite.config.mjs base, but
/// tests + storybook stubs invoke without the prefix).
///
/// Returns null when the path doesn't match — the view shows the
/// "no customer selected" stub in that case rather than 404'ing.
///
/// We deliberately keep this lenient (no full cellId hex validation)
/// — the Semantos Brain-side handler is the canonical validator and emits a
/// typed JSON-RPC error for malformed refs, which the view surfaces
/// to the operator.  Doing redundant validation here would just mean
/// two error paths to maintain.
export function parseCustomerIdFromPath(pathname: string): string | null {
  const m = /\/customers\/([^/?#]+)/.exec(pathname);
  if (m === null) return null;
  const id = m[1] ?? "";
  if (id.length === 0) return null;
  return id;
}

```
