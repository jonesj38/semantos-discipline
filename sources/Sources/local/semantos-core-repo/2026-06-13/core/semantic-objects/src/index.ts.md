---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/semantic-objects/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.935537+00:00
---

# core/semantic-objects/src/index.ts

```ts
/**
 * @semantos/semantic-objects — canonical patch substrate.
 *
 * The "loom" of the semantos system. Every domain extension writes into
 * these four tables via `createObject` + `appendPatch`; state is
 * reconstructed via `listPatches` + `foldState`.
 *
 * See README.md for the model + concurrency + federation overview.
 */
export * from './schema.js';
export * from './types.js';
export * from './operations.js';
export { computeNewStateHash, stableStringify } from './hash.js';

```
