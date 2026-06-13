---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/attachment-pipeline.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.129573+00:00
---

# runtime/legacy-ingest/src/attachment-pipeline.ts

```ts
/**
 * D-RTC.5 — Attachment pipeline.
 *
 * Reference: docs/prd/D-Reingest-Typed-Cells.md §Deliverables / D-RTC.5.
 *
 * Bridge between the existing MIME-multipart parser
 * (`extractor/attachment.ts::parseEmailMimeParts`) and the cell encoder
 * (`cell-encoder.ts::encodeAttachment`). For each attachment in an email:
 *
 *   1. Persist the verbatim bytes through a content-addressed blob store
 *      (keyed by SHA-256 of the bytes).
 *   2. Build an AttachmentCellPayload + EntityEncodeRequest that links
 *      to the parent job cell.
 *   3. Aggregate per-email: did ANY image attachment exist (regardless
 *      of extraction success)? How many distinct images?
 *
 * The aggregation is what feeds the parent job cell's `has_pictures`
 * and `picture_count` fields per the PRD — even when image extraction
 * fails, the operator gets to know pictures EXISTED via
 * `has_pictures=true` + `extraction_status=failed`.
 */

import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, renameSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import type { EmailMimePart } from './extractor/attachment';

/**
 * Canonical SPEC_ATTACHMENT type hash (sha256 of the attachment
 * type-path triplet) — the value the brain mints for attachment cells
 * (verified against the live oddjobz attachments.jsonl). Emitted on
 * every attachment payload so the brain's v2 decode block (gated on a
 * 64-hex cellId + typeHash) parses `jobRef`.
 */
const ATTACHMENT_TYPE_HASH =
  'fb1a23a8172cd686deaa6acdee01a9726ea29dfc3c075b7ebe9f661bddb71b37';
import {
  encodeAttachment,
  type AttachmentCellPayload,
  type EntityEncodeRequest,
} from './cell-encoder';

/* ──────────────────────────────────────────────────────────────────────
 * Public types
 * ────────────────────────────────────────────────────────────────────── */

/**
 * Content-addressed blob store seam. The reingest worker injects an
 * implementation (real implementation wraps LegacyBlobStore + a
 * sha256-keyed namespace; tests use the in-memory map below).
 */
export interface AttachmentBlobStore {
  /**
   * Persist `bytes` verbatim and return the lowercase-hex sha256.
   * Idempotent — repeat calls with identical bytes return the same
   * sha256 without rewriting on disk.
   */
  put(bytes: Uint8Array, mimeType: string): Promise<string>;
}

/** Per-email aggregation returned alongside the attachment requests. */
export interface AttachmentParentSummary {
  /**
   * True if at least one `image/*` attachment was detected — regardless
   * of whether the bytes were persisted successfully. Mirrored onto the
   * parent job cell so the operator at minimum knows pictures EXISTED.
   */
  readonly hasPictures: boolean;
  /** Number of distinct `image/*` attachments. */
  readonly pictureCount: number;
  /** Sha256 hex of the FIRST `application/pdf` attachment, if any. */
  readonly primaryPdfSha256: string | null;
}

export interface AttachmentPipelineResult {
  readonly requests: readonly EntityEncodeRequest[];
  readonly parentSummary: AttachmentParentSummary;
}

export interface AttachmentPipelineOpts {
  readonly maxAttachments?: number;
  readonly maxBytesPerAttachment?: number;
}

/* ──────────────────────────────────────────────────────────────────────
 * Public API
 * ────────────────────────────────────────────────────────────────────── */

/**
 * Run the attachment pipeline against a parsed MIME-parts result. The
 * caller provides the parent job's cell id; this function returns the
 * encode-requests for the attachment cells plus the parent-summary
 * metadata to propagate onto the parent job cell.
 *
 * Errors during blob persistence DO NOT throw — the attachment is
 * recorded with `extraction_status='failed'` + the parent still gets
 * `has_pictures=true` for any image. This matches the PRD's "don't
 * silently lose images" posture.
 */
export async function runAttachmentPipeline(args: {
  readonly attachments: readonly EmailMimePart[];
  readonly parentJobCellId: string;
  readonly ownerIdHex: string;
  readonly blobStore: AttachmentBlobStore;
  readonly opts?: AttachmentPipelineOpts;
}): Promise<AttachmentPipelineResult> {
  const limit = args.opts?.maxAttachments ?? 16;
  const maxBytes = args.opts?.maxBytesPerAttachment ?? 25 * 1024 * 1024;

  const requests: EntityEncodeRequest[] = [];
  let pictureCount = 0;
  let primaryPdfSha256: string | null = null;

  for (const att of args.attachments.slice(0, limit)) {
    if (att.kind !== 'pdf' && att.kind !== 'image') continue;
    if (att.bytes.length === 0) continue;

    if (att.kind === 'image') pictureCount += 1;

    // Cap defensively. Oversized attachments still emit a failed
    // record so the operator sees them; we just don't try to
    // persist the bytes.
    const tooLarge = att.bytes.length > maxBytes;
    let sha256: string | null = null;
    let status: AttachmentCellPayload['extraction_status'];

    if (tooLarge) {
      sha256 = computeSha256Hex(att.bytes);
      status = 'failed';
    } else {
      try {
        sha256 = await args.blobStore.put(att.bytes, att.contentType);
        status =
          att.kind === 'pdf' ? 'stored_verbatim'
          : 'image_extracted';
      } catch {
        // Persistence failed but the bytes still hashed cleanly — we
        // can record the sha so the operator can retry later.
        sha256 = computeSha256Hex(att.bytes);
        status = 'failed';
      }
    }

    if (att.kind === 'pdf' && primaryPdfSha256 === null && status !== 'failed') {
      primaryPdfSha256 = sha256;
    }

    // sha256 is always computed (success, too-large, or persist-fail
    // path) — never null here; coalesce defensively for the type.
    const sha = sha256 ?? computeSha256Hex(att.bytes);
    const payload: AttachmentCellPayload = {
      // id == content_hash == sha == the `<sha>.bin` filename the
      // brain's blob endpoint serves. Without `id` the brain dropped
      // every attachment cell — this is the fix that makes job-sheet
      // PDFs/photos reachable.
      id: sha,
      // cellId + typeHash gate the brain's v2 decode block that parses
      // jobRef — without BOTH, jobRef is dropped and the job→
      // attachment link is lost. cellId = the sha (deterministic
      // 64-hex); typeHash = the canonical SPEC_ATTACHMENT type hash.
      cellId: sha,
      typeHash: ATTACHMENT_TYPE_HASH,
      content_hash: sha,
      content_size: att.bytes.length,
      created_at: new Date().toISOString(),
      jobRef: args.parentJobCellId,
      mime_type: att.contentType,
      filename: att.filename,
      blob_sha256: sha,
      parent_cell_id: args.parentJobCellId,
      extraction_status: status,
      // hasPictures on the Attachment cell itself: true for any image
      // (success OR failed), false for PDFs. Matches the index-speed
      // mirror per cell-schema.json.
      has_pictures: att.kind === 'image',
      state: 'captured',
    };
    requests.push(encodeAttachment(payload, args.ownerIdHex));
  }

  return {
    requests,
    parentSummary: {
      hasPictures: pictureCount > 0,
      pictureCount,
      primaryPdfSha256,
    },
  };
}

/* ──────────────────────────────────────────────────────────────────────
 * Helpers
 * ────────────────────────────────────────────────────────────────────── */

function computeSha256Hex(bytes: Uint8Array): string {
  const h = createHash('sha256');
  h.update(bytes);
  return h.digest('hex');
}

/* ──────────────────────────────────────────────────────────────────────
 * In-memory AttachmentBlobStore (tests + dry-run reingest)
 * ────────────────────────────────────────────────────────────────────── */

/**
 * Trivial map-backed implementation. The reingest worker uses this in
 * `--dry-run` mode and tests use it everywhere. The production wiring
 * extends LegacyBlobStore with a sha256-keyed namespace; that's
 * separate from D-RTC.5's TS-side scope.
 */
export class InMemoryAttachmentBlobStore implements AttachmentBlobStore {
  private readonly map = new Map<string, Uint8Array>();

  async put(bytes: Uint8Array, _mimeType: string): Promise<string> {
    const sha = computeSha256Hex(bytes);
    if (!this.map.has(sha)) {
      // Copy so external mutation of the input doesn't corrupt our store.
      this.map.set(sha, new Uint8Array(bytes));
    }
    return sha;
  }

  size(): number {
    return this.map.size;
  }

  get(sha256: string): Uint8Array | null {
    return this.map.get(sha256) ?? null;
  }
}

/**
 * Disk-backed content-addressed blob store. Writes `<dir>/<sha256>.bin`
 * — byte-for-byte the layout the brain's
 * `attachment_blobs_fs.BlobStore` reads from
 * (`<data_dir>/oddjobz/blobs/<sha>.bin`), so after a re-mint the
 * staging dir rsyncs straight into the brain's blob dir and
 * `GET /api/v1/attachments/<id>/blob` serves it. Idempotent: identical
 * bytes → same sha → skip rewrite. Atomic temp-then-rename.
 *
 * This replaces InMemoryAttachmentBlobStore in the legacy-cli
 * bootstrap — the in-memory one discarded every byte on process exit,
 * which is why job-sheet PDFs/photos were never inspectable.
 */
export class FsAttachmentBlobStore implements AttachmentBlobStore {
  constructor(private readonly dir: string) {
    mkdirSync(dir, { recursive: true });
  }

  async put(bytes: Uint8Array, _mimeType: string): Promise<string> {
    const sha = computeSha256Hex(bytes);
    const final = join(this.dir, `${sha}.bin`);
    if (existsSync(final)) return sha; // content-addressed → already stored
    const tmp = `${final}.tmp-${process.pid}-${Date.now()}`;
    writeFileSync(tmp, bytes, { mode: 0o644 });
    renameSync(tmp, final);
    return sha;
  }
}

```
