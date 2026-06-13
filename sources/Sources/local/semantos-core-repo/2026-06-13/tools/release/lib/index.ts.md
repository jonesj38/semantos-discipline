---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/release/lib/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.559472+00:00
---

# tools/release/lib/index.ts

```ts
export { LocalContentStore, sha256Hex, type ContentRef } from './contentstore';
export { canonicalJson, buildReleaseCell } from './cell';
export {
  jsonlPathFor,
  loadAllCells,
  lastReleaseCell,
  appendCell,
  walkChain,
} from './jsonl';
export { assembleManifest, loadConfig } from './manifest';
export {
  RELEASE_OP,
  type ArtifactConfig,
  type ReleaseConfig,
  type ReleaseManifest,
  type SerializedCell,
} from './types';

```
