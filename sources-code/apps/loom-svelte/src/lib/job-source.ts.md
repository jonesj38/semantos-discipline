---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/lib/job-source.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.078829+00:00
---

# apps/loom-svelte/src/lib/job-source.ts

```ts
// Source-provenance pill for job rows.
//
// A canonical lead can arrive from several intake paths. The provenance
// lives on the CUSTOMER cell (`sourceProvenance.providerId`, stamped by the
// legacy-ingest pipeline + the widget funnel), NOT on the job cell — a job
// has no source field of its own. So a job's source is derived from its
// PRIMARY customer's providerId, surfaced here as a small pill so the
// operator can tell legacy Gmail leads apart from widget leads at a glance.
//
// Mapping is intentionally tolerant: unknown providers pass through as an
// "other" pill labelled with the raw providerId rather than being dropped.

export type JobSourceKind = "email" | "widget" | "other";

export interface JobSource {
  /// Stable kind token — drives the pill's CSS class / colour.
  readonly kind: JobSourceKind;
  /// Operator-facing label rendered in the pill.
  readonly label: string;
}

/// Derive the source pill from a customer's `providerId`.
///
///   gmail / email / imap   → email pill
///   widget / chat / chat-widget → widget pill
///   any other non-empty id → "other" pill labelled with the raw id
///   null / undefined / ""  → null (operator-created job; no pill)
export function jobSourceFromProvider(
  providerId: string | null | undefined,
): JobSource | null {
  if (providerId === null || providerId === undefined) return null;
  const p = providerId.trim().toLowerCase();
  if (p.length === 0) return null;
  if (p === "gmail" || p === "email" || p === "imap") {
    return { kind: "email", label: "email" };
  }
  if (p === "widget" || p === "chat" || p === "chat-widget") {
    return { kind: "widget", label: "widget" };
  }
  return { kind: "other", label: providerId };
}

```
