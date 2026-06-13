---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/cell-types/attachment.v2.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.503612+00:00
---

# cartridges/oddjobz/brain/src/cell-types/attachment.v2.ts

```ts
/**
 * `oddjobz.attachment.v2` — LINEAR cell.
 *
 * Graph-aware successor to `oddjobz.attachment.v1`, scoped by D-DOG.1.0c
 * Phase 1. v1 was specifically the visit-side photo/voice-memo metadata
 * from D-O5m.followup-8 (mobile camera capture). v2 lifts the surface
 * area to also describe **the source PDFs themselves** that proposals
 * are extracted from — so the helm + mobile graph navigation can drill
 * from a job back to "the work-order PDF + the embedded photos" as a
 * cell, with a path to fetch the original blob bytes for re-display.
 *
 * v2 carries every v1 field verbatim and adds:
 *
 *   - sourceBlobKey  — the blob-store key in `legacy-ingest`'s blob
 *                      store, so a future `legacy attachment <id>` verb
 *                      can find + decrypt the source bytes
 *   - mimeType (already in v1; kept REQUIRED in v2)
 *   - pageCount      — total pages for PDFs, null otherwise
 *   - photoCount     — distinct embedded photos in the PDF
 *                      (Vision-detected), null for non-PDFs
 *   - hasPhotos      — convenience derived flag, true iff
 *                      photoCount > 0
 *
 * v1 cells stay valid + readable; the registry resolves both versions.
 *
 * NOTE: v1's REQUIRED fields (visitId, kind, contentHash, contentSize,
 * capturedAt, capturedByCertId) are RELAXED to optional in v2 because
 * a source-PDF attachment minted at ratify-time has no parent visit and
 * no device-capture cert. Callers that mint a visit-side attachment via
 * v2 must still supply those fields; the validator enforces the v1
 * shape when visitId is present.
 */

import { defineCellType, type CellTypeDef } from './cell-type.js';
import {
  assertUuid,
  assertOptionalUuid,
  assertNonEmptyString,
  assertOptionalString,
  assertEnum,
  assertOptionalEnum,
  assertNonNegativeInt,
  assertIsoDateString,
  assertOptionalIsoDateString,
} from './validators.js';
import {
  ATTACHMENT_KINDS,
  type AttachmentKind,
} from './attachment.js';

export { ATTACHMENT_KINDS, type AttachmentKind };

export interface OddjobzAttachmentV2 {
  // ── v1 carry-over fields ────────────────────────────────────────────
  // visitId/kind/contentHash/contentSize/capturedAt/capturedByCertId are
  // REQUIRED in v1; v2 makes them optional so a source-PDF attachment
  // minted at ratify-time (no visit, no device cert) is representable.
  // The visit-capture path still passes them; v2's validator enforces
  // the v1 shape when visitId is present.
  readonly attachmentId: string;
  readonly visitId?: string;
  readonly kind?: AttachmentKind;
  readonly contentHash?: string;
  readonly contentSize?: number;
  readonly mimeType: string;
  readonly capturedAt?: string;
  readonly capturedByCertId?: string;
  readonly caption?: string;
  readonly createdAt: string;

  // ── v2 graph-aware additions ────────────────────────────────────────
  /** Blob-store key in `legacy-ingest`'s blob store. */
  readonly sourceBlobKey: string;
  /** Total pages for PDFs; null otherwise. */
  readonly pageCount: number | null;
  /** Distinct embedded photos detected in the source PDF; null for non-PDFs. */
  readonly photoCount: number | null;
  /** Convenience derived flag: true iff `photoCount > 0`. */
  readonly hasPhotos: boolean;
}

const HEX_RE = /^[0-9a-f]+$/;
const CONTENT_HASH_LEN = 64;
const CERT_ID_LEN = 32;
const MAX_CAPTION_LEN = 500;

function assertHexString(field: string, value: unknown, length: number): asserts value is string {
  if (typeof value !== 'string' || value.length !== length || !HEX_RE.test(value)) {
    throw new Error(`field ${field}: not a ${length}-char lowercase hex string`);
  }
}

function validate(v: OddjobzAttachmentV2): void {
  // ── v1 carry-over validation (verbatim from attachment.v1) ──────────
  assertUuid('attachmentId', v.attachmentId);
  assertOptionalUuid('visitId', v.visitId);
  assertOptionalEnum('kind', v.kind, ATTACHMENT_KINDS);
  if (v.contentHash !== undefined) {
    assertHexString('contentHash', v.contentHash, CONTENT_HASH_LEN);
  }
  if (v.contentSize !== undefined) {
    assertNonNegativeInt('contentSize', v.contentSize);
  }
  assertNonEmptyString('mimeType', v.mimeType);
  assertOptionalIsoDateString('capturedAt', v.capturedAt);
  if (v.capturedByCertId !== undefined) {
    assertHexString('capturedByCertId', v.capturedByCertId, CERT_ID_LEN);
  }
  assertOptionalString('caption', v.caption);
  if (v.caption !== undefined && v.caption.length > MAX_CAPTION_LEN) {
    throw new Error(`field caption: exceeds ${MAX_CAPTION_LEN} chars`);
  }
  assertIsoDateString('createdAt', v.createdAt);

  // v1-shape enforcement: when this is a visit-side attachment (visitId
  // present), all v1 REQUIRED fields must be present.
  if (v.visitId !== undefined) {
    if (v.kind === undefined) {
      throw new Error('field kind: required when visitId is present (v1 visit-attachment shape)');
    }
    if (v.contentHash === undefined) {
      throw new Error('field contentHash: required when visitId is present');
    }
    if (v.contentSize === undefined) {
      throw new Error('field contentSize: required when visitId is present');
    }
    if (v.capturedAt === undefined) {
      throw new Error('field capturedAt: required when visitId is present');
    }
    if (v.capturedByCertId === undefined) {
      throw new Error('field capturedByCertId: required when visitId is present');
    }
  }

  // ── v2-specific validation ──────────────────────────────────────────
  assertNonEmptyString('sourceBlobKey', v.sourceBlobKey);

  if (v.pageCount !== null) {
    assertNonNegativeInt('pageCount', v.pageCount);
  }
  if (v.photoCount !== null) {
    assertNonNegativeInt('photoCount', v.photoCount);
  }

  if (typeof v.hasPhotos !== 'boolean') {
    throw new Error('field hasPhotos: not a boolean');
  }
  // hasPhotos derives deterministically from photoCount; enforce parity
  const derivedHasPhotos = v.photoCount !== null && v.photoCount > 0;
  if (v.hasPhotos !== derivedHasPhotos) {
    throw new Error(
      `field hasPhotos: must equal (photoCount > 0); expected ${derivedHasPhotos}, got ${v.hasPhotos}`,
    );
  }
}

function toCanonical(v: OddjobzAttachmentV2): Record<string, unknown> {
  const out: Record<string, unknown> = {
    attachmentId: v.attachmentId,
    mimeType: v.mimeType,
    createdAt: v.createdAt,
    sourceBlobKey: v.sourceBlobKey,
    pageCount: v.pageCount,
    photoCount: v.photoCount,
    hasPhotos: v.hasPhotos,
  };
  if (v.visitId !== undefined) out.visitId = v.visitId;
  if (v.kind !== undefined) out.kind = v.kind;
  if (v.contentHash !== undefined) out.contentHash = v.contentHash;
  if (v.contentSize !== undefined) out.contentSize = v.contentSize;
  if (v.capturedAt !== undefined) out.capturedAt = v.capturedAt;
  if (v.capturedByCertId !== undefined) out.capturedByCertId = v.capturedByCertId;
  if (v.caption !== undefined) out.caption = v.caption;
  return out;
}

function fromCanonical(c: unknown): OddjobzAttachmentV2 {
  if (typeof c !== 'object' || c === null) throw new Error('attachment.v2: payload not an object');
  const r = c as Record<string, unknown>;
  return {
    attachmentId: r.attachmentId as string,
    visitId: r.visitId as string | undefined,
    kind: r.kind as AttachmentKind | undefined,
    contentHash: r.contentHash as string | undefined,
    contentSize: r.contentSize as number | undefined,
    mimeType: r.mimeType as string,
    capturedAt: r.capturedAt as string | undefined,
    capturedByCertId: r.capturedByCertId as string | undefined,
    caption: r.caption as string | undefined,
    createdAt: r.createdAt as string,
    sourceBlobKey: r.sourceBlobKey as string,
    pageCount: (r.pageCount ?? null) as number | null,
    photoCount: (r.photoCount ?? null) as number | null,
    hasPhotos: r.hasPhotos as boolean,
  };
}

export const attachmentCellTypeV2: CellTypeDef<OddjobzAttachmentV2> = defineCellType({
  name: 'oddjobz.attachment.v2',
  identity: {
    whatPath: 'oddjobz.attachment',
    howSlug: 'capture',
    instPath: 'inst.evidence.site-artifact.v2',
  },
  linearity: 'LINEAR',
  toCanonical,
  fromCanonical,
  validate,
});

export function packAttachmentV2(value: OddjobzAttachmentV2): Uint8Array {
  return attachmentCellTypeV2.pack(value);
}

export function unpackAttachmentV2(bytes: Uint8Array): OddjobzAttachmentV2 {
  return attachmentCellTypeV2.unpack(bytes);
}

```
