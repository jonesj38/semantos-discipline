---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/host-exec/handlers/process-kill-by-port.manifest.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.395686+00:00
---

# runtime/shell/src/host-exec/handlers/process-kill-by-port.manifest.ts

```ts
/**
 * Manifest-only registration for process.killByPort.
 *
 * Pure data — no node:* imports. Safe to pull into the browser bundle
 * via the manifests barrel so the extractor (LLM prompt + fallback
 * allowlist) sees this handler as available.
 *
 * The Node-only implementation lives in ./process-kill-by-port.ts and
 * imports this file before attaching its fn.
 */

// Subpath import keeps the browser bundle minimal — skip the full
// runtime-services barrel (which transitively pulls stores and SDKs)
// and reach straight for the registry module.
import { registerHandlerManifest } from '@semantos/runtime-services/host-exec-registry';

export const processKillByPortManifest = {
  id: 'process.killByPort',
  description: 'Send a signal to the process listening on a given TCP port',
  argsSchema: {
    port: { type: 'number', required: true },
    signal: { type: 'string' },
    dryRun: { type: 'boolean' },
  },
  capabilityId: 11, // HOST_EXEC from host-ops.json
} as const;

registerHandlerManifest(processKillByPortManifest);

```
