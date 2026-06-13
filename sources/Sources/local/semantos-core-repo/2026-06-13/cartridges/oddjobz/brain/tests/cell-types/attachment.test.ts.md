---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/tests/cell-types/attachment.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.483301+00:00
---

# cartridges/oddjobz/brain/tests/cell-types/attachment.test.ts

```ts
/**
 * D-O5m.followup-8 substrate — attachment cell-type round-trip + validator
 * tests.  Mirrors the registry-driven coverage in
 * `src/__tests__/cell-types.test.ts` but pinned at the cell-type level so
 * the substrate gets a dedicated focused test surface independent of the
 * cross-cell registry sweep.
 *
 * Asserts:
 *   1. Round-trip identity: pack(unpack(pack(v))) === pack(v) byte-for-
 *      byte for every committed conformance vector.
 *   2. Registry shape: attachment cell type carries the canonical name,
 *      LINEAR linearity, and is registered under both name and typeHash.
 *   3. Validators reject bad inputs (UUID, hex string, kind, mime, size,
 *      caption length, date format).
 */

import { describe, expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  attachmentCellType,
  ATTACHMENT_KINDS,
  cellTypeByName,
  cellTypeByHashHex,
  packAttachment,
  unpackAttachment,
  WireLinearity,
  type OddjobzAttachment,
} from '../../src/cell-types/index.js';

const HERE = dirname(fileURLToPath(import.meta.url));
const VECTOR_PATH = resolve(HERE, '..', 'vectors', 'oddjobz_attachment.json');

interface Vector {
  name: string;
  input: OddjobzAttachment;
  packed: string;
  typeHash: string;
  linearity: string;
}

function bytesToHex(b: Uint8Array): string {
  let out = '';
  for (let i = 0; i < b.length; i++) {
    out += (b[i] as number).toString(16).padStart(2, '0');
  }
  return out;
}

function hexToBytes(hex: string): Uint8Array {
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) {
    out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }
  return out;
}

function loadVectors(): Vector[] {
  return JSON.parse(readFileSync(VECTOR_PATH, 'utf-8')) as Vector[];
}

const sample: OddjobzAttachment = {
  attachmentId: '4a4a4a4a-4a4a-4a4a-8a4a-4a4a4a4a4a4a',
  visitId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  kind: 'photo',
  contentHash: 'a'.repeat(64),
  contentSize: 2_457_600,
  mimeType: 'image/heic',
  capturedAt: '2026-05-15T14:30:00Z',
  capturedByCertId: '20202020202040208020202020202020',
  createdAt: '2026-05-15T14:30:01Z',
};

describe('oddjobz.attachment.v1 — registry shape', () => {
  test('canonical name is `oddjobz.attachment.v1`', () => {
    expect(attachmentCellType.name).toBe('oddjobz.attachment.v1');
  });

  test('linearity is LINEAR (wire code 1)', () => {
    expect(attachmentCellType.linearity).toBe('LINEAR');
    expect(attachmentCellType.wireLinearity).toBe(WireLinearity.LINEAR);
  });

  test('registered under both name and typeHash', () => {
    expect(cellTypeByName['oddjobz.attachment.v1']).toBe(attachmentCellType);
    expect(cellTypeByHashHex[attachmentCellType.typeHashHex]).toBe(attachmentCellType);
  });

  test('typeHash is 32 bytes / 64 hex chars', () => {
    expect(attachmentCellType.typeHash.length).toBe(32);
    expect(attachmentCellType.typeHashHex.length).toBe(64);
  });

  test('ATTACHMENT_KINDS exports the four canonical kinds', () => {
    expect([...ATTACHMENT_KINDS]).toEqual([
      'photo',
      'voice_memo',
      'gps_pin',
      'file_other',
    ]);
  });
});

describe('oddjobz.attachment.v1 — round-trip identity', () => {
  test('packs → unpacks → re-packs byte-identical', () => {
    const packed1 = packAttachment(sample);
    const unpacked = unpackAttachment(packed1);
    const packed2 = packAttachment(unpacked);
    expect(bytesToHex(packed2)).toBe(bytesToHex(packed1));
  });

  test('caption-bearing sample also round-trips', () => {
    const v: OddjobzAttachment = { ...sample, caption: 'Customer pointed out the asbestos eaves.' };
    const packed1 = packAttachment(v);
    const unpacked = unpackAttachment(packed1);
    expect(unpacked.caption).toBe(v.caption);
    const packed2 = packAttachment(unpacked);
    expect(bytesToHex(packed2)).toBe(bytesToHex(packed1));
  });

  test('every committed conformance vector round-trips byte-identical', () => {
    const vectors = loadVectors();
    expect(vectors.length).toBeGreaterThanOrEqual(3);

    for (const vec of vectors) {
      // typeHash + linearity match the def.
      expect(vec.typeHash).toBe(attachmentCellType.typeHashHex);
      expect(vec.linearity).toBe('LINEAR');

      // Re-pack the input and assert hex equality with the committed bytes.
      const repacked = packAttachment(vec.input);
      expect(bytesToHex(repacked)).toBe(vec.packed);

      // Unpack the committed bytes and re-pack — byte-identical.
      const bytes = hexToBytes(vec.packed);
      const unpacked = unpackAttachment(bytes);
      const repacked2 = packAttachment(unpacked);
      expect(bytesToHex(repacked2)).toBe(vec.packed);
    }
  });

  test('vector file covers all four attachment kinds (photo / voice_memo / gps_pin)', () => {
    const vectors = loadVectors();
    const kinds = new Set(vectors.map((v) => v.input.kind));
    expect(kinds.has('photo')).toBe(true);
    expect(kinds.has('voice_memo')).toBe(true);
    expect(kinds.has('gps_pin')).toBe(true);
  });
});

describe('oddjobz.attachment.v1 — validators reject bad input', () => {
  test('rejects non-UUID attachmentId', () => {
    expect(() => packAttachment({ ...sample, attachmentId: 'not-a-uuid' })).toThrow(/attachmentId/);
  });

  test('rejects non-UUID visitId', () => {
    expect(() => packAttachment({ ...sample, visitId: 'not-a-uuid' })).toThrow(/visitId/);
  });

  test('rejects unknown kind', () => {
    expect(() =>
      packAttachment({ ...sample, kind: 'video' as unknown as OddjobzAttachment['kind'] }),
    ).toThrow(/kind/);
  });

  test('rejects content_hash with wrong length', () => {
    expect(() => packAttachment({ ...sample, contentHash: 'a'.repeat(63) })).toThrow(/contentHash/);
    expect(() => packAttachment({ ...sample, contentHash: 'a'.repeat(65) })).toThrow(/contentHash/);
  });

  test('rejects content_hash with non-hex characters', () => {
    expect(() => packAttachment({ ...sample, contentHash: 'g'.repeat(64) })).toThrow(/contentHash/);
  });

  test('rejects negative or non-integer contentSize', () => {
    expect(() => packAttachment({ ...sample, contentSize: -1 })).toThrow(/contentSize/);
    expect(() => packAttachment({ ...sample, contentSize: 1.5 })).toThrow(/contentSize/);
  });

  test('rejects empty mimeType', () => {
    expect(() => packAttachment({ ...sample, mimeType: '' })).toThrow(/mimeType/);
  });

  test('rejects malformed capturedAt', () => {
    expect(() => packAttachment({ ...sample, capturedAt: '2026-05-15' })).toThrow(/capturedAt/);
  });

  test('rejects capturedByCertId of wrong length / non-hex', () => {
    expect(() => packAttachment({ ...sample, capturedByCertId: '00'.repeat(15) })).toThrow(
      /capturedByCertId/,
    );
    expect(() => packAttachment({ ...sample, capturedByCertId: 'g'.repeat(32) })).toThrow(
      /capturedByCertId/,
    );
  });

  test('rejects caption longer than 500 chars', () => {
    expect(() => packAttachment({ ...sample, caption: 'x'.repeat(501) })).toThrow(/caption/);
  });

  test('accepts caption at exactly 500 chars', () => {
    expect(() => packAttachment({ ...sample, caption: 'x'.repeat(500) })).not.toThrow();
  });
});

```
