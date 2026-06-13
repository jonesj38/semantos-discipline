---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/constants/__tests__/constants.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.820259+00:00
---

# core/constants/__tests__/constants.test.ts

```ts
/**
 * D0.1 — Constants tests
 *
 * Expected values are hardcoded from the actual source files:
 *   - FORTH:SEMOBJ lines 23-26, 73-81
 *   - FORTH:COMMERCE lines 38-46, 51-54
 *   - FORTH:2PDA lines 16-18
 *   - PACKER:TYPE-REGISTRY buildCellHeader() offsets
 *   - PACKER:MAIN continuation types
 *
 * RED: These tests must pass by reading constants.json + generated output.
 * If any test fails, fix the code — never adjust the test.
 */

import { describe, test, expect } from "bun:test";
import { readFileSync, existsSync } from "fs";
import { join } from "path";
import { createHash } from "crypto";
import { execSync } from "child_process";

const ROOT = join(import.meta.dir, "../../..");
const CONSTANTS_JSON = join(import.meta.dir, "../constants.json");
const GENERATED_TS = join(ROOT, "core/protocol-types/src/constants.ts");
const GENERATED_ZIG = join(ROOT, "core/cell-engine/src/constants.zig");

function sha256File(path: string): string {
  return createHash("sha256").update(readFileSync(path)).digest("hex");
}

describe("constants.json schema and values", () => {
  test("exists and has all 13 required sections", () => {
    expect(existsSync(CONSTANTS_JSON)).toBe(true);
    const c = JSON.parse(readFileSync(CONSTANTS_JSON, "utf-8"));
    for (const key of ["protocol", "stacks", "magic", "linearity", "commercePhase",
      "taxonomyDimension", "cellType", "headerOffsets", "opcodeRanges",
      "domainFlags", "binding", "bca", "extensionPages"]) {
      expect(c).toHaveProperty(key);
    }
  });

  test("extensionPages: tessera page + 7 hat sub-pages unique under 0x000104xx", () => {
    const { extensionPages } = JSON.parse(readFileSync(CONSTANTS_JSON, "utf-8"));
    const expected = {
      TESSERA_PAGE: 0x00010400,
      TESSERA_HAT_PRODUCER: 0x00010401,
      TESSERA_HAT_FIELD_WORKER: 0x0001041A,
      TESSERA_HAT_DISTRIBUTOR: 0x00010402,
      TESSERA_HAT_DOCK_HANDLER: 0x0001042A,
      TESSERA_HAT_RETAILER: 0x00010403,
      TESSERA_HAT_CLUB_MEMBER: 0x00010404,
      TESSERA_HAT_CONSUMER: 0x00010405,
    };
    const values = new Set<number>();
    for (const [k, expectedValue] of Object.entries(expected)) {
      const actual = parseInt(String(extensionPages[k]), 16);
      expect(actual).toBe(expectedValue);
      // All tessera flags share the 0x000104 page prefix.
      expect(actual & 0xffffff00).toBe(0x00010400);
      // Hat byte fits in low byte.
      expect(actual & 0xff).toBeLessThanOrEqual(0xff);
      // Uniqueness: no two hats share a value.
      expect(values.has(actual)).toBe(false);
      values.add(actual);
    }
  });

  // From FORTH:SEMOBJ lines 73-75
  test("protocol: cellSize=1024, headerSize=256, payloadSize=768", () => {
    const { protocol } = JSON.parse(readFileSync(CONSTANTS_JSON, "utf-8"));
    expect(protocol.cellSize).toBe(1024);
    expect(protocol.headerSize).toBe(256);
    expect(protocol.payloadSize).toBe(768);
    expect(protocol.continuationHeaderSize).toBe(8);
    expect(protocol.continuationPayloadSize).toBe(1016);
  });

  // From FORTH:2PDA lines 16-18
  test("stacks: mainStackCells=1024, auxStackCells=256", () => {
    const { stacks } = JSON.parse(readFileSync(CONSTANTS_JSON, "utf-8"));
    expect(stacks.mainStackCells).toBe(1024);
    expect(stacks.auxStackCells).toBe(256);
    expect(stacks.mainStackBytes).toBe(1024 * 1024);
    expect(stacks.auxStackBytes).toBe(256 * 1024);
  });

  // From FORTH:SEMOBJ lines 78-81
  test("magic: MAGIC_1=0xDEADBEEF through MAGIC_4=0x42424242", () => {
    const { magic } = JSON.parse(readFileSync(CONSTANTS_JSON, "utf-8"));
    expect(magic.MAGIC_1).toBe("0xDEADBEEF");
    expect(magic.MAGIC_2).toBe("0xCAFEBABE");
    expect(magic.MAGIC_3).toBe("0x13371337");
    expect(magic.MAGIC_4).toBe("0x42424242");
  });

  // From FORTH:SEMOBJ lines 23-26
  test("linearity: LINEAR=1, AFFINE=2, RELEVANT=3, DEBUG=4", () => {
    const { linearity } = JSON.parse(readFileSync(CONSTANTS_JSON, "utf-8"));
    expect(linearity.LINEAR).toBe(1);
    expect(linearity.AFFINE).toBe(2);
    expect(linearity.RELEVANT).toBe(3);
    expect(linearity.DEBUG).toBe(4);
  });

  // From PACKER:TYPE-REGISTRY buildCellHeader() lines 165-211
  test("headerOffsets match typeHashRegistry.ts packed wire format", () => {
    const { headerOffsets } = JSON.parse(readFileSync(CONSTANTS_JSON, "utf-8"));
    // Each offset/size verified against buildCellHeader() in typeHashRegistry.ts
    expect(headerOffsets.magic).toBe(0);
    expect(headerOffsets.magicSize).toBe(16);
    expect(headerOffsets.linearity).toBe(16);
    expect(headerOffsets.linearitySize).toBe(4);
    expect(headerOffsets.version).toBe(20);
    expect(headerOffsets.versionSize).toBe(4);
    expect(headerOffsets.flags).toBe(24);
    expect(headerOffsets.flagsSize).toBe(4);
    expect(headerOffsets.refCount).toBe(28);
    expect(headerOffsets.refCountSize).toBe(2);
    expect(headerOffsets.typeHash).toBe(30);
    expect(headerOffsets.typeHashSize).toBe(32);
    expect(headerOffsets.ownerId).toBe(62);
    expect(headerOffsets.ownerIdSize).toBe(16);
    expect(headerOffsets.timestamp).toBe(78);
    expect(headerOffsets.timestampSize).toBe(8);
    expect(headerOffsets.cellCount).toBe(86);
    expect(headerOffsets.payloadTotal).toBe(90);
    // RM-032b: bytes 94-95 (former commercePhase/commerceDimension)
    // are unnamed reserved. Chain fields kept at 96 / 128 under
    // non-commerce names.
    expect(headerOffsets.parentHash).toBe(96);
    expect(headerOffsets.parentHashSize).toBe(32);
    expect(headerOffsets.prevStateHash).toBe(128);
    expect(headerOffsets.prevStateHashSize).toBe(32);
    expect(headerOffsets.prevStateHash + headerOffsets.prevStateHashSize).toBe(160);
    // RM-023: domainPayloadRoot at offset 224, 32 bytes.
    expect(headerOffsets.domainPayloadRoot).toBe(224);
    expect(headerOffsets.domainPayloadRootSize).toBe(32);
  });
});

describe("generator idempotency", () => {
  test("produces both files and re-run is byte-identical", () => {
    execSync("bun run generate-constants", { cwd: ROOT });
    expect(existsSync(GENERATED_TS)).toBe(true);
    expect(existsSync(GENERATED_ZIG)).toBe(true);
    const tsHash1 = sha256File(GENERATED_TS);
    const zigHash1 = sha256File(GENERATED_ZIG);
    execSync("bun run generate-constants", { cwd: ROOT });
    expect(sha256File(GENERATED_TS)).toBe(tsHash1);
    expect(sha256File(GENERATED_ZIG)).toBe(zigHash1);
  });
});

describe("generated Zig output matches source values", () => {
  test("contains MAGIC_1 through MAGIC_4 with correct hex", () => {
    const zig = readFileSync(GENERATED_ZIG, "utf-8");
    expect(zig).toContain("pub const MAGIC_1: u32 = 0xDEADBEEF;");
    expect(zig).toContain("pub const MAGIC_2: u32 = 0xCAFEBABE;");
    expect(zig).toContain("pub const MAGIC_3: u32 = 0x13371337;");
    expect(zig).toContain("pub const MAGIC_4: u32 = 0x42424242;");
  });

  test("contains CELL_SIZE=1024, HEADER_SIZE=256, PAYLOAD_SIZE=768", () => {
    const zig = readFileSync(GENERATED_ZIG, "utf-8");
    expect(zig).toContain("pub const CELL_SIZE: u32 = 1024;");
    expect(zig).toContain("pub const HEADER_SIZE: u32 = 256;");
    expect(zig).toContain("pub const PAYLOAD_SIZE: u32 = 768;");
  });

  test("contains HEADER_OFFSET_TYPE_HASH=30 (from typeHashRegistry.ts)", () => {
    const zig = readFileSync(GENERATED_ZIG, "utf-8");
    expect(zig).toContain("pub const HEADER_OFFSET_TYPE_HASH: u16 = 30;");
    expect(zig).toContain("pub const HEADER_OFFSET_LINEARITY: u16 = 16;");
  });

  // Opcodes section — the named Plexus/hostcall opcodes that the Zig executor
  // dispatches on (plexus.zig 0xC6/0xC7/0xC8, executor.zig 0xD0). These live in
  // constants.json as decimal and must be emitted verbatim (SCREAMING_SNAKE, u8)
  // so constants.zig is the single source of truth, exactly like OP_BRANCHONOUTPUT.
  test("contains named opcodes OP_CHECKDOMAINFLAG=198 … OP_CALLHOST=208", () => {
    const zig = readFileSync(GENERATED_ZIG, "utf-8");
    expect(zig).toContain("pub const OP_CHECKDOMAINFLAG: u8 = 198;");
    expect(zig).toContain("pub const OP_CHECKTYPEHASH: u8 = 199;");
    expect(zig).toContain("pub const OP_DEREF_POINTER: u8 = 200;");
    expect(zig).toContain("pub const OP_CALLHOST: u8 = 208;");
  });

  // The opcodes section values must match the published opcode ranges:
  // CHECK*/DEREF live in the Plexus range [192,207]; CALLHOST in hostcall [208,223].
  test("opcode values fall in their declared ranges (plexus / hostcall)", () => {
    const { opcodes, opcodeRanges } = JSON.parse(readFileSync(CONSTANTS_JSON, "utf-8"));
    expect(opcodes.OP_CHECKDOMAINFLAG).toBeGreaterThanOrEqual(opcodeRanges.plexusMin);
    expect(opcodes.OP_CHECKDOMAINFLAG).toBeLessThanOrEqual(opcodeRanges.plexusMax);
    expect(opcodes.OP_CHECKTYPEHASH).toBeLessThanOrEqual(opcodeRanges.plexusMax);
    expect(opcodes.OP_DEREF_POINTER).toBeLessThanOrEqual(opcodeRanges.plexusMax);
    expect(opcodes.OP_CALLHOST).toBe(opcodeRanges.hostCallMin);
  });
});

```
