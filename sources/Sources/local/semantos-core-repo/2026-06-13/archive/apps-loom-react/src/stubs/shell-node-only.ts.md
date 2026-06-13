---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/stubs/shell-node-only.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.945862+00:00
---

# archive/apps-loom-react/src/stubs/shell-node-only.ts

```ts
/**
 * Browser stubs for Node-only shell command modules.
 *
 * The shell router imports taxonomy, infer, extract, and grammar — all of
 * which use `fs`/`path` to read grammar files off disk. The browser never
 * dispatches these verbs, so stubbing them out lets Vite's dep scan succeed
 * without pulling fs into the bundle.
 *
 * If one of these verbs is ever invoked in the browser, the returned
 * ShellError surfaces a clear diagnostic rather than a runtime crash.
 */

import type { ShellCommand } from '../../../shell/src/parser';
import type { ShellContext } from '../../../shell/src/types';

const NOT_IN_BROWSER = {
  __shellError: true,
  code: 'NOT_IN_BROWSER',
  message: 'This shell verb requires Node.js (filesystem access) and is not available in the browser build.',
};

export async function routeTaxonomy(_cmd: ShellCommand, _ctx: ShellContext): Promise<unknown> {
  return NOT_IN_BROWSER;
}

export async function routeInfer(_cmd: ShellCommand, _ctx: ShellContext): Promise<unknown> {
  return NOT_IN_BROWSER;
}

export async function routeExtract(_cmd: ShellCommand, _ctx: ShellContext): Promise<unknown> {
  return NOT_IN_BROWSER;
}

export async function routeGrammar(_cmd: ShellCommand, _ctx: ShellContext): Promise<unknown> {
  return NOT_IN_BROWSER;
}

```
