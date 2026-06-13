---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/game-sdk/src/policies/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.529860+00:00
---

# packages/game-sdk/src/policies/index.ts

```ts
/**
 * Game policy authoring — templates, compiler, and domain primitives.
 */

export {
  compileGamePolicy,
  compileGamePolicyFile,
  packPolicyCell,
  unpackPolicyCell,
} from './compiler';

export {
  BOARD_PRIMITIVES,
  ENTITY_PRIMITIVES,
  INVENTORY_PRIMITIVES,
  ALL_PRIMITIVES,
  type GamePrimitive,
} from './primitives';

```
