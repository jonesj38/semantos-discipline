---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/router/verb-handlers/doc.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.383734+00:00
---

# runtime/shell/src/router/verb-handlers/doc.ts

```ts
/**
 * Document-bundle verbs: `share` / `export` / `merge` / `diff`. All
 * delegate to commands/doc.ts.
 */

import {
  routeDiff,
  routeExport,
  routeMerge,
  routeShare,
} from '../../commands/doc';
import type { VerbHandler } from '../types';

export const docHandlers: Record<string, VerbHandler> = {
  share: routeShare as VerbHandler,
  export: routeExport as VerbHandler,
  merge: routeMerge as VerbHandler,
  diff: routeDiff as VerbHandler,
};

```
