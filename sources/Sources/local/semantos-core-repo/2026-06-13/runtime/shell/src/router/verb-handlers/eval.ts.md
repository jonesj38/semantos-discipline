---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/router/verb-handlers/eval.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.382491+00:00
---

# runtime/shell/src/router/verb-handlers/eval.ts

```ts
/**
 * Lisp eval / compile / bind verbs (Phase 21). All three live in
 * commands/eval.ts; this file just exposes them as VerbHandlers.
 */

import { routeBind, routeCompile, routeEval } from '../../commands/eval';
import type { VerbHandler } from '../types';

export const evalHandlers: Record<string, VerbHandler> = {
  eval: routeEval as VerbHandler,
  compile: routeCompile as VerbHandler,
  bind: routeBind as VerbHandler,
};

```
