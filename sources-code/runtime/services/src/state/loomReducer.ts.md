---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/state/loomReducer.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.102354+00:00
---

# runtime/services/src/state/loomReducer.ts

```ts
/**
 * @deprecated Use `@semantos/runtime-services/services/loom` instead.
 * This module is a one-release re-export shim for the new home of the
 * loom reducer (`runtime/services/src/services/loom/`). It will be
 * removed once all consumers have migrated.
 */

export { loomReducer } from '../services/loom/loom-reducer';
export { initialState } from '../services/loom/loom-types';
export type { LoomState, LoomAction } from '../services/loom/loom-types';

```
