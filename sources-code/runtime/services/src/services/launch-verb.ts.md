---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/launch-verb.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.093604+00:00
---

# runtime/services/src/services/launch-verb.ts

```ts
/**
 * launch — REPL/SSH verb for the 1-3-5 control plane.
 *
 * Usage:
 *   launch list                  — list all 15 slots with their mode
 *   launch <slot>                — show promoted shortlist for the slot
 *   launch <slot> <query>        — search within the slot
 *
 * Example:
 *   > launch do.create
 *   > launch find.memory semantos
 */

import { intentLauncher, getLaunchDeps, ALL_SLOTS, SLOT_MODE, SLOT_LABEL } from './IntentLauncher';
import type { IntentContext } from './IntentLauncher';

export function routeLaunch(cmd: unknown): unknown {
  const deps = getLaunchDeps();
  if (!deps) return { ok: false, error: 'launcher deps not initialised' };

  const args: string[] = Array.isArray(cmd)
    ? (cmd as string[])
    : typeof cmd === 'string'
    ? cmd.split(/\s+/)
    : [];

  const [sub, ...rest] = args;

  if (!sub || sub === 'list') {
    const rows = ALL_SLOTS.map((slot) => ({
      slot,
      mode: SLOT_MODE[slot],
      label: SLOT_LABEL[slot],
    }));
    return { ok: true, data: rows };
  }

  if (!ALL_SLOTS.includes(sub as IntentContext)) {
    return { ok: false, error: `unknown slot "${sub}". Valid: ${ALL_SLOTS.join(', ')}` };
  }

  const result = intentLauncher.resolve(sub as IntentContext, deps);

  if (rest.length > 0) {
    const query = rest.join(' ');
    return { ok: true, data: { slot: sub, query, results: result.search(query) } };
  }

  return { ok: true, data: { slot: sub, promoted: result.promoted } };
}

```
