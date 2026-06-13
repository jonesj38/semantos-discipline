---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/shell/ExtensionSwitcher.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.084997+00:00
---

# apps/loom-svelte/src/shell/ExtensionSwitcher.svelte

```svelte
<script lang="ts">
  /**
   * ExtensionSwitcher — "what am I doing?" workspace selector.
   *
   * D-svelte-extension-switcher: Svelte port of
   * apps/loom-react/src/helm/ExtensionSwitcher.tsx.
   *
   * Distinct from HatSwitcher ("who am I being?").  An extension / cartridge
   * re-weights which types populate the centre slot and tier-3 popovers — it
   * does NOT change the 15-context grammar.
   *
   * Cartridge list is fetched from GET /api/v1/info's `cartridges` array via
   * lib/extensions-api.ts.  The "core" entry (attention home) is always first.
   * Switching fires onSwitch(id) where id is the extension's stable id string
   * ('core' maps to activeCartridge = null in App.svelte).
   *
   * Degrades gracefully when brain is unavailable: shows core + any
   * hardcoded fallback extensions.
   */
  import { fetchExtensions, CORE_EXTENSION, type ExtensionInfo, type CartridgePeerViewShape, type UiVerb, type SurfacingMode } from '../lib/extensions-api';

  let {
    brainBase = '',
    bearer = '',
    activeId,
    onSwitch,
  }: {
    brainBase?: string;
    bearer?: string;
    /** Currently active extension id. null or 'core' both mean home. */
    activeId: string | null;
    /**
     * Called when the operator picks a workspace.
     * peerView is the cartridge's declared peer-view (null for core / undeclared).
     * verbs is the cartridge's declarative ui.verbs[] overlay (SH2-B / D11) —
     * empty for core or cartridges that declare none.
     * surfacingMode (SH3 / D11) drives the body route: default | dedicated.
     */
    onSwitch: (id: string, peerView: CartridgePeerViewShape | null, verbs: UiVerb[], surfacingMode: SurfacingMode) => void;
  } = $props();

  // ── State ─────────────────────────────────────────────────────────────────

  let open = $state(false);
  let extensions = $state<ExtensionInfo[]>([CORE_EXTENSION]);
  let loaded = $state(false);

  // ── Derived ───────────────────────────────────────────────────────────────

  /** Normalise: null → 'core'. */
  const effectiveId = $derived(activeId ?? 'core');

  const activeExt = $derived(
    extensions.find(e => e.id === effectiveId) ?? CORE_EXTENSION,
  );

  const activeLabel = $derived(
    activeExt.id === 'core' ? 'Home' : activeExt.label,
  );

  // ── Load ──────────────────────────────────────────────────────────────────

  $effect(() => {
    if (!loaded) void loadExtensions();
  });

  async function loadExtensions() {
    const fetched = await fetchExtensions(brainBase, bearer);
    if (fetched && fetched.length > 0) {
      // Always keep core first; append any brain-returned cartridges.
      // SH3 / D11 — passive cartridges are not operator-facing: exclude them
      // from the picker (they have no surface).
      const extras = fetched.filter(e => e.id !== 'core' && e.surfacingMode !== 'passive');
      extensions = [
        CORE_EXTENSION,
        ...extras,
      ];
    } else {
      // Brain unavailable or returned nothing — keep static fallback.
      extensions = [
        CORE_EXTENSION,
        { id: 'oddjobz', label: 'Oddjobz', description: 'Field jobs & quoting', active: false },
      ];
    }
    loaded = true;
  }

  // ── Interactions ──────────────────────────────────────────────────────────

  function handleToggle() {
    open = !open;
  }

  function select(ext: ExtensionInfo) {
    open = false;
    onSwitch(ext.id, ext.peerView ?? null, ext.verbs ?? [], ext.surfacingMode ?? 'default');
  }

  // Close on outside click / Escape.
  function onDocClick(e: MouseEvent) {
    const el = document.querySelector('.ext-switcher');
    if (el && !el.contains(e.target as Node)) open = false;
  }

  function onDocKey(e: KeyboardEvent) {
    if (e.key === 'Escape') open = false;
  }

  $effect(() => {
    if (open) {
      document.addEventListener('click', onDocClick);
      document.addEventListener('keydown', onDocKey);
      return () => {
        document.removeEventListener('click', onDocClick);
        document.removeEventListener('keydown', onDocKey);
      };
    }
  });
</script>

<div class="ext-switcher">
  <button
    class="ext-trigger"
    onclick={handleToggle}
    aria-haspopup="menu"
    aria-expanded={open}
    title="Switch workspace"
  >
    <span class="ext-icon">▣</span>
    <span class="ext-label">{activeLabel}</span>
    <span class="ext-caret">{open ? '▴' : '▾'}</span>
  </button>

  {#if open}
    <div class="ext-menu" role="menu">
      <div class="ext-menu-header">Workspace</div>
      {#each extensions as ext (ext.id)}
        <button
          class="ext-row"
          class:ext-active={ext.id === effectiveId}
          onclick={() => select(ext)}
          role="menuitem"
        >
          <div class="ext-row-main">
            <span class="ext-row-label">{ext.id === 'core' ? 'Home' : ext.label}</span>
            {#if ext.id === effectiveId}
              <span class="ext-active-badge">active</span>
            {/if}
          </div>
          {#if ext.description}
            <div class="ext-row-desc">{ext.description}</div>
          {/if}
        </button>
      {/each}
      <div class="ext-menu-footer">
        More workspaces land with the cartridge-manifest pass.
      </div>
    </div>
  {/if}
</div>

<style>
  .ext-switcher {
    position: relative;
    display: inline-flex;
    align-items: center;
  }

  /* ── Trigger ── */
  .ext-trigger {
    display: inline-flex;
    align-items: center;
    gap: 0.3125rem;
    padding: 0.25rem 0.625rem;
    background: rgba(255,255,255,0.05);
    border: 1px solid rgba(255,255,255,0.1);
    border-radius: 0.375rem;
    color: #e2e8f0;
    font: inherit;
    font-size: 0.8125rem;
    cursor: pointer;
    transition: background 0.1s, border-color 0.1s;
  }

  .ext-trigger:hover {
    background: rgba(255,255,255,0.1);
    border-color: rgba(255,255,255,0.18);
  }

  .ext-icon {
    font-size: 0.75rem;
    color: #64748b;
  }

  .ext-label {
    font-weight: 500;
    color: #f1f5f9;
    max-width: 100px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .ext-caret {
    font-size: 0.5rem;
    color: #64748b;
  }

  /* ── Dropdown ── */
  .ext-menu {
    position: absolute;
    left: 50%;
    transform: translateX(-50%);
    top: calc(100% + 0.375rem);
    min-width: 200px;
    background: #1e293b;
    border: 1px solid #334155;
    border-radius: 0.5rem;
    box-shadow: 0 8px 24px rgba(0,0,0,0.4);
    z-index: 200;
    overflow: hidden;
  }

  .ext-menu-header {
    padding: 0.375rem 0.75rem;
    font-size: 0.6875rem;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: #475569;
    border-bottom: 1px solid #1e293b;
  }

  /* ── Rows ── */
  .ext-row {
    display: flex;
    flex-direction: column;
    gap: 0.125rem;
    width: 100%;
    padding: 0.5rem 0.75rem;
    background: transparent;
    border: none;
    border-bottom: 1px solid rgba(51,65,85,0.4);
    cursor: pointer;
    text-align: left;
    color: inherit;
    transition: background 0.1s;
  }

  .ext-row:last-of-type { border-bottom: none; }
  .ext-row:hover { background: rgba(255,255,255,0.04); }
  .ext-row.ext-active { background: rgba(59, 130, 246, 0.08); }

  .ext-row-main {
    display: flex;
    align-items: center;
    gap: 0.5rem;
  }

  .ext-row-label {
    font-size: 0.875rem;
    font-weight: 500;
    color: #e2e8f0;
  }

  .ext-active-badge {
    font-size: 0.625rem;
    background: rgba(74, 222, 128, 0.15);
    color: #4ade80;
    border: 1px solid rgba(74, 222, 128, 0.2);
    border-radius: 999px;
    padding: 0.0625rem 0.375rem;
    flex-shrink: 0;
  }

  .ext-row-desc {
    font-size: 0.75rem;
    color: #475569;
  }

  /* ── Footer ── */
  .ext-menu-footer {
    padding: 0.375rem 0.75rem;
    font-size: 0.6875rem;
    color: #334155;
    font-style: italic;
    border-top: 1px solid #1e293b;
  }
</style>

```
