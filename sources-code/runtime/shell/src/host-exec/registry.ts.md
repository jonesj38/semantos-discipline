---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/host-exec/registry.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.380983+00:00
---

# runtime/shell/src/host-exec/registry.ts

```ts
/**
 * Host-exec handler registry — re-export shim.
 *
 * The registry moved to runtime-services so both shell and extensions
 * can import it without creating a cycle, and so the browser can
 * populate the allowlist via manifest-only registration without
 * pulling node:child_process into the bundle.
 *
 * See runtime/services/src/host-exec-registry.ts for the authoritative
 * implementation. This file stays to keep existing importers working.
 */

// Subpath import so the browser entry (browser.ts → ./registry) doesn't
// drag the whole runtime-services barrel — stores, SDKs, plexus — into
// the client bundle. Server-side importers still get the same symbols.
export {
  registerHandlerManifest,
  attachHandlerFn,
  registerHandler,
  getHandler,
  listHandlers,
  invokeHandler,
  _clearHostExecRegistry,
} from '@semantos/runtime-services/host-exec-registry';

```
