---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/attachment-pipeline.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.148101+00:00
---

# runtime/legacy-ingest/src/__tests__/attachment-pipeline.test.ts

```ts
/**
 * D-RTC.5 — attachment-pipeline conformance tests.
 *
 * Reference: docs/prd/D-Reingest-Typed-Cells.md §Deliverables / D-RTC.5.
 *
 * Acceptance gate: PDF byte-identical round-trip; every image is
 * either extracted OR has_pictures=true+extraction_status=failed
 * recorded; parent job cell gets accurate has_pictures + picture_count.
 */

import { describe, test, expect } from 'bun:test';
import { createHash, randomBytes } from 'node:crypto';
import {
  runAttachmentPipeline,
  InMemoryAttachmentBlobStore,
  type AttachmentBlobStore,
} from '../attachment-pipeline';
import type { EmailMimePart } from '../extractor/attachment';
import { SPEC_ATTACHMENT } from '../cell-encoder';

const ZERO_OWNER = '00000000000000000000000000000000';
const PARENT = 'a'.repeat(64);

function sha256Hex(bytes: Uint8Array): string {
  const h = createHash('sha256');
  h.update(bytes);
  return h.digest('hex');
}

function makePdf(bytes: Uint8Array, filename: string | null = 'work-order.pdf'): EmailMimePart {
  return {
    contentType: 'application/pdf',
    bytes,
    filename,
    kind: 'pdf',
  };
}

function makeImage(
  bytes: Uint8Array,
  contentType = 'image/jpeg',
  filename: string | null = 'photo.jpg',
): EmailMimePart {
  return {
    contentType,
    bytes,
    filename,
    kind: 'image',
  };
}

/* ──────────────────────────────────────────────────────────────────────
 * Happy path
 * ────────────────────────────────────────────────────────────────────── */

describe('runAttachmentPipeline: PDF round-trip', () => {
  test('persists PDF bytes verbatim + builds Attachment cell request', async () => {
    const blobStore = new InMemoryAttachmentBlobStore();
    const pdfBytes = randomBytes(2048);
    const expectedSha = sha256Hex(pdfBytes);

    const result = await runAttachmentPipeline({
      attachments: [makePdf(pdfBytes)],
      parentJobCellId: PARENT,
      ownerIdHex: ZERO_OWNER,
      blobStore,
    });

    expect(result.requests).toHaveLength(1);
    const req = result.requests[0]!;
    expect(req.spec).toBe(SPEC_ATTACHMENT);
    expect(req.linearity).toBe('relevant');

    const payload = JSON.parse(req.payloadJson);
    expect(payload.mime_type).toBe('application/pdf');
    expect(payload.blob_sha256).toBe(expectedSha);
    expect(payload.parent_cell_id).toBe(PARENT);
    expect(payload.extraction_status).toBe('stored_verbatim');
    expect(payload.has_pictures).toBe(false);

    // Byte-identical round-trip from the blob store.
    const stored = blobStore.get(expectedSha);
    expect(stored).not.toBeNull();
    expect(stored!.length).toBe(pdfBytes.length);
    expect(sha256Hex(stored!)).toBe(expectedSha);

    expect(result.parentSummary.hasPictures).toBe(false);
    expect(result.parentSummary.pictureCount).toBe(0);
    expect(result.parentSummary.primaryPdfSha256).toBe(expectedSha);
  });

  test('30-PDF batch: every PDF survives byte-identical', async () => {
    const blobStore = new InMemoryAttachmentBlobStore();
    const pdfs: EmailMimePart[] = [];
    const shas: string[] = [];
    for (let i = 0; i < 30; i++) {
      const bytes = randomBytes(1024 + i * 7);
      pdfs.push(makePdf(bytes, `wo-${i}.pdf`));
      shas.push(sha256Hex(bytes));
    }
    const result = await runAttachmentPipeline({
      attachments: pdfs,
      parentJobCellId: PARENT,
      ownerIdHex: ZERO_OWNER,
      blobStore,
      opts: { maxAttachments: 32 },
    });
    expect(result.requests).toHaveLength(30);
    for (let i = 0; i < 30; i++) {
      const stored = blobStore.get(shas[i]!);
      expect(stored).not.toBeNull();
      expect(sha256Hex(stored!)).toBe(shas[i]);
    }
  });
});

describe('runAttachmentPipeline: image handling', () => {
  test('persists image + sets parent has_pictures + picture_count', async () => {
    const blobStore = new InMemoryAttachmentBlobStore();
    const imgBytes = randomBytes(1024);
    const expectedSha = sha256Hex(imgBytes);

    const result = await runAttachmentPipeline({
      attachments: [makeImage(imgBytes)],
      parentJobCellId: PARENT,
      ownerIdHex: ZERO_OWNER,
      blobStore,
    });

    expect(result.requests).toHaveLength(1);
    const payload = JSON.parse(result.requests[0]!.payloadJson);
    expect(payload.mime_type).toBe('image/jpeg');
    expect(payload.extraction_status).toBe('image_extracted');
    expect(payload.has_pictures).toBe(true);
    expect(payload.blob_sha256).toBe(expectedSha);

    expect(result.parentSummary.hasPictures).toBe(true);
    expect(result.parentSummary.pictureCount).toBe(1);
    expect(result.parentSummary.primaryPdfSha256).toBeNull();
  });

  test('mixed PDF + 3 images: parent picks up correct counts', async () => {
    const blobStore = new InMemoryAttachmentBlobStore();
    const result = await runAttachmentPipeline({
      attachments: [
        makePdf(randomBytes(512)),
        makeImage(randomBytes(256), 'image/jpeg'),
        makeImage(randomBytes(256), 'image/png'),
        makeImage(randomBytes(256), 'image/heic'),
      ],
      parentJobCellId: PARENT,
      ownerIdHex: ZERO_OWNER,
      blobStore,
    });
    expect(result.requests).toHaveLength(4);
    expect(result.parentSummary.hasPictures).toBe(true);
    expect(result.parentSummary.pictureCount).toBe(3);
    expect(result.parentSummary.primaryPdfSha256).not.toBeNull();
  });
});

/* ──────────────────────────────────────────────────────────────────────
 * Failure-mode posture (PRD: don't silently lose images)
 * ────────────────────────────────────────────────────────────────────── */

describe('runAttachmentPipeline: failure modes', () => {
  test('blob-store throws: status=failed + parent.hasPictures still true', async () => {
    const failing: AttachmentBlobStore = {
      async put() {
        throw new Error('disk full');
      },
    };
    const imgBytes = randomBytes(256);
    const expectedSha = sha256Hex(imgBytes);

    const result = await runAttachmentPipeline({
      attachments: [makeImage(imgBytes)],
      parentJobCellId: PARENT,
      ownerIdHex: ZERO_OWNER,
      blobStore: failing,
    });

    expect(result.requests).toHaveLength(1);
    const payload = JSON.parse(result.requests[0]!.payloadJson);
    expect(payload.extraction_status).toBe('failed');
    // Even on failure, the sha was computed so the operator can retry
    // and the cell carries a forensic anchor.
    expect(payload.blob_sha256).toBe(expectedSha);
    expect(payload.has_pictures).toBe(true);

    // The keystone PRD invariant: parent still knows pictures EXISTED.
    expect(result.parentSummary.hasPictures).toBe(true);
    expect(result.parentSummary.pictureCount).toBe(1);
  });

  test('oversized attachment: status=failed, no put attempted', async () => {
    let putCalls = 0;
    const blobStore: AttachmentBlobStore = {
      async put(bytes) {
        putCalls += 1;
        return sha256Hex(bytes);
      },
    };
    const huge = randomBytes(2 * 1024 * 1024);
    const result = await runAttachmentPipeline({
      attachments: [makePdf(huge)],
      parentJobCellId: PARENT,
      ownerIdHex: ZERO_OWNER,
      blobStore,
      opts: { maxBytesPerAttachment: 1024 * 1024 },
    });
    expect(result.requests).toHaveLength(1);
    expect(putCalls).toBe(0);
    const payload = JSON.parse(result.requests[0]!.payloadJson);
    expect(payload.extraction_status).toBe('failed');
  });

  test('empty-byte attachment is dropped silently', async () => {
    const blobStore = new InMemoryAttachmentBlobStore();
    const result = await runAttachmentPipeline({
      attachments: [makePdf(new Uint8Array(0))],
      parentJobCellId: PARENT,
      ownerIdHex: ZERO_OWNER,
      blobStore,
    });
    expect(result.requests).toHaveLength(0);
    expect(blobStore.size()).toBe(0);
  });

  test('non-pdf, non-image MIME parts are skipped', async () => {
    const blobStore = new InMemoryAttachmentBlobStore();
    const result = await runAttachmentPipeline({
      attachments: [
        { contentType: 'application/zip', bytes: randomBytes(64), filename: 'x.zip', kind: 'other' as never },
        { contentType: 'text/plain', bytes: randomBytes(64), filename: null, kind: 'text' as never },
      ],
      parentJobCellId: PARENT,
      ownerIdHex: ZERO_OWNER,
      blobStore,
    });
    expect(result.requests).toHaveLength(0);
  });
});

/* ──────────────────────────────────────────────────────────────────────
 * Idempotence + dedupe via SHA-256 content addressing
 * ────────────────────────────────────────────────────────────────────── */

describe('runAttachmentPipeline: SHA-256 dedupe', () => {
  test('identical bytes across two runs reuse the same blob', async () => {
    const blobStore = new InMemoryAttachmentBlobStore();
    const pdfBytes = randomBytes(512);
    await runAttachmentPipeline({
      attachments: [makePdf(pdfBytes)],
      parentJobCellId: PARENT,
      ownerIdHex: ZERO_OWNER,
      blobStore,
    });
    await runAttachmentPipeline({
      attachments: [makePdf(pdfBytes)],
      parentJobCellId: 'b'.repeat(64),
      ownerIdHex: ZERO_OWNER,
      blobStore,
    });
    // Same bytes → same sha → one blob.
    expect(blobStore.size()).toBe(1);
  });

  test('same bytes inside one batch dedupe in the blob store', async () => {
    const blobStore = new InMemoryAttachmentBlobStore();
    const pdfBytes = randomBytes(512);
    const result = await runAttachmentPipeline({
      attachments: [makePdf(pdfBytes, 'a.pdf'), makePdf(pdfBytes, 'b.pdf')],
      parentJobCellId: PARENT,
      ownerIdHex: ZERO_OWNER,
      blobStore,
    });
    // Two cells are emitted (each filename gets its own Attachment),
    // but they reference the same blob.
    expect(result.requests).toHaveLength(2);
    expect(blobStore.size()).toBe(1);
    const p0 = JSON.parse(result.requests[0]!.payloadJson);
    const p1 = JSON.parse(result.requests[1]!.payloadJson);
    expect(p0.blob_sha256).toBe(p1.blob_sha256);
  });
});

/* ──────────────────────────────────────────────────────────────────────
 * maxAttachments cap
 * ────────────────────────────────────────────────────────────────────── */

describe('runAttachmentPipeline: maxAttachments', () => {
  test('caps the number of attachments processed', async () => {
    const blobStore = new InMemoryAttachmentBlobStore();
    const atts: EmailMimePart[] = [];
    for (let i = 0; i < 20; i++) atts.push(makePdf(randomBytes(128)));
    const result = await runAttachmentPipeline({
      attachments: atts,
      parentJobCellId: PARENT,
      ownerIdHex: ZERO_OWNER,
      blobStore,
      opts: { maxAttachments: 5 },
    });
    expect(result.requests).toHaveLength(5);
  });
});

```
