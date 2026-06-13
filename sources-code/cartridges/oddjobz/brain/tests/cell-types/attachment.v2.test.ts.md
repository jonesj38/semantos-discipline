---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/tests/cell-types/attachment.v2.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.483936+00:00
---

# cartridges/oddjobz/brain/tests/cell-types/attachment.v2.test.ts

```ts
/**
 * D-DOG.1.0c Phase 1 — `oddjobz.attachment.v2` schema tests.
 */

import { describe, expect, test } from 'bun:test';
import {
  attachmentCellType,
  attachmentCellTypeV2,
  cellTypeByName,
  cellTypeByHashHex,
  WireLinearity,
  packAttachmentV2,
  unpackAttachmentV2,
  type OddjobzAttachmentV2,
  type OddjobzAttachment,
} from '../../src/cell-types/index.js';

function bytesToHex(b: Uint8Array): string {
  let out = '';
  for (let i = 0; i < b.length; i++) out += (b[i] as number).toString(16).padStart(2, '0');
  return out;
}

const sourcePdfV2: OddjobzAttachmentV2 = {
  attachmentId: 'aaaa1111-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  mimeType: 'application/pdf',
  createdAt: '2026-05-01T10:00:00Z',
  // v2 graph fields
  sourceBlobKey: 'blob:legacy-ingest:abc123',
  pageCount: 3,
  photoCount: 4,
  hasPhotos: true,
};

const visitPhotoV2: OddjobzAttachmentV2 = {
  attachmentId: 'bbbb1111-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  visitId: 'cccc1111-cccc-4ccc-8ccc-cccccccccccc',
  kind: 'photo',
  contentHash: 'a'.repeat(64),
  contentSize: 2_457_600,
  mimeType: 'image/heic',
  capturedAt: '2026-05-15T14:30:00Z',
  capturedByCertId: '00112233445566778899aabbccddeeff',
  createdAt: '2026-05-15T14:30:01Z',
  // v2 graph fields
  sourceBlobKey: 'blob:device-uploads:xyz789',
  pageCount: null,
  photoCount: null,
  hasPhotos: false,
};

const v1Sample: OddjobzAttachment = {
  attachmentId: 'dddd1111-dddd-4ddd-8ddd-dddddddddddd',
  visitId: 'eeee1111-eeee-4eee-8eee-eeeeeeeeeeee',
  kind: 'photo',
  contentHash: 'b'.repeat(64),
  contentSize: 1024,
  mimeType: 'image/jpeg',
  capturedAt: '2026-05-15T14:30:00Z',
  capturedByCertId: '00112233445566778899aabbccddeeff',
  createdAt: '2026-05-15T14:30:01Z',
};

describe('oddjobz.attachment.v2 — registry shape', () => {
  test('canonical name is `oddjobz.attachment.v2`', () => {
    expect(attachmentCellTypeV2.name).toBe('oddjobz.attachment.v2');
  });

  test('linearity is LINEAR (matches v1)', () => {
    expect(attachmentCellTypeV2.linearity).toBe('LINEAR');
    expect(attachmentCellTypeV2.wireLinearity).toBe(WireLinearity.LINEAR);
  });

  test('registered under both name and typeHash (and v1 still resolves)', () => {
    expect(cellTypeByName['oddjobz.attachment.v2']).toBe(attachmentCellTypeV2);
    expect(cellTypeByName['oddjobz.attachment.v1']).toBe(attachmentCellType);
    expect(cellTypeByHashHex[attachmentCellTypeV2.typeHashHex]).toBe(attachmentCellTypeV2);
    expect(cellTypeByHashHex[attachmentCellType.typeHashHex]).toBe(attachmentCellType);
  });

  test('v1 and v2 typeHashes are distinct', () => {
    expect(attachmentCellTypeV2.typeHashHex).not.toBe(attachmentCellType.typeHashHex);
  });
});

describe('oddjobz.attachment.v1 — backward compat', () => {
  test('v1 payload still validates without v2 fields', () => {
    expect(() => attachmentCellType.pack(v1Sample)).not.toThrow();
  });
});

describe('oddjobz.attachment.v2 — happy path', () => {
  test('source-PDF attachment round-trips byte-identical', () => {
    const a = packAttachmentV2(sourcePdfV2);
    const u = unpackAttachmentV2(a);
    const b = packAttachmentV2(u);
    expect(bytesToHex(b)).toBe(bytesToHex(a));
  });

  test('visit-side photo attachment round-trips byte-identical', () => {
    const a = packAttachmentV2(visitPhotoV2);
    const u = unpackAttachmentV2(a);
    const b = packAttachmentV2(u);
    expect(bytesToHex(b)).toBe(bytesToHex(a));
  });

  test('hasPhotos=true requires photoCount > 0', () => {
    const v: OddjobzAttachmentV2 = {
      ...sourcePdfV2,
      photoCount: 1,
      hasPhotos: true,
    };
    expect(() => packAttachmentV2(v)).not.toThrow();
  });

  test('hasPhotos=false with photoCount=0 validates', () => {
    const v: OddjobzAttachmentV2 = {
      ...sourcePdfV2,
      photoCount: 0,
      hasPhotos: false,
    };
    expect(() => packAttachmentV2(v)).not.toThrow();
  });
});

describe('oddjobz.attachment.v2 — validators reject bad input', () => {
  test('rejects missing sourceBlobKey', () => {
    const bad = { ...sourcePdfV2, sourceBlobKey: '' };
    expect(() => packAttachmentV2(bad as OddjobzAttachmentV2)).toThrow(/sourceBlobKey/);
  });

  test('rejects missing mimeType', () => {
    const bad = { ...sourcePdfV2, mimeType: '' };
    expect(() => packAttachmentV2(bad as OddjobzAttachmentV2)).toThrow(/mimeType/);
  });

  test('rejects negative pageCount', () => {
    const bad = { ...sourcePdfV2, pageCount: -1 };
    expect(() => packAttachmentV2(bad as OddjobzAttachmentV2)).toThrow(/pageCount/);
  });

  test('rejects non-integer photoCount', () => {
    const bad = { ...sourcePdfV2, photoCount: 1.5 };
    expect(() => packAttachmentV2(bad as OddjobzAttachmentV2)).toThrow(/photoCount/);
  });

  test('rejects hasPhotos=true with photoCount=0', () => {
    const bad = { ...sourcePdfV2, photoCount: 0, hasPhotos: true };
    expect(() => packAttachmentV2(bad as OddjobzAttachmentV2)).toThrow(/hasPhotos/);
  });

  test('rejects hasPhotos=true with photoCount=null', () => {
    const bad = { ...sourcePdfV2, photoCount: null, hasPhotos: true };
    expect(() => packAttachmentV2(bad as OddjobzAttachmentV2)).toThrow(/hasPhotos/);
  });

  test('rejects hasPhotos=false with photoCount > 0', () => {
    const bad = { ...sourcePdfV2, photoCount: 5, hasPhotos: false };
    expect(() => packAttachmentV2(bad as OddjobzAttachmentV2)).toThrow(/hasPhotos/);
  });

  test('when visitId is present, kind is required (v1 visit-attachment shape)', () => {
    const bad = { ...visitPhotoV2, kind: undefined as never };
    expect(() => packAttachmentV2(bad as OddjobzAttachmentV2)).toThrow(/kind/);
  });

  test('when visitId is present, contentHash is required', () => {
    const bad = { ...visitPhotoV2, contentHash: undefined as never };
    expect(() => packAttachmentV2(bad as OddjobzAttachmentV2)).toThrow(/contentHash/);
  });

  test('when visitId is present, capturedByCertId is required', () => {
    const bad = { ...visitPhotoV2, capturedByCertId: undefined as never };
    expect(() => packAttachmentV2(bad as OddjobzAttachmentV2)).toThrow(/capturedByCertId/);
  });

  test('still rejects v1-style violations (bad attachmentId)', () => {
    const bad = { ...sourcePdfV2, attachmentId: 'not-uuid' };
    expect(() => packAttachmentV2(bad as OddjobzAttachmentV2)).toThrow(/attachmentId/);
  });

  test('still rejects v1-style violations (caption > 500 chars)', () => {
    const bad = { ...sourcePdfV2, caption: 'x'.repeat(501) };
    expect(() => packAttachmentV2(bad as OddjobzAttachmentV2)).toThrow(/caption/);
  });
});

```
