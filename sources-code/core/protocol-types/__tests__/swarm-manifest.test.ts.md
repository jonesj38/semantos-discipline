---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/__tests__/swarm-manifest.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.861398+00:00
---

# core/protocol-types/__tests__/swarm-manifest.test.ts

```ts
/**
 * Swarm manifest / infohash — M0.
 *
 * Pins the canonical manifest wire format + the infohash derivation, and
 * proves the proof-based verification model: a leecher verifies any single
 * fetched data cell against the manifest's 32-byte merkle root, so the
 * manifest cell stays a single tiny cell at any file size (no inline
 * leaf-hash vector). Wire/infohash drift between a TS seeder and the Zig
 * brain tracker would silently break `swarm.locate`, so this fixes it.
 */
import { describe, expect, test } from 'bun:test';
import { CELL_SIZE, PAYLOAD_SIZE, HEADER_SIZE } from '../src/constants';
import {
  SWARM_MANIFEST_TYPE_HASH,
  bytesEqual,
  computeInfohash,
  encodeManifestCell,
  parseManifestCell,
} from '../src/swarm-manifest';
import {
  publishFile,
  fileToDataCells,
  dataCellsToFile,
  generateDataCellProof,
  verifyDataCell,
} from '../src/swarm-file';
import { cellMerkleSha256 as sha256 } from '@semantos/cell-ops/packer';

/** Deterministic pseudo-file of `n` bytes. */
function fileOf(n: number): Uint8Array {
  const b = new Uint8Array(n);
  for (let i = 0; i < n; i++) b[i] = (i * 31 + 7) & 0xff;
  return b;
}

describe('swarm manifest — file ⇄ cells', () => {
  test('round-trips bytes through data cells', () => {
    const file = fileOf(5000); // 5 cells @ 1016
    const { dataCells, totalSize } = fileToDataCells(file);
    expect(dataCells.length).toBe(Math.ceil(5000 / 1016));
    for (const c of dataCells) expect(c.length).toBe(CELL_SIZE);
    const back = dataCellsToFile(dataCells, totalSize);
    expect(bytesEqual(back, file)).toBe(true);
  });

  test('contentHash commits to the reassembled file', () => {
    const file = fileOf(5000);
    const pub = publishFile(file, 'media/clip.bin');
    expect(bytesEqual(pub.manifest.contentHash, sha256(file))).toBe(true);
    expect(pub.manifest.totalSize).toBe(5000);
    expect(pub.manifest.totalCells).toBe(pub.dataCells.length);
  });

  test('single-cell file works', () => {
    const file = fileOf(10);
    const pub = publishFile(file, 'tiny');
    expect(pub.dataCells.length).toBe(1);
    expect(bytesEqual(dataCellsToFile(pub.dataCells, pub.manifest.totalSize), file)).toBe(true);
  });
});

describe('swarm manifest — infohash + cell', () => {
  test('infohash is stable across manifest-cell encode/parse', () => {
    const pub = publishFile(fileOf(3000), 'a/b/c');
    const reparsed = parseManifestCell(pub.manifestCell);
    expect(bytesEqual(computeInfohash(reparsed), pub.infohash)).toBe(true);
    expect(reparsed.semanticPath).toBe('a/b/c');
    expect(reparsed.totalCells).toBe(pub.manifest.totalCells);
    expect(bytesEqual(reparsed.merkleRoot, pub.manifest.merkleRoot)).toBe(true);
  });

  test('infohash is independent of owner + timestamp', () => {
    const pub = publishFile(fileOf(3000), 'a/b/c');
    const cellA = encodeManifestCell(pub.manifest, { ownerId: new Uint8Array(16).fill(1), timestamp: 111n });
    const cellB = encodeManifestCell(pub.manifest, { ownerId: new Uint8Array(16).fill(2), timestamp: 999n });
    // Cells differ (owner/timestamp in header) but infohash is payload-only.
    expect(bytesEqual(cellA, cellB)).toBe(false);
    expect(bytesEqual(computeInfohash(parseManifestCell(cellA)), pub.infohash)).toBe(true);
    expect(bytesEqual(computeInfohash(parseManifestCell(cellB)), pub.infohash)).toBe(true);
  });

  test('manifest cell stays a single tiny cell even for large files', () => {
    // 200 cells: the inline-leaf-vector approach (32B × 200 = 6400B) would
    // overflow the 768B payload many times over. Proof-based verification
    // keeps the manifest a single cell.
    const file = fileOf(200 * 1016);
    const pub = publishFile(file, 'big/file.bin');
    expect(pub.manifest.totalCells).toBe(200);
    expect(pub.manifestCell.length).toBe(CELL_SIZE);
    const payloadLen = parseManifestCell(pub.manifestCell).totalCells; // sanity parse
    expect(payloadLen).toBe(200);
    // The canonical payload is comfortably under PAYLOAD_SIZE.
    const headerTotalSize = new DataView(
      pub.manifestCell.buffer, pub.manifestCell.byteOffset, pub.manifestCell.byteLength,
    ).getUint32(90, true);
    expect(headerTotalSize).toBeLessThan(PAYLOAD_SIZE);
  });

  test('parse rejects a non-manifest cell (type-hash guard)', () => {
    const pub = publishFile(fileOf(100), 'x');
    const bad = pub.manifestCell.slice();
    bad[30] ^= 0xff; // corrupt the typeHash region (offset 30)
    expect(() => parseManifestCell(bad)).toThrow();
  });

  test('manifest cell carries the swarm.manifest type hash', () => {
    const pub = publishFile(fileOf(100), 'x');
    const typeHash = pub.manifestCell.slice(30, 62);
    expect(bytesEqual(typeHash, SWARM_MANIFEST_TYPE_HASH)).toBe(true);
  });
});

describe('swarm manifest — per-cell inclusion proofs', () => {
  test('every cell verifies against the merkle root', () => {
    const pub = publishFile(fileOf(20 * 1016 + 5), 'proofs');
    for (let i = 0; i < pub.dataCells.length; i++) {
      const proof = generateDataCellProof(pub.dataCells, i);
      expect(verifyDataCell(pub.manifest, i, pub.dataCells[i]!, proof)).toBe(true);
    }
  });

  test('a tampered cell fails inclusion', () => {
    const pub = publishFile(fileOf(8000), 'tamper');
    const i = 3;
    const proof = generateDataCellProof(pub.dataCells, i);
    const tampered = pub.dataCells[i]!.slice();
    tampered[HEADER_SIZE + 10] ^= 0x01; // flip a payload byte
    expect(verifyDataCell(pub.manifest, i, tampered, proof)).toBe(false);
    // The pristine cell still verifies with the same proof.
    expect(verifyDataCell(pub.manifest, i, pub.dataCells[i]!, proof)).toBe(true);
  });

  test('a proof for the wrong index is rejected', () => {
    const pub = publishFile(fileOf(8000), 'idx');
    const proof = generateDataCellProof(pub.dataCells, 2);
    // Serving cell 2's bytes but claiming index 4 → rejected.
    expect(verifyDataCell(pub.manifest, 4, pub.dataCells[2]!, proof)).toBe(false);
  });
});

```
