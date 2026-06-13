---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/router/verb-handlers/taxonomy.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.383158+00:00
---

# runtime/shell/src/router/verb-handlers/taxonomy.ts

```ts
/**
 * `taxonomy` verb — node-only (reads grammar files off disk).
 */

import { routeTaxonomy } from '../../taxonomy';
import type { VerbHandler } from '../types';

const taxonomyHandler: VerbHandler = async (cmd) => routeTaxonomy(cmd);

export const taxonomyHandlers = { taxonomy: taxonomyHandler };

```
