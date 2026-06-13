---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/router/verb-handlers/host-exec.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.386558+00:00
---

# runtime/shell/src/router/verb-handlers/host-exec.ts

```ts
/**
 * Host-exec verbs: `host.exec`, `host.audit`. Both are node-only
 * because they touch the host-exec registry / audit log.
 */

import { routeHostAudit } from '../../commands/host-audit';
import { routeHostExec } from '../../commands/host-exec';
import type { VerbHandler } from '../types';

export const hostExecHandlers: Record<string, VerbHandler> = {
  'host.exec': routeHostExec as VerbHandler,
  'host.audit': routeHostAudit as VerbHandler,
};

```
