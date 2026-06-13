---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/semantic-fs/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.864943+00:00
---

# core/protocol-types/src/semantic-fs/index.ts

```ts
/**
 * Semantic-fs barrel — re-exports the public surface plus selected
 * helpers so consumers can drill in for testing or composition.
 */

export { SemanticFS } from './semantic-fs-facade';
export {
  FLAGS_TOMBSTONE,
  InvalidSemanticPathError,
  type ParsedSemanticPath,
  type SemanticFsOptions,
  type SemanticPutOptions,
  type CellMeta,
  VALID_PREFIXES,
  MAX_REDIRECT_HOPS,
} from './types';
export { parseSemanticPath } from './semantic-path-parser';
export { validateForWrite } from './semantic-path-validator';
export { computeTypeHash } from './type-hasher';
export {
  scanMetaFilter,
  listCellKeys,
  metaRefsFor,
  readMeta,
  type ScanFilterOptions,
} from './metadata-scanner';
export { resolvePath } from './tombstone-resolver';
export {
  queryByParent,
  queryByType,
  queryByOwner,
} from './semantic-queries';
export {
  searchEmbedded,
  embeddingPort,
  type SemanticSearchHit,
  type SemanticSearchOptions,
} from './semantic-search';
export { reclassifyCell, type ReclassifyResult } from './cell-reclassifier';

```
