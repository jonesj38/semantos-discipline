---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/router/bootstrap-node.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.375906+00:00
---

# runtime/shell/src/router/bootstrap-node.ts

```ts
/**
 * Node bootstrap — registers every shell verb against a fresh
 * registry and exposes a `route(cmd, ctx)` bound to it. This is what
 * the legacy `router.ts` exported.
 */

import type { ShellCommand } from '../parser';
import type { ShellContext } from '../types';
import { route as routeCore } from './router-core';
import { conversationsHandlers } from './verb-handlers/conversations';
import { docHandlers } from './verb-handlers/doc';
import { evalHandlers } from './verb-handlers/eval';
import { extensionHandlers } from './verb-handlers/extension-verbs';
import { flowHandlers } from './verb-handlers/flow';
import { governHandlers } from './verb-handlers/govern';
import { governanceHandlers } from './verb-handlers/governance';
import { grammarHandlers } from './verb-handlers/grammar';
import { hostExecHandlers } from './verb-handlers/host-exec';
import { identityHandlers } from './verb-handlers/identity';
import { inspectHandlers } from './verb-handlers/inspect';
import { listHandlers } from './verb-handlers/list';
import { newHandlers } from './verb-handlers/new';
import { patchHandlers } from './verb-handlers/patch';
import { settleHandlers } from './verb-handlers/settle';
import { taxonomyHandlers } from './verb-handlers/taxonomy';
import { transferHandlers } from './verb-handlers/transfer';
import { transferContentHandlers } from './verb-handlers/transfer-content';
import { transitionHandlers } from './verb-handlers/transition';
import { makeVerbRegistry, registerHandlers, type VerbRegistry } from './verb-registry';

/** Build a registry pre-populated with every verb the node shell exposes. */
export function buildNodeRegistry(): VerbRegistry {
  const reg = makeVerbRegistry();
  registerHandlers(reg, newHandlers);
  registerHandlers(reg, patchHandlers);
  registerHandlers(reg, transitionHandlers);
  registerHandlers(reg, inspectHandlers);
  registerHandlers(reg, governanceHandlers);
  registerHandlers(reg, transferHandlers);
  registerHandlers(reg, transferContentHandlers);
  registerHandlers(reg, flowHandlers);
  registerHandlers(reg, listHandlers);
  registerHandlers(reg, identityHandlers);
  registerHandlers(reg, evalHandlers);
  registerHandlers(reg, taxonomyHandlers);
  registerHandlers(reg, grammarHandlers);
  registerHandlers(reg, governHandlers);
  registerHandlers(reg, settleHandlers);
  registerHandlers(reg, docHandlers);
  registerHandlers(reg, hostExecHandlers);
  registerHandlers(reg, extensionHandlers);
  registerHandlers(reg, conversationsHandlers);
  return reg;
}

/** Module-level singleton — same lifecycle as the legacy `route()`. */
const nodeRegistry: VerbRegistry = buildNodeRegistry();

/** Drop-in replacement for the legacy `router.ts` export. */
export async function route(cmd: ShellCommand, ctx: ShellContext): Promise<unknown> {
  return routeCore(cmd, ctx, nodeRegistry);
}

```
