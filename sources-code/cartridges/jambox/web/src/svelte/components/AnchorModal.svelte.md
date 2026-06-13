---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/svelte/components/AnchorModal.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.619782+00:00
---

# cartridges/jambox/web/src/svelte/components/AnchorModal.svelte

```svelte
<script lang="ts">
  /**
   * AnchorModal — BSV session anchor via the local WASM BRC-100 wallet.
   *
   * Flow:
   *   1. User clicks CAP → modal opens.
   *   2. Modal checks wallet connectivity (isAuthenticated / getPublicKey).
   *   3. If connected: show pubkey fragment + "Anchor" button.
   *   4. If not connected: show wallet URL config field + retry.
   *   5. On anchor: calls anchorJamWithWallet() → shows txid + WoC link.
   *
   * No WIF is ever shown or stored. The WASM wallet holds the keys.
   */

  import { anchorJamWithWallet, createJamWalletClient, type JamSessionPayload } from '../../core/anchor.js';
  import type { JamWalletClient } from '../../core/wallet-client.js';

  interface Props {
    bpm: number;
    scene: string;
    roomId: string;
    peers: string[];
    onClose: () => void;
  }

  let { bpm, scene, roomId, peers, onClose }: Props = $props();

  // ── State ─────────────────────────────────────────────────────────────────
  const DEFAULT_WALLET_URL = 'http://localhost:3321';
  const WALLET_URL_KEY = 'jam.wallet.url';

  let walletUrl     = $state(localStorage.getItem(WALLET_URL_KEY) ?? DEFAULT_WALLET_URL);
  let walletStatus  = $state<'checking' | 'ready' | 'disconnected' | 'error'>('checking');
  let walletPubKey  = $state('');
  let anchorStatus  = $state<'idle' | 'anchoring' | 'done' | 'error'>('idle');
  let txid          = $state('');
  let errorMsg      = $state('');
  let editingUrl    = $state(false);
  let walletUrlInput = $state('');

  function sceneToIndex(s: string): number {
    return ['A','B','C','D'].indexOf(s);
  }

  // Recreated whenever walletUrl changes
  const wallet: JamWalletClient = $derived(createJamWalletClient(walletUrl));

  // Check wallet on mount
  async function checkWallet() {
    walletStatus = 'checking';
    walletPubKey = '';
    errorMsg = '';
    try {
      const pubKey = await wallet.getPublicKey({ identityKey: true });
      walletPubKey = pubKey;
      walletStatus = 'ready';
    } catch {
      walletStatus = 'disconnected';
    }
  }

  // Run immediately
  checkWallet();

  function saveWalletUrl() {
    walletUrl = walletUrlInput.trim() || DEFAULT_WALLET_URL;
    try { localStorage.setItem(WALLET_URL_KEY, walletUrl); } catch {}
    editingUrl = false;
    checkWallet();
  }

  async function anchor() {
    anchorStatus = 'anchoring';
    errorMsg = '';

    const payload: JamSessionPayload = {
      v: 1,
      room: roomId,
      bpm,
      scene: sceneToIndex(scene),
      identities: peers,
      cells: [],
      ts: Date.now(),
    };

    const result = await anchorJamWithWallet(payload, wallet);
    if (result.status === 'ok') {
      txid = result.txid;
      anchorStatus = 'done';
    } else {
      errorMsg = `Wallet error: ${result.arcResponse ?? 'unknown'}`;
      anchorStatus = 'error';
    }
  }
</script>

<!-- svelte-ignore a11y_click_events_have_key_events a11y_no_static_element_interactions -->
<div class="modal-backdrop" onclick={onClose}>
  <!-- svelte-ignore a11y_click_events_have_key_events a11y_no_static_element_interactions -->
  <div class="modal" onclick={(e) => e.stopPropagation()}>

    <!-- Head -->
    <div class="modal-head">
      <span class="modal-title">⌃ CAP · Anchor Session</span>
      <!-- svelte-ignore a11y_click_events_have_key_events a11y_no_static_element_interactions -->
      <span class="close-btn" onclick={onClose}>✕</span>
    </div>

    <!-- Session meta -->
    <div class="meta-row">
      <span class="meta-item">room <strong>{roomId}</strong></span>
      <span class="meta-item">scene <strong>{scene}</strong></span>
      <span class="meta-item">bpm <strong>{bpm}</strong></span>
      <span class="meta-item">{peers.length} player{peers.length !== 1 ? 's' : ''}</span>
    </div>

    <!-- Wallet status row -->
    <div class="wallet-row" class:ready={walletStatus === 'ready'} class:bad={walletStatus === 'disconnected' || walletStatus === 'error'}>
      <span class="wallet-dot" class:dot-checking={walletStatus === 'checking'} class:dot-ready={walletStatus === 'ready'} class:dot-bad={walletStatus === 'disconnected' || walletStatus === 'error'}></span>

      {#if walletStatus === 'checking'}
        <span class="wallet-label">Connecting to wallet…</span>
      {:else if walletStatus === 'ready'}
        <span class="wallet-label">
          Wallet ready ·
          <span class="pubkey-frag">{walletPubKey.slice(0,6)}…{walletPubKey.slice(-4)}</span>
        </span>
        <!-- svelte-ignore a11y_click_events_have_key_events a11y_no_static_element_interactions -->
        <span class="link" onclick={() => { editingUrl = !editingUrl; walletUrlInput = walletUrl; }} role="button" tabindex="0">configure</span>
      {:else}
        <span class="wallet-label">Wallet not found</span>
        <!-- svelte-ignore a11y_click_events_have_key_events a11y_no_static_element_interactions -->
        <span class="link" onclick={() => { editingUrl = true; walletUrlInput = walletUrl; }}>configure</span>
        <!-- svelte-ignore a11y_click_events_have_key_events a11y_no_static_element_interactions -->
        <span class="link" onclick={checkWallet}>retry</span>
      {/if}
    </div>

    <!-- Wallet URL editor -->
    {#if editingUrl}
      <div class="field-group">
        <label class="field-label">Wallet endpoint</label>
        <div class="url-row">
          <input
            class="url-input"
            type="text"
            placeholder="http://localhost:3321"
            bind:value={walletUrlInput}
            autocomplete="off"
          />
          <button class="btn-small" onclick={saveWalletUrl}>Save</button>
        </div>
        <div class="field-hint">
          Metanet Desktop or WASM wallet HTTP endpoint.
          Default: <code>http://localhost:3321</code>
        </div>
      </div>
    {/if}

    <!-- Wallet not connected help text -->
    {#if walletStatus === 'disconnected' && !editingUrl}
      <div class="help-box">
        <div class="help-title">Start your WASM wallet</div>
        <div class="help-body">
          Open Metanet Desktop (or the wallet-browser app) and make sure it is
          running on <code>{walletUrl}</code>. The wallet holds your keys and
          signs the anchor transaction — no passphrase is entered here.
        </div>
      </div>
    {/if}

    <!-- Anchor result -->
    {#if anchorStatus === 'done'}
      <div class="success-box">
        <div class="success-label">Anchored on BSV ✓</div>
        <a
          class="txid-link"
          href="https://whatsonchain.com/tx/{txid}"
          target="_blank"
          rel="noopener noreferrer"
        >{txid.slice(0, 16)}…{txid.slice(-8)}</a>
      </div>
    {/if}

    {#if errorMsg}
      <div class="error-box">{errorMsg}</div>
    {/if}

    <!-- Actions -->
    <div class="modal-actions">
      {#if anchorStatus === 'done'}
        <button class="btn-secondary" onclick={onClose}>Close</button>
        <button class="btn-primary" onclick={() => { anchorStatus = 'idle'; txid = ''; errorMsg = ''; }}>
          Anchor Again
        </button>
      {:else}
        <button class="btn-secondary" onclick={onClose}>Cancel</button>
        <button
          class="btn-primary"
          disabled={walletStatus !== 'ready' || anchorStatus === 'anchoring'}
          onclick={anchor}
        >
          {anchorStatus === 'anchoring' ? 'Signing…' : 'Anchor on BSV'}
        </button>
      {/if}
    </div>
  </div>
</div>

<style>
  .modal-backdrop {
    position: fixed; inset: 0; z-index: 200;
    background: rgba(8,9,12,0.78);
    display: grid; place-items: center;
    backdrop-filter: blur(4px);
  }
  .modal {
    background: var(--ink-2); border: 1px solid var(--brass);
    border-radius: 14px; padding: 22px 24px;
    width: 440px; max-width: calc(100vw - 32px);
    display: flex; flex-direction: column; gap: 14px;
    box-shadow: 0 24px 64px rgba(0,0,0,0.7);
  }
  .modal-head {
    display: flex; align-items: center; justify-content: space-between;
  }
  .modal-title {
    font-family: var(--f-mono); font-size: 12px;
    color: var(--brass-bright); letter-spacing: 0.16em; text-transform: uppercase;
  }
  .close-btn { font-size: 14px; color: var(--muted); cursor: pointer; padding: 2px 6px; }
  .close-btn:hover { color: var(--paper); }

  .meta-row {
    display: flex; flex-wrap: wrap; gap: 12px;
    font-family: var(--f-mono); font-size: 10px; color: var(--muted);
    padding-bottom: 12px; border-bottom: 1px dashed var(--line);
  }
  .meta-item strong { color: var(--paper-2); }

  /* Wallet status */
  .wallet-row {
    display: flex; align-items: center; gap: 8px;
    font-family: var(--f-mono); font-size: 10px; color: var(--muted);
    background: var(--ink-3); border: 1px solid var(--line);
    border-radius: 8px; padding: 10px 12px;
    flex-wrap: wrap;
  }
  .wallet-row.ready { border-color: rgba(109,205,154,0.35); }
  .wallet-row.bad   { border-color: rgba(239,77,106,0.3); }

  .wallet-dot {
    width: 7px; height: 7px; border-radius: 50%;
    background: var(--muted); flex-shrink: 0;
  }
  .dot-checking { background: var(--brass); animation: blink 900ms ease-in-out infinite alternate; }
  .dot-ready    { background: var(--live); }
  .dot-bad      { background: var(--record); }

  @keyframes blink { from { opacity: 0.3; } to { opacity: 1; } }

  .wallet-label { flex: 1; }
  .pubkey-frag { color: var(--live); letter-spacing: 0.06em; }
  .link { color: var(--accent-bright); cursor: pointer; white-space: nowrap; }
  .link:hover { text-decoration: underline; }

  /* URL editor */
  .field-group { display: flex; flex-direction: column; gap: 6px; }
  .field-label {
    font-family: var(--f-mono); font-size: 10px;
    color: var(--muted); letter-spacing: 0.1em; text-transform: uppercase;
  }
  .url-row { display: flex; gap: 8px; }
  .url-input {
    flex: 1; background: var(--ink-3); border: 1px solid var(--line);
    border-radius: 8px; padding: 9px 12px;
    font-family: var(--f-mono); font-size: 11px; color: var(--paper);
    outline: none;
  }
  .url-input:focus { border-color: var(--brass); }
  .btn-small {
    background: var(--ink-4); color: var(--paper-2);
    border: 1px solid var(--line); border-radius: 8px;
    padding: 8px 14px; font-family: var(--f-mono); font-size: 10px;
    cursor: pointer; white-space: nowrap;
  }
  .btn-small:hover { border-color: var(--muted); }
  .field-hint {
    font-family: var(--f-mono); font-size: 9.5px;
    color: var(--muted); line-height: 1.5;
  }
  code { color: var(--brass-bright); background: none; }

  /* Help box */
  .help-box {
    background: var(--ink-3); border: 1px dashed var(--line);
    border-radius: 8px; padding: 12px 14px;
    display: flex; flex-direction: column; gap: 6px;
  }
  .help-title {
    font-family: var(--f-mono); font-size: 10px;
    color: var(--paper-2); letter-spacing: 0.08em; text-transform: uppercase;
  }
  .help-body {
    font-family: var(--f-mono); font-size: 10px;
    color: var(--muted); line-height: 1.6;
  }

  /* Results */
  .success-box {
    background: rgba(109,205,154,0.1); border: 1px solid rgba(109,205,154,0.35);
    border-radius: 8px; padding: 12px 14px;
    display: flex; flex-direction: column; gap: 6px;
  }
  .success-label {
    font-family: var(--f-mono); font-size: 10px;
    color: var(--live); letter-spacing: 0.1em; text-transform: uppercase;
  }
  .txid-link {
    font-family: var(--f-mono); font-size: 11px;
    color: var(--brass-bright); text-decoration: none; word-break: break-all;
  }
  .txid-link:hover { text-decoration: underline; }

  .error-box {
    background: rgba(239,77,106,0.1); border: 1px solid rgba(239,77,106,0.35);
    border-radius: 8px; padding: 10px 14px;
    font-family: var(--f-mono); font-size: 10px; color: var(--record);
    word-break: break-all;
  }

  .modal-actions {
    display: flex; justify-content: flex-end; gap: 10px;
    padding-top: 8px; border-top: 1px dashed var(--line);
  }
  .btn-primary {
    background: var(--brass); color: var(--ink-0);
    border: none; border-radius: 8px;
    padding: 9px 18px; font-family: var(--f-mono); font-size: 11px;
    font-weight: 600; cursor: pointer; letter-spacing: 0.08em;
    transition: background 120ms;
  }
  .btn-primary:hover:not(:disabled) { background: var(--brass-bright); }
  .btn-primary:disabled { opacity: 0.4; cursor: not-allowed; }
  .btn-secondary {
    background: var(--ink-3); color: var(--paper-2);
    border: 1px solid var(--line); border-radius: 8px;
    padding: 9px 16px; font-family: var(--f-mono); font-size: 11px;
    cursor: pointer; transition: border-color 120ms;
  }
  .btn-secondary:hover { border-color: var(--muted); }
</style>

```
