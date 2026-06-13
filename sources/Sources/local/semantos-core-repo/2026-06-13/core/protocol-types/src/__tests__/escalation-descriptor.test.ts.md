---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/__tests__/escalation-descriptor.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.886974+00:00
---

# core/protocol-types/src/__tests__/escalation-descriptor.test.ts

```ts
/**
 * Tests for the escalation-descriptor TS oracle.
 *
 * Spec: docs/design/OCTAVE-ESCALATION-UNIFICATION.md §5
 * Oracle: core/protocol-types/src/escalation-descriptor.ts
 * Mirror: core/cell-engine/src/escalation_descriptor.zig
 *
 * Run: bun test src/__tests__/escalation-descriptor.test.ts
 *      (or `bun test` from core/protocol-types with the full suite)
 */

import { describe, test, expect } from "bun:test";
import {
  ESCALATION_DESCRIPTOR_SIZE,
  EscalationDescriptorOffsets,
  PAYLOAD_OFFSET,
  TYPED_SEGMENTS_HEADER_SIZE,
  Rung,
  OctaveLevel,
  readRung,
  writeRung,
  readOctaveLevel,
  writeOctaveLevel,
  readChildCount,
  writeChildCount,
  readTotalBytes,
  writeTotalBytes,
  readDescriptor,
  writeDescriptor,
  escalationDescriptorOffsetUnrouted,
  escalationDescriptorOffsetRouted,
  CANONICAL_DESCRIPTOR_BYTES,
  CANONICAL_TOTAL_BYTES,
} from "../escalation-descriptor";

// ── Layout constants ──────────────────────────────────────────────────────────
describe("ESCALATION_DESCRIPTOR_SIZE", () => {
  test("is 16 bytes", () => {
    expect(ESCALATION_DESCRIPTOR_SIZE).toBe(16);
  });
});

describe("EscalationDescriptorOffsets", () => {
  test("rung at offset 0, size 1", () => {
    expect(EscalationDescriptorOffsets.rung).toBe(0);
    expect(EscalationDescriptorOffsets.rungSize).toBe(1);
  });
  test("octaveLevel at offset 1, size 1", () => {
    expect(EscalationDescriptorOffsets.octaveLevel).toBe(1);
    expect(EscalationDescriptorOffsets.octaveLevelSize).toBe(1);
  });
  test("childCount at offset 2, size 2", () => {
    expect(EscalationDescriptorOffsets.childCount).toBe(2);
    expect(EscalationDescriptorOffsets.childCountSize).toBe(2);
  });
  test("totalBytes at offset 4, size 8", () => {
    expect(EscalationDescriptorOffsets.totalBytes).toBe(4);
    expect(EscalationDescriptorOffsets.totalBytesSize).toBe(8);
  });
  test("reserved at offset 12, size 4", () => {
    expect(EscalationDescriptorOffsets.reserved).toBe(12);
    expect(EscalationDescriptorOffsets.reservedSize).toBe(4);
  });
  test("offsets sum to 16 bytes total", () => {
    const total =
      EscalationDescriptorOffsets.rungSize +
      EscalationDescriptorOffsets.octaveLevelSize +
      EscalationDescriptorOffsets.childCountSize +
      EscalationDescriptorOffsets.totalBytesSize +
      EscalationDescriptorOffsets.reservedSize;
    expect(total).toBe(ESCALATION_DESCRIPTOR_SIZE);
  });
});

// ── Rung enum ────────────────────────────────────────────────────────────────
describe("Rung enum", () => {
  test("INLINE = 0", () => {
    expect(Rung.INLINE).toBe(0);
  });
  test("OCTAVE_ESCALATED = 1", () => {
    expect(Rung.OCTAVE_ESCALATED).toBe(1);
  });
  test("MERKLE_ROOTED_HIERARCHY = 2", () => {
    expect(Rung.MERKLE_ROOTED_HIERARCHY).toBe(2);
  });
  test("all rung values are 0, 1, 2", () => {
    const vals = Object.values(Rung).sort();
    expect(vals).toEqual([0, 1, 2]);
  });
});

// ── OctaveLevel enum ─────────────────────────────────────────────────────────
describe("OctaveLevel enum", () => {
  test("BASE = 0 (1 KiB)", () => {
    expect(OctaveLevel.BASE).toBe(0);
  });
  test("KILO = 1 (1 MiB)", () => {
    expect(OctaveLevel.KILO).toBe(1);
  });
  test("MEGA = 2 (1 GiB)", () => {
    expect(OctaveLevel.MEGA).toBe(2);
  });
  test("GIGA = 3 (1 TiB)", () => {
    expect(OctaveLevel.GIGA).toBe(3);
  });
  test("all octave level values are 0..3", () => {
    const vals = Object.values(OctaveLevel).sort();
    expect(vals).toEqual([0, 1, 2, 3]);
  });
});

// ── Offset helpers ────────────────────────────────────────────────────────────
describe("escalationDescriptorOffsetUnrouted", () => {
  test("returns PAYLOAD_OFFSET (256)", () => {
    expect(escalationDescriptorOffsetUnrouted()).toBe(PAYLOAD_OFFSET);
    expect(escalationDescriptorOffsetUnrouted()).toBe(256);
  });
});

describe("escalationDescriptorOffsetRouted", () => {
  test("returns PAYLOAD_OFFSET + TYPED_SEGMENTS_HEADER_SIZE (260)", () => {
    expect(escalationDescriptorOffsetRouted()).toBe(PAYLOAD_OFFSET + TYPED_SEGMENTS_HEADER_SIZE);
    expect(escalationDescriptorOffsetRouted()).toBe(260);
  });
  test("same result regardless of payloadStartsAt argument (unused param, documented)", () => {
    expect(escalationDescriptorOffsetRouted(0)).toBe(260);
    expect(escalationDescriptorOffsetRouted(512)).toBe(260);
  });
  test("descriptor ends at 276 (260 + 16)", () => {
    expect(escalationDescriptorOffsetRouted() + ESCALATION_DESCRIPTOR_SIZE).toBe(276);
  });
});

// ── rung read/write ───────────────────────────────────────────────────────────
describe("readRung / writeRung", () => {
  test("round-trip INLINE (0)", () => {
    const buf = new Uint8Array(ESCALATION_DESCRIPTOR_SIZE);
    writeRung(buf, 0, Rung.INLINE);
    expect(readRung(buf, 0)).toBe(Rung.INLINE);
  });
  test("round-trip OCTAVE_ESCALATED (1)", () => {
    const buf = new Uint8Array(ESCALATION_DESCRIPTOR_SIZE);
    writeRung(buf, 0, Rung.OCTAVE_ESCALATED);
    expect(readRung(buf, 0)).toBe(Rung.OCTAVE_ESCALATED);
  });
  test("round-trip MERKLE_ROOTED_HIERARCHY (2)", () => {
    const buf = new Uint8Array(ESCALATION_DESCRIPTOR_SIZE);
    writeRung(buf, 0, Rung.MERKLE_ROOTED_HIERARCHY);
    expect(readRung(buf, 0)).toBe(Rung.MERKLE_ROOTED_HIERARCHY);
  });
  test("written byte lands at the correct offset within a larger buffer", () => {
    const buf = new Uint8Array(64);
    const base = 16;
    writeRung(buf, base, Rung.OCTAVE_ESCALATED);
    expect(buf[base + EscalationDescriptorOffsets.rung]).toBe(1);
  });
  test("masks high bits (u8 truncation)", () => {
    const buf = new Uint8Array(ESCALATION_DESCRIPTOR_SIZE);
    writeRung(buf, 0, (0x101 as unknown) as Rung); // 257 & 0xff == 1
    expect(buf[0]).toBe(1);
  });
});

// ── octaveLevel read/write ────────────────────────────────────────────────────
describe("readOctaveLevel / writeOctaveLevel", () => {
  test("round-trip BASE (0)", () => {
    const buf = new Uint8Array(ESCALATION_DESCRIPTOR_SIZE);
    writeOctaveLevel(buf, 0, OctaveLevel.BASE);
    expect(readOctaveLevel(buf, 0)).toBe(OctaveLevel.BASE);
  });
  test("round-trip KILO (1)", () => {
    const buf = new Uint8Array(ESCALATION_DESCRIPTOR_SIZE);
    writeOctaveLevel(buf, 0, OctaveLevel.KILO);
    expect(readOctaveLevel(buf, 0)).toBe(OctaveLevel.KILO);
  });
  test("round-trip MEGA (2)", () => {
    const buf = new Uint8Array(ESCALATION_DESCRIPTOR_SIZE);
    writeOctaveLevel(buf, 0, OctaveLevel.MEGA);
    expect(readOctaveLevel(buf, 0)).toBe(OctaveLevel.MEGA);
  });
  test("round-trip GIGA (3)", () => {
    const buf = new Uint8Array(ESCALATION_DESCRIPTOR_SIZE);
    writeOctaveLevel(buf, 0, OctaveLevel.GIGA);
    expect(readOctaveLevel(buf, 0)).toBe(OctaveLevel.GIGA);
  });
  test("written byte at correct offset (1)", () => {
    const buf = new Uint8Array(64);
    const base = 0;
    writeOctaveLevel(buf, base, OctaveLevel.GIGA);
    expect(buf[base + EscalationDescriptorOffsets.octaveLevel]).toBe(3);
  });
});

// ── childCount read/write ─────────────────────────────────────────────────────
describe("readChildCount / writeChildCount", () => {
  test("round-trip 0", () => {
    const buf = new Uint8Array(ESCALATION_DESCRIPTOR_SIZE);
    writeChildCount(buf, 0, 0);
    expect(readChildCount(buf, 0)).toBe(0);
  });
  test("round-trip 1", () => {
    const buf = new Uint8Array(ESCALATION_DESCRIPTOR_SIZE);
    writeChildCount(buf, 0, 1);
    expect(readChildCount(buf, 0)).toBe(1);
  });
  test("round-trip 1024", () => {
    const buf = new Uint8Array(ESCALATION_DESCRIPTOR_SIZE);
    writeChildCount(buf, 0, 1024);
    expect(readChildCount(buf, 0)).toBe(1024);
  });
  test("round-trip u16 max (65535)", () => {
    const buf = new Uint8Array(ESCALATION_DESCRIPTOR_SIZE);
    writeChildCount(buf, 0, 0xffff);
    expect(readChildCount(buf, 0)).toBe(0xffff);
  });
  test("stored little-endian — low byte first", () => {
    const buf = new Uint8Array(ESCALATION_DESCRIPTOR_SIZE);
    writeChildCount(buf, 0, 0x0307); // low=0x07, high=0x03
    expect(buf[EscalationDescriptorOffsets.childCount]).toBe(0x07); // low byte
    expect(buf[EscalationDescriptorOffsets.childCount + 1]).toBe(0x03); // high byte
  });
});

// ── totalBytes read/write ─────────────────────────────────────────────────────
describe("readTotalBytes / writeTotalBytes", () => {
  test("round-trip 0n", () => {
    const buf = new Uint8Array(ESCALATION_DESCRIPTOR_SIZE);
    writeTotalBytes(buf, 0, 0n);
    expect(readTotalBytes(buf, 0)).toBe(0n);
  });
  test("round-trip 1n", () => {
    const buf = new Uint8Array(ESCALATION_DESCRIPTOR_SIZE);
    writeTotalBytes(buf, 0, 1n);
    expect(readTotalBytes(buf, 0)).toBe(1n);
  });
  test("round-trip 1024n (1 KiB)", () => {
    const buf = new Uint8Array(ESCALATION_DESCRIPTOR_SIZE);
    writeTotalBytes(buf, 0, 1024n);
    expect(readTotalBytes(buf, 0)).toBe(1024n);
  });
  test("round-trip 1 MiB (octave-1 cell size)", () => {
    const mib = BigInt(1024 * 1024);
    const buf = new Uint8Array(ESCALATION_DESCRIPTOR_SIZE);
    writeTotalBytes(buf, 0, mib);
    expect(readTotalBytes(buf, 0)).toBe(mib);
  });
  test("round-trip 1 GiB (octave-2 cell size)", () => {
    const gib = BigInt(1024 * 1024 * 1024);
    const buf = new Uint8Array(ESCALATION_DESCRIPTOR_SIZE);
    writeTotalBytes(buf, 0, gib);
    expect(readTotalBytes(buf, 0)).toBe(gib);
  });
  test("round-trip 1 TiB (octave-3 cell size)", () => {
    const tib = BigInt(1024) ** 4n;
    const buf = new Uint8Array(ESCALATION_DESCRIPTOR_SIZE);
    writeTotalBytes(buf, 0, tib);
    expect(readTotalBytes(buf, 0)).toBe(tib);
  });
  test("round-trip u64 max (2^64 - 1)", () => {
    const u64Max = 0xffff_ffff_ffff_ffffn;
    const buf = new Uint8Array(ESCALATION_DESCRIPTOR_SIZE);
    writeTotalBytes(buf, 0, u64Max);
    expect(readTotalBytes(buf, 0)).toBe(u64Max);
  });
  test("little-endian encoding — LSB first", () => {
    // 0x0102_0304_0506_0708 → bytes [0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01]
    const val = 0x0102_0304_0506_0708n;
    const buf = new Uint8Array(ESCALATION_DESCRIPTOR_SIZE);
    writeTotalBytes(buf, 0, val);
    const base = EscalationDescriptorOffsets.totalBytes;
    expect(buf[base + 0]).toBe(0x08); // LSB
    expect(buf[base + 1]).toBe(0x07);
    expect(buf[base + 2]).toBe(0x06);
    expect(buf[base + 3]).toBe(0x05);
    expect(buf[base + 4]).toBe(0x04);
    expect(buf[base + 5]).toBe(0x03);
    expect(buf[base + 6]).toBe(0x02);
    expect(buf[base + 7]).toBe(0x01); // MSB
  });
});

// ── Composite writeDescriptor / readDescriptor ────────────────────────────────
describe("writeDescriptor / readDescriptor (round-trip)", () => {
  test("inline rung round-trip", () => {
    const buf = new Uint8Array(ESCALATION_DESCRIPTOR_SIZE);
    writeDescriptor(buf, 0, {
      rung: Rung.INLINE,
      octaveLevel: OctaveLevel.BASE,
      childCount: 0,
      totalBytes: 512n,
    });
    const d = readDescriptor(buf, 0);
    expect(d.rung).toBe(Rung.INLINE);
    expect(d.octaveLevel).toBe(OctaveLevel.BASE);
    expect(d.childCount).toBe(0);
    expect(d.totalBytes).toBe(512n);
    expect(d.reserved).toBe(0);
  });

  test("octave-escalated rung round-trip", () => {
    const buf = new Uint8Array(ESCALATION_DESCRIPTOR_SIZE);
    writeDescriptor(buf, 0, {
      rung: Rung.OCTAVE_ESCALATED,
      octaveLevel: OctaveLevel.KILO,
      childCount: 1,
      totalBytes: BigInt(1024 * 1024),
    });
    const d = readDescriptor(buf, 0);
    expect(d.rung).toBe(Rung.OCTAVE_ESCALATED);
    expect(d.octaveLevel).toBe(OctaveLevel.KILO);
    expect(d.childCount).toBe(1);
    expect(d.totalBytes).toBe(BigInt(1024 * 1024));
    expect(d.reserved).toBe(0);
  });

  test("merkle-rooted-hierarchy rung round-trip", () => {
    const buf = new Uint8Array(ESCALATION_DESCRIPTOR_SIZE);
    writeDescriptor(buf, 0, {
      rung: Rung.MERKLE_ROOTED_HIERARCHY,
      octaveLevel: OctaveLevel.MEGA,
      childCount: 1024,
      totalBytes: BigInt(1024) ** 4n, // 1 TiB
    });
    const d = readDescriptor(buf, 0);
    expect(d.rung).toBe(Rung.MERKLE_ROOTED_HIERARCHY);
    expect(d.octaveLevel).toBe(OctaveLevel.MEGA);
    expect(d.childCount).toBe(1024);
    expect(d.totalBytes).toBe(BigInt(1024) ** 4n);
    expect(d.reserved).toBe(0);
  });

  test("reserved is always written as 0 regardless of input buffer state", () => {
    // Pre-fill buffer with 0xff to ensure reserved is zeroed by writeDescriptor.
    const buf = new Uint8Array(ESCALATION_DESCRIPTOR_SIZE).fill(0xff);
    writeDescriptor(buf, 0, {
      rung: Rung.INLINE,
      octaveLevel: OctaveLevel.BASE,
      childCount: 0,
      totalBytes: 0n,
    });
    const d = readDescriptor(buf, 0);
    expect(d.reserved).toBe(0);
    // Verify reserved bytes directly.
    const base = EscalationDescriptorOffsets.reserved;
    expect(buf[base]).toBe(0);
    expect(buf[base + 1]).toBe(0);
    expect(buf[base + 2]).toBe(0);
    expect(buf[base + 3]).toBe(0);
  });

  test("write at non-zero offset in a larger buffer", () => {
    const OFFSET = 256; // simulate unrouted data cell position in a full cell
    const buf = new Uint8Array(1024);
    writeDescriptor(buf, OFFSET, {
      rung: Rung.OCTAVE_ESCALATED,
      octaveLevel: OctaveLevel.GIGA,
      childCount: 7,
      totalBytes: CANONICAL_TOTAL_BYTES,
    });
    const d = readDescriptor(buf, OFFSET);
    expect(d.rung).toBe(Rung.OCTAVE_ESCALATED);
    expect(d.octaveLevel).toBe(OctaveLevel.GIGA);
    expect(d.childCount).toBe(7);
    expect(d.totalBytes).toBe(CANONICAL_TOTAL_BYTES);
    expect(d.reserved).toBe(0);
  });

  test("writeDescriptor / readDescriptor at routed offset (260)", () => {
    const OFFSET = escalationDescriptorOffsetRouted();
    const buf = new Uint8Array(1024);
    writeDescriptor(buf, OFFSET, {
      rung: Rung.MERKLE_ROOTED_HIERARCHY,
      octaveLevel: OctaveLevel.KILO,
      childCount: 3,
      totalBytes: 3n * BigInt(1024 * 1024),
    });
    const d = readDescriptor(buf, OFFSET);
    expect(d.rung).toBe(Rung.MERKLE_ROOTED_HIERARCHY);
    expect(d.octaveLevel).toBe(OctaveLevel.KILO);
    expect(d.childCount).toBe(3);
    expect(d.totalBytes).toBe(3n * BigInt(1024 * 1024));
  });

  test("throws when buffer is too small at given offset", () => {
    const buf = new Uint8Array(10);
    expect(() => writeDescriptor(buf, 0, {
      rung: Rung.INLINE,
      octaveLevel: OctaveLevel.BASE,
      childCount: 0,
      totalBytes: 0n,
    })).toThrow();
    expect(() => readDescriptor(buf, 0)).toThrow();
  });
});

// ── Canonical byte vector ─────────────────────────────────────────────────────
describe("CANONICAL_DESCRIPTOR_BYTES / CANONICAL_TOTAL_BYTES", () => {
  test("CANONICAL_DESCRIPTOR_BYTES is exactly 16 bytes", () => {
    expect(CANONICAL_DESCRIPTOR_BYTES.length).toBe(ESCALATION_DESCRIPTOR_SIZE);
  });

  test("canonical byte vector matches expected hand-encoded values", () => {
    // rung = 0x01 (OCTAVE_ESCALATED)
    expect(CANONICAL_DESCRIPTOR_BYTES[0]).toBe(0x01);
    // octave_level = 0x02 (MEGA)
    expect(CANONICAL_DESCRIPTOR_BYTES[1]).toBe(0x02);
    // child_count = 7 (u16 LE: 0x07 0x00)
    expect(CANONICAL_DESCRIPTOR_BYTES[2]).toBe(0x07);
    expect(CANONICAL_DESCRIPTOR_BYTES[3]).toBe(0x00);
    // total_bytes = 0x0000_0ABC_DEF0_1234 (u64 LE)
    expect(CANONICAL_DESCRIPTOR_BYTES[4]).toBe(0x34);
    expect(CANONICAL_DESCRIPTOR_BYTES[5]).toBe(0x12);
    expect(CANONICAL_DESCRIPTOR_BYTES[6]).toBe(0xf0);
    expect(CANONICAL_DESCRIPTOR_BYTES[7]).toBe(0xde);
    expect(CANONICAL_DESCRIPTOR_BYTES[8]).toBe(0xbc);
    expect(CANONICAL_DESCRIPTOR_BYTES[9]).toBe(0x0a);
    expect(CANONICAL_DESCRIPTOR_BYTES[10]).toBe(0x00);
    expect(CANONICAL_DESCRIPTOR_BYTES[11]).toBe(0x00);
    // reserved = 0x00 0x00 0x00 0x00
    expect(CANONICAL_DESCRIPTOR_BYTES[12]).toBe(0x00);
    expect(CANONICAL_DESCRIPTOR_BYTES[13]).toBe(0x00);
    expect(CANONICAL_DESCRIPTOR_BYTES[14]).toBe(0x00);
    expect(CANONICAL_DESCRIPTOR_BYTES[15]).toBe(0x00);
  });

  test("CANONICAL_TOTAL_BYTES matches the value encoded in CANONICAL_DESCRIPTOR_BYTES", () => {
    expect(CANONICAL_TOTAL_BYTES).toBe(BigInt("0x00000ABCDEF01234"));
    // Read it back from the canonical bytes to confirm round-trip.
    expect(readTotalBytes(CANONICAL_DESCRIPTOR_BYTES, 0)).toBe(CANONICAL_TOTAL_BYTES);
  });

  test("canonical bytes decode correctly via readDescriptor", () => {
    // Copy into a writable buffer at offset 0 for readDescriptor.
    const buf = new Uint8Array(ESCALATION_DESCRIPTOR_SIZE);
    buf.set(CANONICAL_DESCRIPTOR_BYTES);
    const d = readDescriptor(buf, 0);
    expect(d.rung).toBe(Rung.OCTAVE_ESCALATED);
    expect(d.octaveLevel).toBe(OctaveLevel.MEGA);
    expect(d.childCount).toBe(7);
    expect(d.totalBytes).toBe(CANONICAL_TOTAL_BYTES);
    expect(d.reserved).toBe(0);
  });

  test("writeDescriptor produces canonical byte vector byte-for-byte", () => {
    const buf = new Uint8Array(ESCALATION_DESCRIPTOR_SIZE);
    writeDescriptor(buf, 0, {
      rung: Rung.OCTAVE_ESCALATED,
      octaveLevel: OctaveLevel.MEGA,
      childCount: 7,
      totalBytes: CANONICAL_TOTAL_BYTES,
    });
    for (let i = 0; i < ESCALATION_DESCRIPTOR_SIZE; i++) {
      expect(buf[i]).toBe(CANONICAL_DESCRIPTOR_BYTES[i]);
    }
  });
});

// ── Cell-level integration with offset helpers ────────────────────────────────
describe("integration — write + read at cell offsets", () => {
  test("unrouted data cell: descriptor at offset 256 in a 1024-byte cell", () => {
    const cell = new Uint8Array(1024);
    const off = escalationDescriptorOffsetUnrouted(); // 256
    writeDescriptor(cell, off, {
      rung: Rung.OCTAVE_ESCALATED,
      octaveLevel: OctaveLevel.KILO,
      childCount: 2,
      totalBytes: 2n * BigInt(1024 * 1024),
    });
    // Verify header region is untouched.
    expect(cell[0]).toBe(0);
    expect(cell[255]).toBe(0);
    const d = readDescriptor(cell, off);
    expect(d.rung).toBe(Rung.OCTAVE_ESCALATED);
    expect(d.octaveLevel).toBe(OctaveLevel.KILO);
    expect(d.childCount).toBe(2);
    expect(d.totalBytes).toBe(2n * BigInt(1024 * 1024));
  });

  test("routed cell: descriptor at offset 260 does not clobber typed-segments header at 256-259", () => {
    const cell = new Uint8Array(1024);
    // Write typed-segments header sentinel values at 256-259.
    cell[256] = 0x03; // segment count = 3 (low byte)
    cell[257] = 0x00; // segment count = 3 (high byte)
    cell[258] = 0x10; // payloadStartsAt = 0x0010 (low byte)
    cell[259] = 0x00; // payloadStartsAt = 0x0010 (high byte)

    const off = escalationDescriptorOffsetRouted(); // 260
    writeDescriptor(cell, off, {
      rung: Rung.MERKLE_ROOTED_HIERARCHY,
      octaveLevel: OctaveLevel.MEGA,
      childCount: 1024,
      totalBytes: BigInt(1024) ** 3n,
    });
    // Typed-segments header must be untouched.
    expect(cell[256]).toBe(0x03);
    expect(cell[257]).toBe(0x00);
    expect(cell[258]).toBe(0x10);
    expect(cell[259]).toBe(0x00);
    // Descriptor round-trips correctly.
    const d = readDescriptor(cell, off);
    expect(d.rung).toBe(Rung.MERKLE_ROOTED_HIERARCHY);
    expect(d.octaveLevel).toBe(OctaveLevel.MEGA);
    expect(d.childCount).toBe(1024);
    expect(d.totalBytes).toBe(BigInt(1024) ** 3n);
  });
});

```
