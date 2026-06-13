---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/cell-types/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.502380+00:00
---

# cartridges/oddjobz/brain/src/cell-types/index.ts

```ts
/**
 * Cell-type registry — the ten `oddjobz.*.v1` typed cells:
 *   - eight from §O2 (D-O2): job, quote, visit, invoice, customer,
 *     site, estimate, message
 *   - one from §O6b (D-O6b): lead — the AFFINE ratification anchor
 *   - one from D-O5m.followup-8 substrate: attachment — the LINEAR
 *     metadata cell for binary artifacts captured at a Visit (the
 *     mobile camera capture flow lands the producer in the next PR;
 *     this PR ships only the cell-type substrate so the brain knows
 *     about the shape before the phone starts producing signed cells).
 *
 * Post-CC5.B2b (2026-05-20): the v2 TS hand-mirrors for job / customer /
 * site were retired — their canonical schema now lives declaratively in
 * `cartridges/oddjobz/cartridge.json` `objectTypes` per CC5.B2a (#478).
 * Only `oddjobz.attachment.v2` remains as a TS-side v2 cell-type (it was
 * out of CC5.B2's deletion scope; attachment-v2 wiring carries the
 * sourceBlobKey/mimeType/pageCount/photoCount/hasPhotos accumulators).
 *
 * The export shape is deliberately flat: each type module exports its
 * own `CellTypeDef<T>` object; this file aggregates them into a
 * registry keyed by canonical name and a parallel registry keyed by
 * `typeHashHex` (downstream consumers — D-O3 cap mints, D-O4 state
 * machines — look up cell types by hash from the on-wire header).
 */

import type { CellTypeDef } from './cell-type.js';
import { customerCellType, type OddjobzCustomer } from './customer.js';
import { siteCellType, type OddjobzSite } from './site.js';
import { jobCellType, type OddjobzJob } from './job.js';
import { quoteCellType, type OddjobzQuote } from './quote.js';
import { visitCellType, type OddjobzVisit } from './visit.js';
import { invoiceCellType, type OddjobzInvoice } from './invoice.js';
import { estimateCellType, type OddjobzEstimate } from './estimate.js';
import {
  pricingPolicyCellType,
  type OddjobzPricingPolicy,
} from './pricing-policy.js';
import { messageCellType, type OddjobzMessage } from './message.js';
import { leadCellType, type OddjobzLead } from './lead.js';
import { attachmentCellType, type OddjobzAttachment } from './attachment.js';

// ── Remaining v2 cell type (attachment only — job/customer/site retired by CC5.B2b) ──
import {
  attachmentCellTypeV2,
  type OddjobzAttachmentV2,
} from './attachment.v2.js';

// ── v1 exports (unchanged) ─────────────────────────────────────────────
export {
  customerCellType,
  siteCellType,
  jobCellType,
  quoteCellType,
  visitCellType,
  invoiceCellType,
  estimateCellType,
  messageCellType,
  leadCellType,
  attachmentCellType,
  pricingPolicyCellType,
};

export type {
  OddjobzCustomer,
  OddjobzSite,
  OddjobzJob,
  OddjobzQuote,
  OddjobzVisit,
  OddjobzInvoice,
  OddjobzEstimate,
  OddjobzMessage,
  OddjobzLead,
  OddjobzAttachment,
  OddjobzPricingPolicy,
};

export { LEAD_PROVENANCES, type LeadProvenance } from './lead.js';
export {
  ATTACHMENT_KINDS,
  type AttachmentKind,
  packAttachment,
  unpackAttachment,
} from './attachment.js';

// ── v2 exports (attachment only) ───────────────────────────────────────

export { attachmentCellTypeV2 };

export type { OddjobzAttachmentV2 } from './attachment.v2.js';
export { packAttachmentV2, unpackAttachmentV2 } from './attachment.v2.js';

// ── Address normalisation utilities (extracted to stable module by CC5.B2b) ──
// Site-dedupe runtime helpers; canonical TS implementation lives in
// `cartridges/oddjobz/brain/src/address-normalisation.ts` (extracted from
// the retired `site.v2.ts`). `core/cell-ops` conformance vectors consume
// these directly; `runtime/legacy-ingest` currently has its own local
// copies (CC6 will retire that dual-truth).
export { normaliseAddress, deriveLookupKey } from '../address-normalisation.js';

// ── Explicit V1 / V2 aliases ───────────────────────────────────────────
// Post-CC5.B2b: job/customer/site no longer have a TS-side v2 cell-type
// (their canonical schema is in `cartridge.json` `objectTypes`). The
// default aliases point at v1 for those three; attachment keeps v2 as
// the default per the original PRD intent.
export const JOB_TYPE_V1: CellTypeDef<OddjobzJob> = jobCellType;
export const CUSTOMER_TYPE_V1: CellTypeDef<OddjobzCustomer> = customerCellType;
export const SITE_TYPE_V1: CellTypeDef<OddjobzSite> = siteCellType;
export const ATTACHMENT_TYPE_V1: CellTypeDef<OddjobzAttachment> = attachmentCellType;
export const ATTACHMENT_TYPE_V2: CellTypeDef<OddjobzAttachmentV2> = attachmentCellTypeV2;

// ── Defaults ───────────────────────────────────────────────────────────
// JOB/CUSTOMER/SITE: v2 was retired → default to v1. ATTACHMENT: default
// stays at v2 (the v2 entry is the only one in ODDJOBZ_CELL_TYPES_V2).
export const JOB_TYPE = JOB_TYPE_V1;
export const CUSTOMER_TYPE = CUSTOMER_TYPE_V1;
export const SITE_TYPE = SITE_TYPE_V1;
export const ATTACHMENT_TYPE = ATTACHMENT_TYPE_V2;

export type AnyOddjobzCellTypeDef =
  | CellTypeDef<OddjobzCustomer>
  | CellTypeDef<OddjobzSite>
  | CellTypeDef<OddjobzJob>
  | CellTypeDef<OddjobzQuote>
  | CellTypeDef<OddjobzVisit>
  | CellTypeDef<OddjobzInvoice>
  | CellTypeDef<OddjobzEstimate>
  | CellTypeDef<OddjobzMessage>
  | CellTypeDef<OddjobzLead>
  | CellTypeDef<OddjobzAttachment>
  | CellTypeDef<OddjobzAttachmentV2>
  // A5.P2 — operator CONFIG cell (not a §O2 entity). Joins the union
  // so it can be wired into the global cellTypeByName / cellTypeByHashHex
  // lookup tables (the write-walker decode + on-wire header type-hash
  // resolution need it).
  | CellTypeDef<OddjobzPricingPolicy>;

/**
 * The ten v1 cell types in canonical declaration order — matches the
 * §O2 table row-for-row, with the §O6b Lead cell + D-O5m.followup-8
 * Attachment cell appended as additive entries. Emitting tests,
 * glossary entries, and conformance-vector files iterate this array.
 *
 * v2 cell types (now only attachment.v2) are tracked separately in
 * `ODDJOBZ_CELL_TYPES_V2` so the §O2 / glossary tests don't see them;
 * both are unioned into the `cellTypeByName` / `cellTypeByHashHex`
 * lookup tables below.
 */
export const ODDJOBZ_CELL_TYPES: readonly AnyOddjobzCellTypeDef[] = Object.freeze([
  jobCellType,
  quoteCellType,
  visitCellType,
  invoiceCellType,
  customerCellType,
  siteCellType,
  estimateCellType,
  messageCellType,
  leadCellType,
  attachmentCellType,
]);

/**
 * Remaining v2 cell types (attachment only, post-CC5.B2b).
 * Listed separately from `ODDJOBZ_CELL_TYPES` so existing v1-only
 * assertions (length, names sweep against glossary.yml) continue to
 * hold; both are unioned into the lookup tables.
 */
export const ODDJOBZ_CELL_TYPES_V2: readonly AnyOddjobzCellTypeDef[] = Object.freeze([
  attachmentCellTypeV2,
]);

/**
 * A5.P0/P1a — operator-CONFIG cell types (not entities). Tracked in
 * a separate list, exactly as v2 is (the documented convention
 * above), so the §O2 / glossary / v1-length assertions over
 * `ODDJOBZ_CELL_TYPES` continue to hold. `pricing_policy` is
 * accumulate-never-consumed operator config (PERSISTENT/RELEVANT),
 * not an entity in the §O2 table.
 */
export const ODDJOBZ_CONFIG_CELL_TYPES: readonly CellTypeDef<OddjobzPricingPolicy>[] =
  Object.freeze([pricingPolicyCellType]);

/**
 * Union of all registered cell types (v1 ∪ v2 ∪ config). `ODDJOBZ_CELL_TYPES`
 * (v1 entities) stays length 10; `ODDJOBZ_CELL_TYPES_V2` is length 1
 * (attachment only, post-CC5.B2b); config is a separate list of 1, only
 * the *_ALL union grows. Total: 10 + 1 + 1 = 12.
 */
export const ODDJOBZ_CELL_TYPES_ALL: readonly AnyOddjobzCellTypeDef[] = Object.freeze([
  ...ODDJOBZ_CELL_TYPES,
  ...ODDJOBZ_CELL_TYPES_V2,
  ...ODDJOBZ_CONFIG_CELL_TYPES,
]);

/** Lookup by canonical name (e.g. `oddjobz.job.v1`, `oddjobz.attachment.v2`). */
export const cellTypeByName: Readonly<Record<string, AnyOddjobzCellTypeDef>> = Object.freeze(
  Object.fromEntries(ODDJOBZ_CELL_TYPES_ALL.map((t) => [t.name, t])) as Record<
    string,
    AnyOddjobzCellTypeDef
  >,
);

/** Lookup by lowercase typeHash hex (matches glossary.yml + on-wire bytes). */
export const cellTypeByHashHex: Readonly<Record<string, AnyOddjobzCellTypeDef>> = Object.freeze(
  Object.fromEntries(ODDJOBZ_CELL_TYPES_ALL.map((t) => [t.typeHashHex, t])) as Record<
    string,
    AnyOddjobzCellTypeDef
  >,
);

export { defineCellType, type CellTypeDef } from './cell-type.js';
export { type Linearity, WireLinearity, linearityWire } from './linearity.js';
export {
  computeTypeHash,
  typeHashHex,
  typeHashFromHex,
  typeHashEquals,
  type TypeHashInput,
} from './type-hash.js';
export {
  buildCellFieldTree,
  discloseCellField,
  verifyCellFieldDisclosure,
  computeCellFieldCommitments,
} from './field-tree-adapter.js';
export {
  authoriseFieldDisclosure,
  verifyAuthorisedFieldDisclosure,
  buildFullAuthorisedDisclosure,
  type AuthoriseFieldDisclosureInput,
  type VerifyAuthorisedFieldDisclosureInput,
  type VerifyAuthorisedFieldDisclosureResult,
} from './disclosure-authoriser.js';

```
