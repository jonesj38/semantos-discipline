---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/shell/body-route.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.084410+00:00
---

# apps/loom-svelte/src/shell/body-route.ts

```ts
/**
 * body-route.ts — SH3 (svelte-helm matrix; DECISION D11).
 *
 * Decides what the helm's centre-slot renders, given the active shell view,
 * the active cartridge, and that cartridge's surfacingMode. Pure (no Svelte,
 * no I/O) so the routing precedence + surfacingMode semantics are unit-
 * testable without a rendered App.
 *
 * surfacingMode semantics (the "takeover"):
 *   - dedicated → full-surface takeover: the cartridge owns the centre-slot
 *     (route carries dedicated:true; App renders it full-bleed). With a single
 *     active cartridge there is, by construction, "no evidence" of any other.
 *   - default   → shared body: the cartridge renders with the shell chrome
 *     around it (dedicated:false).
 *   - passive   → never surfaces as a body (defensive: treated as home; the
 *     picker also excludes passive cartridges — see ExtensionSwitcher).
 */

import type { SurfacingMode } from '../lib/extensions-api';
import type { TalkContextId } from './context-weights';

export type ShellView =
  | { kind: 'find-network' }
  | { kind: 'talk'; context: TalkContextId };

export type BodyRoute =
  | { kind: 'view-find-network' }
  | { kind: 'view-talk'; context: TalkContextId }
  | { kind: 'home' }
  | { kind: 'cartridge'; id: string; dedicated: boolean };

export interface BodyRouteInput {
  /** Active explicit shell view (find-network / talk), or null. */
  activeView: ShellView | null;
  /** Active cartridge id, or null for the attention home. */
  activeCartridgeId: string | null;
  /** The active cartridge's surfacingMode (ignored when no cartridge active). */
  surfacingMode: SurfacingMode;
}

/**
 * Resolve the centre-slot route. Precedence: explicit shell views first
 * (find-network / talk), then the active cartridge, then home.
 */
export function resolveBodyRoute(input: BodyRouteInput): BodyRoute {
  const { activeView, activeCartridgeId, surfacingMode } = input;
  if (activeView?.kind === 'find-network') return { kind: 'view-find-network' };
  if (activeView?.kind === 'talk') return { kind: 'view-talk', context: activeView.context };
  if (!activeCartridgeId) return { kind: 'home' };
  // Defensive: a passive cartridge should never have become active (the
  // picker excludes them); if it somehow did, fall back to home.
  if (surfacingMode === 'passive') return { kind: 'home' };
  return { kind: 'cartridge', id: activeCartridgeId, dedicated: surfacingMode === 'dedicated' };
}

```
