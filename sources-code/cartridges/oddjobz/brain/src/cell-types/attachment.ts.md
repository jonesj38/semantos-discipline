---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/cell-types/attachment.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.501182+00:00
---

# cartridges/oddjobz/brain/src/cell-types/attachment.ts

```ts
/**
 * `oddjobz.attachment.v1` — LINEAR cell.
 *
 * D-O5m.followup-8 substrate — the metadata cell for a binary
 * artifact captured at a Visit (photo, voice memo, GPS pin, file).
 * Binary blob upload + mobile camera capture ship in the next PR;
 * this PR ships only the cell-type substrate + read-only handler so
 * the brain knows about the shape before the phone starts producing
 * signed cells.
 *
 * Per §O2 the cell is LINEAR: an Attachment is created once and never
 * mutated.  Deletion (out of scope for the read-only substrate PR)
 * supersedes by minting a tombstone successor.  Attachments are
 * AFFINE-ish at the operator-altitude (write-once, no FSM, never
 * transition) but ride the LINEAR wire shape so they sit alongside
 * Visit / Job / Quote / Invoice cells in the cell-DAG without a
 * special case.
 *
 * Field shape derived from the §O5m mobile-capture brief:
 *   • visitId — REQUIRED FK to the parent Visit; an Attachment
 *     without a Visit is meaningless at the operator-altitude.
 *   • kind — `photo | voice_memo | gps_pin | file_other`; surfaces
 *     the rendering mode the helms pick (image preview, audio
 *     player, map dot, file icon).
 *   • contentHash — sha256 hex of the binary blob; the next PR
 *     uploads the blob keyed by this hash, so the metadata cell can
 *     be signed before the blob has propagated.
 *   • contentSize — bytes; non-negative integer.  Helps the helm
 *     decide whether to fetch inline vs. lazy-load.
 *   • mimeType — best-effort; defaults to
 *     `application/octet-stream` for `file_other`.
 *   • capturedAt — ISO-8601; from the device clock at capture time.
 *   • capturedByCertId — 32 hex chars (16 bytes) of the device
 *     child cert that signed the cell.  Lets the helm group
 *     attachments by device for an at-a-glance audit view.
 *   • caption — optional operator note (≤ 500 chars).
 *   • createdAt — ISO-8601; server-stamped on receipt.
 */

import { defineCellType, type CellTypeDef } from './cell-type.js';
import {
  assertUuid,
  assertNonEmptyString,
  assertOptionalString,
  assertEnum,
  assertNonNegativeInt,
  assertIsoDateString,
} from './validators.js';

export const ATTACHMENT_KINDS = [
  'photo',
  'voice_memo',
  'gps_pin',
  'file_other',
] as const;
export type AttachmentKind = (typeof ATTACHMENT_KINDS)[number];

export interface OddjobzAttachment {
  /** Stable attachment identifier (UUID v4). */
  readonly attachmentId: string;
  /** Parent Visit (UUID v4) — REQUIRED. */
  readonly visitId: string;
  /** What kind of artifact this metadata describes. */
  readonly kind: AttachmentKind;
  /** sha256 hex of the binary blob — 64 lowercase hex chars. */
  readonly contentHash: string;
  /** Blob size in bytes; non-negative integer. */
  readonly contentSize: number;
  /** MIME type of the blob (e.g. `image/heic`, `audio/m4a`). */
  readonly mimeType: string;
  /** Device-clock capture timestamp (ISO-8601). */
  readonly capturedAt: string;
  /** Device child-cert id that signed the cell — 32 lowercase hex. */
  readonly capturedByCertId: string;
  /** Optional operator caption (≤ 500 chars). */
  readonly caption?: string;
  /** Server-stamped receipt timestamp (ISO-8601). */
  readonly createdAt: string;
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

function validate(v: OddjobzAttachment): void {
  assertUuid('attachmentId', v.attachmentId);
  assertUuid('visitId', v.visitId);
  assertEnum('kind', v.kind, ATTACHMENT_KINDS);
  assertHexString('contentHash', v.contentHash, CONTENT_HASH_LEN);
  assertNonNegativeInt('contentSize', v.contentSize);
  assertNonEmptyString('mimeType', v.mimeType);
  assertIsoDateString('capturedAt', v.capturedAt);
  assertHexString('capturedByCertId', v.capturedByCertId, CERT_ID_LEN);
  assertOptionalString('caption', v.caption);
  if (v.caption !== undefined && v.caption.length > MAX_CAPTION_LEN) {
    throw new Error(`field caption: exceeds ${MAX_CAPTION_LEN} chars`);
  }
  assertIsoDateString('createdAt', v.createdAt);
}

function toCanonical(v: OddjobzAttachment): Record<string, unknown> {
  const out: Record<string, unknown> = {
    attachmentId: v.attachmentId,
    visitId: v.visitId,
    kind: v.kind,
    contentHash: v.contentHash,
    contentSize: v.contentSize,
    mimeType: v.mimeType,
    capturedAt: v.capturedAt,
    capturedByCertId: v.capturedByCertId,
    createdAt: v.createdAt,
  };
  if (v.caption !== undefined) out.caption = v.caption;
  return out;
}

function fromCanonical(c: unknown): OddjobzAttachment {
  if (typeof c !== 'object' || c === null) throw new Error('attachment: payload not an object');
  const r = c as Record<string, unknown>;
  return {
    attachmentId: r.attachmentId as string,
    visitId: r.visitId as string,
    kind: r.kind as AttachmentKind,
    contentHash: r.contentHash as string,
    contentSize: r.contentSize as number,
    mimeType: r.mimeType as string,
    capturedAt: r.capturedAt as string,
    capturedByCertId: r.capturedByCertId as string,
    caption: r.caption as string | undefined,
    createdAt: r.createdAt as string,
  };
}

export const attachmentCellType: CellTypeDef<OddjobzAttachment> = defineCellType({
  name: 'oddjobz.attachment.v1',
  identity: {
    whatPath: 'oddjobz.attachment',
    howSlug: 'capture',
    instPath: 'inst.evidence.site-artifact',
  },
  linearity: 'LINEAR',
  toCanonical,
  fromCanonical,
  validate,
});

/**
 * Pack helper — wraps the cellType.pack so call sites that prefer a
 * named function over reaching through `.pack` (e.g. tests, future
 * adapters) have a stable identifier to import.  Mirrors the shape
 * `core/cell-ops` consumers expect from typed cell-type modules.
 */
export function packAttachment(value: OddjobzAttachment): Uint8Array {
  return attachmentCellType.pack(value);
}

/** Inverse of {@link packAttachment}. */
export function unpackAttachment(bytes: Uint8Array): OddjobzAttachment {
  return attachmentCellType.unpack(bytes);
}

```
