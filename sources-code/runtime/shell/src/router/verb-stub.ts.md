---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/router/verb-stub.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.375372+00:00
---

# runtime/shell/src/router/verb-stub.ts

```ts
/**
 * Browser-stub factory — produces a `VerbHandler` that always returns
 * a `NOT_IN_BROWSER` ShellError-shaped envelope. Used by the browser
 * bootstrap to bind safe placeholders for Node-only verbs (taxonomy,
 * grammar, host.exec, host.audit, cdm, extract, infer, extension,
 * game) so the shell still routes the verb name rather than crashing.
 */

import type { VerbHandler } from './types';

export const NOT_IN_BROWSER = {
  error:
    'This shell verb requires Node.js (filesystem/crypto) and is not available in the browser build.',
  code: 'NOT_IN_BROWSER',
};

export function makeNotInBrowserStub(verb: string): VerbHandler {
  return async () => ({ ...NOT_IN_BROWSER, verb });
}

export function makeStubsFor(verbs: readonly string[]): Record<string, VerbHandler> {
  const out: Record<string, VerbHandler> = {};
  for (const verb of verbs) out[verb] = makeNotInBrowserStub(verb);
  return out;
}

```
