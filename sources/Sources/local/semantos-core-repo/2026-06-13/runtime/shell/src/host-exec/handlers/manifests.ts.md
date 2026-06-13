---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/host-exec/handlers/manifests.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.395404+00:00
---

# runtime/shell/src/host-exec/handlers/manifests.ts

```ts
/**
 * Browser-safe manifest barrel.
 *
 * Side-effect imports — each `*.manifest.ts` calls registerHandlerManifest()
 * at module load time. This file is intentionally free of node:* imports
 * so `@semantos/shell/browser` can pull it in without breaking the
 * browser bundle.
 *
 * Browser tier populates the allowlist via these manifest files so the
 * LLM prompt and deterministic fallback extractor can recognize HOST_EXEC
 * targets. Actual invocation happens server-side — invokeHandler in the
 * browser returns HANDLER_NOT_AVAILABLE (no fn attached in this runtime),
 * but browser code never calls it directly: host.exec goes through the
 * capability gate.
 */

import './process-kill-by-port.manifest';

```
