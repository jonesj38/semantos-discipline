---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.087712+00:00
---

# runtime/services/src/index.ts

```ts
/**
 * @semantos/runtime-services — renderer-agnostic stores and services.
 *
 * The full API mirrors what was previously @semantos/loom's services/index.ts
 * barrel. UI shells (loom-react, loom-svelte, demo apps, headless tests) import
 * from here without picking up any framework dependency.
 */

export * from "./services/index";

// Verb registry — extension-provided shell command dispatch.
// Imports here so consumers can use either `@semantos/runtime-services`
// (bare) or `@semantos/runtime-services/verb-registry` (subpath).
export {
  registerVerb,
  getVerb,
  getVerbRegistration,
  listVerbs,
  listVerbRegistrations,
  _clearVerbRegistry,
  type VerbHandler,
  type VerbRegistration,
} from "./verb-registry";

// Host-exec handler registry — allowlist dispatch for HOST_EXEC.
// Mirrors verb-registry: neutral module both shell and extensions can
// import. Supports manifest/impl split so browser code can populate the
// allowlist without pulling node:child_process.
export {
  registerHandlerManifest,
  attachHandlerFn,
  registerHandler,
  getHandler,
  listHandlers,
  invokeHandler,
  _clearHostExecRegistry,
} from "./host-exec-registry";
export type {
  Handler,
  HandlerArgs,
  HandlerContext,
  HandlerError,
  HandlerManifest,
  HandlerOk,
  HandlerResult,
} from "./host-exec-types";

```
