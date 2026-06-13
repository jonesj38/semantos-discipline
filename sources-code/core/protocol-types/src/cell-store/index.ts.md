---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/cell-store/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.889752+00:00
---

# core/protocol-types/src/cell-store/index.ts

```ts
/**
 * Cell-store barrel — re-exports the public class plus selected
 * helpers so consumers can drill in for testing or composition.
 */

export { CellStore } from './cell-store-facade';
export type {
  CellRef,
  CellValue,
  PutOptions,
  CellMeta,
  ContentIndexEntry,
  ChunkManifest,
} from './types';

export {
  packCell,
  unpackCell,
  buildContinuationHeader,
  parseContinuationHeader,
  packContinuationCell,
  unpackContinuationCell,
  type ContinuationHeaderFields,
} from './cell-packer';

export {
  chunkData,
  reassembleChunks,
  isChunked,
  chunkCountFor,
  type ChunkPlan,
} from './cell-chunker';

export {
  contentHasherPort,
  bindDefaultContentHasher,
  defaultSha256,
  sha256,
  hexFromBuffer,
  hexToBytes,
  type ContentHasher,
} from './content-hasher';

export { ContentIndexer } from './content-indexer';
export { StorageAdapterFacade } from './storage-adapter-facade';
export { walkVersions, collectVersions } from './version-chain-walker';

```
