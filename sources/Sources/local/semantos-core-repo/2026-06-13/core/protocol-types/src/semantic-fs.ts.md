---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/semantic-fs.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.844174+00:00
---

# core/protocol-types/src/semantic-fs.ts

```ts
/**
 * @deprecated Use `@semantos/protocol-types/semantic-fs/semantic-fs-facade`
 * (or the package barrel) instead. This module is a one-release
 * re-export shim for the new home of the semantic-fs implementation
 * under `semantic-fs/`. It will be removed once all consumers have
 * migrated.
 *
 * The split lives in `core/protocol-types/src/semantic-fs/`:
 *   - `semantic-path-parser.ts`       — pure greedy backward-scan parser
 *   - `semantic-path-validator.ts`    — write-path validation
 *   - `type-hasher.ts`                — SHA-256 of dotted taxonomy path
 *   - `metadata-scanner.ts`           — `objects/` + .meta sidecar scan
 *   - `tombstone-resolver.ts`         — redirect-chain follower
 *   - `semantic-queries.ts`           — queryByParent/Type/Owner
 *   - `semantic-search.ts`            — embedding search + embeddingPort
 *   - `cell-reclassifier.ts`          — tombstone + new-cell write
 *   - `semantic-fs-facade.ts`         — public SemanticFS class
 */

export { SemanticFS } from './semantic-fs/semantic-fs-facade';
export {
  FLAGS_TOMBSTONE,
  InvalidSemanticPathError,
  type ParsedSemanticPath,
  type SemanticFsOptions,
  type SemanticPutOptions,
} from './semantic-fs/types';

```
