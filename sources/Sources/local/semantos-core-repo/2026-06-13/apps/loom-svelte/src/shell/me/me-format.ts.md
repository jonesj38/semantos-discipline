---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/shell/me/me-format.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.090066+00:00
---

# apps/loom-svelte/src/shell/me/me-format.ts

```ts
/**
 * me-format.ts — SH5 (svelte-helm matrix; DECISION D13).
 *
 * Small pure formatters for the "me" panel (wallet + identity cert + hat
 * role). Kept out of the .svelte component so they're unit-testable under
 * node --test/tsx (no DOM).
 */

import type { HatRole } from '../../lib/extensions-api';

/** Abbreviate a long id (cert id, hat id) to a head…tail form for display. */
export function shortId(id: string | null | undefined, head = 8, tail = 4): string {
  if (!id) return '—';
  if (id.length <= head + tail + 1) return id;
  return `${id.slice(0, head)}…${id.slice(-tail)}`;
}

/** Operator-facing label for a hat role. */
export function roleLabel(role: HatRole): string {
  return role === 'admin' ? 'Admin' : 'Operator';
}

/** Format an epoch-ms timestamp as a date, or a dash when absent/invalid. */
export function formatIssued(epochMs: number | null | undefined): string {
  if (!epochMs || epochMs <= 0) return '—';
  // Deterministic ISO date (no locale/tz surprises in tests).
  return new Date(epochMs).toISOString().slice(0, 10);
}

```
