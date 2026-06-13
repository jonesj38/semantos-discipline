---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/swarm-manifest.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.842457+00:00
---

# core/protocol-types/src/swarm-manifest.ts

```ts
/**
 * Swarm manifest — the "infohash" object for the paid-swarm file-distribution
 * system (runtime/session-protocol/src/swarm). This is the CANONICAL,
 * language-portable surface: the byte layout here MUST match the Zig sibling
 * (cartridges/swarm/brain/zig/swarm_manifest.zig) so a manifest published by a
 * TS seeder and a manifest indexed/located by the Zig brain agree on the same
 * 32-byte infohash. A conformance vector cross-checks the two (see the swarm
 * cartridge tests).
 *
 * A manifest commits to a file as a chain of fixed-size data cells:
 *   - `merkleRoot` — root over the 1024-byte data cells (sha256-leaf merkle,
 *     the data side of the unified verifier in @semantos/cell-ops). A peer
 *     verifies any single fetched cell against this root with a per-cell
 *     inclusion proof — so the manifest stays a single tiny cell regardless of
 *     file size (BitTorrent-v2 style; no inline leaf-hash vector needed).
 *   - `contentHash` — sha256 of the reassembled original bytes (final check).
 *
 * The infohash is `sha256(canonical manifest payload)`. It is independent of
 * the manifest cell's owner / timestamp (those live in the header, not the
 * payload), so the same file always yields the same infohash.
 *
 * Substrate governance: this file is pure wire — it depends only on other
 * substrate packages (@semantos/cell-ops, local constants/cell-header). It
 * MUST NOT import from cartridges/ or runtime/.
 */

import { cellMerkleSha256 as sha256, computeCellMerkleRoot } from '@semantos/cell-ops/packer';

/** Re-exported so swarm consumers (engine + tests) get sha256 without a direct cell-ops dep. */
export { cellMerkleSha256 as sha256 } from '@semantos/cell-ops/packer';
import {
  CELL_SIZE,
  HEADER_SIZE,
  PAYLOAD_SIZE,
  VERSION,
  Linearity,
} from './constants';
import type { CellHeader } from './cell-header';
import { serializeCellHeader, deserializeCellHeader } from './cell-header';

/** Manifest schema version (bump on any canonical-layout change). */
export const SWARM_MANIFEST_VERSION = 1 as const;

/**
 * 32-byte type hash for the `swarm.manifest` cell type.
 *
 * Derivation (must match the Zig cartridge): `sha256("swarm.manifest")`.
 * The swarm cartridge registers this same type hash in
 * cartridge_cell_registry so `cellsByType` indexes manifests by it.
 */
export const SWARM_MANIFEST_TYPE_NAME = 'swarm.manifest' as const;
export const SWARM_MANIFEST_TYPE_HASH: Uint8Array = sha256(
  new TextEncoder().encode(SWARM_MANIFEST_TYPE_NAME),
);

/** The logical manifest. Byte fields are 32-byte SHA-256 digests. */
export interface SwarmManifest {
  version: number;
  /** Human/overlay path for the file (UTF-8). */
  semanticPath: string;
  /** Original (reassembled) file size in bytes. */
  totalSize: number;
  /** Number of data cells the file chunks into. */
  totalCells: number;
  /** Payload bytes carried per data cell (continuation payload size). */
  chunkSize: number;
  /** sha256(original file bytes). */
  contentHash: Uint8Array;
  /** Merkle root over the 1024-byte data cells. */
  merkleRoot: Uint8Array;
}

// ── hex helpers (lowercase, no prefix) ─────────────────────────────────────────

const HEX = '0123456789abcdef';
export function toHex(bytes: Uint8Array): string {
  let s = '';
  for (let i = 0; i < bytes.length; i++) {
    const b = bytes[i]!;
    s += HEX[(b >> 4) & 0xf]! + HEX[b & 0xf]!;
  }
  return s;
}
export function fromHex(hex: string): Uint8Array {
  if (hex.length % 2 !== 0) throw new Error(`fromHex: odd-length string (${hex.length})`);
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) {
    out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }
  return out;
}

// ── canonicalization + infohash ───────────────────────────────────────────────

/**
 * Canonical manifest payload bytes. Fixed key order + compact JSON so TS and
 * Zig produce byte-identical output (and therefore the same infohash). Do NOT
 * reorder keys or add whitespace.
 *
 *   {"v":1,"p":<path>,"ts":<n>,"n":<n>,"cs":<n>,"ch":"<hex>","mr":"<hex>"}
 */
export function canonicalizeManifest(m: SwarmManifest): Uint8Array {
  if (m.contentHash.length !== 32) throw new Error('canonicalizeManifest: contentHash must be 32 bytes');
  if (m.merkleRoot.length !== 32) throw new Error('canonicalizeManifest: merkleRoot must be 32 bytes');
  const json =
    '{"v":' + (m.version >>> 0) +
    ',"p":' + JSON.stringify(m.semanticPath) +
    ',"ts":' + (m.totalSize >>> 0) +
    ',"n":' + (m.totalCells >>> 0) +
    ',"cs":' + (m.chunkSize >>> 0) +
    ',"ch":"' + toHex(m.contentHash) + '"' +
    ',"mr":"' + toHex(m.merkleRoot) + '"}';
  return new TextEncoder().encode(json);
}

/** infohash = sha256(canonical manifest payload). */
export function computeInfohash(m: SwarmManifest): Uint8Array {
  return sha256(canonicalizeManifest(m));
}

/**
 * Build a manifest from the file's data cells. `dataCells` are the full
 * 1024-byte cells (continuation cells); the merkle root is computed over them.
 */
export function buildManifest(args: {
  dataCells: Uint8Array[];
  semanticPath: string;
  contentHash: Uint8Array;
  totalSize: number;
  chunkSize: number;
}): SwarmManifest {
  if (args.dataCells.length === 0) throw new Error('buildManifest: no data cells');
  return {
    version: SWARM_MANIFEST_VERSION,
    semanticPath: args.semanticPath,
    totalSize: args.totalSize,
    totalCells: args.dataCells.length,
    chunkSize: args.chunkSize,
    contentHash: args.contentHash.slice(0, 32),
    merkleRoot: computeCellMerkleRoot(args.dataCells),
  };
}

// ── manifest cell (1024-byte wire form) ────────────────────────────────────────

const ZERO16 = new Uint8Array(16);
const ZERO32 = new Uint8Array(32);

export interface EncodeManifestCellOptions {
  /** 16-byte owner id; defaults to zeros. */
  ownerId?: Uint8Array;
  /** Cell timestamp; defaults to 0n (kept out of the infohash deliberately). */
  timestamp?: bigint;
}

/**
 * Pack a manifest into a canonical 1024-byte `swarm.manifest` cell. The
 * canonical payload is written verbatim into the payload region (NUL-padded by
 * the zero-initialised buffer) and `domainPayloadRoot` is bound to the infohash.
 */
export function encodeManifestCell(m: SwarmManifest, opts: EncodeManifestCellOptions = {}): Uint8Array {
  const payload = canonicalizeManifest(m);
  if (payload.length > PAYLOAD_SIZE) {
    throw new Error(
      `encodeManifestCell: manifest payload (${payload.length}B) exceeds PAYLOAD_SIZE (${PAYLOAD_SIZE}). ` +
        'Shorten semanticPath.',
    );
  }
  const infohash = sha256(payload);
  const header: CellHeader = {
    magic: new Uint8Array(16), // filled by serializeCellHeader
    linearity: Linearity.LINEAR,
    version: VERSION,
    flags: 0,
    refCount: 0,
    typeHash: SWARM_MANIFEST_TYPE_HASH,
    ownerId: opts.ownerId ?? ZERO16,
    timestamp: opts.timestamp ?? 0n,
    cellCount: 1,
    totalSize: payload.length,
    parentHash: ZERO32,
    prevStateHash: ZERO32,
    domainPayloadRoot: infohash,
  };
  const cell = new Uint8Array(CELL_SIZE);
  cell.set(serializeCellHeader(header), 0);
  cell.set(payload, HEADER_SIZE);
  return cell;
}

/** Parse a `swarm.manifest` cell back into a manifest. Validates the type hash. */
export function parseManifestCell(cellBytes: Uint8Array): SwarmManifest {
  if (cellBytes.length < CELL_SIZE) {
    throw new Error(`parseManifestCell: expected ${CELL_SIZE} bytes, got ${cellBytes.length}`);
  }
  const header = deserializeCellHeader(cellBytes);
  if (!bytesEqual(header.typeHash, SWARM_MANIFEST_TYPE_HASH)) {
    throw new Error('parseManifestCell: cell is not a swarm.manifest (type hash mismatch)');
  }
  const end = HEADER_SIZE + Math.min(header.totalSize, PAYLOAD_SIZE);
  const json = new TextDecoder().decode(cellBytes.subarray(HEADER_SIZE, end));
  const o = JSON.parse(json) as {
    v: number; p: string; ts: number; n: number; cs: number; ch: string; mr: string;
  };
  return {
    version: o.v,
    semanticPath: o.p,
    totalSize: o.ts,
    totalCells: o.n,
    chunkSize: o.cs,
    contentHash: fromHex(o.ch),
    merkleRoot: fromHex(o.mr),
  };
}

export function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i]! ^ b[i]!;
  return diff === 0;
}

```
