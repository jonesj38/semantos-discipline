---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/node/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.302015+00:00
---

# runtime/node/src/index.ts

```ts
/**
 * @semantos/node — Node daemon, admin API, and CLI.
 *
 * Re-exports the public surface for programmatic usage.
 */

export { startAdminApi, type AdminApiOptions } from './api/server';
export { createDaemon, type DaemonOptions } from './daemon';

```
