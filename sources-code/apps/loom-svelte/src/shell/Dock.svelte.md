---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/shell/Dock.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.086170+00:00
---

# apps/loom-svelte/src/shell/Dock.svelte

```svelte
<script lang="ts">
  import {
    KERNEL_CONTEXT_WEIGHTS,
    resolveFavourites,
    DO_CONTEXTS,
    TALK_CONTEXTS,
    FIND_CONTEXTS,
    type ContextPath,
    type IntentId,
  } from './context-weights';
  // SH2-B / DECISION D11 — cartridge verb overlay on the kernel CSD pyramid.
  import { composeShelfModal, filterVerbsByHatRole } from './shelf-compose';
  import type { UiVerb, HatRole } from '../lib/extensions-api';

  let {
    onGoHome,
    homeBadge = 0,
    onInvoke = () => {},
    directContextNav = {},
    cartridgeVerbs = [],
    hatRole = 'operator',
  }: {
    onGoHome: () => void;
    homeBadge?: number;
    onInvoke?: (command: string) => void;
    /** Context paths that navigate directly (skip tier-3). Map contextPath → command. */
    directContextNav?: Partial<Record<ContextPath, string>>;
    /**
     * SH2-B / D11 — the ACTIVE cartridge's declarative ui.verbs[] (all
     * modals). Composed onto the kernel pyramid per modal as direct-dispatch
     * overlay tiles. Empty at home / for cartridges that declare no verbs.
     */
    cartridgeVerbs?: UiVerb[];
    /**
     * SH14-B / D12 — the active hat role. operator (default) hides admin
     * overlay verbs; admin reveals the managerial verbs too.
     */
    hatRole?: HatRole;
  } = $props();

  let activeIntent = $state<IntentId | null>(null);
  let activeContext = $state<string | null>(null);
  let tier3Input = $state('');

  // Tier 2 contexts for the active intent
  const tier2Contexts = $derived(
    activeIntent === 'do' ? DO_CONTEXTS :
    activeIntent === 'talk' ? TALK_CONTEXTS :
    activeIntent === 'find' ? FIND_CONTEXTS : []
  );

  // Tier 3 favourites for the active context
  const tier3Favourites = $derived.by(() => {
    if (!activeIntent || !activeContext) return [];
    const path = `${activeIntent}.${activeContext}` as ContextPath;
    return resolveFavourites(path, KERNEL_CONTEXT_WEIGHTS);
  });

  // SH2-B / D11 — the active cartridge's overlay verbs for the active modal,
  // rendered as direct-dispatch tiles in the tier-2 strip alongside the kernel
  // contexts. Empty when no modal is open or the cartridge declares none.
  const overlayVerbs = $derived(
    activeIntent
      ? filterVerbsByHatRole(composeShelfModal(activeIntent, cartridgeVerbs).cartridgeVerbs, hatRole)
      : []
  );

  function handleOverlayVerbClick(verb: UiVerb) {
    onInvoke(verb.intentType);
    activeIntent = null;
    activeContext = null;
  }

  // Keyboard shortcuts
  $effect(() => {
    function handler(e: KeyboardEvent) {
      const tag = (e.target as HTMLElement)?.tagName;
      if (tag === 'INPUT' || tag === 'TEXTAREA') return;
      if (e.ctrlKey || e.metaKey || e.altKey) return;
      if (e.key === 'Escape') { activeContext = null; activeIntent = null; return; }
      if (e.key.toLowerCase() === 'd') { e.preventDefault(); activeIntent = activeIntent === 'do' ? null : 'do'; activeContext = null; }
      if (e.key.toLowerCase() === 't') { e.preventDefault(); activeIntent = activeIntent === 'talk' ? null : 'talk'; activeContext = null; }
      if (e.key.toLowerCase() === 'f') { e.preventDefault(); activeIntent = activeIntent === 'find' ? null : 'find'; activeContext = null; }
    }
    document.addEventListener('keydown', handler);
    return () => document.removeEventListener('keydown', handler);
  });

  // Click outside to close
  $effect(() => {
    if (!activeIntent) return;
    function handler(e: MouseEvent) {
      const target = e.target as HTMLElement;
      if (target.closest('[data-dock-root]')) return;
      activeIntent = null;
      activeContext = null;
    }
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  });

  function handleIntentClick(intent: IntentId) {
    if (activeIntent === intent) { activeIntent = null; activeContext = null; }
    else { activeIntent = intent; activeContext = null; }
  }

  function handleContextClick(contextId: string) {
    if (activeIntent) {
      const path = `${activeIntent}.${contextId}` as ContextPath;
      const navCmd = directContextNav[path];
      if (navCmd) {
        onInvoke(navCmd);
        activeIntent = null;
        activeContext = null;
        return;
      }
    }
    activeContext = activeContext === contextId ? null : contextId;
    tier3Input = '';
  }

  function handleFavouriteClick(command: string, stubbed: boolean) {
    if (stubbed) return; // TODO: show stub hint
    onInvoke(command);
    activeIntent = null;
    activeContext = null;
  }

  function handleTier3Submit(e: SubmitEvent) {
    e.preventDefault();
    const cmd = tier3Input.trim();
    if (!cmd) return;
    onInvoke(cmd);
    activeIntent = null;
    activeContext = null;
    tier3Input = '';
  }

  const INTENTS = [
    { id: 'do' as IntentId, label: 'Do', icon: '⚡', key: 'D' },
    { id: 'talk' as IntentId, label: 'Talk', icon: '💬', key: 'T' },
    { id: 'find' as IntentId, label: 'Find', icon: '🔍', key: 'F' },
  ];
</script>

<!-- Tier 3 popover -->
{#if activeIntent && activeContext}
<div class="tier3-overlay" data-dock-root>
  <div class="tier3-popover">
    <div class="tier3-header">
      {tier2Contexts.find(c => c.id === activeContext)?.icon ?? ''}
      {tier2Contexts.find(c => c.id === activeContext)?.label ?? ''}
    </div>
    <div class="tier3-favs">
      {#each tier3Favourites as fav, i}
        <button
          class="fav-btn"
          class:stubbed={fav.stubbed}
          onclick={() => handleFavouriteClick(fav.command, fav.stubbed ?? false)}
          title={fav.stubbed ? 'Coming soon' : fav.command}
        >
          <span class="fav-star">{fav.stubbed ? '○' : '★'}</span>
          {fav.label}
          {#if fav.stubbed}<span class="soon-badge">soon</span>{/if}
          <kbd class="fav-key">{i + 1}</kbd>
        </button>
      {/each}
      {#if tier3Favourites.length === 0}
        <div class="no-favs">Type a command below.</div>
      {/if}
    </div>
    <form onsubmit={handleTier3Submit} class="tier3-input-row">
      <span class="tier3-prompt">▷</span>
      <input
        type="text"
        bind:value={tier3Input}
        placeholder="type a command…"
        autocomplete="off"
        spellcheck={false}
      />
    </form>
  </div>
</div>
{/if}

<!-- Tier 2 context strip — shown when intent is active but no context selected -->
{#if activeIntent && !activeContext}
<div class="tier2-strip" data-dock-root>
  {#each tier2Contexts as ctx}
    <button
      class="ctx-btn"
      class:active={activeContext === ctx.id}
      onclick={() => handleContextClick(ctx.id)}
      title={ctx.description}
    >
      <span class="ctx-icon">{ctx.icon}</span>
      <span class="ctx-label">{ctx.label}</span>
    </button>
  {/each}
  <!-- SH2-B / D11 — active cartridge's overlay verbs (direct-dispatch). -->
  {#each overlayVerbs as v}
    <button
      class="ctx-btn overlay-verb"
      onclick={() => handleOverlayVerbClick(v)}
      title={v.subtitle ?? v.label}
    >
      <span class="ctx-icon">{v.icon ?? '◆'}</span>
      <span class="ctx-label">{v.label}</span>
    </button>
  {/each}
</div>
{/if}
<!-- When a context is active (tier 3 open), still show tier 2 for context switch -->
{#if activeIntent && activeContext}
<div class="tier2-strip tier2-under-tier3" data-dock-root>
  {#each tier2Contexts as ctx}
    <button
      class="ctx-btn"
      class:active={activeContext === ctx.id}
      onclick={() => handleContextClick(ctx.id)}
      title={ctx.description}
    >
      <span class="ctx-icon">{ctx.icon}</span>
      <span class="ctx-label">{ctx.label}</span>
    </button>
  {/each}
</div>
{/if}

<!-- Tier 1: Home + intents -->
<nav data-dock-root class="dock-tier1">
  <button class="dock-btn" onclick={onGoHome} aria-label="Home">
    <span class="dock-icon">⚓</span>
    <span class="dock-label">Home</span>
    {#if homeBadge > 0}
      <span class="dock-badge">{homeBadge > 99 ? '99+' : homeBadge}</span>
    {/if}
  </button>
  {#each INTENTS as intent}
    <button
      class="dock-btn"
      class:active={activeIntent === intent.id}
      onclick={() => handleIntentClick(intent.id)}
      aria-label={intent.label}
    >
      <span class="dock-icon">{intent.icon}</span>
      <span class="dock-label">
        {intent.label}
        <kbd class="dock-key">{intent.key}</kbd>
      </span>
    </button>
  {/each}
</nav>

<style>
  /* ── Tier 1 — always-visible dock bar ── */
  .dock-tier1 {
    display: flex;
    align-items: center;
    justify-content: space-around;
    background: #111827;
    border-top: 1px solid #374151;
    padding: 0.25rem 0.5rem;
    height: 64px;
  }

  .dock-btn {
    position: relative;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 2px;
    padding: 0.375rem 1.5rem;
    border: none;
    background: transparent;
    color: #9ca3af;
    border-radius: 0.5rem;
    cursor: pointer;
    transition: color 0.15s, background 0.15s;
    font-size: 0.75rem;
  }

  .dock-btn:hover {
    color: #e5e7eb;
    background: rgba(55, 65, 81, 0.5);
  }

  .dock-btn.active {
    color: #60a5fa;
    background: #1f2937;
  }

  .dock-icon {
    font-size: 1.125rem;
    line-height: 1;
  }

  .dock-label {
    font-size: 0.6875rem;
    font-weight: 500;
    display: flex;
    align-items: center;
    gap: 3px;
  }

  .dock-key {
    font-size: 0.5625rem;
    font-family: monospace;
    color: #4b5563;
    border: 1px solid #374151;
    border-radius: 2px;
    padding: 0 3px;
    line-height: 1.2;
  }

  .dock-badge {
    position: absolute;
    top: 0;
    right: 0.5rem;
    min-width: 18px;
    height: 18px;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 9999px;
    background: #ef4444;
    color: #fff;
    font-size: 0.625rem;
    font-weight: 600;
    padding: 0 3px;
  }

  /* ── Tier 2 — context strip ── */
  .tier2-strip {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 0.25rem;
    background: rgba(17, 24, 39, 0.97);
    border: 1px solid #374151;
    border-radius: 0.5rem;
    box-shadow: 0 10px 25px rgba(0, 0, 0, 0.4);
    padding: 0.25rem 0.5rem;
    margin: 0 auto 0.25rem;
    width: fit-content;
    max-width: 100%;
  }

  .tier2-under-tier3 {
    margin-bottom: 0.25rem;
  }

  .ctx-btn {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    width: 3.5rem;
    height: 3.5rem;
    border: none;
    background: transparent;
    color: #9ca3af;
    border-radius: 0.375rem;
    cursor: pointer;
    transition: color 0.15s, background 0.15s;
    gap: 2px;
  }

  .ctx-btn:hover {
    color: #f3f4f6;
    background: #1f2937;
  }

  .ctx-btn.active {
    color: #f3f4f6;
    background: #374151;
  }

  .ctx-icon {
    font-size: 1.25rem;
    line-height: 1;
  }

  .ctx-label {
    font-size: 0.625rem;
    font-weight: 500;
  }

  /* ── Tier 3 — popover overlay ── */
  .tier3-overlay {
    display: flex;
    justify-content: center;
    margin-bottom: 0.25rem;
  }

  .tier3-popover {
    background: #111827;
    border: 1px solid #374151;
    border-radius: 0.5rem;
    box-shadow: 0 20px 40px rgba(0, 0, 0, 0.6);
    padding: 0.5rem;
    min-width: 280px;
    max-width: 360px;
    width: 100%;
  }

  .tier3-header {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    padding: 0.25rem 0.5rem;
    font-size: 0.75rem;
    color: #9ca3af;
    border-bottom: 1px solid #1f2937;
    margin-bottom: 0.5rem;
  }

  .tier3-favs {
    display: flex;
    flex-direction: column;
    gap: 2px;
    margin-bottom: 0.5rem;
  }

  .fav-btn {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    padding: 0.375rem 0.5rem;
    border: none;
    background: transparent;
    color: #e5e7eb;
    border-radius: 0.25rem;
    cursor: pointer;
    text-align: left;
    font-size: 0.875rem;
    transition: background 0.1s;
    width: 100%;
  }

  .fav-btn:hover {
    background: #1f2937;
    color: #fff;
  }

  .fav-btn.stubbed {
    opacity: 0.7;
  }

  .fav-star {
    color: #eab308;
    font-size: 0.875rem;
    flex-shrink: 0;
  }

  .fav-btn.stubbed .fav-star {
    color: #4b5563;
  }

  .soon-badge {
    font-size: 0.5625rem;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: rgba(251, 191, 36, 0.8);
    border: 1px solid rgba(245, 158, 11, 0.3);
    border-radius: 2px;
    padding: 1px 3px;
    margin-left: auto;
  }

  .fav-key {
    font-size: 0.625rem;
    font-family: monospace;
    color: #6b7280;
    background: #1f2937;
    border-radius: 2px;
    padding: 1px 4px;
    margin-left: auto;
  }

  .fav-btn:hover .fav-key {
    opacity: 1;
  }

  .no-favs {
    font-size: 0.75rem;
    color: #6b7280;
    padding: 0.75rem 0.5rem;
    text-align: center;
  }

  .tier3-input-row {
    display: flex;
    align-items: center;
    gap: 0.25rem;
    background: #1f2937;
    border-radius: 0.25rem;
    padding: 0.25rem 0.5rem;
    border-top: 1px solid #1f2937;
    margin-top: 0.5rem;
  }

  .tier3-prompt {
    color: #6b7280;
    font-size: 0.75rem;
    flex-shrink: 0;
  }

  .tier3-input-row input {
    flex: 1;
    background: transparent;
    border: none;
    outline: none;
    color: #f3f4f6;
    font-size: 0.875rem;
    font-family: monospace;
  }

  .tier3-input-row input::placeholder {
    color: #6b7280;
  }
</style>

```
