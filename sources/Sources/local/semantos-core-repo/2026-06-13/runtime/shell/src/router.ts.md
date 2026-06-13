---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/router.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.365729+00:00
---

# runtime/shell/src/router.ts

```ts
/**
 * @deprecated Use `./router/bootstrap-node` (or the package barrel
 * `./router`) instead. This module is a one-release re-export shim
 * for the new home of the verb router under `router/`. It will be
 * removed once all consumers have migrated.
 *
 * The split lives in `runtime/shell/src/router/`:
 *   - `verb-registry.ts`             registry built on @semantos/state
 *   - `capability-gate.ts`           pure checkPlexusCapability
 *   - `dry-run-mode.ts`              dry-run selector + envelope
 *   - `intent-pipeline-adapter.ts`   conditional pipeline routing
 *   - `verb-stub.ts`                 NOT_IN_BROWSER stub factory
 *   - `verb-handlers/*.ts`           one file per verb / verb group
 *   - `router-core.ts`               registry-driven dispatch
 *   - `bootstrap-node.ts`            registers everything (this file's old home)
 *   - `bootstrap-browser.ts`         registers browser-safe set + stubs
 */

export {
  route,
  buildNodeRegistry,
} from './router/bootstrap-node';
export {
  shouldUsePipelineRoute,
  routeTransitionViaPipeline,
} from './router/intent-pipeline-adapter';

```
