---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/router/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.376189+00:00
---

# runtime/shell/src/router/types.ts

```ts
/**
 * Verb registry types — shape of a registered handler and the dry-run
 * envelope returned by the capability gate.
 */

import type { ShellCommand } from '../parser';
import type { ShellContext } from '../types';

/** A registered verb handler — identical signature to the legacy switch arms. */
export type VerbHandler = (cmd: ShellCommand, ctx: ShellContext) => Promise<unknown>;

export interface CapabilityCheckResult {
  allowed: boolean;
  requiredCapability: number | null;
  message?: string;
}

export interface DryRunResult {
  dryRun: true;
  verb: string;
  wouldExecute: boolean;
  requiredCapability: number | null;
  requiredCapabilityName: string | null;
  hasCapability: boolean;
  hatId: string | null | undefined;
  message: string | undefined;
}

```
