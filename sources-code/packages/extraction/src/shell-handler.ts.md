---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/shell-handler.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.454231+00:00
---

# packages/extraction/src/shell-handler.ts

```ts
/**
 * @semantos/extraction/shell-handler — verb registration entry.
 *
 * Loaded dynamically by shell at startup (see runtime/shell/src/index.ts
 * loadExtensions). Importing this module has the side effect of
 * registering the three extraction-provided shell verbs:
 *
 *   extract      — run the semantic extraction pipeline
 *   infer        — bootstrap an Extension Grammar from API responses
 *   extension    — list / status / detail for installed extensions
 *
 * The actual handler logic lives in src/shell-handlers/{extract,infer,extension}.ts.
 * Each of those files calls registerVerb() at module load. This barrel
 * just imports them all in one place so dynamic-loading consumers only
 * need to know one path.
 */

import { registerVerb } from "@semantos/runtime-services";
import { routeExtract } from "./shell-handlers/extract";
import { routeInfer } from "./shell-handlers/infer";
import { routeExtension } from "./shell-handlers/extension";

registerVerb("extract", routeExtract as (cmd: unknown, ctx: unknown) => Promise<unknown>);
registerVerb("infer", routeInfer as (cmd: unknown, ctx: unknown) => Promise<unknown>);
registerVerb("extension", routeExtension as (cmd: unknown, ctx: unknown) => Promise<unknown>);

```
