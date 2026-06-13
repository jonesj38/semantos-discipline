---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/cell-store.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.849044+00:00
---

# core/protocol-types/src/cell-store.ts

```ts
/**
 * @deprecated Use `@semantos/protocol-types/cell-store/cell-store-facade`
 * (or the package barrel `@semantos/protocol-types`) instead. This
 * module is a one-release re-export shim for the new home of the
 * cell-store implementation under `cell-store/`. It will be removed
 * once all consumers have migrated.
 *
 * The split lives in `core/protocol-types/src/cell-store/`:
 *   - `cell-packer.ts`           — pure pack/unpack + continuation cells
 *   - `cell-chunker.ts`          — pure chunking helpers
 *   - `content-hasher.ts`        — bindable SHA-256 port
 *   - `storage-adapter-facade.ts`— named ops over StorageAdapter
 *   - `content-indexer.ts`       — `_index/content/{hash}` writer
 *   - `version-chain-walker.ts`  — async-iterator history walk
 *   - `cell-store-facade.ts`     — public CellStore class
 */

export { CellStore } from './cell-store/cell-store-facade';
export type { CellRef, CellValue, PutOptions } from './cell-store/types';

```
