---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/cell-store/cell-store-facade.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.891414+00:00
---

# core/protocol-types/src/cell-store/cell-store-facade.ts

```ts
/**
 * Cell-store facade — orchestrates header serialization, packing,
 * chunking, hashing, indexing and version-chain walking. Public API
 * (`put`, `get`, `getByHash`, `history`, `verify`, `findByContent`)
 * matches the pre-split CellStore class so downstream consumers
 * continue to compile without changes.
 */

import type { StorageAdapter } from '../storage';
import type { CellHeader } from '../cell-header';
import {
  CELL_SIZE,
  HEADER_SIZE,
  PAYLOAD_SIZE,
  CONTINUATION_PAYLOAD_SIZE,
  Linearity,
  CellType,
  MAGIC_1,
  MAGIC_2,
  MAGIC_3,
  MAGIC_4,
} from '../constants';
import {
  packCell,
  packContinuationCell,
  unpackContinuationCell,
  deserializeCellHeader,
  parseManifest,
} from './cell-packer';
import { chunkData, isChunked, chunkCountFor } from './cell-chunker';
import { hexToBytes, sha256 } from './content-hasher';
import { collectVersions } from './version-chain-walker';
import { verifyChain, type VerifyResult } from './cell-verifier';
import { ContentIndexer } from './content-indexer';
import { StorageAdapterFacade } from './storage-adapter-facade';
import type {
  CellMeta,
  CellRef,
  CellValue,
  ChunkManifest,
  PutOptions,
} from './types';

function makeMagic(): Uint8Array {
  const m = new Uint8Array(16);
  const dv = new DataView(m.buffer);
  dv.setUint32(0, MAGIC_1, true);
  dv.setUint32(4, MAGIC_2, true);
  dv.setUint32(8, MAGIC_3, true);
  dv.setUint32(12, MAGIC_4, true);
  return m;
}

function padTo(src: Uint8Array, size: number): Uint8Array {
  if (src.length >= size) return src.subarray(0, size);
  const result = new Uint8Array(size);
  result.set(src, 0);
  return result;
}

export class CellStore {
  private readonly storage: StorageAdapterFacade;
  private readonly indexer: ContentIndexer;

  constructor(adapter: StorageAdapter) {
    this.storage = new StorageAdapterFacade(adapter);
    this.indexer = new ContentIndexer(this.storage);
  }

  async put(key: string, data: Uint8Array, options?: PutOptions): Promise<CellRef> {
    const linearity = options?.linearity ?? Linearity.LINEAR;
    const contentHash = await sha256(data);

    const prevMeta = await this.storage.readMeta(key);
    const version = prevMeta ? prevMeta.version + 1 : 1;

    let prevStateHash = new Uint8Array(32);
    if (options?.prevStateHash) prevStateHash = options.prevStateHash;
    else if (prevMeta) prevStateHash = hexToBytes(prevMeta.cellHash);

    const now = Date.now();
    const chunked = isChunked(data.length, PAYLOAD_SIZE);
    let chunkCount = 0;
    let manifest: ChunkManifest | undefined;

    if (chunked) {
      chunkCount = chunkCountFor(data.length, CONTINUATION_PAYLOAD_SIZE);
      const chunkHashes: string[] = [];
      for (const c of chunkData(data, CONTINUATION_PAYLOAD_SIZE).chunks) {
        chunkHashes.push(await sha256(c));
      }
      manifest = { totalSize: data.length, chunkCount, contentHash, chunkHashes };
    }

    const header: CellHeader = {
      magic: makeMagic(),
      linearity,
      version,
      flags: options?.flags ?? 0,
      refCount: 1,
      typeHash: padTo(options?.typeHash ?? new Uint8Array(32), 32),
      ownerId: padTo(options?.ownerId ?? new Uint8Array(16), 16),
      timestamp: BigInt(now),
      cellCount: 1 + chunkCount,
      totalSize: data.length,
      parentHash: padTo(options?.parentHash ?? new Uint8Array(32), 32),
      prevStateHash,
      // RM-032b: commerce taxonomy (phase, dimension) moved to the
      // cell payload under commerceSchemaV1. Callers wanting commerce
      // binding encode a CommercePayload (see
      // @semantos/plexus-schema-registry/schemas/commerce) and set
      // domainPayloadRoot = computeDomainPayloadRoot(...).
      domainPayloadRoot: new Uint8Array(32),
    };

    let payload: Uint8Array;
    if (chunked && manifest) {
      const manifestBytes = new TextEncoder().encode(JSON.stringify(manifest));
      if (manifestBytes.length > PAYLOAD_SIZE) {
        throw new Error(
          `Manifest too large: ${manifestBytes.length} bytes exceeds ${PAYLOAD_SIZE}. Too many chunks.`,
        );
      }
      payload = manifestBytes;
    } else {
      payload = data;
    }

    const cell = packCell(header, payload);
    const cellHash = await sha256(cell);

    if (prevMeta) await this.storage.archivePrevious(key, prevMeta.version);
    await this.storage.writeCell(key, cell);

    if (chunked && manifest) {
      const plan = chunkData(data, CONTINUATION_PAYLOAD_SIZE);
      for (let i = 0; i < plan.chunks.length; i++) {
        const contCell = packContinuationCell(
          CellType.DATA,
          i + 1,
          manifest.chunkCount,
          plan.chunks[i] as Uint8Array,
        );
        const chunkKey = `${key}.chunk.${String(i).padStart(4, '0')}`;
        await this.storage.writeChunk(chunkKey, contCell);
      }
    }

    const meta: CellMeta = {
      cellHash,
      contentHash,
      version,
      timestamp: now,
      linearity,
      prevCellHash: prevMeta?.cellHash ?? null,
    };
    await this.storage.writeMeta(key, meta);
    await this.indexer.append(contentHash, { key, cellHash, version, timestamp: now });

    return { key, cellHash, contentHash, version, timestamp: now, linearity };
  }

  async get(key: string): Promise<CellValue | null> {
    const cellBytes = await this.storage.readCell(key);
    if (!cellBytes || cellBytes.length < CELL_SIZE) return null;

    const header = deserializeCellHeader(cellBytes);
    const meta = await this.storage.readMeta(key);

    if (header.cellCount > 1) {
      const manifest = parseManifest<ChunkManifest>(cellBytes);
      if (!manifest) return null;

      const chunks: Uint8Array[] = [];
      for (let i = 0; i < manifest.chunkCount; i++) {
        const chunkKey = `${key}.chunk.${String(i).padStart(4, '0')}`;
        const chunkCell = await this.storage.readChunk(chunkKey);
        if (!chunkCell) return null;
        const { chunk } = unpackContinuationCell(chunkCell);
        chunks.push(chunk);
      }

      const payload = new Uint8Array(manifest.totalSize);
      let offset = 0;
      for (const chunk of chunks) {
        payload.set(chunk, offset);
        offset += chunk.length;
      }

      return {
        key,
        cellHash: meta?.cellHash ?? (await sha256(cellBytes)),
        contentHash: meta?.contentHash ?? (await sha256(payload)),
        version: header.version,
        timestamp: Number(header.timestamp),
        linearity: header.linearity as Linearity,
        header,
        payload,
      };
    }

    const payloadSize = Math.min(header.totalSize, PAYLOAD_SIZE);
    const payload = cellBytes.slice(HEADER_SIZE, HEADER_SIZE + payloadSize);

    return {
      key,
      cellHash: meta?.cellHash ?? (await sha256(cellBytes)),
      contentHash: meta?.contentHash ?? (await sha256(payload)),
      version: header.version,
      timestamp: Number(header.timestamp),
      linearity: header.linearity as Linearity,
      header,
      payload,
    };
  }

  async getByHash(cellHash: string): Promise<CellValue | null> {
    const indexKeys = await this.storage.list('_index/hash/');
    const targetKey = indexKeys.find((k) => k === cellHash);
    if (!targetKey) return null;
    const entry = await this.storage.read(`_index/hash/${targetKey}`);
    if (!entry) return null;
    return this.get(new TextDecoder().decode(entry));
  }

  async history(key: string): Promise<CellRef[]> {
    return collectVersions(this.storage, key);
  }

  async verify(key: string): Promise<VerifyResult> {
    return verifyChain(this.storage, key);
  }

  async findByContent(contentHash: string): Promise<CellRef[]> {
    const entries = await this.indexer.lookup(contentHash);
    return entries.map((e) => ({
      key: e.key,
      cellHash: e.cellHash,
      contentHash,
      version: e.version,
      timestamp: e.timestamp,
      linearity: Linearity.LINEAR,
    }));
  }
}

```
