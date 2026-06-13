---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/router/verb-handlers/govern.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.384295+00:00
---

# runtime/shell/src/router/verb-handlers/govern.ts

```ts
/**
 * `govern` verb — delegates to commands/govern.ts.
 */

import { routeGovern } from '../../commands/govern';
import type { VerbHandler } from '../types';

export const governHandlers: Record<string, VerbHandler> = {
  govern: routeGovern as VerbHandler,
};

```
