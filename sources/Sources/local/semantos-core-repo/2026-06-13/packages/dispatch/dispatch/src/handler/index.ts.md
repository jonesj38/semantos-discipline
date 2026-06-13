---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/dispatch/dispatch/src/handler/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.516986+00:00
---

# packages/dispatch/dispatch/src/handler/index.ts

```ts
/**
 * D-O11 phase O11b — handler surface.
 */

export {
  processDispatchEnvelope,
  makeRollbackableConsumedCellSet,
  type CertChainVerifier,
  type DispatchHandlerInput,
  type DispatchHandlerResult,
  type RollbackableConsumedCellSet,
} from './handler.js';

export { makeAcceptHandlerRegistry } from './registry.js';

export type {
  AcceptHandlerContext,
  AcceptHandlerFn,
  AcceptHandlerRegistry,
  AcceptOutput,
  DispatchHandlerFailure,
} from './types.js';

```
