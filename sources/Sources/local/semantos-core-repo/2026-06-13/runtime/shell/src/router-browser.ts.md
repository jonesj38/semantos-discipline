---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/router-browser.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.366263+00:00
---

# runtime/shell/src/router-browser.ts

```ts
/**
 * @deprecated Use `./router/bootstrap-browser` (or the package barrel
 * `./router`) instead. This module is a one-release re-export shim
 * for the new home of the browser router under `router/`. It will be
 * removed once all consumers have migrated.
 */

export {
  route,
  buildBrowserRegistry,
} from './router/bootstrap-browser';

```
