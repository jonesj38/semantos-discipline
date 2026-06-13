---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/cell-store/cell-chunker.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.892230+00:00
---

# core/protocol-types/src/cell-store/cell-chunker.ts

```ts
/**
 * Pure chunking helpers — split a byte buffer into uniformly-sized
 * pieces and reassemble them. Cell-store uses these for payloads that
 * exceed `PAYLOAD_SIZE` and need to ride in continuation cells.
 *
 * No I/O. No hashing. The caller owns hashing each chunk and recording
 * those hashes in the manifest.
 */

export interface ChunkPlan {
  chunks: Uint8Array[];
  chunkSize: number;
  totalSize: number;
}

/**
 * Split `data` into N chunks of at most `chunkSize` bytes. The final
 * chunk may be shorter. Returns the plan plus the original total size
 * for symmetry with reassembleChunks.
 */
export function chunkData(data: Uint8Array, chunkSize: number): ChunkPlan {
  if (chunkSize <= 0) {
    throw new Error(`chunkData: chunkSize must be > 0, got ${chunkSize}`);
  }
  const chunks: Uint8Array[] = [];
  for (let offset = 0; offset < data.length; offset += chunkSize) {
    const end = Math.min(offset + chunkSize, data.length);
    chunks.push(data.subarray(offset, end));
  }
  return { chunks, chunkSize, totalSize: data.length };
}

/**
 * Reassemble a list of chunks into a single buffer of `totalSize`
 * bytes. When `totalSize` is omitted, the chunk lengths are summed.
 */
export function reassembleChunks(chunks: Uint8Array[], totalSize?: number): Uint8Array {
  const total = totalSize ?? chunks.reduce((acc, c) => acc + c.length, 0);
  const out = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    if (offset + chunk.length > total) {
      out.set(chunk.subarray(0, total - offset), offset);
      offset = total;
      break;
    }
    out.set(chunk, offset);
    offset += chunk.length;
  }
  return out;
}

/** True when a buffer of `dataLength` requires chunking at the given chunk size. */
export function isChunked(dataLength: number, chunkSize: number): boolean {
  return dataLength > chunkSize;
}

/** Convenience: ceil(dataLength / chunkSize). */
export function chunkCountFor(dataLength: number, chunkSize: number): number {
  if (chunkSize <= 0) {
    throw new Error(`chunkCountFor: chunkSize must be > 0, got ${chunkSize}`);
  }
  return Math.ceil(dataLength / chunkSize);
}

```
