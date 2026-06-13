---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/components/HatSwitcher.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.069216+00:00
---

# apps/loom-svelte/src/components/HatSwitcher.svelte

```svelte
<script lang="ts">
  /**
   * HatSwitcher — top-nav hat session dropdown.
   *
   * D-svelte-hat-switcher extends the existing localStorage-backed component
   * with brain-side identity calls (D-brain-identity-store-api):
   *
   *   • On mount + each open: GET /api/v1/identity/hat refreshes the active
   *     hat's metadata (hat_name, cert_id, color_hex) into the local store.
   *   • On switch: POST /api/v1/identity/hat/switch {hat_id} + localStorage.
   *   • On cert pill click: GET /api/v1/identity/cert shows the cert snapshot.
   *
   * Brain calls are fire-and-complete; the component degrades gracefully when
   * the brain is unreachable (falls back to localStorage state only).
   *
   * Props:
   *   walletOrigin  — origin for "Pair another hat" deep-link (required)
   *   brainBase     — brain HTTP base URL (optional; skips brain calls if empty)
   *   bearer        — active bearer token (optional; required for brain calls)
   */
  import {
    hatSessions,
    setActive,
    removeSession,
    updateSession,
    type HatSession,
  } from '../lib/hat-sessions';
  import { getActiveHat, switchHat, getCert, type BrainCertSnapshot } from '../lib/identity-api';

  let {
    walletOrigin,
    brainBase = '',
    bearer = '',
  }: {
    walletOrigin: string;
    brainBase?: string;
    bearer?: string;
  } = $props();

  // ── UI state ──────────────────────────────────────────────────────────────

  let open = $state(false);
  let switching = $state<string | null>(null); // id of session being switched to
  let cert = $state<BrainCertSnapshot | null>(null);
  let certLoading = $state(false);
  let showCert = $state(false);
  let brainSynced = $state(false); // true after first successful brain sync

  // ── Derived ───────────────────────────────────────────────────────────────

  const active = $derived.by((): HatSession | null => {
    const state = $hatSessions;
    if (state.activeId === null) return null;
    return state.sessions.find((s) => s.id === state.activeId) ?? null;
  });

  const canCallBrain = $derived(brainBase.length > 0 && bearer.length > 0);

  // ── Helpers ───────────────────────────────────────────────────────────────

  function relativeTime(unixMs: number): string {
    const now = Date.now();
    const delta = Math.max(0, now - unixMs);
    if (delta < 1000)       return 'just now';
    if (delta < 60_000)     return `${Math.floor(delta / 1000)}s ago`;
    if (delta < 3_600_000)  return `${Math.floor(delta / 60_000)}m ago`;
    if (delta < 86_400_000) return `${Math.floor(delta / 3_600_000)}h ago`;
    return `${Math.floor(delta / 86_400_000)}d ago`;
  }

  function tail(s: string, n = 6): string {
    return !s ? '' : s.length <= n ? s : `…${s.slice(-n)}`;
  }

  function shortCert(certId: string): string {
    return certId.length > 12 ? `${certId.slice(0, 6)}…${certId.slice(-4)}` : certId;
  }

  // ── Brain sync ────────────────────────────────────────────────────────────

  /** Refresh the active hat's metadata from the brain; update local store if richer. */
  async function syncActiveHat() {
    if (!canCallBrain) return;
    const hat = await getActiveHat(brainBase, bearer);
    if (!hat || !active) return;
    // Patch the local session with brain-authoritative fields if they differ.
    updateSession(active.id, {
      hatId:   hat.hat_id   || active.hatId,
      hatName: hat.hat_name || active.hatName,
      certId:  hat.cert_id  || active.certId,
      colorHex: hat.color_hex || active.colorHex,
    });
    brainSynced = true;
  }

  /** Load cert snapshot for the "Cert" pill. */
  async function loadCert() {
    if (!canCallBrain) return;
    certLoading = true;
    cert = await getCert(brainBase, bearer);
    certLoading = false;
  }

  // ── Mount: sync once ──────────────────────────────────────────────────────

  $effect(() => {
    void syncActiveHat();
  });

  // ── Interactions ──────────────────────────────────────────────────────────

  function handleToggle() {
    open = !open;
    if (open) {
      showCert = false;
      // Refresh brain metadata each time the dropdown opens.
      void syncActiveHat();
    }
  }

  async function onSwitch(session: HatSession) {
    if (session.id === $hatSessions.activeId || switching) return;

    switching = session.id;

    // Call brain first (non-blocking for UX — we proceed even on failure).
    if (canCallBrain && session.hatId && session.hatId !== 'default') {
      await switchHat(brainBase, bearer, session.hatId);
    }

    // Always update localStorage (source of truth while brain migration is partial).
    setActive(session.id);
    open = false;
    switching = null;

    if (typeof document !== 'undefined') {
      document.dispatchEvent(
        new CustomEvent('hat-switched', { detail: { activeId: session.id } }),
      );
    }
  }

  function onRemove(id: string) {
    removeSession(id);
  }

  function onPairAnother() {
    if (typeof window === 'undefined') return;
    const url = `${walletOrigin}?return_to=${encodeURIComponent(window.location.origin + '/helm')}`;
    window.open(url, '_blank', 'noopener,noreferrer');
    open = false;
  }

  function toggleCert() {
    showCert = !showCert;
    if (showCert && !cert && !certLoading) {
      void loadCert();
    }
  }

  // Close on outside click / Escape.
  function handleDocClick(e: MouseEvent) {
    const target = e.target as Node;
    const el = document.querySelector('.hat-switcher');
    if (el && !el.contains(target)) open = false;
  }

  function handleDocKey(e: KeyboardEvent) {
    if (e.key === 'Escape') open = false;
  }

  $effect(() => {
    if (open) {
      document.addEventListener('click', handleDocClick);
      document.addEventListener('keydown', handleDocKey);
      return () => {
        document.removeEventListener('click', handleDocClick);
        document.removeEventListener('keydown', handleDocKey);
      };
    }
  });
</script>

<div class="hat-switcher">
  {#if active}
    <button
      class="hat-active"
      onclick={handleToggle}
      title={`Active hat: ${active.hatName}`}
      aria-haspopup="menu"
      aria-expanded={open}
    >
      <span
        class="hat-avatar"
        style="background-color: {active.colorHex || 'var(--color-primary, #4F46E5)'};"
      ></span>
      <span class="hat-name">{active.hatName}</span>
      {#if canCallBrain && brainSynced}
        <span class="brain-dot" title="Synced with brain"></span>
      {/if}
      <span class="hat-caret">{open ? '▴' : '▾'}</span>
    </button>
  {:else}
    <button class="hat-pair-cta" onclick={onPairAnother}>
      Pair a hat
    </button>
  {/if}

  {#if open && active}
    <div class="hat-menu" role="menu">
      <!-- Cert row (if brain available) -->
      {#if canCallBrain}
        <div class="cert-section">
          <button class="cert-toggle" onclick={toggleCert}>
            <span class="cert-label">Cert</span>
            {#if active.certId}
              <span class="cert-id">{shortCert(active.certId)}</span>
            {:else}
              <span class="cert-unknown">unknown</span>
            {/if}
            <span class="cert-chevron">{showCert ? '▴' : '▾'}</span>
          </button>

          {#if showCert}
            <div class="cert-detail">
              {#if certLoading}
                <span class="cert-loading">Loading…</span>
              {:else if cert}
                <dl class="cert-dl">
                  <dt>ID</dt><dd class="mono">{shortCert(cert.cert_id)}</dd>
                  <dt>Label</dt><dd>{cert.label || '—'}</dd>
                  <dt>Status</dt>
                  <dd>
                    {#if cert.active}
                      <span class="cert-active-badge">active</span>
                    {:else}
                      <span class="cert-revoked-badge">revoked</span>
                    {/if}
                  </dd>
                </dl>
              {:else}
                <span class="cert-none">No cert linked to this bearer.</span>
              {/if}
            </div>
          {/if}
        </div>
        <div class="menu-sep"></div>
      {/if}

      <!-- Hat list -->
      <ul>
        {#each $hatSessions.sessions as s (s.id)}
          <li class:active-row={s.id === $hatSessions.activeId}>
            <span
              class="hat-avatar small"
              style="background-color: {s.colorHex || 'var(--color-primary, #4F46E5)'};"
            ></span>
            <div class="hat-row-text">
              <strong>{s.hatName}</strong>
              {#if s.hatId && s.hatId !== 'default'}
                <span class="hat-id-tail">{tail(s.hatId)}</span>
              {/if}
              <span class="hat-last-used">{relativeTime(s.lastUsedAt)}</span>
            </div>
            <div class="hat-row-actions">
              {#if s.id !== $hatSessions.activeId}
                <button
                  onclick={() => onSwitch(s)}
                  class="hat-row-switch"
                  disabled={switching === s.id}
                >
                  {switching === s.id ? '…' : 'Switch'}
                </button>
              {:else}
                <span class="active-badge">active</span>
              {/if}
              <button onclick={() => onRemove(s.id)} class="hat-row-remove">
                Remove
              </button>
            </div>
          </li>
        {/each}
      </ul>

      <!-- Footer -->
      <div class="hat-menu-footer">
        <button class="hat-pair-another" onclick={onPairAnother}>
          + Pair another hat
        </button>
      </div>
    </div>
  {/if}
</div>

<style>
  .hat-switcher {
    position: relative;
    display: inline-flex;
    align-items: center;
  }

  /* ── Trigger ── */
  .hat-active,
  .hat-pair-cta {
    display: inline-flex;
    align-items: center;
    gap: 0.4em;
    padding: 0.25em 0.6em;
    border: 1px solid rgba(255,255,255,0.12);
    border-radius: 0.375rem;
    background: rgba(255,255,255,0.05);
    cursor: pointer;
    font: inherit;
    color: #e2e8f0;
    transition: background 0.1s, border-color 0.1s;
  }

  .hat-active:hover,
  .hat-pair-cta:hover {
    background: rgba(255,255,255,0.1);
    border-color: rgba(255,255,255,0.2);
  }

  .hat-avatar {
    width: 0.875em;
    height: 0.875em;
    border-radius: 50%;
    display: inline-block;
    flex-shrink: 0;
    border: 1px solid rgba(255,255,255,0.2);
  }

  .hat-avatar.small {
    width: 0.75em;
    height: 0.75em;
  }

  .hat-name {
    font-size: 0.875rem;
    font-weight: 500;
    max-width: 120px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .brain-dot {
    width: 5px;
    height: 5px;
    border-radius: 50%;
    background: #4ade80;
    flex-shrink: 0;
  }

  .hat-caret {
    font-size: 0.625rem;
    color: #64748b;
  }

  /* ── Dropdown ── */
  .hat-menu {
    position: absolute;
    right: 0;
    top: calc(100% + 0.375em);
    min-width: 18em;
    background: #1e293b;
    border: 1px solid #334155;
    border-radius: 0.5rem;
    box-shadow: 0 8px 24px rgba(0,0,0,0.4);
    z-index: 200;
    overflow: hidden;
  }

  /* ── Cert section ── */
  .cert-section {
    padding: 0.25rem 0;
  }

  .cert-toggle {
    display: flex;
    align-items: center;
    gap: 0.375rem;
    width: 100%;
    padding: 0.375rem 0.75rem;
    background: transparent;
    border: none;
    cursor: pointer;
    color: #94a3b8;
    font-size: 0.75rem;
    text-align: left;
    transition: background 0.1s;
  }

  .cert-toggle:hover { background: rgba(255,255,255,0.04); }

  .cert-label {
    font-weight: 600;
    color: #64748b;
    font-size: 0.6875rem;
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  .cert-id {
    font-family: monospace;
    color: #60a5fa;
    font-size: 0.75rem;
    flex: 1;
  }

  .cert-unknown {
    color: #475569;
    font-size: 0.75rem;
    flex: 1;
  }

  .cert-chevron {
    font-size: 0.5rem;
    color: #475569;
  }

  .cert-detail {
    padding: 0.375rem 0.75rem 0.5rem;
    background: rgba(15, 23, 42, 0.5);
  }

  .cert-loading,
  .cert-none {
    font-size: 0.75rem;
    color: #475569;
    font-style: italic;
  }

  .cert-dl {
    display: grid;
    grid-template-columns: auto 1fr;
    gap: 0.125rem 0.5rem;
    margin: 0;
    font-size: 0.75rem;
  }

  .cert-dl dt { color: #475569; }
  .cert-dl dd { margin: 0; color: #94a3b8; }
  .cert-dl .mono { font-family: monospace; color: #60a5fa; }

  .cert-active-badge {
    background: rgba(74, 222, 128, 0.15);
    color: #4ade80;
    border-radius: 999px;
    padding: 0 0.375rem;
    font-size: 0.6875rem;
  }

  .cert-revoked-badge {
    background: rgba(239, 68, 68, 0.15);
    color: #f87171;
    border-radius: 999px;
    padding: 0 0.375rem;
    font-size: 0.6875rem;
  }

  .menu-sep {
    height: 1px;
    background: #1e293b;
    margin: 0;
  }

  /* ── Hat list ── */
  .hat-menu ul {
    list-style: none;
    margin: 0;
    padding: 0.25rem 0;
  }

  .hat-menu li {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    padding: 0.5rem 0.75rem;
    border-bottom: 1px solid rgba(51, 65, 85, 0.4);
    transition: background 0.1s;
  }

  .hat-menu li:last-child { border-bottom: none; }
  .hat-menu li:hover { background: rgba(255,255,255,0.03); }
  .hat-menu li.active-row { background: rgba(59, 130, 246, 0.06); }

  .hat-row-text {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 1px;
    min-width: 0;
  }

  .hat-row-text strong {
    font-size: 0.875rem;
    font-weight: 500;
    color: #e2e8f0;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .hat-id-tail {
    font-family: monospace;
    font-size: 0.6875rem;
    color: #475569;
  }

  .hat-last-used {
    font-size: 0.6875rem;
    color: #334155;
  }

  .hat-row-actions {
    display: flex;
    align-items: center;
    gap: 0.25rem;
    flex-shrink: 0;
  }

  .hat-row-actions button {
    padding: 0.125rem 0.5rem;
    border: 1px solid #334155;
    border-radius: 0.25rem;
    background: transparent;
    cursor: pointer;
    font-size: 0.75rem;
    transition: background 0.1s, color 0.1s;
  }

  .hat-row-switch {
    color: #60a5fa;
    border-color: rgba(96, 165, 250, 0.3) !important;
  }

  .hat-row-switch:hover:not(:disabled) {
    background: rgba(96, 165, 250, 0.1);
  }

  .hat-row-switch:disabled {
    opacity: 0.5;
    cursor: default;
  }

  .hat-row-remove {
    color: #64748b;
  }

  .hat-row-remove:hover {
    background: rgba(239, 68, 68, 0.1);
    color: #f87171;
    border-color: rgba(239, 68, 68, 0.3) !important;
  }

  .active-badge {
    font-size: 0.6875rem;
    color: #4ade80;
    background: rgba(74, 222, 128, 0.1);
    border: 1px solid rgba(74, 222, 128, 0.2);
    border-radius: 999px;
    padding: 0.0625rem 0.5rem;
  }

  /* ── Footer ── */
  .hat-menu-footer {
    border-top: 1px solid #1e293b;
    padding: 0.375rem 0.625rem;
  }

  .hat-pair-another {
    width: 100%;
    border: none;
    background: transparent;
    cursor: pointer;
    font: inherit;
    font-size: 0.8125rem;
    padding: 0.25rem;
    color: #60a5fa;
    text-align: left;
    transition: color 0.1s;
  }

  .hat-pair-another:hover { color: #93c5fd; }
</style>

```
