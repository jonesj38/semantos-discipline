---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/shell/me/MePanel.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.090360+00:00
---

# apps/loom-svelte/src/shell/me/MePanel.svelte

```svelte
<script lang="ts">
  // MePanel — SH5 (svelte-helm matrix; DECISIONS D13 + D1).
  //
  // The consolidated identity surface (mirrors the Flutter helm "me"
  // surface): identity cert in effect + hat switching with operator/admin
  // role + wallet + contacts/PKI. Opened from a "me" affordance in the
  // AppBar AND a `view:me` dispatch (so the TALK tab can reach it). The
  // HatSwitcher lives HERE now, not as loose AppBar chrome.
  import HatSwitcher from '../../components/HatSwitcher.svelte';
  import { getCert, fetchBrainInfo, type BrainCertSnapshot, type BrainInfo } from '../../lib/identity-api';
  import type { HatRole } from '../../lib/extensions-api';
  import { shortId, roleLabel, formatIssued } from './me-format';

  let {
    brainBase = '',
    bearer = '',
    walletOrigin,
    hatRole = 'operator',
    onClose = () => {},
    onOpenContacts = () => {},
  }: {
    brainBase?: string;
    bearer?: string;
    walletOrigin: string;
    hatRole?: HatRole;
    onClose?: () => void;
    onOpenContacts?: () => void;
  } = $props();

  let cert = $state<BrainCertSnapshot | null>(null);
  let certLoaded = $state(false);
  let info = $state<BrainInfo | null>(null);

  $effect(() => {
    if (!brainBase || !bearer) { certLoaded = true; return; }
    void getCert(brainBase, bearer)
      .then((c) => { cert = c; certLoaded = true; })
      .catch(() => { certLoaded = true; });
    void fetchBrainInfo(brainBase, bearer)
      .then((i) => { info = i; })
      .catch(() => {});
  });

  // Same-origin WSS wallet endpoint (the brain that serves this SPA).
  const walletEndpoint = typeof window !== 'undefined'
    ? `${window.location.protocol}//${window.location.host}/api/v1/wallet`
    : '';
</script>

<div class="me-overlay" role="presentation" onclick={onClose}>
  <!-- stop propagation so clicks inside the panel don't close it -->
  <div
    class="me-panel"
    role="dialog"
    aria-label="Me — identity and wallet"
    tabindex="-1"
    onclick={(e) => e.stopPropagation()}
    onkeydown={(e) => { if (e.key === 'Escape') onClose(); }}
  >
    <header class="me-header">
      <h2>Me</h2>
      <button class="me-close" onclick={onClose} aria-label="Close">✕</button>
    </header>

    <!-- Identity cert in effect -->
    <section class="me-section">
      <h3>Identity cert</h3>
      {#if !certLoaded}
        <p class="me-muted">Loading…</p>
      {:else if cert}
        <dl class="me-kv">
          <dt>Cert</dt><dd><code>{shortId(cert.cert_id)}</code></dd>
          <dt>Label</dt><dd>{cert.label || '—'}</dd>
          <dt>Issued</dt><dd>{formatIssued(cert.issued_at)}</dd>
          <dt>Status</dt><dd>{cert.active ? 'active' : 'inactive'}</dd>
        </dl>
      {:else}
        <p class="me-muted">No cert linked to this hat yet.</p>
      {/if}
    </section>

    <!-- Hat + operator/admin role -->
    <section class="me-section">
      <h3>
        Hat
        <span class="role-badge" class:admin={hatRole === 'admin'}>{roleLabel(hatRole)}</span>
      </h3>
      <HatSwitcher {walletOrigin} {brainBase} {bearer} />
    </section>

    <!-- Wallet in effect -->
    <section class="me-section">
      <h3>Wallet</h3>
      <p class="me-muted">{walletEndpoint}</p>
      {#if walletOrigin}
        <a class="me-link" href={walletOrigin} target="_blank" rel="noopener">Open wallet ↗</a>
      {:else}
        <p class="me-muted">No wallet origin configured.</p>
      {/if}
    </section>

    <!-- Brain — operator pin pubkey + version + installed cartridges (parity
         with the PWA "me" sheet; sourced from GET /api/v1/info). -->
    {#if info}
      <section class="me-section">
        <h3>Brain</h3>
        <dl class="me-kv">
          <dt>Pubkey</dt><dd><code>{shortId(info.pinPubkey, 10, 6)}</code></dd>
          {#if info.pinCertId}
            <dt>Pin cert</dt><dd><code>{shortId(info.pinCertId)}</code></dd>
          {/if}
          <dt>Version</dt><dd>{info.serverVersion || '—'}</dd>
          <dt>Cartridges</dt>
          <dd>{info.cartridges.length > 0 ? info.cartridges.join(', ') : 'none'}</dd>
        </dl>
      </section>
    {/if}

    <!-- Contacts / PKI -->
    <section class="me-section">
      <h3>Contacts &amp; PKI</h3>
      <button class="me-link-btn" onclick={onOpenContacts}>Open contacts →</button>
    </section>
  </div>
</div>

<style>
  .me-overlay {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.5);
    display: flex;
    justify-content: flex-end;
    z-index: 50;
  }
  .me-panel {
    width: 24rem;
    max-width: 90vw;
    height: 100%;
    overflow-y: auto;
    background: #111827;
    border-left: 1px solid #374151;
    color: #e5e7eb;
    padding: 1rem 1.25rem;
  }
  .me-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: 0.5rem;
  }
  .me-header h2 { font-size: 1.125rem; margin: 0; }
  .me-close {
    background: transparent;
    border: none;
    color: #9ca3af;
    font-size: 1rem;
    cursor: pointer;
  }
  .me-close:hover { color: #e5e7eb; }
  .me-section {
    border-top: 1px solid #1f2937;
    padding: 0.75rem 0;
  }
  .me-section h3 {
    font-size: 0.8125rem;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    color: #9ca3af;
    margin: 0 0 0.5rem;
    display: flex;
    align-items: center;
    gap: 0.5rem;
  }
  .me-kv {
    display: grid;
    grid-template-columns: auto 1fr;
    gap: 0.25rem 0.75rem;
    margin: 0;
    font-size: 0.8125rem;
  }
  .me-kv dt { color: #9ca3af; }
  .me-kv dd { margin: 0; }
  .me-muted { color: #6b7280; font-size: 0.8125rem; word-break: break-all; }
  .role-badge {
    font-size: 0.625rem;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    background: #1f2937;
    color: #9ca3af;
    border: 1px solid #374151;
    border-radius: 0.25rem;
    padding: 0.0625rem 0.375rem;
  }
  .role-badge.admin {
    background: #3b1d1d;
    color: #fca5a5;
    border-color: #7f1d1d;
  }
  .me-link, .me-link-btn {
    display: inline-block;
    color: #60a5fa;
    background: transparent;
    border: none;
    padding: 0;
    font-size: 0.8125rem;
    cursor: pointer;
    text-decoration: none;
  }
  .me-link:hover, .me-link-btn:hover { text-decoration: underline; }
</style>

```
