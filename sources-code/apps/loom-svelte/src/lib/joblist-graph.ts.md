---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/lib/joblist-graph.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.076894+00:00
---

# apps/loom-svelte/src/lib/joblist-graph.ts

```ts
// D-DOG.1.0c Phase 3 E.1 — pure helpers for the graph-aware JobList.
//
// Reference: docs/prd/D-DOG-1.0c-LAYER-1-PROMOTION-MATRIX.md §4 Phase 3
//   E.1 — render site address + primary customer + due date + has-photos
//   badge.  All four fields key off the v2 graph; v1 carry-over rows
//   render the legacy fallback shape.
//
// This module is pure (no Svelte / no fetch) so the parser/renderer
// invariants are tested under `node --test` without instantiating a
// Svelte component.  The component file (views/JobList.svelte)
// orchestrates the IO; this file does the joining + formatting.
//
// The N+1 prevention contract lives here too: [enrichJobs] takes the
// already-fetched [Map<siteCellId, OddjobzSiteRow>] +
// [Map<customerCellId, OddjobzCustomerRow>] +
// [Map<jobId, OddjobzJobRow>] (the v2 enrichment) and joins them
// against the REPL-shape base list with zero further IO.

import type {
  OddjobzCustomerRow,
  OddjobzJobRow,
  OddjobzSiteRow,
} from "./oddjobz-query.js";

/// One row as the JobList view model — what each rendered <tr> binds to.
/// Keeps the v1 carry-over fields and adds graph-aware extensions.  v1
/// rows have all the v2 fields as `null` / `false` / `""`.
export interface JobListRow {
  /// v1 carry-over — UUID job id.
  readonly id: string;
  /// v1 carry-over — flat customer-name string.  Used as the fallback
  /// when `primaryCustomer` is null.
  readonly customer_name: string;
  readonly state: string;
  readonly scheduled_at: string;
  /// True when the row has v2 graph enrichment available.  False for
  /// pure-v1 rows (we still render them — see E.1.c).
  readonly hasV2: boolean;
  /// Operator-supplied display address pulled from the linked v2 site
  /// (e.g. "13 Orealla Cr, Surfers Paradise").  Null for v1 rows.
  readonly propertyAddress: string | null;
  /// Operator-facing access key (e.g. "key #177").  Null when the v2
  /// row doesn't carry one or the row is v1.
  readonly propertyKey: string | null;
  /// 64-hex cellID of the linked v2 site — null on v1 rows.  Carried
  /// here (not just `propertyAddress`) so the E.2 site-pivot navigation
  /// has the raw ref needed to deep-link into `/sites/<cellId>` without
  /// a second round-trip to resolve address → ref.
  readonly siteRef: string | null;
  /// The customer the linked v2 job marks `primary: true` (resolved
  /// against the customer map).  Null for v1 rows or when the primary
  /// ref doesn't resolve (orphaned graph edge — render fallback).
  readonly primaryCustomer: PrimaryCustomer | null;
  /// ISO calendar date (YYYY-MM-DD) the work order is due.  Null for v1.
  readonly dueDate: string | null;
  /// True when the linked v2 job has photos in its source PDF.
  readonly hasPhotos: boolean;
  /// Photo count — 0 / null when none / unknown.
  readonly photoCount: number | null;
  /// D-DOG.1.0c Phase 5 G.2 — true when the row is a pre-Layer-1
  /// (v1 flat) cell that the `legacy migrate-to-graph` verb couldn't
  /// match to a source proposal.  Such rows render a small "legacy"
  /// pill alongside the state chip so the operator knows they're
  /// pre-promotion and unsigned (per Phase 4's BKDS posture).  False
  /// for every v2 graph-aware row and for v1 rows that successfully
  /// migrated to a graph during the verb's run.
  readonly legacyUnsigned: boolean;
}

/// Resolved primary-customer record.  We keep the shape minimal — only
/// the fields the row renderer actually displays.  Additional fields
/// (email, normalisedPhone) are reachable via `customerCellId` if a
/// future detail-popover wants them.
export interface PrimaryCustomer {
  /// The customer's display name from the v2 cell.
  readonly displayName: string;
  /// The customer's role on this job (tenant / agent / owner / pm /
  /// sub-tradie / other).  Comes off the customerRef inside the v2 job
  /// cell, not the customer cell — a customer can be `tenant` on one
  /// job and `agent` on another.
  readonly role: string;
  /// Phone string from the v1 carry-over field, when present.  v2's
  /// `normalisedPhone` is the canonical reachable channel; this is the
  /// raw display string the operator typed.
  readonly phone: string | null;
  /// 64-hex cellID — kept so a future row-click can navigate to the
  /// customer-pivot route (E.3, deferred).
  readonly customerCellId: string;
  /// The customer's source provenance providerId (e.g. "gmail" for a
  /// legacy email lead, "widget" for the chat funnel), or null when the
  /// customer cell carries no provenance (operator-created). Drives the
  /// job-row source pill via [jobSourceFromProvider]. Lives on the
  /// customer cell, not the job — see job-source.ts.
  readonly providerId: string | null;
}

/// Build a `Map<cellId, OddjobzSiteRow>` for fast site lookup by cellId.
/// The brain side guarantees `cellId` uniqueness; duplicates would
/// indicate store corruption (last-write-wins is fine for the helm).
export function siteMap(
  sites: readonly OddjobzSiteRow[],
): Map<string, OddjobzSiteRow> {
  const m = new Map<string, OddjobzSiteRow>();
  for (const s of sites) m.set(s.cellId, s);
  return m;
}

/// Build a `Map<cellId, OddjobzCustomerRow>` for fast customer lookup
/// by cellId.  v1 rows (cellId === null) are skipped — they're
/// unreachable from a v2 job's customerRefs by definition.
export function customerMap(
  customers: readonly OddjobzCustomerRow[],
): Map<string, OddjobzCustomerRow> {
  const m = new Map<string, OddjobzCustomerRow>();
  for (const c of customers) {
    if (c.cellId !== null) m.set(c.cellId, c);
  }
  return m;
}

/// Build a `Map<jobId, OddjobzJobRow>` keyed by the v1 carry-over UUID.
/// Used to associate v2 enrichment rows back to the REPL-shape base
/// list rows (which carry `id` but not `cellId`).
export function jobV2Map(
  jobs: readonly OddjobzJobRow[],
): Map<string, OddjobzJobRow> {
  const m = new Map<string, OddjobzJobRow>();
  for (const j of jobs) {
    // Only v2 rows have a cellId; v1 rows lack the graph enrichment so
    // joining them buys us nothing beyond the REPL shape we already have.
    if (j.cellId !== null) m.set(j.id, j);
  }
  return m;
}

/// Pick the primary customer-ref out of a v2 job's customerRefs array.
/// Returns null when the array is empty / null or no entry is marked
/// primary.  Per the v2 schema validator, exactly one ref is primary,
/// but the wire decoder doesn't re-validate so a corrupt row degrades
/// to "no primary".
export function pickPrimaryCustomerRef(
  refs: readonly { cellId: string; role: string; primary: boolean }[] | null,
): { cellId: string; role: string } | null {
  if (refs === null) return null;
  for (const r of refs) {
    if (r.primary) return { cellId: r.cellId, role: r.role };
  }
  return null;
}

/// Resolve the primary customer for a v2 job into a [PrimaryCustomer]
/// record.  Returns null when the job has no v2 enrichment, no primary
/// ref, or the ref points at a customer the customers map doesn't
/// know about (orphaned edge).
export function resolvePrimaryCustomer(
  v2Job: OddjobzJobRow | null,
  customers: Map<string, OddjobzCustomerRow>,
): PrimaryCustomer | null {
  if (v2Job === null) return null;
  const ref = pickPrimaryCustomerRef(v2Job.customerRefs);
  if (ref === null) return null;
  const cust = customers.get(ref.cellId);
  if (cust === undefined) return null;
  return {
    displayName: cust.display_name,
    role: ref.role,
    phone: cust.phone.length > 0 ? cust.phone : null,
    customerCellId: ref.cellId,
    providerId: cust.sourceProvenance?.providerId ?? null,
  };
}

// ─── Row construction ───────────────────────────────────────────────────

/// One row of the existing REPL `find jobs` shape — the legacy entry
/// point that emits v1 fields for every job (v1 + v2).  The component's
/// `parseJobs` produces these.
export interface ReplJobRow {
  readonly id: string;
  readonly customer_name: string;
  readonly state: string;
  readonly scheduled_at: string;
}

/// Join the REPL base list with the v2 enrichment maps to produce
/// view-model rows.  Pure — no IO.  Returns one row per REPL row in the
/// same order; v1 rows render with the v2 fields set to null/false.
///
/// D-DOG.1.0c Phase 5 G.2 — accepts an optional [legacyUnsignedIds]
/// set.  When a v1 row's id is in the set, the produced row carries
/// `legacyUnsigned: true` and the renderer paints the "legacy" pill
/// (the operator's signal that the row pre-dates Layer 1 promotion
/// and is unsigned, per Phase 4's BKDS posture).  Sourced from the
/// `legacy-unsigned.jsonl` sidecar the `legacy migrate-to-graph` verb
/// writes for un-matchable v1 rows.  v2 graph-aware rows are never
/// flagged: their cells are signed by the BKDS retrofit.
export function enrichJobs(
  baseRows: readonly ReplJobRow[],
  v2ById: Map<string, OddjobzJobRow>,
  sites: Map<string, OddjobzSiteRow>,
  customers: Map<string, OddjobzCustomerRow>,
  legacyUnsignedIds: ReadonlySet<string> = new Set(),
): JobListRow[] {
  const out: JobListRow[] = [];
  for (const base of baseRows) {
    const v2 = v2ById.get(base.id) ?? null;
    if (v2 === null) {
      out.push({
        id: base.id,
        customer_name: base.customer_name,
        state: base.state,
        scheduled_at: base.scheduled_at,
        hasV2: false,
        propertyAddress: null,
        propertyKey: null,
        siteRef: null,
        primaryCustomer: null,
        dueDate: null,
        hasPhotos: false,
        photoCount: null,
        legacyUnsigned: legacyUnsignedIds.has(base.id),
      });
      continue;
    }
    const site = v2.siteRef !== null ? (sites.get(v2.siteRef) ?? null) : null;
    out.push({
      id: base.id,
      customer_name: base.customer_name,
      state: base.state,
      scheduled_at: base.scheduled_at,
      hasV2: true,
      propertyAddress: site?.fullAddress ?? null,
      propertyKey: v2.propertyKey,
      siteRef: v2.siteRef,
      primaryCustomer: resolvePrimaryCustomer(v2, customers),
      dueDate: v2.dueDate,
      hasPhotos: v2.hasPhotos === true,
      photoCount: v2.photoCount,
      // v2 rows are signed by the Phase 4 BKDS retrofit; they are
      // never legacy-unsigned even if their id appears in the marker
      // (defensive: the marker is keyed on v1 id but a re-run after
      // a successful migration could leave a stale entry pointing at
      // an id that has since gone v2).
      legacyUnsigned: false,
    });
  }
  return out;
}

// ─── Date formatting ────────────────────────────────────────────────────

/// Format an ISO calendar date (YYYY-MM-DD) relative to `today` for the
/// JobList "Due" column.  Returns "—" for null input, "Due today" /
/// "Due tomorrow" / "Overdue (N days)" for near-dates, and
/// "Due 24 Mar" / "Due 24 Mar 2027" for far-dates.  `today` is a Date
/// (caller passes `new Date()` in production); injecting it keeps the
/// formatter testable without freezing the system clock.
export function formatDueDate(
  isoDate: string | null,
  today: Date = new Date(),
): string {
  if (isoDate === null || isoDate.length === 0) return "—";
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(isoDate);
  if (m === null) return isoDate;
  const year = Number(m[1]);
  const month = Number(m[2]);
  const day = Number(m[3]);
  // Compare in UTC days to avoid TZ flapping near midnight; the dueDate
  // is a calendar date with no time component, so UTC vs local is moot
  // beyond same-day comparison.
  const dueMs = Date.UTC(year, month - 1, day);
  const todayMs = Date.UTC(
    today.getUTCFullYear(),
    today.getUTCMonth(),
    today.getUTCDate(),
  );
  const oneDay = 24 * 60 * 60 * 1000;
  const diffDays = Math.round((dueMs - todayMs) / oneDay);

  if (diffDays === 0) return "Due today";
  if (diffDays === 1) return "Due tomorrow";
  if (diffDays === -1) return "Overdue 1 day";
  if (diffDays < 0) return `Overdue ${-diffDays} days`;

  const months = [
    "Jan",
    "Feb",
    "Mar",
    "Apr",
    "May",
    "Jun",
    "Jul",
    "Aug",
    "Sep",
    "Oct",
    "Nov",
    "Dec",
  ];
  const mon = months[month - 1] ?? "";
  if (year === today.getUTCFullYear()) {
    return `Due ${day} ${mon}`;
  }
  return `Due ${day} ${mon} ${year}`;
}

/// Format a primary customer for inline display, e.g.
/// "Jo-Anne Bisman (tenant)".  Returns null when no primary is
/// available — the renderer falls back to `customer_name`.
export function formatPrimaryCustomer(
  pc: PrimaryCustomer | null,
): string | null {
  if (pc === null) return null;
  return `${pc.displayName} (${pc.role})`;
}

```
