---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/router/verb-handlers/settle.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.382186+00:00
---

# runtime/shell/src/router/verb-handlers/settle.ts

```ts
/**
 * `settle` verb — delegates to commands/settle.ts.
 */

import { routeSettle } from '../../commands/settle';
import type { VerbHandler } from '../types';

export const settleHandlers: Record<string, VerbHandler> = {
  settle: routeSettle as VerbHandler,
};

```
