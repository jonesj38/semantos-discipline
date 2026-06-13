---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/shell/surface-registry.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.084709+00:00
---

# apps/loom-svelte/src/shell/surface-registry.ts

```ts
/**
 * surface-registry.ts — SH4 (svelte-helm matrix; DECISIONS D10/D11).
 *
 * Pure lookup over a cartridge-surface registry. A bundled SPA must import
 * the components it can render, so the CONCRETE registry (id → bundled Svelte
 * component) is assembled in App.svelte. This module stays pure (no .svelte
 * imports) so the lookup semantics are unit-testable under node --test/tsx and
 * an unregistered cartridge id degrades to a graceful placeholder rather than
 * a hardcoded `{:else if id === 'oddjobz'}` chain.
 *
 * (True zero-import / runtime dynamic surface loading would need code-split
 * dynamic import + a manifest-declared entry; out of scope — the realistic
 * decoupling for a web helm is ONE central binding point, this registry.)
 */

export interface SurfaceEntry<C = unknown> {
  /** Cartridge id this surface renders (matches the manifest / activeCartridge). */
  id: string;
  /** Operator-facing label. */
  label: string;
  /** The bundled component to mount (typed by the caller; opaque here). */
  component: C;
}

/** Resolve a surface by id; null when unknown / no id (→ placeholder). */
export function lookupSurface<C>(
  registry: Record<string, SurfaceEntry<C>>,
  id: string | null | undefined,
): SurfaceEntry<C> | null {
  if (!id) return null;
  return registry[id] ?? null;
}

/** True iff a surface is bundled for this id in the given registry. */
export function isRegistered<C>(
  registry: Record<string, SurfaceEntry<C>>,
  id: string | null | undefined,
): boolean {
  return lookupSurface(registry, id) !== null;
}

```
