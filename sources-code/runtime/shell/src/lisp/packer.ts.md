---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/lisp/packer.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.371474+00:00
---

# runtime/shell/src/lisp/packer.ts

```ts
/**
 * Capability token cell packer — packs compiled script bytecode
 * into a 1024-byte cell compatible with the Zig 2PDA cell engine.
 *
 * Uses serializeCellHeader/deserializeCellHeader from @semantos/protocol-types.
 */

import {
  CELL_SIZE,
  HEADER_SIZE,
  Linearity,
  MAGIC_1,
  MAGIC_2,
  MAGIC_3,
  MAGIC_4,
  PAYLOAD_SIZE,
  VERSION,
} from '@semantos/protocol-types';

import {
  type CellHeader,
  deserializeCellHeader,
  serializeCellHeader,
} from '@semantos/protocol-types';

import type { LinearityMode } from './types';

// ── Linearity Mapping ──────────────────────────────────────────

const LINEARITY_MAP: Record<LinearityMode, number> = {
  LINEAR: Linearity.LINEAR,     // 1
  AFFINE: Linearity.AFFINE,     // 2
  RELEVANT: Linearity.RELEVANT, // 3
  FUNGIBLE: Linearity.DEBUG,    // 4 — using DEBUG slot until FUNGIBLE added to constants
};

// ── Hex Utilities ──────────────────────────────────────────────

/** Decode a hex string to Uint8Array. */
function hexToBytes(hex: string): Uint8Array {
  const clean = hex.startsWith('0x') ? hex.slice(2) : hex;
  const bytes = new Uint8Array(clean.length / 2);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = parseInt(clean.slice(i * 2, i * 2 + 2), 16);
  }
  return bytes;
}

// ── Pack Options ───────────────────────────────────────────────

export interface PackOptions {
  /** Linearity mode for the capability cell. Default: LINEAR. */
  linearity?: LinearityMode;
  /** 64-char hex SHA256 type hash. If omitted, zeroed. */
  typeHash?: string;
  /** 16-byte owner ID. If omitted, zeroed. */
  ownerId?: Uint8Array;
  /** Cell timestamp as BigInt (ms since epoch). If omitted, uses current time. */
  timestamp?: bigint;
}

// ── Public API ─────────────────────────────────────────────────

/**
 * Pack compiled script bytecode into a 1024-byte capability cell.
 *
 * @param scriptBytes - The compiled script bytes to embed in the payload.
 * @param options - Packing options (linearity, typeHash, ownerId, timestamp).
 * @returns A 1024-byte Uint8Array ready for the cell engine.
 * @throws If scriptBytes exceeds PAYLOAD_SIZE (768 bytes).
 */
export function packCapabilityCell(
  scriptBytes: Uint8Array,
  options: PackOptions = {},
): Uint8Array {
  if (scriptBytes.length > PAYLOAD_SIZE) {
    throw new Error(
      `Script too large: ${scriptBytes.length} bytes exceeds payload limit of ${PAYLOAD_SIZE} bytes`,
    );
  }

  const linearity = LINEARITY_MAP[options.linearity ?? 'LINEAR'];
  const typeHash = options.typeHash
    ? hexToBytes(options.typeHash)
    : new Uint8Array(32);
  const ownerId = options.ownerId ?? new Uint8Array(16);
  const timestamp = options.timestamp ?? BigInt(Date.now());

  // Build header
  const magic = new Uint8Array(16);
  const magicView = new DataView(magic.buffer);
  magicView.setUint32(0, MAGIC_1, true);
  magicView.setUint32(4, MAGIC_2, true);
  magicView.setUint32(8, MAGIC_3, true);
  magicView.setUint32(12, MAGIC_4, true);

  const header: CellHeader = {
    magic,
    linearity,
    version: VERSION,
    flags: 0,
    refCount: 1,
    typeHash: typeHash.length >= 32 ? typeHash.subarray(0, 32) : padTo(typeHash, 32),
    ownerId: ownerId.length >= 16 ? ownerId.subarray(0, 16) : padTo(ownerId, 16),
    timestamp,
    cellCount: 1,
    totalSize: scriptBytes.length,
    parentHash: new Uint8Array(32),
    prevStateHash: new Uint8Array(32),
    // RM-032b: commerce taxonomy (phase=CODEGEN, dimension=0) moved
    // out of the header. Capability-script cells aren't commerce-
    // domain; domainPayloadRoot stays zero-filled.
    domainPayloadRoot: new Uint8Array(32),
  };

  // Serialize header to 256 bytes
  const headerBytes = serializeCellHeader(header);

  // Assemble cell: 256-byte header + 768-byte payload (script + zero padding)
  const cell = new Uint8Array(CELL_SIZE);
  cell.set(headerBytes, 0);
  cell.set(scriptBytes, HEADER_SIZE);

  return cell;
}

/**
 * Unpack a 1024-byte capability cell into header and script bytes.
 *
 * @param cell - The 1024-byte cell.
 * @returns The parsed header and the script payload (trimmed to totalSize).
 */
export function unpackCapabilityCell(cell: Uint8Array): {
  header: CellHeader;
  script: Uint8Array;
} {
  if (cell.length < CELL_SIZE) {
    throw new Error(`Cell too small: ${cell.length} bytes, need ${CELL_SIZE}`);
  }

  const headerBuf = cell.subarray(0, HEADER_SIZE);
  const header = deserializeCellHeader(headerBuf);

  // Extract script bytes from payload, trimmed to actual size
  const scriptLength = Math.min(header.totalSize, PAYLOAD_SIZE);
  const script = cell.slice(HEADER_SIZE, HEADER_SIZE + scriptLength);

  return { header, script };
}

// ── Helpers ────────────────────────────────────────────────────

function padTo(src: Uint8Array, size: number): Uint8Array {
  const result = new Uint8Array(size);
  result.set(src, 0);
  return result;
}

```
