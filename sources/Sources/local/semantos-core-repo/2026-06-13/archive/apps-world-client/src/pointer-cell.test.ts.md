---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-world-client/src/pointer-cell.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.826245+00:00
---

# archive/apps-world-client/src/pointer-cell.test.ts

```ts
// M4.4 — Pointer cell TypeScript parity tests (D6.3 deferred work).
//
// The pointer cell is a 1024-byte continuation cell (type 0x06) whose first
// 8 bytes are a standard ContinuationHeader and bytes 8..97 are a 90-byte
// PointerPayload.  The remaining 926 bytes are zero padding.
//
// Wire format (1024 bytes total):
//   [0..7]    8-byte ContinuationHeader (cellType=0x06, cellIndex u16 LE,
//             totalCells u16 LE, payloadSize=90 u16 LE, reserved=0)
//   [8..97]   90-byte PointerPayload
//   [98..1023] 926 zero bytes
//
// PointerPayload layout (byte offsets relative to byte 8 of the cell):
//   [0]      octave         u8      target octave level (0-3)
//   [1..2]   slot           u16 LE  slot within that octave (0-1023)
//   [3..6]   offset         u32 LE  byte offset within the cell
//   [7]      _slot_pad      u8      always 0
//   [8..39]  content_hash   [32]u8  SHA-256 of referenced content
//   [40..71] type_hash      [32]u8  type hash (CAS lookup)
//   [72..79] total_size     u64 LE  actual byte size of referenced object
//   [80]     flags          u8      IMMUTABLE=0x01, ENCRYPTED=0x02, COMPRESSED=0x04
//   [81..82] fragment_count u16 LE  sub-cells at target octave (0 = single)
//   [83..89] reserved       [7]u8   future use (zeros)
//
// Tests:
//   M4.4-T-pack-unpack-octave0 — pack octave-0 address → unpack → same fields
//   M4.4-T-pack-unpack-octave1 — pack octave-1 address (with slot/offset) → unpack → same
//   M4.4-T-pack-unpack-octave2 — pack octave-2 address (with flags) → unpack → same
//   M4.4-T-byte-length         — packed cell is exactly 1024 bytes
//   M4.4-T-content-hash-length — throws if contentHash is not 32 bytes
//   M4.4-T-invalid-cell        — unpack of non-pointer-cell bytes → throws
//   M4.4-T-zig-parity          — hardcoded golden fixture verifies byte-parity with Zig

import { describe, it, expect } from "vitest";
import {
  packPointerCell,
  unpackPointerCell,
  type PointerPayload,
  PointerFlags,
  POINTER_CELL_TYPE,
  POINTER_PAYLOAD_SIZE,
} from "./pointer-cell.js";

// ── Helpers ──────────────────────────────────────────────────────────────────

function makeHash(fill: number): Uint8Array {
  return new Uint8Array(32).fill(fill);
}

function makeReserved(): Uint8Array {
  return new Uint8Array(7).fill(0);
}

// ── Tests ─────────────────────────────────────────────────────────────────────

describe("M4.4 Pointer cell pack/unpack parity", () => {
  it("M4.4-T-pack-unpack-octave0: octave-0 round-trip", () => {
    const payload: PointerPayload = {
      octave: 0,
      slot: 0,
      offset: 0,
      contentHash: makeHash(0x11),
      typeHash: makeHash(0x22),
      totalSize: BigInt(0),
      flags: 0,
      fragmentCount: 0,
      reserved: makeReserved(),
    };
    const cell = packPointerCell(payload, 1, 1);
    const result = unpackPointerCell(cell);

    expect(result.octave).toBe(0);
    expect(result.slot).toBe(0);
    expect(result.offset).toBe(0);
    expect(result.contentHash).toEqual(makeHash(0x11));
    expect(result.typeHash).toEqual(makeHash(0x22));
    expect(result.totalSize).toBe(BigInt(0));
    expect(result.flags).toBe(0);
    expect(result.fragmentCount).toBe(0);
  });

  it("M4.4-T-pack-unpack-octave1: octave-1 with slot and offset", () => {
    const payload: PointerPayload = {
      octave: 1,
      slot: 42,
      offset: 1024,
      contentHash: makeHash(0xAA),
      typeHash: makeHash(0xBB),
      totalSize: BigInt(2_000_000),
      flags: PointerFlags.IMMUTABLE,
      fragmentCount: 2,
      reserved: makeReserved(),
    };
    const cell = packPointerCell(payload, 1, 1);
    const result = unpackPointerCell(cell);

    expect(result.octave).toBe(1);
    expect(result.slot).toBe(42);
    expect(result.offset).toBe(1024);
    expect(result.contentHash).toEqual(makeHash(0xAA));
    expect(result.typeHash).toEqual(makeHash(0xBB));
    expect(result.totalSize).toBe(BigInt(2_000_000));
    expect(result.flags).toBe(PointerFlags.IMMUTABLE);
    expect(result.fragmentCount).toBe(2);
  });

  it("M4.4-T-pack-unpack-octave2: octave-2 with ENCRYPTED|COMPRESSED flags", () => {
    const payload: PointerPayload = {
      octave: 2,
      slot: 999,
      offset: 0,
      contentHash: new Uint8Array(32).fill(0xFF),
      typeHash: new Uint8Array(32).fill(0xEE),
      totalSize: BigInt(1_073_741_824),
      flags: PointerFlags.ENCRYPTED | PointerFlags.COMPRESSED,
      fragmentCount: 0,
      reserved: makeReserved(),
    };
    const cell = packPointerCell(payload, 1, 1);
    const result = unpackPointerCell(cell);

    expect(result.octave).toBe(2);
    expect(result.slot).toBe(999);
    expect(result.offset).toBe(0);
    expect(result.contentHash).toEqual(new Uint8Array(32).fill(0xFF));
    expect(result.typeHash).toEqual(new Uint8Array(32).fill(0xEE));
    expect(result.totalSize).toBe(BigInt(1_073_741_824));
    expect(result.flags).toBe(PointerFlags.ENCRYPTED | PointerFlags.COMPRESSED);
    expect(result.fragmentCount).toBe(0);
  });

  it("M4.4-T-byte-length: packed cell is exactly 1024 bytes", () => {
    const payload: PointerPayload = {
      octave: 0,
      slot: 0,
      offset: 0,
      contentHash: makeHash(0),
      typeHash: makeHash(0),
      totalSize: BigInt(0),
      flags: 0,
      fragmentCount: 0,
      reserved: makeReserved(),
    };
    const cell = packPointerCell(payload, 1, 1);
    expect(cell.length).toBe(1024);
  });

  it("M4.4-T-content-hash-length: throws if contentHash is not 32 bytes", () => {
    const bad: PointerPayload = {
      octave: 0,
      slot: 0,
      offset: 0,
      contentHash: new Uint8Array(31), // wrong length
      typeHash: makeHash(0),
      totalSize: BigInt(0),
      flags: 0,
      fragmentCount: 0,
      reserved: makeReserved(),
    };
    expect(() => packPointerCell(bad, 1, 1)).toThrow();
  });

  it("M4.4-T-invalid-cell: unpack of non-pointer-cell bytes throws", () => {
    // A cell whose first byte is not 0x06
    const notPointer = new Uint8Array(1024).fill(0);
    notPointer[0] = 0x04; // DATA type
    expect(() => unpackPointerCell(notPointer)).toThrow();

    // A cell of wrong length
    const wrongLen = new Uint8Array(512).fill(0);
    wrongLen[0] = POINTER_CELL_TYPE;
    expect(() => unpackPointerCell(wrongLen)).toThrow();
  });

  it("M4.4-T-zig-parity: golden fixture matches Zig-generated bytes", () => {
    // Golden fixture constructed from the Zig pack logic (T6.07 test values):
    //   octave=1, slot=42, offset=1024, content_hash=0xAA*32,
    //   type_hash=0xBB*32, total_size=2_000_000, flags=IMMUTABLE(0x01),
    //   fragment_count=2, reserved=[0]*7, cell_index=1, total_cells=1
    //
    // Continuation header (bytes 0-7):
    //   [0]    = 0x06  (POINTER_CELL_TYPE)
    //   [1..2] = 0x01 0x00  (cellIndex=1 LE)
    //   [3..4] = 0x01 0x00  (totalCells=1 LE)
    //   [5..6] = 0x5A 0x00  (payloadSize=90 LE)
    //   [7]    = 0x00  (reserved)
    //
    // PointerPayload (bytes 8-97):
    //   [8]         = 0x01  (octave=1)
    //   [9..10]     = 0x2A 0x00  (slot=42 LE)
    //   [11..14]    = 0x00 0x04 0x00 0x00  (offset=1024 LE)
    //   [15]        = 0x00  (slot_pad)
    //   [16..47]    = 0xAA * 32  (content_hash)
    //   [48..79]    = 0xBB * 32  (type_hash)
    //   [80..87]    = 0x80 0x84 0x1E 0x00 0x00 0x00 0x00 0x00  (total_size=2_000_000 LE)
    //   [88]        = 0x01  (flags=IMMUTABLE)
    //   [89..90]    = 0x02 0x00  (fragment_count=2 LE)
    //   [91..97]    = 0x00 * 7  (reserved)
    //
    // Bytes 98..1023 = 0x00 (padding)

    const golden = new Uint8Array(1024).fill(0);
    // Continuation header
    golden[0] = 0x06;
    golden[1] = 0x01; golden[2] = 0x00;  // cellIndex=1 LE
    golden[3] = 0x01; golden[4] = 0x00;  // totalCells=1 LE
    golden[5] = 0x5A; golden[6] = 0x00;  // payloadSize=90 LE
    golden[7] = 0x00; // reserved
    // PointerPayload at byte 8
    golden[8] = 0x01; // octave=1
    golden[9] = 0x2A; golden[10] = 0x00;  // slot=42 LE
    golden[11] = 0x00; golden[12] = 0x04; golden[13] = 0x00; golden[14] = 0x00; // offset=1024 LE
    golden[15] = 0x00; // slot_pad
    golden.fill(0xAA, 16, 48);  // content_hash
    golden.fill(0xBB, 48, 80);  // type_hash
    // total_size=2_000_000 = 0x001E4240 LE: 0x40, 0x42, 0x1E, 0x00, 0x00, 0x00, 0x00, 0x00
    // total_size=2_000_000 = 0x1E8480, LE: 80 84 1E 00 00 00 00 00
    golden[80] = 0x80; golden[81] = 0x84; golden[82] = 0x1E; golden[83] = 0x00;
    golden[84] = 0x00; golden[85] = 0x00; golden[86] = 0x00; golden[87] = 0x00;
    golden[88] = 0x01; // flags=IMMUTABLE
    golden[89] = 0x02; golden[90] = 0x00; // fragment_count=2 LE
    // reserved [91..97] = 0x00 (already zeroed)

    const result = unpackPointerCell(golden);
    expect(result.octave).toBe(1);
    expect(result.slot).toBe(42);
    expect(result.offset).toBe(1024);
    expect(result.contentHash).toEqual(new Uint8Array(32).fill(0xAA));
    expect(result.typeHash).toEqual(new Uint8Array(32).fill(0xBB));
    expect(result.totalSize).toBe(BigInt(2_000_000));
    expect(result.flags).toBe(0x01);
    expect(result.fragmentCount).toBe(2);

    // Also verify that packPointerCell produces the exact same bytes
    const repacked = packPointerCell(
      {
        octave: 1,
        slot: 42,
        offset: 1024,
        contentHash: new Uint8Array(32).fill(0xAA),
        typeHash: new Uint8Array(32).fill(0xBB),
        totalSize: BigInt(2_000_000),
        flags: PointerFlags.IMMUTABLE,
        fragmentCount: 2,
        reserved: new Uint8Array(7).fill(0),
      },
      1,
      1,
    );
    expect(repacked).toEqual(golden);
  });

  it("M4.4-T-constants: POINTER_CELL_TYPE=0x06, POINTER_PAYLOAD_SIZE=90", () => {
    expect(POINTER_CELL_TYPE).toBe(0x06);
    expect(POINTER_PAYLOAD_SIZE).toBe(90);
  });
});

```
