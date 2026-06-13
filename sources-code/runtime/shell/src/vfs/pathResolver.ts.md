---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/vfs/pathResolver.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.379625+00:00
---

# runtime/shell/src/vfs/pathResolver.ts

```ts
/**
 * @deprecated Use `./path-resolver` (the split) instead. This file is
 * a one-release re-export shim for the new home of the VFS path
 * resolver under `path-resolver/`.
 *
 * The split lives in `runtime/shell/src/vfs/path-resolver/`:
 *   - `types.ts`                       VfsEntry / VfsFileContent / VFS_PREFIXES
 *   - `path-parser.ts`                 pure parseVfsPath + jsonContent
 *   - `vfs-metadata-serializer.ts`     serializeHeaderBin (uses cell-store helpers)
 *   - `taxonomy-walker.ts`             pure walkTaxonomyDir + readTaxonomyNode
 *   - `governance-index.ts`            ballots/disputes view
 *   - `object-resolver.ts`             objects/* dispatch
 *   - `identity-resolver.ts`           identities/* dispatch
 *   - `taxonomy-resolver.ts`           taxonomy/* dispatch
 *   - `flow-resolver.ts`               flows/* dispatch
 *   - `async-resolver.ts`              SemanticFS-backed async helpers
 *   - `entry-cache.ts`                 atom-backed cache + loom invalidator
 *   - `path-resolver-facade.ts`        public VfsPathResolver class
 */

export { VfsPathResolver } from './path-resolver/path-resolver-facade';
export type {
  VfsEntry,
  VfsFileContent,
} from './path-resolver/types';

```
