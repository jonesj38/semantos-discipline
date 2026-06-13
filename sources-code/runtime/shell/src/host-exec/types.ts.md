---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/host-exec/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.380522+00:00
---

# runtime/shell/src/host-exec/types.ts

```ts
/**
 * Host execution types — re-export shim.
 *
 * Authoritative definitions moved to runtime-services alongside the
 * registry itself. See runtime/services/src/host-exec-types.ts.
 */

export type {
  Handler,
  HandlerArgs,
  HandlerContext,
  HandlerError,
  HandlerManifest,
  HandlerOk,
  HandlerResult,
} from '@semantos/runtime-services/host-exec-types';

```
