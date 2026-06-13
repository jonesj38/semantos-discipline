---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/lib/extensions-api.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.076338+00:00
---

# apps/loom-svelte/src/lib/extensions-api.ts

```ts
/**
 * extensions-api.ts — typed HTTP client for /api/v1/info cartridges list.
 *
 * Fetches the available cartridge/extension list from the brain's info
 * endpoint.  Used by ExtensionSwitcher to populate the workspace dropdown
 * and NetworkView to apply cartridge-scoped peer vocabulary + filtering.
 */

/**
 * Declarative peer-view declaration echoed from cartridge.json through
 * the brain's /api/v1/info response. Mirrors CartridgePeerView in
 * core/experience-cartridge — shell-side mirror uses loose types so the
 * Svelte bundle doesn't import @semantos/* packages.
 */
export interface CartridgePeerViewShape {
  label?: string;
  pluralLabel?: string;
  emptyState?: string;
  filterEdgeTypes?: string[];
  defaultFace?: 'social' | 'topical' | 'commercial';
  primaryEdgeTypes?: string[];
  verbs?: string[];
}

/** Semantic surface intent — how the helm should present a cartridge. */
export type SurfacingMode = 'default' | 'dedicated' | 'passive';

/** SH14 / D12 — which hat a verb is visible to. operator = base; admin = +managerial. */
export type HatRole = 'operator' | 'admin';

/**
 * SH1/SH2 (svelte-helm matrix; DECISION D9) — one declarative UI verb the
 * brain surfaces for a cartridge via /api/v1/info. Form-factor-agnostic:
 * the helm decides HOW to render each (a DO/TALK/FIND shelf tile here).
 */
export interface UiVerb {
  /** Semantic modal bucket. */
  modal: 'do' | 'talk' | 'find';
  label: string;
  /** Intent the helm dispatches (REPL verb / cell mint). */
  intentType: string;
  subtitle?: string;
  icon?: string;
  /**
   * SH14 / D12 — the hat role this verb is visible to. "operator" (default)
   * shows for every hat; "admin" only for an admin hat. Managerial verbs
   * (website / widget / policy) declare "admin".
   */
  role?: HatRole;
}

export interface ExtensionInfo {
  id: string;
  label: string;
  description?: string;
  active: boolean;
  /** Canonical cartridge role ("experience" | "domain" | …); "" when absent. */
  role?: string;
  /**
   * SH1-B — the declarative surface intent. The helm treats absent/"" as
   * 'default' (see normalizeExtension). 'dedicated' = whole-surface takeover.
   */
  surfacingMode?: SurfacingMode;
  /** SH1-B — the cartridge's verb vocabulary; empty for UI-less cartridges. */
  verbs?: UiVerb[];
  /** Peer-view declaration from cartridge.json; absent when not declared. */
  peerView?: CartridgePeerViewShape;
}

/** The built-in "Home" entry — always first, never fetched from brain. */
export const CORE_EXTENSION: ExtensionInfo = {
  id: 'core',
  label: 'core',
  description: 'Attention home and global context',
  active: true,
  surfacingMode: 'default',
  verbs: [],
};

/**
 * Raw cartridge entry as it arrives in the /api/v1/info `cartridges[]`
 * array (brain wire shape; see SVELTE-HELM-CONTRACTS §1). Loose by design
 * — the Svelte bundle never imports @semantos/* types.
 */
interface RawCartridge {
  id?: string;
  label?: string;
  description?: string;
  role?: string;
  surfacingMode?: string;
  verbs?: UiVerb[];
  peerView?: CartridgePeerViewShape;
  active?: boolean;
}

const VALID_MODES: ReadonlyArray<SurfacingMode> = ['default', 'dedicated', 'passive'];

/**
 * SH14 / D12 — coerce a verb's role: only "admin" is honoured as admin;
 * anything else (missing / unknown) defaults to "operator" (base, visible to
 * every hat). Keeps the hat-gate fail-safe: a malformed role never hides a
 * verb behind admin, nor silently elevates one.
 */
export function normalizeVerb(v: UiVerb): UiVerb {
  return { ...v, role: v.role === 'admin' ? 'admin' : 'operator' };
}

/**
 * SH2-B — normalize a raw brain cartridge entry into an ExtensionInfo the
 * shell can render directly. Pure (no I/O) so it's unit-testable without a
 * live brain. Key rules:
 *   • surfacingMode "" / missing / unknown  → 'default' (the safe intent).
 *   • label falls back to id when the brain omits a display name.
 *   • verbs default to [] (UI-less / data-only cartridges).
 */
export function normalizeExtension(raw: RawCartridge): ExtensionInfo {
  const id = raw.id ?? '';
  const mode = (raw.surfacingMode && (VALID_MODES as readonly string[]).includes(raw.surfacingMode))
    ? (raw.surfacingMode as SurfacingMode)
    : 'default';
  return {
    id,
    label: raw.label && raw.label.length > 0 ? raw.label : id,
    description: raw.description,
    active: raw.active ?? false,
    role: raw.role ?? '',
    surfacingMode: mode,
    verbs: (raw.verbs ?? []).map(normalizeVerb),
    peerView: raw.peerView,
  };
}

/** Normalize the whole cartridges[] array; drops entries with no id. */
export function normalizeExtensions(raws: RawCartridge[] | undefined | null): ExtensionInfo[] {
  if (!raws) return [];
  return raws.map(normalizeExtension).filter((e) => e.id.length > 0);
}

/**
 * SH14-B / D12 — read the active hat's role from /api/v1/info's hat block.
 * Defaults to "operator" on any error / missing field / non-admin value
 * (fail-safe: the shelf never reveals admin verbs unless the brain says admin).
 */
export async function fetchActiveHatRole(brainBase: string, bearer: string): Promise<HatRole> {
  if (!brainBase || !bearer) return 'operator';
  try {
    const res = await fetch(`${brainBase}/api/v1/info`, {
      headers: { Authorization: `Bearer ${bearer}`, Accept: 'application/json' },
    });
    if (!res.ok) return 'operator';
    const data = await res.json() as { hat?: { role?: string } };
    return data.hat?.role === 'admin' ? 'admin' : 'operator';
  } catch {
    return 'operator';
  }
}

/**
 * Fetch the cartridges list from GET /api/v1/info.
 * Returns null on network error or non-2xx response.
 * The caller is responsible for prepending CORE_EXTENSION if needed.
 */
export async function fetchExtensions(
  brainBase: string,
  bearer: string,
): Promise<ExtensionInfo[] | null> {
  if (!brainBase || !bearer) return null;
  try {
    const res = await fetch(`${brainBase}/api/v1/info`, {
      headers: {
        Authorization: `Bearer ${bearer}`,
        Accept: 'application/json',
      },
    });
    if (!res.ok) return null;
    const data = await res.json() as { cartridges?: RawCartridge[] };
    // SH2-B — normalize so surfacingMode + verbs[] (SH1-B) are typed and
    // defaulted; consumers (picker, shelf, SH3 router) read them directly.
    return normalizeExtensions(data.cartridges);
  } catch {
    return null;
  }
}

```
