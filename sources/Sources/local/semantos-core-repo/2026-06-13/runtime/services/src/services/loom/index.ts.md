---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/loom/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.102730+00:00
---

# runtime/services/src/services/loom/index.ts

```ts
/**
 * Loom domain barrel — pure state primitives co-located with LoomStore.
 *
 * Imported by LoomStore (the facade) and any consumer that wants the
 * reducer directly without taking a dependency on the class.
 */

export { loomReducer } from './loom-reducer';
export {
  initialState,
  type LoomState,
  type LoomAction,
} from './loom-types';
export {
  validateVisibilityTransition,
  LINEARITY_LINEAR,
  LINEARITY_AFFINE,
  LINEARITY_RELEVANT,
  type VisibilityState,
  type VisibilityTransitionResult,
} from './visibility-rules';

```
