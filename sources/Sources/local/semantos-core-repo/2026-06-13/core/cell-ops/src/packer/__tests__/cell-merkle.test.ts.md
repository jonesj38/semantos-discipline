---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-ops/src/packer/__tests__/cell-merkle.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.835374+00:00
---

# core/cell-ops/src/packer/__tests__/cell-merkle.test.ts

```ts
/**
 * D-OCT-merkle-hierarchy — cell merkle tests (TS oracle side).
 *
 * Test plan:
 *   (a) Rung-0/1 compat: existing packMultiCell/packEscalated bytes unaffected.
 *   (b) Merkle root: correct domainPayloadRoot committed for known child cells.
 *   (c) Inclusion proof: verifyCellInclusion succeeds for valid leaf+path.
 *   (d) Inclusion proof: verifyCellInclusion fails for tampered leaf/path.
 *   (e) Round-trip: pack → unpack recovers descriptor.
 *   (f) Canonical byte-vector: oracle↔Zig mirror agreement.
 *   (g) isMerkleHierarchy distinguishes rung-0, rung-1, rung-2.
 *   (h) Edge cases: single child cell, many child cells.
 */

import { describe, expect, test } from 'bun:test';

import {
  // Rung-2 (new)
  cellMerkleSha256,
  computeCellMerkleRoot,
  generateCellInclusionProof,
  verifyCellInclusion,
  packMerkleHierarchy,
  unpackMerkleHierarchy,
  isMerkleHierarchy,
  DOMAIN_PAYLOAD_ROOT_OFFSET,
  // Rung-0/1 (existing — must be unaffected)
  packMultiCell,
  packEscalated,
  isEscalated,
  ESCALATION_CELL_COUNT_SENTINEL,
} from '../index';
import { CELL_SIZE, HEADER_SIZE, PAYLOAD_SIZE } from '../constants';
import { CONTINUATION_TYPE } from '../constants';
import type { MultiCellObject } from '../types';

// ── Helpers ────────────────────────────────────────────────────────────────────

function makeHeader(payloadSize = 0): Buffer {
  const h = Buffer.alloc(HEADER_SIZE, 0);
  h.writeUInt32LE(payloadSize, 90);
  return h;
}

function makeChildCell(pattern: number): Uint8Array {
  const cell = new Uint8Array(CELL_SIZE);
  cell.fill(pattern & 0xff);
  return cell;
}

// ── (a) Rung-0/1 backward-compat regression guard ─────────────────────────────

describe('backward-compat: rung-0/1 bytes are unaffected', () => {
  test('rung-0 packMultiCell is NOT detected as merkle hierarchy', () => {
    const obj: MultiCellObject = {
      header: makeHeader(10),
      payload: Buffer.from('hello world'),
      continuations: [],
    };
    const packed = packMultiCell(obj);
    expect(isMerkleHierarchy(new Uint8Array(packed.buffer))).toBe(false);
    // Also must not be sentinel
    expect(packed.buffer.readUInt32LE(86)).not.toBe(ESCALATION_CELL_COUNT_SENTINEL);
  });

  test('rung-0 packMultiCell with continuations is NOT merkle hierarchy', () => {
    const obj: MultiCellObject = {
      header: makeHeader(10),
      payload: Buffer.from('data'),
      continuations: [
        { type: CONTINUATION_TYPE.DATA, data: Buffer.from('cont') },
      ],
    };
    const packed = packMultiCell(obj);
    expect(isMerkleHierarchy(new Uint8Array(packed.buffer))).toBe(false);
    expect(isEscalated(packed.buffer)).toBe(false);
  });

  test('rung-1 packEscalated is NOT detected as merkle hierarchy (different rung)', () => {
    const header = Buffer.alloc(HEADER_SIZE, 0);
    const payload = Buffer.alloc(500, 0xab);
    const packed = packEscalated(header, payload);
    // isEscalated = true (rung-1), but isMerkleHierarchy = false (rung != 2)
    expect(isEscalated(packed.buffer)).toBe(true);
    expect(isMerkleHierarchy(new Uint8Array(packed.buffer))).toBe(false);
    // Rung byte (cell byte 256) must be 1 for octave-escalated
    expect(packed.buffer[256]).toBe(1);
  });
});

// ── (b) Merkle root committed correctly ────────────────────────────────────────

describe('packMerkleHierarchy — root commitment', () => {
  test('builds and commits a 32-byte root for 3 child cells', () => {
    const header = makeHeader(0);
    const cells = [
      makeChildCell(0x11),
      makeChildCell(0x22),
      makeChildCell(0x33),
    ];

    const result = packMerkleHierarchy(new Uint8Array(header), cells, BigInt(3 * CELL_SIZE));

    // anchor cell is exactly 1024 bytes
    expect(result.anchorCell.length).toBe(CELL_SIZE);
    // merkle root is 32 bytes
    expect(result.merkleRoot.length).toBe(32);
    expect(result.childCount).toBe(3);

    // domainPayloadRoot (offset 224) matches merkleRoot
    const rootInHeader = result.anchorCell.slice(DOMAIN_PAYLOAD_ROOT_OFFSET, DOMAIN_PAYLOAD_ROOT_OFFSET + 32);
    expect(Buffer.from(rootInHeader).equals(Buffer.from(result.merkleRoot))).toBe(true);
  });

  test('cell_count (offset 86) is sentinel 0xFFFFFFFF', () => {
    const header = makeHeader(0);
    const cells = [makeChildCell(0xaa)];
    const result = packMerkleHierarchy(new Uint8Array(header), cells, BigInt(CELL_SIZE));
    const view = new DataView(result.anchorCell.buffer);
    expect(view.getUint32(86, true)).toBe(0xffffffff);
  });

  test('total_size (offset 90) is 16 (descriptor size, O-1)', () => {
    const header = makeHeader(0);
    const cells = [makeChildCell(0xbb)];
    const result = packMerkleHierarchy(new Uint8Array(header), cells, BigInt(100));
    const view = new DataView(result.anchorCell.buffer);
    expect(view.getUint32(90, true)).toBe(16);
  });

  test('descriptor at payload offset 0: rung=2, octave_level=0, child_count=N', () => {
    const header = makeHeader(0);
    const N = 5;
    const cells = Array.from({ length: N }, (_, i) => makeChildCell(i));
    const totalB = BigInt(N * CELL_SIZE);
    const result = packMerkleHierarchy(new Uint8Array(header), cells, totalB);

    const a = result.anchorCell;
    // rung at cell byte 256
    expect(a[HEADER_SIZE + 0]).toBe(2);
    // octave_level at cell byte 257
    expect(a[HEADER_SIZE + 1]).toBe(0);
    // child_count u16 LE at cell bytes 258-259
    const view = new DataView(a.buffer);
    expect(view.getUint16(HEADER_SIZE + 2, true)).toBe(N);
    // total_bytes u64 LE at cell bytes 260-267
    expect(view.getBigUint64(HEADER_SIZE + 4, true)).toBe(totalB);
    // reserved at cell bytes 268-271
    expect(view.getUint32(HEADER_SIZE + 12, true)).toBe(0);
  });

  test('payload bytes 272..1023 are zeroed', () => {
    const header = makeHeader(0);
    const cells = [makeChildCell(0xcc), makeChildCell(0xdd)];
    const result = packMerkleHierarchy(new Uint8Array(header), cells, BigInt(0));
    const a = result.anchorCell;
    for (let i = HEADER_SIZE + 16; i < CELL_SIZE; i++) {
      if (a[i] !== 0) {
        throw new Error(`Non-zero at offset ${i}: 0x${a[i]!.toString(16)}`);
      }
    }
  });

  test('root is deterministic (same cells → same root)', () => {
    const cells = [makeChildCell(0x01), makeChildCell(0x02)];
    const r1 = computeCellMerkleRoot(cells);
    const r2 = computeCellMerkleRoot(cells);
    expect(Buffer.from(r1).equals(Buffer.from(r2))).toBe(true);
  });

  test('different cells → different roots', () => {
    const cells1 = [makeChildCell(0x01), makeChildCell(0x02)];
    const cells2 = [makeChildCell(0x03), makeChildCell(0x04)];
    const r1 = computeCellMerkleRoot(cells1);
    const r2 = computeCellMerkleRoot(cells2);
    expect(Buffer.from(r1).equals(Buffer.from(r2))).toBe(false);
  });
});

// ── (c) Inclusion proof: valid ────────────────────────────────────────────────

describe('inclusion proof — valid', () => {
  test('proof verifies for leaf 0 of a 2-cell set', () => {
    const cells = [makeChildCell(0xaa), makeChildCell(0xbb)];
    const root = computeCellMerkleRoot(cells);
    const proof = generateCellInclusionProof(cells, 0);
    expect(verifyCellInclusion(cells[0]!, proof, root)).toBe(true);
  });

  test('proof verifies for leaf 1 of a 2-cell set', () => {
    const cells = [makeChildCell(0xaa), makeChildCell(0xbb)];
    const root = computeCellMerkleRoot(cells);
    const proof = generateCellInclusionProof(cells, 1);
    expect(verifyCellInclusion(cells[1]!, proof, root)).toBe(true);
  });

  test('all leaves verify in a 4-cell set', () => {
    const cells = Array.from({ length: 4 }, (_, i) => makeChildCell(i + 1));
    const root = computeCellMerkleRoot(cells);
    for (let i = 0; i < cells.length; i++) {
      const proof = generateCellInclusionProof(cells, i);
      expect(verifyCellInclusion(cells[i]!, proof, root)).toBe(true);
    }
  });

  test('all leaves verify in a 5-cell set (odd count)', () => {
    const cells = Array.from({ length: 5 }, (_, i) => makeChildCell(i + 1));
    const root = computeCellMerkleRoot(cells);
    for (let i = 0; i < cells.length; i++) {
      const proof = generateCellInclusionProof(cells, i);
      expect(verifyCellInclusion(cells[i]!, proof, root)).toBe(true);
    }
  });

  test('single-cell proof verifies', () => {
    const cells = [makeChildCell(0x42)];
    const root = computeCellMerkleRoot(cells);
    const proof = generateCellInclusionProof(cells, 0);
    expect(verifyCellInclusion(cells[0]!, proof, root)).toBe(true);
  });

  test('100-cell set: all leaves verify', () => {
    const cells = Array.from({ length: 100 }, (_, i) => makeChildCell(i));
    const root = computeCellMerkleRoot(cells);
    for (let i = 0; i < cells.length; i++) {
      const proof = generateCellInclusionProof(cells, i);
      expect(verifyCellInclusion(cells[i]!, proof, root)).toBe(true);
    }
  });
});

// ── (d) Inclusion proof: tampered ────────────────────────────────────────────

describe('inclusion proof — tampered (must fail)', () => {
  test('tampered cell bytes → verification fails', () => {
    const cells = [makeChildCell(0x01), makeChildCell(0x02), makeChildCell(0x03)];
    const root = computeCellMerkleRoot(cells);
    const proof = generateCellInclusionProof(cells, 0);

    // Tamper one byte in the cell
    const tampered = new Uint8Array(cells[0]!);
    tampered[100] ^= 0xff;

    expect(verifyCellInclusion(tampered, proof, root)).toBe(false);
  });

  test('tampered sibling hash → verification fails', () => {
    const cells = [makeChildCell(0x10), makeChildCell(0x20)];
    const root = computeCellMerkleRoot(cells);
    const proof = generateCellInclusionProof(cells, 0);

    // Tamper the sibling hash
    const tamperedProof = {
      leafIndex: proof.leafIndex,
      siblings: proof.siblings.map(s => ({
        ...s,
        hash: new Uint8Array(s.hash).map((b, i) => (i === 5 ? b ^ 0xff : b)),
      })),
    };

    expect(verifyCellInclusion(cells[0]!, tamperedProof, root)).toBe(false);
  });

  test('wrong root → verification fails', () => {
    const cells = [makeChildCell(0xaa), makeChildCell(0xbb)];
    const root = computeCellMerkleRoot(cells);
    const proof = generateCellInclusionProof(cells, 0);

    // Tamper the root
    const wrongRoot = new Uint8Array(root);
    wrongRoot[0] ^= 0xff;

    expect(verifyCellInclusion(cells[0]!, proof, wrongRoot)).toBe(false);
  });

  test('proof for leaf 0 does NOT verify for leaf 1', () => {
    const cells = [makeChildCell(0x11), makeChildCell(0x22)];
    const root = computeCellMerkleRoot(cells);
    const proof = generateCellInclusionProof(cells, 0);
    // Use cells[1] with the proof for cells[0]
    expect(verifyCellInclusion(cells[1]!, proof, root)).toBe(false);
  });
});

// ── (e) Round-trip: pack → unpack ────────────────────────────────────────────

describe('round-trip: packMerkleHierarchy → unpackMerkleHierarchy', () => {
  test('descriptor fields round-trip correctly', () => {
    const header = makeHeader(0);
    const N = 7;
    const cells = Array.from({ length: N }, (_, i) => makeChildCell(i + 1));
    const totalB = BigInt(N * CELL_SIZE);

    const packed = packMerkleHierarchy(new Uint8Array(header), cells, totalB);
    const desc = unpackMerkleHierarchy(packed.anchorCell);

    expect(Buffer.from(desc.merkleRoot).equals(Buffer.from(packed.merkleRoot))).toBe(true);
    expect(desc.childCount).toBe(N);
    expect(desc.totalBytes).toBe(totalB);
    expect(desc.octaveLevel).toBe(0);
  });

  test('isMerkleHierarchy returns true for packed anchor', () => {
    const header = makeHeader(0);
    const cells = [makeChildCell(0x01), makeChildCell(0x02)];
    const packed = packMerkleHierarchy(new Uint8Array(header), cells, BigInt(2 * CELL_SIZE));
    expect(isMerkleHierarchy(packed.anchorCell)).toBe(true);
  });

  test('unpackMerkleHierarchy throws if rung is not 2', () => {
    // Build a rung-1 buffer and try to unpack as rung-2
    const header = Buffer.alloc(HEADER_SIZE, 0);
    const payload = Buffer.alloc(500, 0xab);
    const packed = packEscalated(header, payload);
    const buf = new Uint8Array(packed.buffer);
    expect(() => unpackMerkleHierarchy(buf)).toThrow('Expected rung 2');
  });
});

// ── (f) Canonical byte-vector — oracle↔Zig mirror agreement ──────────────────
//
// CANONICAL VECTOR (rung-2):
//   header = 256 zero bytes
//   child cells:
//     cell A = 1024 bytes, all 0x41 ('A')
//     cell B = 1024 bytes, all 0x42 ('B')
//     cell C = 1024 bytes, all 0x43 ('C')
//   totalBytes = 3072 (3 * 1024)
//
// Expected wire bytes (anchor cell):
//   offset 86..89:  FF FF FF FF       (sentinel u32 LE)
//   offset 90..93:  10 00 00 00       (total_size = 16, u32 LE)
//   offset 224..255: merkle_root (32 bytes, computed below)
//   offset 256:     02                (rung = 2)
//   offset 257:     00                (octave_level = 0)
//   offset 258..259: 03 00            (child_count = 3, u16 LE)
//   offset 260..267: 00 0C 00 00 00 00 00 00  (total_bytes = 3072, u64 LE)
//   offset 268..271: 00 00 00 00      (reserved)
//
// The Zig test ("canonical rung-2 vector") must produce the identical root.

describe('canonical byte-vector (oracle↔Zig mirror)', () => {
  // Build the canonical vector once.
  const cellA = new Uint8Array(CELL_SIZE).fill(0x41);
  const cellB = new Uint8Array(CELL_SIZE).fill(0x42);
  const cellC = new Uint8Array(CELL_SIZE).fill(0x43);
  const canonCells = [cellA, cellB, cellC];
  const canonHeader = new Uint8Array(HEADER_SIZE).fill(0);
  const canonTotalBytes = BigInt(3 * CELL_SIZE);

  // Compute expected merkle root step by step for documentation:
  //   leafA = sha256(cellA)
  //   leafB = sha256(cellB)
  //   leafC = sha256(cellC)
  //   branchAB = sha256(leafA || leafB)
  //   branchCC = sha256(leafC || leafC)  [duplicate last for odd]
  //   root = sha256(branchAB || branchCC)

  test('canonical root matches hand-computed value', () => {
    const leafA = cellMerkleSha256(cellA);
    const leafB = cellMerkleSha256(cellB);
    const leafC = cellMerkleSha256(cellC);

    const abInput = new Uint8Array(64);
    abInput.set(leafA, 0); abInput.set(leafB, 32);
    const branchAB = cellMerkleSha256(abInput);

    const ccInput = new Uint8Array(64);
    ccInput.set(leafC, 0); ccInput.set(leafC, 32);  // duplicate last
    const branchCC = cellMerkleSha256(ccInput);

    const rootInput = new Uint8Array(64);
    rootInput.set(branchAB, 0); rootInput.set(branchCC, 32);
    const expectedRoot = cellMerkleSha256(rootInput);

    const computedRoot = computeCellMerkleRoot(canonCells);
    expect(Buffer.from(computedRoot).equals(Buffer.from(expectedRoot))).toBe(true);
  });

  test('canonical anchor cell wire bytes at known offsets', () => {
    const packed = packMerkleHierarchy(canonHeader, canonCells, canonTotalBytes);
    const a = packed.anchorCell;
    const view = new DataView(a.buffer);

    // sentinel at offset 86
    expect(view.getUint32(86, true)).toBe(0xffffffff);
    // total_size = 16 at offset 90
    expect(view.getUint32(90, true)).toBe(16);
    // rung = 2 at offset 256
    expect(a[256]).toBe(2);
    // octave_level = 0 at offset 257
    expect(a[257]).toBe(0);
    // child_count = 3 at offsets 258-259
    expect(a[258]).toBe(0x03);
    expect(a[259]).toBe(0x00);
    // total_bytes = 3072 at offsets 260-267
    expect(a[260]).toBe(0x00);
    expect(a[261]).toBe(0x0c);  // 3072 = 0x0C00; LE: low byte = 0x00, next = 0x0C
    expect(a[262]).toBe(0x00);
    expect(a[263]).toBe(0x00);
    expect(a[264]).toBe(0x00);
    expect(a[265]).toBe(0x00);
    expect(a[266]).toBe(0x00);
    expect(a[267]).toBe(0x00);
    // reserved at 268-271
    expect(view.getUint32(268, true)).toBe(0);

    // domainPayloadRoot at 224-255 matches packed.merkleRoot
    const rootInHeader = a.slice(224, 256);
    expect(Buffer.from(rootInHeader).equals(Buffer.from(packed.merkleRoot))).toBe(true);
  });

  test('canonical inclusion proof for leaf 1 (cellB) verifies', () => {
    const root = computeCellMerkleRoot(canonCells);
    const proof = generateCellInclusionProof(canonCells, 1);
    expect(verifyCellInclusion(cellB, proof, root)).toBe(true);
  });

  test('canonical inclusion proof for leaf 0 (cellA) verifies', () => {
    const root = computeCellMerkleRoot(canonCells);
    const proof = generateCellInclusionProof(canonCells, 0);
    expect(verifyCellInclusion(cellA, proof, root)).toBe(true);
  });

  test('canonical inclusion proof for leaf 2 (cellC) verifies', () => {
    const root = computeCellMerkleRoot(canonCells);
    const proof = generateCellInclusionProof(canonCells, 2);
    expect(verifyCellInclusion(cellC, proof, root)).toBe(true);
  });

  test('canonical root hex value is stable (print for Zig reference)', () => {
    // Print the canonical root so the Zig engineer can hardcode it in tests.
    const root = computeCellMerkleRoot(canonCells);
    const rootHex = Buffer.from(root).toString('hex');
    // Verify it is 32 bytes / 64 hex chars
    expect(rootHex.length).toBe(64);
    // Log for reference
    console.log('CANONICAL_ROOT_HEX:', rootHex);
    // This value is recorded in the canonical test vector; the Zig test must agree.
    // Exact value captured at implementation time — used as the cross-language anchor.
    // DO NOT change this value without updating the Zig canonical vector test.
    expect(rootHex).toMatchSnapshot();
  });
});

// ── (g) isMerkleHierarchy distinguishes rungs ─────────────────────────────────

describe('isMerkleHierarchy', () => {
  test('returns false for rung-0 buffer', () => {
    const obj: MultiCellObject = {
      header: makeHeader(0),
      payload: Buffer.alloc(0),
      continuations: [],
    };
    const packed = packMultiCell(obj);
    expect(isMerkleHierarchy(new Uint8Array(packed.buffer))).toBe(false);
  });

  test('returns false for rung-1 buffer', () => {
    const packed = packEscalated(Buffer.alloc(HEADER_SIZE, 0), Buffer.alloc(100, 0x55));
    expect(isMerkleHierarchy(new Uint8Array(packed.buffer))).toBe(false);
  });

  test('returns true for rung-2 buffer', () => {
    const packed = packMerkleHierarchy(
      new Uint8Array(HEADER_SIZE).fill(0),
      [makeChildCell(0x01), makeChildCell(0x02)],
      BigInt(2048),
    );
    expect(isMerkleHierarchy(packed.anchorCell)).toBe(true);
  });

  test('returns false for buffer smaller than CELL_SIZE', () => {
    expect(isMerkleHierarchy(new Uint8Array(100))).toBe(false);
  });
});

// ── (h) Edge cases ────────────────────────────────────────────────────────────

describe('edge cases', () => {
  test('single child cell — root equals its own leaf hash', () => {
    const cell = makeChildCell(0xff);
    const root = computeCellMerkleRoot([cell]);
    const leafHash = cellMerkleSha256(cell);
    // Single-leaf tree: root = leaf hash (no combination)
    expect(Buffer.from(root).equals(Buffer.from(leafHash))).toBe(true);
  });

  test('many child cells (200) — all proofs verify', () => {
    const cells = Array.from({ length: 200 }, (_, i) => makeChildCell(i & 0xff));
    const root = computeCellMerkleRoot(cells);
    // Spot-check 10 indices across the range
    const indices = [0, 1, 50, 99, 100, 101, 150, 197, 198, 199];
    for (const i of indices) {
      const proof = generateCellInclusionProof(cells, i);
      expect(verifyCellInclusion(cells[i]!, proof, root)).toBe(true);
    }
  });

  test('throws on empty child cells', () => {
    expect(() => computeCellMerkleRoot([])).toThrow();
    expect(() => packMerkleHierarchy(new Uint8Array(HEADER_SIZE), [], BigInt(0))).toThrow();
    expect(() => generateCellInclusionProof([], 0)).toThrow();
  });

  test('throws on leaf index out of range', () => {
    const cells = [makeChildCell(0x01), makeChildCell(0x02)];
    expect(() => generateCellInclusionProof(cells, 2)).toThrow('out of range');
    expect(() => generateCellInclusionProof(cells, -1)).toThrow('out of range');
  });
});

```
