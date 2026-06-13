---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/router/dry-run-mode.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.377547+00:00
---

# runtime/shell/src/router/dry-run-mode.ts

```ts
/**
 * Dry-run helpers — `--dry-run` selector + the structured envelope
 * the gate returns when a mutation verb is dry-running.
 */

import { getCapabilityName } from '../capabilities';
import type { ShellCommand } from '../parser';
import type { ShellContext } from '../types';
import { checkPlexusCapability } from './capability-gate';
import type { DryRunResult } from './types';

export function isDryRun(cmd: ShellCommand): boolean {
  return cmd.flags['dry-run'] === true;
}

export async function buildDryRunResult(
  cmd: ShellCommand,
  ctx: ShellContext,
): Promise<DryRunResult> {
  const check = await checkPlexusCapability(ctx, cmd.verb);
  return {
    dryRun: true,
    verb: cmd.verb,
    wouldExecute: check.allowed,
    requiredCapability: check.requiredCapability,
    requiredCapabilityName: check.requiredCapability
      ? getCapabilityName(check.requiredCapability)
      : null,
    hasCapability: check.allowed,
    hatId: ctx.activeHatId,
    message: check.message,
  };
}

```
