---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/router/router-core.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.376454+00:00
---

# runtime/shell/src/router/router-core.ts

```ts
/**
 * router-core — `route(cmd, ctx, registry)` runs the standard
 * pre-dispatch pipeline (mutation gate + dry-run envelope) then
 * delegates to the verb's handler from the supplied registry.
 *
 * The pipeline is the same for both bootstraps (node + browser); only
 * the registry contents differ.
 */

import { MUTATION_VERBS } from '../capabilities';
import { CAPABILITY_CHECK_FAILED, UNKNOWN_VERB } from '../error-codes';
import type { ShellCommand } from '../parser';
import type { ShellContext } from '../types';
import { checkPlexusCapability } from './capability-gate';
import { buildDryRunResult, isDryRun } from './dry-run-mode';
import type { VerbRegistry } from './verb-registry';

export async function route(
  cmd: ShellCommand,
  ctx: ShellContext,
  registry: VerbRegistry,
): Promise<unknown> {
  if (MUTATION_VERBS.has(cmd.verb)) {
    // host.exec has its own dry-run semantics inside the handler.
    if (isDryRun(cmd) && cmd.verb !== 'host.exec') {
      return buildDryRunResult(cmd, ctx);
    }
    const check = await checkPlexusCapability(ctx, cmd.verb);
    if (!check.allowed) {
      return { error: check.message, code: CAPABILITY_CHECK_FAILED };
    }
  }

  const handler = registry.get(cmd.verb);
  if (!handler) {
    return {
      error: `Unknown verb: ${cmd.verb}`,
      code: UNKNOWN_VERB,
    };
  }
  return handler(cmd, ctx);
}

```
