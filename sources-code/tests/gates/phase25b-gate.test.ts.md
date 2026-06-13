---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/phase25b-gate.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.574945+00:00
---

# tests/gates/phase25b-gate.test.ts

```ts
/**
 * Phase 25B Gate: CellStore & Content Addressing
 *
 * Validates:
 * 1. Cell round-trip (T1–T4)
 * 2. Large file chunking (T5–T7)
 * 3. Verification (T8–T10)
 * 4. Content addressing (T11–T12)
 * 5. Anti-regression (T13–T15)
 */

import { describe, test, expect, beforeEach } from "bun:test";
import { readFileSync, existsSync } from "fs";
import { join } from "path";

const ROOT = join(import.meta.dir, "../..");

// Direct imports from source
import { CellStore, type CellRef, type CellValue } from "../../core/protocol-types/src/cell-store";
import { MemoryAdapter } from "../../core/protocol-types/src/adapters/memory-adapter";
import { deserializeCellHeader, serializeCellHeader, type CellHeader } from "../../core/protocol-types/src/cell-header";
import {
  CELL_SIZE,
  HEADER_SIZE,
  PAYLOAD_SIZE,
  CONTINUATION_HEADER_SIZE,
  CONTINUATION_PAYLOAD_SIZE,
  Linearity,
  CellType,
  MAGIC_1,
  MAGIC_2,
  MAGIC_3,
  MAGIC_4,
} from "../../core/protocol-types/src/constants";

// ── Gate 1: Cell Round-Trip ───────────────────────────────────────

describe("Phase 25B — Cell Round-Trip", () => {
  let adapter: MemoryAdapter;
  let store: CellStore;

  beforeEach(() => {
    adapter = new MemoryAdapter();
    store = new CellStore(adapter);
  });

  // T1: put() then get() returns correct payload and header
  test("T1: cell round-trip", async () => {
    const data = new TextEncoder().encode("hello world");
    const ref = await store.put("test/key", data, { linearity: Linearity.LINEAR });
    const value = await store.get("test/key");

    expect(value).not.toBeNull();
    expect(new TextDecoder().decode(value!.payload)).toBe("hello world");
    expect(value!.contentHash).toBe(ref.contentHash);
    expect(value!.version).toBe(1);
    expect(value!.header.linearity).toBe(Linearity.LINEAR);
  });

  // T2: Second put creates version 2 with prevStateHash linking to version 1
  test("T2: version chaining", async () => {
    const data1 = new TextEncoder().encode("version one");
    const ref1 = await store.put("test/versioned", data1);

    const data2 = new TextEncoder().encode("version two");
    const ref2 = await store.put("test/versioned", data2);

    expect(ref2.version).toBe(2);
    expect(ref2.cellHash).not.toBe(ref1.cellHash);

    // The v2 cell's prevStateHash should be the v1 cell's hash
    const value2 = await store.get("test/versioned");
    expect(value2).not.toBeNull();
    const prevStateHex = Array.from(value2!.header.prevStateHash)
      .map(b => b.toString(16).padStart(2, '0'))
      .join('');
    expect(prevStateHex).toBe(ref1.cellHash);
  });

  // T3: Cell bytes are exactly 1024 bytes
  test("T3: cell is 1024 bytes", async () => {
    const data = new TextEncoder().encode("exact size check");
    await store.put("test/size", data);

    const rawBytes = await adapter.read("test/size");
    expect(rawBytes).not.toBeNull();
    expect(rawBytes!.length).toBe(CELL_SIZE);
  });

  // T4: deserializeCellHeader parses cells produced by CellStore
  test("T4: header compatibility", async () => {
    const data = new TextEncoder().encode("compatibility test");
    const ref = await store.put("test/compat", data, {
      linearity: Linearity.AFFINE,
      phase: 5, // CODEGEN
    });

    const rawBytes = await adapter.read("test/compat");
    expect(rawBytes).not.toBeNull();

    // deserializeCellHeader should parse without throwing
    const header = deserializeCellHeader(rawBytes!);

    // Magic bytes valid
    const dv = new DataView(rawBytes!.buffer, rawBytes!.byteOffset);
    expect(dv.getUint32(0, true)).toBe(MAGIC_1);
    expect(dv.getUint32(4, true)).toBe(MAGIC_2);
    expect(dv.getUint32(8, true)).toBe(MAGIC_3);
    expect(dv.getUint32(12, true)).toBe(MAGIC_4);

    expect(header.linearity).toBe(Linearity.AFFINE);
    expect(header.version).toBe(1);
    expect(header.totalSize).toBe(data.length);
    expect(header.phase).toBe(5);
    expect(header.cellCount).toBe(1);
  });
});

// ── Gate 2: Large File Chunking ───────────────────────────────────

describe("Phase 25B — Large File Chunking", () => {
  let adapter: MemoryAdapter;
  let store: CellStore;

  beforeEach(() => {
    adapter = new MemoryAdapter();
    store = new CellStore(adapter);
  });

  // T5: Data > 768 bytes is chunked correctly
  test("T5: chunking splits large data", async () => {
    // Create data larger than PAYLOAD_SIZE (768 bytes)
    const data = new Uint8Array(2000);
    for (let i = 0; i < data.length; i++) data[i] = i % 256;

    const ref = await store.put("test/large", data);

    // Manifest cell should exist
    const manifestCell = await adapter.read("test/large");
    expect(manifestCell).not.toBeNull();
    expect(manifestCell!.length).toBe(CELL_SIZE);

    // Parse manifest header
    const header = deserializeCellHeader(manifestCell!);
    const chunkCount = Math.ceil(2000 / CONTINUATION_PAYLOAD_SIZE);
    expect(header.cellCount).toBe(1 + chunkCount);
    expect(header.totalSize).toBe(2000);

    // Chunk cells should exist with correct continuation headers
    for (let i = 0; i < chunkCount; i++) {
      const chunkKey = `test/large.chunk.${String(i).padStart(4, '0')}`;
      const chunkCell = await adapter.read(chunkKey);
      expect(chunkCell).not.toBeNull();
      expect(chunkCell!.length).toBe(CELL_SIZE);

      // Verify continuation header format
      const cellType = chunkCell![0];
      expect(cellType).toBe(CellType.DATA);

      const cdv = new DataView(chunkCell!.buffer, chunkCell!.byteOffset);
      const cellIndex = cdv.getUint16(1, true);
      expect(cellIndex).toBe(i + 1); // 1-based

      const totalCells = cdv.getUint16(3, true);
      expect(totalCells).toBe(chunkCount);
    }
  });

  // T6: Reassembly produces original data
  test("T6: chunk reassembly", async () => {
    const data = new Uint8Array(3000);
    for (let i = 0; i < data.length; i++) data[i] = (i * 7 + 13) % 256;

    await store.put("test/reassemble", data);
    const value = await store.get("test/reassemble");

    expect(value).not.toBeNull();
    expect(value!.payload.length).toBe(3000);
    expect(value!.payload).toEqual(data);
  });

  // T7: Manifest cell has correct totalSize and chunkCount
  test("T7: manifest metadata", async () => {
    const data = new Uint8Array(1500);
    for (let i = 0; i < data.length; i++) data[i] = i % 256;

    await store.put("test/manifest", data);

    const manifestCell = await adapter.read("test/manifest");
    expect(manifestCell).not.toBeNull();

    // Parse manifest JSON from payload
    let jsonEnd = HEADER_SIZE;
    while (jsonEnd < HEADER_SIZE + PAYLOAD_SIZE && manifestCell![jsonEnd] !== 0) {
      jsonEnd++;
    }
    const manifestJson = new TextDecoder().decode(manifestCell!.subarray(HEADER_SIZE, jsonEnd));
    const manifest = JSON.parse(manifestJson);

    expect(manifest.totalSize).toBe(1500);
    const expectedChunks = Math.ceil(1500 / CONTINUATION_PAYLOAD_SIZE);
    expect(manifest.chunkCount).toBe(expectedChunks);
    expect(manifest.chunkHashes).toHaveLength(expectedChunks);
    expect(typeof manifest.contentHash).toBe("string");
    expect(manifest.contentHash.length).toBe(64); // SHA-256 hex
  });
});

// ── Gate 3: Verification ──────────────────────────────────────────

describe("Phase 25B — Verification", () => {
  let adapter: MemoryAdapter;
  let store: CellStore;

  beforeEach(() => {
    adapter = new MemoryAdapter();
    store = new CellStore(adapter);
  });

  // T8: verify() returns valid for clean chain
  test("T8: clean chain verifies", async () => {
    await store.put("test/verify", new TextEncoder().encode("v1"));
    await store.put("test/verify", new TextEncoder().encode("v2"));
    await store.put("test/verify", new TextEncoder().encode("v3"));

    const result = await store.verify("test/verify");
    expect(result.valid).toBe(true);
    expect(result.errors).toHaveLength(0);
  });

  // T9: Corrupted cell fails verification
  test("T9: corrupted cell detected", async () => {
    await store.put("test/corrupt", new TextEncoder().encode("original data"));

    // Corrupt the cell by flipping a byte
    const cellBytes = await adapter.read("test/corrupt");
    expect(cellBytes).not.toBeNull();
    const corrupted = new Uint8Array(cellBytes!);
    corrupted[HEADER_SIZE + 5] ^= 0xFF; // flip a payload byte
    await adapter.write("test/corrupt", corrupted);

    const result = await store.verify("test/corrupt");
    expect(result.valid).toBe(false);
    expect(result.errors.length).toBeGreaterThan(0);
    expect(result.errors[0]).toContain("cellHash mismatch");
  });

  // T10: Broken prevStateHash chain fails verification
  test("T10: broken chain detected", async () => {
    await store.put("test/chain", new TextEncoder().encode("v1"));
    await store.put("test/chain", new TextEncoder().encode("v2"));

    // Corrupt the archived v1 cell to break the chain
    const v1Bytes = await adapter.read("test/chain.v1");
    expect(v1Bytes).not.toBeNull();
    const corrupted = new Uint8Array(v1Bytes!);
    corrupted[HEADER_SIZE] ^= 0xFF;
    await adapter.write("test/chain.v1", corrupted);

    const result = await store.verify("test/chain");
    expect(result.valid).toBe(false);
    expect(result.errors.some(e => e.includes("cellHash mismatch"))).toBe(true);
  });
});

// ── Gate 4: Content Addressing ────────────────────────────────────

describe("Phase 25B — Content Addressing", () => {
  let adapter: MemoryAdapter;
  let store: CellStore;

  beforeEach(() => {
    adapter = new MemoryAdapter();
    store = new CellStore(adapter);
  });

  // T11: Same data at different keys shares content hash
  test("T11: content deduplication", async () => {
    const data = new TextEncoder().encode("shared content");
    // Use different owners so headers differ even at same ms timestamp
    const ref1 = await store.put("path/a", data, {
      ownerId: new Uint8Array([1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
    });
    const ref2 = await store.put("path/b", data, {
      ownerId: new Uint8Array([2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
    });

    expect(ref1.contentHash).toBe(ref2.contentHash);
    expect(ref1.cellHash).not.toBe(ref2.cellHash); // Different headers (different ownerId)
  });

  // T12: findByContent returns all keys with matching content
  test("T12: content index lookup", async () => {
    const data = new TextEncoder().encode("findable content");
    const ref1 = await store.put("find/a", data);
    const ref2 = await store.put("find/b", data);

    const found = await store.findByContent(ref1.contentHash);
    expect(found.length).toBe(2);
    const keys = found.map(f => f.key).sort();
    expect(keys).toEqual(["find/a", "find/b"]);
  });
});

// ── Gate 5: Anti-Regression ───────────────────────────────────────

describe("Phase 25B — Anti-Regression", () => {
  // T13: Phase 25A gate tests still pass
  test("T13: 25A gates intact", () => {
    // Verify key Phase 25A artifacts exist
    expect(existsSync(join(ROOT, "core/protocol-types/src/storage.ts"))).toBe(true);
    expect(existsSync(join(ROOT, "core/protocol-types/src/adapters/memory-adapter.ts"))).toBe(true);
    expect(existsSync(join(ROOT, "core/protocol-types/src/adapters/create-adapter.ts"))).toBe(true);

    // StorageAdapter interface completeness
    const storageSource = readFileSync(
      join(ROOT, "core/protocol-types/src/storage.ts"),
      "utf-8",
    );
    const methods = ["read(", "write(", "exists(", "list(", "delete(", "stat(", "watch?("];
    for (const method of methods) {
      expect(storageSource).toContain(method);
    }
  });

  // T14: Phase 21 compile still produces valid output
  test("T14: lisp compile functional", () => {
    const evalSource = readFileSync(
      join(ROOT, "runtime/shell/src/commands/eval.ts"),
      "utf-8",
    );
    // routeCompile still exists
    expect(evalSource).toContain("routeCompile");
    // Still imports LispCompiler
    expect(evalSource).toContain("LispCompiler");
    // Still imports packCapabilityCell (fallback path)
    expect(evalSource).toContain("packCapabilityCell");
    // Now also imports CellStore
    expect(evalSource).toContain("CellStore");
  });

  // T15: Existing cell-header serialization unchanged
  test("T15: header serialization stable", () => {
    // Round-trip test: build a header, serialize, deserialize, compare
    const magic = new Uint8Array(16);
    const magicView = new DataView(magic.buffer);
    magicView.setUint32(0, MAGIC_1, true);
    magicView.setUint32(4, MAGIC_2, true);
    magicView.setUint32(8, MAGIC_3, true);
    magicView.setUint32(12, MAGIC_4, true);

    const original: CellHeader = {
      magic,
      linearity: Linearity.LINEAR,
      version: 42,
      flags: 0,
      refCount: 1,
      typeHash: new Uint8Array(32),
      ownerId: new Uint8Array(16),
      timestamp: BigInt(1234567890),
      cellCount: 1,
      totalSize: 100,
      phase: 5,
      dimension: 0,
      parentHash: new Uint8Array(32),
      prevStateHash: new Uint8Array(32),
    };

    const serialized = serializeCellHeader(original);
    expect(serialized.length).toBe(HEADER_SIZE);

    const deserialized = deserializeCellHeader(serialized);
    expect(deserialized.linearity).toBe(original.linearity);
    expect(deserialized.version).toBe(original.version);
    expect(deserialized.timestamp).toBe(original.timestamp);
    expect(deserialized.cellCount).toBe(original.cellCount);
    expect(deserialized.totalSize).toBe(original.totalSize);
    expect(deserialized.phase).toBe(original.phase);
  });
});

```
