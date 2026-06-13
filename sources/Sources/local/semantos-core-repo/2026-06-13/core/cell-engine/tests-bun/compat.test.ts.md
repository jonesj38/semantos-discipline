---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests-bun/compat.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.989848+00:00
---

# core/cell-engine/tests-bun/compat.test.ts

```ts
/**
 * Cross-language compatibility tests — Phase 1
 *
 * Verifies that Zig-packed cells (via WASM) produce byte-identical output
 * to the TypeScript packer, and that each can unpack the other's output.
 */

import { describe, test, expect } from "bun:test";
import { readFileSync } from "fs";
import { join } from "path";
import {
  buildCellHeader,
  packCell,
  unpackCell,
  isValidCell,
  computeTypeHash,
  LINEARITY,
  packMultiCell,
  unpackMultiCell,
  CONTINUATION_TYPE,
  type PipelinePhase,
  type Dimension,
} from "@semantos/cell-ops";

// ── Load WASM ──

const WASM_PATH = join(import.meta.dir, "../zig-out/bin/cell-engine.wasm");

let wasmInstance: WebAssembly.Instance;
let wasmMemory: WebAssembly.Memory;

// Host function stubs for WASM imports
const hostImports = {
  host: {
    host_sha256: () => {},
    host_hash160: () => {},
    host_hash256: () => {},
    host_checksig: () => 0,
    host_checkmultisig: () => 0,
    host_get_blocktime: () => 0,
    host_get_sequence: () => 0,
    host_log: () => {},
    host_fetch_cell: () => 0,
    host_call_by_name: () => 0xFFFFFFFF,
  },
};

async function loadWasm(): Promise<void> {
  const wasmBytes = readFileSync(WASM_PATH);
  const result = await WebAssembly.instantiate(wasmBytes, hostImports);
  wasmInstance = result.instance;
  wasmMemory = wasmInstance.exports.memory as WebAssembly.Memory;
}

// ── Test data (must match generate-vectors.ts exactly) ──

const FIXED_TIMESTAMP = BigInt(1700000000000);
const TYPE_HASH = computeTypeHash(
  "services.trades.carpentry",
  "hire",
  "inst.contract.service-agreement"
);
const OWNER_ID = Buffer.alloc(16, 0);
Buffer.from("0123456789abcdef", "hex").copy(OWNER_ID, 0, 0, 8);

function buildHeaderDeterministic(opts: {
  linearity: number;
  phase: PipelinePhase;
  dimension: Dimension;
  payloadSize: number;
  parentHash?: Buffer;
  prevStateHash?: Buffer;
}): Buffer {
  const origDateNow = Date.now;
  Date.now = () => Number(FIXED_TIMESTAMP);
  try {
    return buildCellHeader({
      typeHash: TYPE_HASH,
      linearity: opts.linearity as any,
      ownerId: OWNER_ID,
      phase: opts.phase,
      dimension: opts.dimension,
      parentHash: opts.parentHash,
      prevStateHash: opts.prevStateHash,
      payloadSize: opts.payloadSize,
    });
  } finally {
    Date.now = origDateNow;
  }
}

// ── Vectors ──

const VECTORS_DIR = join(import.meta.dir, "../tests/vectors");

function loadVector(name: string): Buffer {
  return readFileSync(join(VECTORS_DIR, `${name}.bin`));
}

// ── WASM helpers ──

function zigPackCell(headerBuf: Buffer, payload: Buffer): Buffer {
  const cell_pack = wasmInstance.exports.cell_pack as Function;
  const mem = new Uint8Array(wasmMemory.buffer);

  // Write header at offset 0
  const headerOffset = 1024; // well past any stack
  const payloadOffset = headerOffset + 256;
  const outOffset = payloadOffset + 768;

  mem.set(headerBuf, headerOffset);
  mem.set(payload, payloadOffset);

  const result = cell_pack(headerOffset, payloadOffset, payload.length, outOffset);
  if (result !== 0) throw new Error(`cell_pack returned error: ${result}`);

  return Buffer.from(mem.slice(outOffset, outOffset + 1024));
}

function zigValidateMagic(cellBuf: Buffer): boolean {
  const cell_validate_magic = wasmInstance.exports.cell_validate_magic as Function;
  const mem = new Uint8Array(wasmMemory.buffer);
  const offset = 1024;
  mem.set(cellBuf, offset);
  return cell_validate_magic(offset) === 1;
}

// ── Tests ──

describe("Cross-language cell packing", () => {
  test("WASM loads successfully", async () => {
    await loadWasm();
    expect(wasmInstance).toBeDefined();
    expect(wasmInstance.exports.cell_pack).toBeDefined();
    expect(wasmInstance.exports.cell_unpack).toBeDefined();
    expect(wasmInstance.exports.cell_validate_magic).toBeDefined();
  });

  test("Zig packCell output matches TypeScript packCell output (LINEAR)", async () => {
    await loadWasm();

    const header = buildHeaderDeterministic({
      linearity: LINEARITY.LINEAR,
      phase: "parse",
      dimension: "what",
      payloadSize: 32,
    });

    const payload = Buffer.alloc(32);
    for (let i = 0; i < 32; i++) payload[i] = i;

    const tsOutput = packCell(header, payload);
    const zigOutput = zigPackCell(header, payload);

    expect(zigOutput.length).toBe(1024);
    expect(tsOutput.length).toBe(1024);
    expect(zigOutput.equals(tsOutput)).toBe(true);
  });

  test("Zig packCell matches single_cell_linear.bin vector", async () => {
    await loadWasm();

    const expected = loadVector("single_cell_linear");
    const header = buildHeaderDeterministic({
      linearity: LINEARITY.LINEAR,
      phase: "parse",
      dimension: "what",
      payloadSize: 32,
    });

    const payload = Buffer.alloc(32);
    for (let i = 0; i < 32; i++) payload[i] = i;

    const zigOutput = zigPackCell(header, payload);
    expect(zigOutput.equals(expected)).toBe(true);
  });

  test("TypeScript can unpack Zig-packed cells", async () => {
    await loadWasm();

    const header = buildHeaderDeterministic({
      linearity: LINEARITY.AFFINE,
      phase: "ast",
      dimension: "composite",
      payloadSize: 100,
    });

    const payload = Buffer.alloc(100);
    for (let i = 0; i < 100; i++) payload[i] = (i * 3) & 0xFF;

    const zigOutput = zigPackCell(header, payload);

    // TS should be able to unpack it
    expect(isValidCell(zigOutput)).toBe(true);
    const unpacked = unpackCell(zigOutput);
    expect(unpacked.header.linearity).toBe(LINEARITY.AFFINE);
    expect(unpacked.header.totalSize).toBe(100);
    expect(unpacked.payload.length).toBe(100);
    expect(unpacked.payload.equals(payload)).toBe(true);
  });

  test("Zig validates magic on TypeScript-packed cells", async () => {
    await loadWasm();

    const header = buildHeaderDeterministic({
      linearity: LINEARITY.RELEVANT,
      phase: "codegen",
      dimension: "instrument",
      payloadSize: 0,
    });

    const tsPacked = packCell(header, Buffer.alloc(0));
    expect(zigValidateMagic(tsPacked)).toBe(true);

    // Corrupt magic
    const corrupted = Buffer.from(tsPacked);
    corrupted[0] = 0xFF;
    expect(zigValidateMagic(corrupted)).toBe(false);
  });

  test("Full payload (768 bytes) byte-identical across languages", async () => {
    await loadWasm();

    const header = buildHeaderDeterministic({
      linearity: LINEARITY.AFFINE,
      phase: "ast",
      dimension: "composite",
      payloadSize: 768,
    });

    const payload = Buffer.alloc(768);
    for (let i = 0; i < 768; i++) payload[i] = i & 0xFF;

    const tsOutput = packCell(header, payload);
    const zigOutput = zigPackCell(header, payload);

    expect(zigOutput.equals(tsOutput)).toBe(true);
    expect(zigOutput.equals(loadVector("single_cell_affine"))).toBe(true);
  });

  test("Commerce extension fields preserved across languages", async () => {
    await loadWasm();

    const parentHash = Buffer.alloc(32, 0xAA);
    const prevState = Buffer.alloc(32, 0xBB);

    const header = buildHeaderDeterministic({
      linearity: LINEARITY.RELEVANT,
      phase: "codegen",
      dimension: "instrument",
      payloadSize: 256,
      parentHash,
      prevStateHash: prevState,
    });

    const payload = Buffer.alloc(256);
    for (let i = 0; i < 256; i++) payload[i] = i & 0xFF;

    const tsOutput = packCell(header, payload);
    const zigOutput = zigPackCell(header, payload);

    expect(zigOutput.equals(tsOutput)).toBe(true);
    expect(zigOutput.equals(loadVector("single_cell_relevant"))).toBe(true);

    // Verify TS can read the commerce fields from Zig output
    const unpacked = unpackCell(zigOutput);
    expect(unpacked.header.phase).toBe(0x05); // codegen
    expect(unpacked.header.dimension).toBe(0x03); // instrument
    expect(unpacked.header.parentHash.equals(parentHash)).toBe(true);
    expect(unpacked.header.prevStateHash.equals(prevState)).toBe(true);
  });
});

describe("Cross-language multi-cell packing", () => {
  test("WASM exports multicell_pack and multicell_unpack", async () => {
    await loadWasm();
    expect(wasmInstance.exports.multicell_pack).toBeDefined();
    expect(wasmInstance.exports.multicell_unpack).toBeDefined();
  });

  test("Zig multi-cell output matches TypeScript multi-cell output byte-for-byte", async () => {
    await loadWasm();

    // Same inputs as multi_cell_3 vector
    const header = buildHeaderDeterministic({
      linearity: LINEARITY.LINEAR,
      phase: "action",
      dimension: "how",
      payloadSize: 512,
    });

    const payload = Buffer.alloc(512);
    for (let i = 0; i < 512; i++) payload[i] = i & 0xFF;

    const bumpData = Buffer.alloc(330, 0x42);
    const dataPayload = Buffer.alloc(200, 0xDD);

    // Pack with TypeScript
    const tsResult = packMultiCell({
      header,
      payload,
      continuations: [
        { type: CONTINUATION_TYPE.BUMP, data: bumpData },
        { type: CONTINUATION_TYPE.DATA, data: dataPayload },
      ],
    });

    // Pack with Zig via WASM
    const multicell_pack_fn = wasmInstance.exports.multicell_pack as Function;
    const mem = new Uint8Array(wasmMemory.buffer);

    // Layout in WASM memory:
    // 4096: header (256 bytes)
    // 4352: payload (512 bytes)
    // 4864: cont_types (2 bytes)
    // 4866: cont_offsets (2 * 4 = 8 bytes)
    // 4874: cont_sizes (2 * 4 = 8 bytes)
    // 4882: cont_data (330 + 200 = 530 bytes)
    // 8192: output (3 * 1024 = 3072 bytes)

    const headerOff = 0x100000;
    const payloadOff = headerOff + 256;
    const typesOff = payloadOff + 512;
    const offsetsOff = typesOff + 2;
    const sizesOff = offsetsOff + 8;
    const dataOff = sizesOff + 8;
    const outOff = 0x102000;

    mem.set(header, headerOff);
    mem.set(payload, payloadOff);

    // Continuation types
    mem[typesOff] = CONTINUATION_TYPE.BUMP;
    mem[typesOff + 1] = CONTINUATION_TYPE.DATA;

    // Continuation offsets (u32 LE): [0, 330]
    const offsetsBuf = Buffer.alloc(8);
    offsetsBuf.writeUInt32LE(0, 0);
    offsetsBuf.writeUInt32LE(330, 4);
    mem.set(offsetsBuf, offsetsOff);

    // Continuation sizes (u32 LE): [330, 200]
    const sizesBuf = Buffer.alloc(8);
    sizesBuf.writeUInt32LE(330, 0);
    sizesBuf.writeUInt32LE(200, 4);
    mem.set(sizesBuf, sizesOff);

    // Continuation data (bumpData + dataPayload concatenated)
    mem.set(bumpData, dataOff);
    mem.set(dataPayload, dataOff + 330);

    const written = multicell_pack_fn(
      headerOff, payloadOff, 512,
      typesOff, offsetsOff, sizesOff, dataOff,
      2, outOff,
    );

    expect(written).toBe(3072);

    const zigOutput = Buffer.from(mem.slice(outOff, outOff + 3072));

    // Byte-for-byte identity
    expect(zigOutput.length).toBe(tsResult.buffer.length);
    expect(zigOutput.equals(tsResult.buffer)).toBe(true);
  });

  test("Zig multi-cell matches multi_cell_3.bin vector", async () => {
    await loadWasm();

    const expected = loadVector("multi_cell_3");

    const header = buildHeaderDeterministic({
      linearity: LINEARITY.LINEAR,
      phase: "action",
      dimension: "how",
      payloadSize: 512,
    });

    const payload = Buffer.alloc(512);
    for (let i = 0; i < 512; i++) payload[i] = i & 0xFF;

    const bumpData = Buffer.alloc(330, 0x42);
    const dataPayload = Buffer.alloc(200, 0xDD);

    const multicell_pack_fn = wasmInstance.exports.multicell_pack as Function;
    const mem = new Uint8Array(wasmMemory.buffer);

    const headerOff = 0x100000;
    const payloadOff = headerOff + 256;
    const typesOff = payloadOff + 512;
    const offsetsOff = typesOff + 2;
    const sizesOff = offsetsOff + 8;
    const dataOff = sizesOff + 8;
    const outOff = 0x102000;

    mem.set(header, headerOff);
    mem.set(payload, payloadOff);

    mem[typesOff] = CONTINUATION_TYPE.BUMP;
    mem[typesOff + 1] = CONTINUATION_TYPE.DATA;

    const offsetsBuf = Buffer.alloc(8);
    offsetsBuf.writeUInt32LE(0, 0);
    offsetsBuf.writeUInt32LE(330, 4);
    mem.set(offsetsBuf, offsetsOff);

    const sizesBuf = Buffer.alloc(8);
    sizesBuf.writeUInt32LE(330, 0);
    sizesBuf.writeUInt32LE(200, 4);
    mem.set(sizesBuf, sizesOff);

    mem.set(bumpData, dataOff);
    mem.set(dataPayload, dataOff + 330);

    const written = multicell_pack_fn(
      headerOff, payloadOff, 512,
      typesOff, offsetsOff, sizesOff, dataOff,
      2, outOff,
    );

    expect(written).toBe(3072);
    const zigOutput = Buffer.from(mem.slice(outOff, outOff + 3072));
    expect(zigOutput.equals(expected)).toBe(true);
  });

  test("TypeScript can unpack Zig multi-cell output", async () => {
    await loadWasm();

    const header = buildHeaderDeterministic({
      linearity: LINEARITY.AFFINE,
      phase: "outcome",
      dimension: "what",
      payloadSize: 128,
    });

    const payload = Buffer.alloc(128);
    for (let i = 0; i < 128; i++) payload[i] = (i * 5) & 0xFF;

    const bumpData = Buffer.alloc(100, 0xBB);

    const multicell_pack_fn = wasmInstance.exports.multicell_pack as Function;
    const mem = new Uint8Array(wasmMemory.buffer);

    const headerOff = 0x100000;
    const payloadOff = headerOff + 256;
    const typesOff = payloadOff + 128;
    const offsetsOff = typesOff + 1;
    const sizesOff = offsetsOff + 4;
    const dataOff = sizesOff + 4;
    const outOff = 0x102000;

    mem.set(header, headerOff);
    mem.set(payload, payloadOff);

    mem[typesOff] = CONTINUATION_TYPE.BUMP;

    const offsetsBuf = Buffer.alloc(4);
    offsetsBuf.writeUInt32LE(0, 0);
    mem.set(offsetsBuf, offsetsOff);

    const sizesBuf = Buffer.alloc(4);
    sizesBuf.writeUInt32LE(100, 0);
    mem.set(sizesBuf, sizesOff);

    mem.set(bumpData, dataOff);

    const written = multicell_pack_fn(
      headerOff, payloadOff, 128,
      typesOff, offsetsOff, sizesOff, dataOff,
      1, outOff,
    );

    expect(written).toBe(2048);

    const zigOutput = Buffer.from(mem.slice(outOff, outOff + 2048));

    // TS should unpack it successfully
    const unpacked = unpackMultiCell(zigOutput);
    expect(unpacked.payload.length).toBe(128);
    expect(unpacked.payload.equals(payload)).toBe(true);
    expect(unpacked.continuations.length).toBe(1);
    expect(unpacked.continuations[0].type).toBe(CONTINUATION_TYPE.BUMP);
    expect(unpacked.continuations[0].data.length).toBe(100);
    expect(unpacked.continuations[0].data.equals(bumpData)).toBe(true);
  });

  test("Zig multicell_unpack validates and returns cell count", async () => {
    await loadWasm();

    // Pack with TS, unpack with Zig
    const header = buildHeaderDeterministic({
      linearity: LINEARITY.LINEAR,
      phase: "parse",
      dimension: "what",
      payloadSize: 64,
    });

    const payload = Buffer.alloc(64, 0x77);

    const tsResult = packMultiCell({
      header,
      payload,
      continuations: [
        { type: CONTINUATION_TYPE.DATA, data: Buffer.alloc(50, 0x88) },
      ],
    });

    const multicell_unpack_fn = wasmInstance.exports.multicell_unpack as Function;
    const mem = new Uint8Array(wasmMemory.buffer);
    const bufOff = 0x100000;
    mem.set(tsResult.buffer, bufOff);

    const cellCount = multicell_unpack_fn(bufOff, tsResult.buffer.length);
    expect(cellCount).toBe(2); // Cell 0 + 1 continuation
  });
});

describe("WASM binary", () => {
  test("WASM binary size is under 500KB", () => {
    const stats = readFileSync(WASM_PATH);
    expect(stats.length).toBeLessThan(500 * 1024);
  });
});

```
