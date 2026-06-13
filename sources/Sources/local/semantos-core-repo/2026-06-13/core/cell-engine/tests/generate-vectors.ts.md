---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests/generate-vectors.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.967854+00:00
---

# core/cell-engine/tests/generate-vectors.ts

```ts
#!/usr/bin/env bun
/**
 * Test Vector Generator for Phase 1 Cell Packing
 *
 * Generates .bin files from the canonical TypeScript packer.
 * These become the ground truth for Zig conformance tests.
 *
 * Run: cd packages/cell-engine && bun tests/generate-vectors.ts
 */

import { writeFileSync, mkdirSync } from "fs";
import { join } from "path";
import {
  buildCellHeader,
  packCell,
  computeTypeHash,
  PHASE_BYTES,
  DIMENSION_BYTES,
  LINEARITY,
  packMultiCell,
  CONTINUATION_TYPE,
  type PipelinePhase,
  type Dimension,
  type Linearity,
  type ContinuationCell,
  type MultiCellObject,
} from "@semantos/cell-ops";

const VECTORS_DIR = join(import.meta.dir, "vectors");
mkdirSync(VECTORS_DIR, { recursive: true });

// ── Deterministic test inputs ──

// Fixed timestamp so vectors are reproducible
const FIXED_TIMESTAMP = BigInt(1700000000000); // 2023-11-14T22:13:20Z

// Known type hash (SHA256 of "services.trades.carpentry:hire:inst.contract.service-agreement")
const TYPE_HASH = computeTypeHash(
  "services.trades.carpentry",
  "hire",
  "inst.contract.service-agreement"
);

// Fixed 16-byte owner ID
const OWNER_ID = Buffer.from("0123456789abcdef", "hex").subarray(0, 8);
const OWNER_ID_16 = Buffer.alloc(16, 0);
OWNER_ID.copy(OWNER_ID_16);

// Fixed parent hash (32 bytes of 0xAA)
const PARENT_HASH = Buffer.alloc(32, 0xaa);

// Fixed prev state hash (32 bytes of 0xBB)
const PREV_STATE_HASH = Buffer.alloc(32, 0xbb);

/**
 * Build a header with a fixed timestamp (monkey-patch Date.now).
 * The TS packer uses Date.now() inside buildCellHeader, so we override it.
 */
function buildHeaderDeterministic(opts: {
  typeHash: Buffer;
  linearity: Linearity;
  ownerId: Buffer;
  phase: PipelinePhase;
  dimension: Dimension;
  parentHash?: Buffer;
  prevStateHash?: Buffer;
  payloadSize: number;
  version?: number;
}): Buffer {
  const origDateNow = Date.now;
  Date.now = () => Number(FIXED_TIMESTAMP);
  try {
    return buildCellHeader(opts);
  } finally {
    Date.now = origDateNow;
  }
}

// ── Vector definitions ──

interface VectorDef {
  name: string;
  description: string;
  linearity: Linearity;
  phase: PipelinePhase;
  dimension: Dimension;
  payloadSize: number;
  parentHash?: Buffer;
  prevStateHash?: Buffer;
  multiCell?: {
    continuations: ContinuationCell[];
  };
}

const vectors: VectorDef[] = [
  {
    name: "single_cell_linear",
    description: "LINEAR object, 32-byte payload, minimal",
    linearity: LINEARITY.LINEAR,
    phase: "parse",
    dimension: "what",
    payloadSize: 32,
  },
  {
    name: "single_cell_affine",
    description: "AFFINE object, full 768-byte payload",
    linearity: LINEARITY.AFFINE,
    phase: "ast",
    dimension: "composite",
    payloadSize: 768,
  },
  {
    name: "single_cell_relevant",
    description: "RELEVANT object with commerce extension populated",
    linearity: LINEARITY.RELEVANT,
    phase: "codegen",
    dimension: "instrument",
    payloadSize: 256,
    parentHash: PARENT_HASH,
    prevStateHash: PREV_STATE_HASH,
  },
  {
    name: "multi_cell_3",
    description: "3-cell object with BUMP and DATA continuations",
    linearity: LINEARITY.LINEAR,
    phase: "action",
    dimension: "how",
    payloadSize: 512,
    multiCell: {
      continuations: [
        {
          type: CONTINUATION_TYPE.BUMP,
          data: Buffer.alloc(330, 0x42), // Simulated BUMP data
        },
        {
          type: CONTINUATION_TYPE.DATA,
          data: Buffer.alloc(200, 0xDD), // Simulated data payload
        },
      ],
    },
  },
];

// ── Generate vectors ──

interface VectorMeta {
  name: string;
  description: string;
  linearity: number;
  phase: number;
  dimension: number;
  payloadSize: number;
  timestamp: string;
  typeHash: string;
  ownerId: string;
  parentHash: string | null;
  prevStateHash: string | null;
  cellCount: number;
  fileSize: number;
}

const meta: VectorMeta[] = [];

for (const v of vectors) {
  // Build payload (deterministic: sequential bytes mod 256)
  const payload = Buffer.alloc(v.payloadSize);
  for (let i = 0; i < v.payloadSize; i++) {
    payload[i] = i & 0xff;
  }

  const header = buildHeaderDeterministic({
    typeHash: TYPE_HASH,
    linearity: v.linearity,
    ownerId: OWNER_ID_16,
    phase: v.phase,
    dimension: v.dimension,
    parentHash: v.parentHash,
    prevStateHash: v.prevStateHash,
    payloadSize: v.payloadSize,
  });

  let packed: Buffer;
  let cellCount: number;

  if (v.multiCell) {
    const result = packMultiCell({
      header,
      payload,
      continuations: v.multiCell.continuations,
    });
    packed = result.buffer;
    cellCount = result.cellCount;
  } else {
    packed = packCell(header, payload);
    cellCount = packed.length / 1024;
  }

  const filePath = join(VECTORS_DIR, `${v.name}.bin`);
  writeFileSync(filePath, packed);

  meta.push({
    name: v.name,
    description: v.description,
    linearity: v.linearity,
    phase: PHASE_BYTES[v.phase],
    dimension: DIMENSION_BYTES[v.dimension],
    payloadSize: v.payloadSize,
    timestamp: FIXED_TIMESTAMP.toString(),
    typeHash: TYPE_HASH.toString("hex"),
    ownerId: OWNER_ID_16.toString("hex"),
    parentHash: v.parentHash ? v.parentHash.toString("hex") : null,
    prevStateHash: v.prevStateHash ? v.prevStateHash.toString("hex") : null,
    cellCount,
    fileSize: packed.length,
  });

  console.log(`Generated: ${v.name}.bin (${packed.length} bytes, ${cellCount} cells)`);
}

// ── Commerce all phases ──
// Generate a single-cell vector for each commerce phase
const phaseNames: PipelinePhase[] = [
  "source", "parse", "ast", "typecheck", "optimise", "codegen", "action", "outcome", "unknown",
];

const allPhasesBuffer = Buffer.alloc(phaseNames.length * 1024);

for (let i = 0; i < phaseNames.length; i++) {
  const phase = phaseNames[i];
  const payload = Buffer.alloc(64);
  payload.writeUInt8(i, 0); // Tag byte to identify which phase

  const header = buildHeaderDeterministic({
    typeHash: TYPE_HASH,
    linearity: LINEARITY.DEBUG,
    ownerId: OWNER_ID_16,
    phase,
    dimension: "composite",
    payloadSize: 64,
  });

  const packed = packCell(header, payload);
  packed.copy(allPhasesBuffer, i * 1024);
}

const allPhasesPath = join(VECTORS_DIR, "commerce_all_phases.bin");
writeFileSync(allPhasesPath, allPhasesBuffer);
console.log(`Generated: commerce_all_phases.bin (${allPhasesBuffer.length} bytes, ${phaseNames.length} phase cells)`);

// Write metadata
const metaPath = join(VECTORS_DIR, "vectors.json");
writeFileSync(metaPath, JSON.stringify({ vectors: meta, phaseNames, fixedTimestamp: FIXED_TIMESTAMP.toString() }, null, 2));
console.log(`Generated: vectors.json`);

console.log("\nAll test vectors generated successfully.");

```
