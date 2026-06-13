---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/lib/job-detail-graph.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.081625+00:00
---

# apps/loom-svelte/src/lib/job-detail-graph.ts

```ts
// D-DOG.1.0c Phase 3 E.4 — pure helpers for the graph-aware job-detail
// view.
//
// Reference: docs/prd/D-DOG-1.0c-LAYER-1-PROMOTION-MATRIX.md §4 Phase 3
//   E.4 — render the v2 job's full work-order surface (workOrderNumber,
//   issuanceDate, dueDate, propertyKey, billingParty, etc.) plus the
//   linked site (one link), linked customers (primary + secondary, each
//   linked) and the attachments list (sourceBlobKey + mimeType +
//   pageCount + photoCount per row).
//
// This module is pure (no Svelte / no fetch) so the formatters +
// resolvers are tested under `node --test` without instantiating a
// Svelte component.  The component file (views/JobDetailV2.svelte)
// orchestrates the IO; this file does the joining + formatting.
//
// Why a separate module: the joblist-graph helpers project a row-level
// view (one tr per job).  The detail view needs a different shape —
// it joins ONE job against the customer + site maps and resolves the
// ordered customerRefs into displayable cards.  Same maps, different
// projection.

import type {
  OddjobzAttachmentRow,
  OddjobzCustomerRow,
  OddjobzJobBillingPartyWire,
  OddjobzJobRow,
  OddjobzSiteRow,
} from "./oddjobz-query.js";

/// Resolved customer reference — a row in the linked-customers list
/// rendered alongside the job header.  Each entry mirrors one entry in
/// the v2 job's `customerRefs` array, joined against the customers map
/// so the operator sees a name rather than a 64-hex cellID.
export interface JobDetailCustomerLink {
  /// Position in the ordered customerRefs array — primary always sorts
  /// first, then secondary refs in the order the v2 cell encodes them.
  readonly order: number;
  /// 64-hex cellID — the `to` reference and the navigation key for a
  /// future `/customers/<customerRef>` pivot view.
  readonly cellId: string;
  /// Role this customer plays on this job (tenant / agent / owner / pm
  /// / sub-tradie / other) — comes from the customerRef inside the v2
  /// job cell, not the customer cell.
  readonly role: string;
  /// True when the v2 job marks this ref `primary: true`.  Exactly one
  /// primary per job by the schema validator's invariant.
  readonly primary: boolean;
  /// Resolved display name.  Null when the ref points at a customer
  /// cellID we don't have in the snapshot — render fallback so an
  /// orphaned ref doesn't blank the row.
  readonly displayName: string | null;
}

/// View-model the JobDetailV2.svelte component binds to.  Every field
/// the operator can see is populated here; the component is a pure
/// renderer over this struct.  All v2 fields are optional — when the
/// underlying job is a v1 carry-over (cellId === null) only the v1
/// carry-over fields populate and the v2 panels render their fallback.
export interface JobDetailView {
  /// v1 carry-over — UUID job id.  Always present.
  readonly id: string;
  readonly customer_name: string;
  readonly state: string;
  readonly scheduled_at: string;
  readonly created_at: string;
  /// True when the row has v2 graph enrichment available.
  readonly hasV2: boolean;
  /// 64-hex cellID — null on v1.
  readonly cellId: string | null;
  /// Operator-supplied work-order number ("WO-12345").  Null on v1.
  readonly workOrderNumber: string | null;
  /// ISO calendar date (YYYY-MM-DD) the work order was issued.  Null on v1.
  readonly issuanceDate: string | null;
  /// ISO calendar date (YYYY-MM-DD) the work order is due.  Null on v1.
  readonly dueDate: string | null;
  /// Operator-facing access key (e.g. "key #177").  Null when absent.
  readonly propertyKey: string | null;
  /// Billing party (which side of the cert chain pays this WO).  Null on v1.
  readonly billingParty: OddjobzJobBillingPartyWire | null;
  /// Convenience flag — null on v1 rows.
  readonly hasPhotos: boolean | null;
  readonly photoCount: number | null;
  /// 64-hex cellID of the linked v2 site — null on v1.
  readonly siteRef: string | null;
  /// Resolved site fullAddress.  Null on v1, OR when the job's siteRef
  /// is set but the site map didn't carry the row (orphaned graph edge).
  readonly siteAddress: string | null;
  /// Ordered customer links — primary first, secondaries follow.  Empty
  /// array on v1 rows.  Each entry resolves against the customer map.
  readonly customers: readonly JobDetailCustomerLink[];
}

/// Project a v2 [OddjobzJobRow] into the view-model the JobDetailV2
/// component binds to.  Pure — caller hands in the join maps; no IO.
///
/// Site + customer maps are the same shape `joblist-graph.ts` builds, so
/// the JobList → JobDetail navigation path can reuse the snapshot rather
/// than re-fetch.
export function buildJobDetailView(
  job: OddjobzJobRow,
  sites: ReadonlyMap<string, OddjobzSiteRow>,
  customers: ReadonlyMap<string, OddjobzCustomerRow>,
): JobDetailView {
  const hasV2 = job.cellId !== null;
  const siteRef = job.siteRef;
  const siteAddress =
    siteRef !== null ? (sites.get(siteRef)?.fullAddress ?? null) : null;

  const refs = job.customerRefs ?? [];
  // Stable order: primary first, then secondaries in their wire order.
  // `findIndex` on a copy preserves relative order between the
  // secondaries so the operator sees a consistent list across renders.
  const ordered = [...refs].map((ref, idx) => ({ ref, idx }));
  ordered.sort((a, b) => {
    if (a.ref.primary !== b.ref.primary) return a.ref.primary ? -1 : 1;
    return a.idx - b.idx;
  });

  const customerLinks: JobDetailCustomerLink[] = ordered.map(({ ref }, i) => {
    const resolved = customers.get(ref.cellId) ?? null;
    return {
      order: i,
      cellId: ref.cellId,
      role: ref.role,
      primary: ref.primary,
      displayName: resolved?.display_name ?? null,
    };
  });

  return {
    id: job.id,
    customer_name: job.customer_name,
    state: job.state,
    scheduled_at: job.scheduled_at,
    created_at: job.created_at,
    hasV2,
    cellId: job.cellId,
    workOrderNumber: job.workOrderNumber,
    issuanceDate: job.issuanceDate,
    dueDate: job.dueDate,
    propertyKey: job.propertyKey,
    billingParty: job.billingParty,
    hasPhotos: job.hasPhotos,
    photoCount: job.photoCount,
    siteRef,
    siteAddress,
    customers: customerLinks,
  };
}

/// Format an attachment row as the operator-readable summary line.
///
/// Surface shape: `Attachment: <sourceBlobKey> (<mimeType>, N pages, M
/// photos)`.  PDF inline rendering is deferred to the `legacy attachment
/// <id>` verb's surface — this view is read-only metadata.
///
/// Falls back gracefully on v1 rows (no sourceBlobKey / pageCount /
/// photoCount) so the operator's existing visit-side photos still
/// render a useful line.
export function formatAttachmentSummary(att: OddjobzAttachmentRow): string {
  const head = att.sourceBlobKey !== null && att.sourceBlobKey.length > 0
    ? att.sourceBlobKey
    : att.id;
  const parts: string[] = [];
  if (att.mime_type.length > 0) parts.push(att.mime_type);
  if (att.pageCount !== null) {
    parts.push(`${att.pageCount} page${att.pageCount === 1 ? "" : "s"}`);
  }
  if (att.photoCount !== null) {
    parts.push(`${att.photoCount} photo${att.photoCount === 1 ? "" : "s"}`);
  }
  if (parts.length === 0) return `Attachment: ${head}`;
  return `Attachment: ${head} (${parts.join(", ")})`;
}

/// Stable sort for attachment rendering.  v2 rows (those with a
/// non-null pageCount) bubble first so the work-order PDF anchors the
/// list; the visit-side photos follow in capture-time order.  Rows
/// without `captured_at` sort last to keep the comparator total.
export function sortAttachments(
  attachments: readonly OddjobzAttachmentRow[],
): OddjobzAttachmentRow[] {
  const copy = [...attachments];
  copy.sort((a, b) => {
    const aHasPage = a.pageCount !== null;
    const bHasPage = b.pageCount !== null;
    if (aHasPage !== bHasPage) return aHasPage ? -1 : 1;
    if (a.captured_at < b.captured_at) return -1;
    if (a.captured_at > b.captured_at) return 1;
    return 0;
  });
  return copy;
}

```
