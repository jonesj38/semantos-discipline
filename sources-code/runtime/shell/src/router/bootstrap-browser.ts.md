---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/router/bootstrap-browser.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.376997+00:00
---

# runtime/shell/src/router/bootstrap-browser.ts

```ts
/**
 * Browser bootstrap — registers only the verbs whose transitive
 * imports stay inside the browser sandbox. Node-only verbs get a
 * `NOT_IN_BROWSER` stub so callers still see a structured response
 * rather than a hard import-time failure.
 *
 * Sole difference from {@link bootstrap-node} is the registration
 * set; the route pipeline is identical.
 */

import type { ShellCommand } from '../parser';
import type { ShellContext } from '../types';
import { route as routeCore } from './router-core';
import { conversationsHandlers } from './verb-handlers/conversations';
import { docHandlers } from './verb-handlers/doc';
import { evalHandlers } from './verb-handlers/eval';
import { flowHandlers } from './verb-handlers/flow';
import { governHandlers } from './verb-handlers/govern';
import { governanceHandlers } from './verb-handlers/governance';
import { identityHandlers } from './verb-handlers/identity';
import { inspectHandlers } from './verb-handlers/inspect';
import { listHandlers } from './verb-handlers/list';
import { newHandlers } from './verb-handlers/new';
import { patchHandlers } from './verb-handlers/patch';
import { settleHandlers } from './verb-handlers/settle';
import { transferHandlers } from './verb-handlers/transfer';
import { transitionHandlers } from './verb-handlers/transition';
import { makeStubsFor } from './verb-stub';
import {
  makeVerbRegistry,
  registerHandlers,
  type VerbRegistry,
} from './verb-registry';

const NODE_ONLY_VERBS = [
  'taxonomy',
  'grammar',
  'cdm',
  'extract',
  'infer',
  'extension',
  'game',
  'host.exec',
  'host.audit',
  // Metered Content Transfer is node-side (UDP data plane + fs); the PWA drives
  // it remotely over RPC, so in-browser these report NOT_IN_BROWSER.
  'transfer.share',
  'transfer.fetch',
  'transfer.list',
] as const;

export function buildBrowserRegistry(): VerbRegistry {
  const reg = makeVerbRegistry();
  registerHandlers(reg, newHandlers);
  registerHandlers(reg, patchHandlers);
  registerHandlers(reg, transitionHandlers);
  registerHandlers(reg, inspectHandlers);
  registerHandlers(reg, governanceHandlers);
  registerHandlers(reg, transferHandlers);
  registerHandlers(reg, flowHandlers);
  registerHandlers(reg, listHandlers);
  registerHandlers(reg, identityHandlers);
  registerHandlers(reg, evalHandlers);
  registerHandlers(reg, governHandlers);
  registerHandlers(reg, settleHandlers);
  registerHandlers(reg, docHandlers);
  // Conversations persist via ctx.adapter (browser-safe storage seam), so the
  // same handlers register here — sharing references with the node bootstrap.
  registerHandlers(reg, conversationsHandlers);
  // Node-only verbs become safe stubs so the shell still reports a
  // structured NOT_IN_BROWSER instead of "Unknown verb".
  registerHandlers(reg, makeStubsFor(NODE_ONLY_VERBS));
  return reg;
}

const browserRegistry: VerbRegistry = buildBrowserRegistry();

export async function route(cmd: ShellCommand, ctx: ShellContext): Promise<unknown> {
  return routeCore(cmd, ctx, browserRegistry);
}

```
