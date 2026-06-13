---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/cell-encoder.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.130738+00:00
---

# runtime/legacy-ingest/src/cell-encoder.ts

```ts
/**
 * D-RTC.4 — Cell encoder (TS side of substrate_entity dispatcher).
 *
 * Reference: docs/prd/D-Reingest-Typed-Cells.md §Deliverables / D-RTC.4
 *            §Resolved decisions / DECISION-10.
 *
 * DECISION-10 resolution: the brain's `substrate_entity.zig` is the
 * single source of truth for cell typehash + 1024-byte encoding +
 * audit-log emission. TS reingest does NOT reimplement the encoder.
 * Instead, this module builds `EntityEncodeRequest` envelopes that the
 * reingest worker dispatches to the brain via JSON-RPC, where
 * substrate_entity.encode() does the actual cell minting.
 *
 * What this module owns:
 *   1. Map each typed cell (Site/Customer/Job/Attachment) into the
 *      canonical payload-JSON shape the brain encoder expects.
 *   2. Pick the right SPEC tag (TAG_SITE/CUSTOMER/JOB/ATTACHMENT) +
 *      type-path triple for each cell type.
 *   3. Derive the linearity class per (tag, state) — matching the
 *      Zig substrate_entity.linearityFor() switch byte-for-byte so the
 *      brain accepts the cell without re-derivation.
 *   4. Translate the legacy contact-role enum (`tenant|agent|owner|
 *      pm|other`) to the PRD-broader ContactRole at the encoding
 *      boundary, so the Customer cell carries the new taxonomy.
 *
 * What this module does NOT own:
 *   - The actual cell mint (Zig brain).
 *   - The 1024-byte cell format (Zig brain).
 *   - The audit log (Zig brain).
 *   - The dispatcher wiring (separate brain-side `entity.encode` verb
 *     registration — landed alongside or after this commit).
 */

import type { ContactRole } from './role-classifier';
import type { ProposalContact } from './extractor/types';

/* ──────────────────────────────────────────────────────────────────────
 * Public types — mirror substrate_entity.zig
 * ────────────────────────────────────────────────────────────────────── */

/**
 * Mirror of `substrate_entity.zig::TAG_*`. Numeric value is the wire
 * representation the brain dispatcher's `entity.encode` verb expects.
 */
export const ENTITY_TAGS = {
  TAG_CUSTOMER: 0x01,
  TAG_VISIT: 0x02,
  TAG_QUOTE: 0x03,
  TAG_INVOICE: 0x04,
  TAG_ATTACHMENT: 0x05,
  TAG_JOB: 0x06,
  TAG_SITE: 0x07,
  TAG_LEAD: 0x08,
} as const;

export type EntityTag = (typeof ENTITY_TAGS)[keyof typeof ENTITY_TAGS];

/** Mirror of substrate_entity.zig::LinearityClass. */
export type LinearityClass = 'linear' | 'affine' | 'relevant' | 'debug';

/**
 * Mirror of substrate_entity.zig::SPEC_*. The {type_path, how_slug,
 * inst_path} triple is the input to computeTypeHash(); we carry it
 * here so the brain can validate the request against its registry
 * without us having to re-implement sha256.
 */
export interface EntityTypeSpec {
  readonly tag: EntityTag;
  readonly typePath: string;
  readonly howSlug: string;
  readonly instPath: string;
  /** Mirror of EntityTypeSpec.domain_flag — emitted at header offset 24. */
  readonly domainFlag: number;
}

export const SPEC_CUSTOMER: EntityTypeSpec = {
  tag: ENTITY_TAGS.TAG_CUSTOMER,
  typePath: 'oddjobz.customer',
  howSlug: 'identify',
  instPath: 'inst.identity.customer-record.v2',
  domainFlag: 0x00010108,
};

export const SPEC_ATTACHMENT: EntityTypeSpec = {
  tag: ENTITY_TAGS.TAG_ATTACHMENT,
  typePath: 'oddjobz.attachment',
  howSlug: 'capture',
  instPath: 'inst.evidence.site-artifact.v2',
  domainFlag: 0x0001010D,
};

export const SPEC_JOB: EntityTypeSpec = {
  tag: ENTITY_TAGS.TAG_JOB,
  typePath: 'oddjobz.job',
  howSlug: 'worktrack',
  instPath: 'inst.work.job-record.v2',
  domainFlag: 0x00010107,
};

export const SPEC_SITE: EntityTypeSpec = {
  tag: ENTITY_TAGS.TAG_SITE,
  typePath: 'oddjobz.site',
  howSlug: 'locate',
  instPath: 'inst.location.work-site.v2',
  domainFlag: 0x0001010E,
};

/**
 * One envelope the reingest worker dispatches via brain's
 * `entity.encode` verb. The brain replies with the 32-byte cell_id
 * (and writes the audit log).
 */
export interface EntityEncodeRequest {
  /** The substrate_entity spec — picks SPEC_JOB/SITE/CUSTOMER/ATTACHMENT. */
  readonly spec: EntityTypeSpec;
  /** Linearity derived per `linearityFor(tag, state)` Zig switch. */
  readonly linearity: LinearityClass;
  /** UTF-8 JSON the brain feeds straight into substrate_entity.encode(). */
  readonly payloadJson: string;
  /**
   * Owner id — first 16 bytes of the operator's hat id, hex. Brain
   * decodes into [16]u8. Zero-fill ("00..." × 32) when no hat context
   * (surfaces in audit as unowned).
   */
  readonly ownerIdHex: string;
}

/* ──────────────────────────────────────────────────────────────────────
 * Public API — per-cell-type encoders
 * ────────────────────────────────────────────────────────────────────── */

/** Site cell payload shape, ready to go into `EncodeRequest.payloadJson`. */
export interface SiteCellPayload {
  readonly lookup_key: string;
  readonly normalized_address: string;
  readonly key_number: string | null;
  readonly raw_address: string;
  /** "active" or "archived" — drives linearity per substrate_entity. */
  readonly state: 'active' | 'archived';
}

export interface CustomerCellPayload {
  readonly name: string;
  readonly email: string | null;
  readonly phone: string | null;
  readonly role: ContactRole;
  readonly linked_site_id: string | null;
  readonly notes: string | null;
  readonly state: 'active' | 'archived';
}

export interface JobCellPayload {
  readonly site_ref: string | null;
  readonly customer_refs: ReadonlyArray<{
    readonly cell_id: string;
    readonly role: ContactRole;
    readonly primary: boolean;
  }>;
  readonly work_order_number: string | null;
  readonly services: readonly string[];
  readonly issuance_date: string | null;
  readonly due_date: string | null;
  readonly intent:
    | 'quote_request'
    | 'work_order'
    | 'maintenance_order'
    | 'thread_followup'
    | 'not_a_job';
  readonly summary: string;
  readonly display_name: string;
  readonly raw_pdf_blob_sha256: string | null;
  readonly has_pictures: boolean;
  readonly picture_count: number | null;
  /**
   * "lead" / "quoted" / "scheduled" / "in_progress" / "invoiced" /
   * "paid" / "completed" / "closed" — drives linearity.
   */
  readonly state: string;
}

export interface AttachmentCellPayload {
  /**
   * Stable attachment id = the blob sha256 (single source of truth:
   * id == content_hash == the `<sha>.bin` filename the brain serves).
   * The brain's attachments_store_lmdb.applyPayload DROPS any cell
   * without `id` — historically absent, which is why no attachment
   * was ever served. Content-addressed ⇒ identical bytes dedupe.
   */
  readonly id: string;
  /**
   * Attachment cell id (64-hex = the blob sha). REQUIRED: the brain's
   * applyPayload only enters its v2 decode block — the one that parses
   * `jobRef` (and sourceBlobKey/photoCount) — when `cellId` is a
   * 64-hex string. Without it `jobRef` stays null and
   * AttachmentsStore.findForJob never matches → find jobs emits an
   * empty attachments[]. (= id = content_hash; single source of truth.)
   */
  readonly cellId: string;
  /**
   * SPEC_ATTACHMENT type hash (64-hex). The other half of the v2-block
   * gate. Constant for all attachment cells.
   */
  readonly typeHash: string;
  /** = sha256. The brain reads this to locate `<sha>.bin`. */
  readonly content_hash: string;
  /** Byte length of the blob. */
  readonly content_size: number;
  /** ISO timestamp — applyPayload requires `created_at` present. */
  readonly created_at: string;
  /**
   * Parent job cell id (64-hex). Emitted as `jobRef` so the brain's
   * AttachmentsStore.findForJob can return a job's attachments.
   */
  readonly jobRef: string;
  readonly mime_type: string;
  readonly filename: string | null;
  readonly blob_sha256: string;
  readonly parent_cell_id: string;
  readonly extraction_status:
    | 'stored_verbatim'
    | 'image_extracted'
    | 'pdf_text_extracted'
    | 'failed';
  readonly has_pictures: boolean;
  /** Always "captured" — attachments are immutable. Linearity .relevant. */
  readonly state: 'captured';
}

export function encodeSite(p: SiteCellPayload, ownerIdHex: string): EntityEncodeRequest {
  return {
    spec: SPEC_SITE,
    linearity: linearityFor(ENTITY_TAGS.TAG_SITE, p.state),
    payloadJson: JSON.stringify(p),
    ownerIdHex,
  };
}

export function encodeCustomer(p: CustomerCellPayload, ownerIdHex: string): EntityEncodeRequest {
  return {
    spec: SPEC_CUSTOMER,
    linearity: linearityFor(ENTITY_TAGS.TAG_CUSTOMER, p.state),
    payloadJson: JSON.stringify(p),
    ownerIdHex,
  };
}

export function encodeJob(p: JobCellPayload, ownerIdHex: string): EntityEncodeRequest {
  return {
    spec: SPEC_JOB,
    linearity: linearityFor(ENTITY_TAGS.TAG_JOB, p.state),
    payloadJson: slimJobJson(p),
    ownerIdHex,
  };
}

/**
 * Job-payload-specific JSON encoder. The substrate's 768-byte
 * PAYLOAD_BUDGET is tight for jobs that carry several customer_refs +
 * a long summary; default `JSON.stringify(p)` regularly produces
 * 800-900 byte payloads on the OJT corpus.
 *
 * Slim policy (post octave-1 escalation):
 *   1. Send the FULL `summary` (the operator's PDF job-sheet work
 *      scope) — NO truncation. The brain transparently escalates any
 *      payload over the 768-byte inline budget to an octave-1 content
 *      slot + pointer cell (substrate_entity.encodeEntityEscalating),
 *      and derefs it on read, so the full work detail round-trips.
 *      `display_name` stays capped (it is only a short list label).
 *   2. Omit fields that are null / false / empty-array. Readers
 *      MUST treat absence as the documented default (null for
 *      nullable fields, false for has_pictures, empty array for
 *      customer_refs/services). This matches the cell-schema.json
 *      "optional" semantics.
 *
 * Continuation-chain support (multi-cell payloads) per the
 * substrate_entity docstring is the longer-term fix; this slim is
 * the MVP pragmatic patch.
 */
function slimJobJson(p: JobCellPayload): string {
  const DISPLAY_CAP = 30;
  // Cap inline customer_refs at 2 (primary + one secondary). Each ref
  // is ~90 bytes; jobs with 4+ contacts (Clever Property bundles
  // with multiple tenants + agent) routinely blow the budget.
  // Remaining customer cells still exist as TAG_CUSTOMER cells with
  // linked_site_id back to the job's site_ref — the relationship is
  // preserved, just not inlined for free.
  const CUSTOMER_REFS_CAP = 2;
  // Sort by primary-first so the cap keeps the most important ref.
  const refs = [...p.customer_refs]
    .sort((a, b) => (b.primary ? 1 : 0) - (a.primary ? 1 : 0))
    .slice(0, CUSTOMER_REFS_CAP);
  const obj: Record<string, unknown> = {
    intent: p.intent,
    // Full work scope — brain escalates to octave-1 if over budget.
    summary: p.summary,
    display_name: truncate(p.display_name, DISPLAY_CAP),
    state: p.state,
  };
  if (p.site_ref !== null) obj.site_ref = p.site_ref;
  if (refs.length > 0) {
    obj.customer_refs = refs;
    if (p.customer_refs.length > refs.length) {
      obj.customer_refs_total = p.customer_refs.length;
    }
  }
  if (p.work_order_number !== null) obj.work_order_number = p.work_order_number;
  if (p.services.length > 0) obj.services = p.services;
  if (p.issuance_date !== null) obj.issuance_date = p.issuance_date;
  if (p.due_date !== null) obj.due_date = p.due_date;
  if (p.raw_pdf_blob_sha256 !== null) obj.raw_pdf_blob_sha256 = p.raw_pdf_blob_sha256;
  if (p.has_pictures) obj.has_pictures = true;
  if (p.picture_count !== null) obj.picture_count = p.picture_count;
  return JSON.stringify(obj);
}

function truncate(s: string, cap: number): string {
  if (s.length <= cap) return s;
  return s.slice(0, cap - 1) + '…';
}

export function encodeAttachment(
  p: AttachmentCellPayload,
  ownerIdHex: string,
): EntityEncodeRequest {
  return {
    spec: SPEC_ATTACHMENT,
    linearity: linearityFor(ENTITY_TAGS.TAG_ATTACHMENT, p.state),
    payloadJson: JSON.stringify(p),
    ownerIdHex,
  };
}

/* ──────────────────────────────────────────────────────────────────────
 * Linearity — mirrors substrate_entity.zig::linearityFor byte-for-byte
 * ────────────────────────────────────────────────────────────────────── */

/**
 * TS port of substrate_entity.zig::linearityFor(). Keeping this in
 * lock-step with the Zig switch is part of D-RTC.4's acceptance gate
 * (zero drift events from drift_detector.zig).
 */
export function linearityFor(tag: EntityTag, state: string): LinearityClass {
  switch (tag) {
    case ENTITY_TAGS.TAG_LEAD:
      return state === 'pending' ? 'affine' : 'relevant';
    case ENTITY_TAGS.TAG_JOB:
      if (state === 'lead') return 'affine';
      if (state === 'completed' || state === 'closed') return 'relevant';
      return 'linear';
    case ENTITY_TAGS.TAG_QUOTE:
      return state === 'open' ? 'linear' : 'relevant';
    case ENTITY_TAGS.TAG_INVOICE:
      return state === 'issued' || state === 'partial' ? 'linear' : 'relevant';
    case ENTITY_TAGS.TAG_VISIT:
      return state === 'scheduled' ? 'linear' : 'relevant';
    case ENTITY_TAGS.TAG_CUSTOMER:
    case ENTITY_TAGS.TAG_SITE:
      return state === 'archived' ? 'relevant' : 'affine';
    case ENTITY_TAGS.TAG_ATTACHMENT:
      return 'relevant';
    default:
      return 'linear';
  }
}

/* ──────────────────────────────────────────────────────────────────────
 * Role taxonomy bridge
 * ────────────────────────────────────────────────────────────────────── */

/**
 * Map the legacy ProposalContact.role enum to the PRD-broader
 * ContactRole. Done here at the encoding boundary so legacy proposals
 * (extracted before D-RTC.3 v0.6) flow into the new customer cells
 * with the right taxonomy.
 *
 *   tenant → tenant
 *   agent → agent
 *   owner → site_owner
 *   pm → property_manager
 *   other → unknown
 */
export function mapLegacyRole(legacy: ProposalContact['role']): ContactRole {
  switch (legacy) {
    case 'tenant':
      return 'tenant';
    case 'agent':
      return 'agent';
    case 'owner':
      return 'site_owner';
    case 'pm':
      return 'property_manager';
    case 'other':
    default:
      return 'unknown';
  }
}

```
