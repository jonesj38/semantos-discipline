---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/router/verb-handlers/extension-verbs.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.386829+00:00
---

# runtime/shell/src/router/verb-handlers/extension-verbs.ts

```ts
/**
 * Extension-provided verbs: `cdm`, `extract`, `infer`, `extension`,
 * `game`. Each is looked up in the runtime-services verb registry at
 * dispatch time; if the providing extension wasn't loaded at startup
 * we return a structured EXTENSION_NOT_LOADED error rather than
 * crashing.
 */

import { getVerb } from '@semantos/runtime-services';
import type { ShellCommand } from '../../parser';
import type { ShellContext } from '../../types';
import type { VerbHandler } from '../types';

function makeExtensionDispatch(verb: string, extensionName: string): VerbHandler {
  return async (cmd: ShellCommand, ctx: ShellContext) => {
    const handler = getVerb(verb);
    if (!handler) {
      return {
        error: `The '${verb}' verb is not loaded. Ensure the ${extensionName} extension is enabled in configs/extensions/.`,
        code: 'EXTENSION_NOT_LOADED',
      };
    }
    return handler(cmd, ctx);
  };
}

export const extensionHandlers: Record<string, VerbHandler> = {
  cdm: makeExtensionDispatch('cdm', 'cdm'),
  extract: makeExtensionDispatch('extract', 'extraction'),
  infer: makeExtensionDispatch('infer', 'extraction'),
  extension: makeExtensionDispatch('extension', 'extraction'),
  game: makeExtensionDispatch('game', 'games'),
};

```
