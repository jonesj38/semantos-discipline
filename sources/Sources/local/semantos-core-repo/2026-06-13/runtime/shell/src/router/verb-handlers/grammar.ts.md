---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/router/verb-handlers/grammar.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.383445+00:00
---

# runtime/shell/src/router/verb-handlers/grammar.ts

```ts
/**
 * `grammar` verb — node-only (reads grammar files off disk).
 */

import { routeGrammar } from '../../commands/grammar';
import type { VerbHandler } from '../types';

export const grammarHandlers: Record<string, VerbHandler> = {
  grammar: routeGrammar as VerbHandler,
};

```
