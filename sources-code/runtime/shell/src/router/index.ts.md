---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/router/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.375641+00:00
---

# runtime/shell/src/router/index.ts

```ts
/**
 * Router barrel — public surface for the split.
 */

export { route as route } from './bootstrap-node';
export { route as routeBrowser, buildBrowserRegistry } from './bootstrap-browser';
export { buildNodeRegistry } from './bootstrap-node';
export { route as routeCore } from './router-core';
export { makeVerbRegistry, registerHandlers, type VerbRegistry } from './verb-registry';
export { checkPlexusCapability } from './capability-gate';
export { isDryRun, buildDryRunResult } from './dry-run-mode';
export {
  routeTransitionViaPipeline,
  shouldUsePipelineRoute,
} from './intent-pipeline-adapter';
export { makeNotInBrowserStub, makeStubsFor, NOT_IN_BROWSER } from './verb-stub';
export type {
  CapabilityCheckResult,
  DryRunResult,
  VerbHandler,
} from './types';

```
