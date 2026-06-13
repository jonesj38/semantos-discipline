---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/host-exec/handlers/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.394813+00:00
---

# runtime/shell/src/host-exec/handlers/index.ts

```ts
/**
 * Server-side handler barrel.
 *
 * Side-effect imports — each handler `.ts` imports its `.manifest` sibling
 * (registering the manifest) and then calls attachHandlerFn() to supply
 * the Node-only implementation. Import this barrel from the shell daemon
 * at boot so host.exec dispatch has real fns to invoke.
 *
 * The browser tier imports `./manifests` instead — that populates the
 * allowlist without dragging node:* built-ins into the client bundle.
 */

import './process-kill-by-port';

```
