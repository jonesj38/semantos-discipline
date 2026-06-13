---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/router/verb-registry.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.377816+00:00
---

# runtime/shell/src/router/verb-registry.ts

```ts
/**
 * Verb registry — thin wrapper over `Registry<VerbHandler>` from
 * `@semantos/state` so the router has a single object to dispatch
 * against. Each bootstrap file builds a fresh registry, calls
 * `registerXxxHandlers(registry)` from `verb-handlers/`, and hands it
 * to {@link router-core}.
 *
 * Registration is deliberately a runtime API so that follow-up work
 * (extension-installed verbs) can call `registry.register()` after
 * boot without touching the bootstrap module.
 */

import { registry, type Registry } from '@semantos/state';
import type { VerbHandler } from './types';

export type VerbRegistry = Registry<VerbHandler>;

export function makeVerbRegistry(): VerbRegistry {
  return registry<VerbHandler>();
}

/**
 * Register many handlers at once. Useful for the per-file
 * `register*Handlers(registry)` exports under verb-handlers/ that
 * supply a tiny `Record<string, VerbHandler>`.
 */
export function registerHandlers(
  reg: VerbRegistry,
  handlers: Record<string, VerbHandler>,
): void {
  for (const [verb, handler] of Object.entries(handlers)) reg.register(verb, handler);
}

```
