---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/vfs/path-resolver/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.390378+00:00
---

# runtime/shell/src/vfs/path-resolver/index.ts

```ts
/**
 * VFS path-resolver barrel — public surface for the split.
 */

export { VfsPathResolver } from './path-resolver-facade';
export type { VfsEntry, VfsFileContent, ParsedVfsPath, VfsPrefix, ResolverDeps } from './types';
export { VFS_PREFIXES } from './types';
export { jsonContent, parseSegments, parseVfsPath } from './path-parser';
export { serializeHeaderBin } from './vfs-metadata-serializer';
export { walkTaxonomyDir, readTaxonomyNode } from './taxonomy-walker';
export {
  readdirGovernance,
  readGovernance,
  getattrGovernance,
} from './governance-index';
export {
  readdirObjects,
  readObject,
  getattrObject,
} from './object-resolver';
export {
  readdirIdentities,
  readIdentity,
  getattrIdentity,
} from './identity-resolver';
export {
  readdirTaxonomy,
  readTaxonomy,
  getattrTaxonomy,
} from './taxonomy-resolver';
export { readdirFlows, readFlow, getattrFlow } from './flow-resolver';
export {
  readdirAsyncForObjects,
  readAsyncForObjects,
  getattrAsyncForObjects,
} from './async-resolver';
export {
  vfsEntryCacheAtom,
  startCacheInvalidator,
  stopCacheInvalidator,
  clearCache,
  cacheEntry,
  cacheContent,
  getCachedEntry,
  getCachedContent,
} from './entry-cache';

```
