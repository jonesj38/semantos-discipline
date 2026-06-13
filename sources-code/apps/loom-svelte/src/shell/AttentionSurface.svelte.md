---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/shell/AttentionSurface.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.086752+00:00
---

# apps/loom-svelte/src/shell/AttentionSurface.svelte

```svelte
<script lang="ts">
  /**
   * AttentionSurface — Home surface: ranked attention feed.
   *
   * D-svelte-attention-surface:
   *   Polls GET /api/v1/attention/snapshot every 30 s (WSS stream is phase 5).
   *   Records telemetry via POST /api/v1/attention/interact on tap + dismiss.
   *
   *   Card design mirrors apps/loom-react/src/helm/AttentionSurface.tsx:
   *     - Left border accent by urgency (immediate=red, soon=amber, else muted)
   *     - Title + reason action text
   *     - Relevance %, subtitle, time-since
   *     - Dismiss button (×) on hover → records "ignored"
   *     - Tap → records "clicked", calls onItemTap if provided
   */
  import { pollAttention, attentionWssTransport, type AttentionSignal } from '../lib/attention-api';

  let {
    bearer,
    brainBaseUrl,
    onItemTap,
    namespaces = ['shell'],
  }: {
    bearer: string;
    brainBaseUrl: string;
    onItemTap?: (signal: AttentionSignal) => void;
    /** SH8/SH9 — in-scope namespaces for the poll. Default: shell only. */
    namespaces?: string[];
  } = $props();

  // ── State ─────────────────────────────────────────────────────────────────

  let items = $state<AttentionSignal[]>([]);
  let loading = $state(false);
  let lastRefresh = $state<Date | null>(null);

  // Optimistically dismissed refs — removed from the list immediately on ×.
  // No telemetry: the interact endpoint was removed with the REST surface;
  // dismissal is local-only until SH11 wires a poll-era interaction signal.
  let dismissed = $state(new Set<string>());

  // ── Helpers ───────────────────────────────────────────────────────────────

  // SH9 — the poll signal carries no urgency; derive an accent from score.
  function urgencyBorderColor(score: number): string {
    if (score >= 0.8) return '#ef4444';
    if (score >= 0.5) return '#f59e0b';
    return 'transparent';
  }

  function timeSince(epochMs: number): string {
    const s = Math.floor((Date.now() - epochMs) / 1000);
    if (s < 60)  return `${s}s ago`;
    const m = Math.floor(s / 60);
    if (m < 60)  return `${m}m ago`;
    const h = Math.floor(m / 60);
    if (h < 24)  return `${h}h ago`;
    return `${Math.floor(h / 24)}d ago`;
  }

  function relevancePct(r: number): string {
    return `${Math.round(r * 100)}%`;
  }

  // ── Load ──────────────────────────────────────────────────────────────────

  async function load() {
    loading = true;
    const transport = attentionWssTransport(brainBaseUrl, bearer);
    const signals = await pollAttention(transport, namespaces);
    loading = false;
    items = signals;
    lastRefresh = new Date();
    dismissed = new Set(); // reset on each fresh load
  }

  // ── Interactions ──────────────────────────────────────────────────────────

  function handleTap(signal: AttentionSignal) {
    onItemTap?.(signal);
  }

  function handleDismiss(e: MouseEvent, signal: AttentionSignal) {
    e.stopPropagation();
    dismissed = new Set([...dismissed, signal.ref]);
  }

  // ── Auto-refresh ──────────────────────────────────────────────────────────

  $effect(() => {
    void load();
    const interval = setInterval(() => { void load(); }, 30_000);
    return () => clearInterval(interval);
  });

  // ── Visible items (minus dismissed) ──────────────────────────────────────

  const visible = $derived(items.filter(i => !dismissed.has(i.ref)));
</script>

<div class="surface">
  <!-- Header -->
  <div class="surface-header">
    <div class="header-left">
      <span class="surface-title">Home</span>
      {#if !loading && lastRefresh}
        <span class="refresh-time">updated {timeSince(lastRefresh.getTime())}</span>
      {/if}
    </div>
    <button
      class="refresh-btn"
      onclick={() => load()}
      disabled={loading}
      aria-label="Refresh attention feed"
    >
      {#if loading}
        <span class="spin">↻</span>
      {:else}
        ↻
      {/if}
    </button>
  </div>

  <!-- Body -->
  <div class="surface-body">
    {#if loading && items.length === 0}
      <div class="state-notice muted">Loading…</div>
    {:else if visible.length === 0}
      <div class="empty-state">
        <div class="empty-icon">⚓</div>
        <div class="empty-title">Nothing needs your attention right now.</div>
        <div class="empty-sub">Objects will surface here as they become relevant.</div>
      </div>
    {:else}
      <div class="card-list">
        {#each visible as signal (signal.ref)}
          <div
            class="card"
            role="button"
            tabindex="0"
            style="border-left-color: {urgencyBorderColor(signal.score)}"
            onclick={() => handleTap(signal)}
            onkeydown={(e) => { if (e.key === 'Enter' || e.key === ' ') handleTap(signal); }}
          >
            <!-- Main row -->
            <div class="card-top">
              <div class="card-left">
                <div class="card-title">{signal.summary || signal.ref}</div>
                <div class="card-reason">{signal.kind}</div>
              </div>
            </div>

            <!-- Meta row -->
            <div class="card-meta">
              <span class="relevance">{relevancePct(signal.score)}</span>
            </div>

            <!-- Dismiss button (appears on hover via CSS .card:hover) -->
            <button
              class="dismiss-btn"
              onclick={(e) => handleDismiss(e, signal)}
              aria-label="Dismiss"
              title="Dismiss"
            >×</button>
          </div>
        {/each}
      </div>
    {/if}
  </div>
</div>

<style>
  .surface {
    display: flex;
    flex-direction: column;
    height: 100%;
    background: #0f172a;
    color: #e2e8f0;
    overflow: hidden;
  }

  /* ── Header ── */
  .surface-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0.75rem 1rem;
    border-bottom: 1px solid #1e293b;
    background: #111827;
    flex-shrink: 0;
  }

  .header-left {
    display: flex;
    align-items: baseline;
    gap: 0.5rem;
  }

  .surface-title {
    font-size: 1rem;
    font-weight: 600;
    color: #f1f5f9;
  }

  .refresh-time {
    font-size: 0.6875rem;
    color: #475569;
  }

  .refresh-btn {
    width: 28px;
    height: 28px;
    border-radius: 0.25rem;
    background: transparent;
    border: 1px solid #1e293b;
    color: #64748b;
    font-size: 0.9375rem;
    display: flex;
    align-items: center;
    justify-content: center;
    cursor: pointer;
    transition: color 0.1s, background 0.1s, border-color 0.1s;
    flex-shrink: 0;
  }

  .refresh-btn:hover:not(:disabled) {
    color: #94a3b8;
    background: #1e293b;
    border-color: #334155;
  }

  .refresh-btn:disabled { opacity: 0.4; cursor: default; }

  .spin {
    display: inline-block;
    animation: spin 0.8s linear infinite;
  }

  @keyframes spin { to { transform: rotate(360deg); } }

  /* ── Body ── */
  .surface-body {
    flex: 1;
    overflow-y: auto;
    padding: 0.5rem;
  }

  /* ── Notices ── */
  .state-notice {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    padding: 1rem;
    font-size: 0.875rem;
    color: #f87171;
  }

  .state-notice.muted { color: #475569; }

  /* ── Empty state ── */
  .empty-state {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    height: 100%;
    gap: 0.5rem;
    text-align: center;
    padding: 2rem;
    min-height: 200px;
  }

  .empty-icon { font-size: 2rem; color: #334155; }
  .empty-title { font-size: 0.9375rem; font-weight: 500; color: #64748b; }
  .empty-sub { font-size: 0.8125rem; color: #334155; max-width: 220px; }

  /* ── Card list ── */
  .card-list {
    display: flex;
    flex-direction: column;
    gap: 0.375rem;
  }

  /* ── Card ── */
  .card {
    position: relative;
    display: flex;
    flex-direction: column;
    gap: 0.25rem;
    width: 100%;
    text-align: left;
    background: rgba(30, 41, 59, 0.6);
    border: 1px solid #1e293b;
    border-left: 4px solid transparent; /* urgency color set inline */
    border-radius: 0 0.375rem 0.375rem 0;
    padding: 0.625rem 0.75rem;
    cursor: pointer;
    transition: background 0.1s, border-color 0.1s;
    color: inherit;
    box-sizing: border-box;
    user-select: none;
  }

  .card:hover {
    background: #1e293b;
    border-color: #334155;
    border-left-color: inherit; /* keep urgency accent */
  }

  .card:hover .dismiss-btn { opacity: 1; }

  /* ── Card rows ── */
  .card-top {
    display: flex;
    align-items: flex-start;
    gap: 0.5rem;
  }

  .card-left { flex: 1; min-width: 0; }

  .card-title {
    font-size: 0.9375rem;
    font-weight: 500;
    color: #f1f5f9;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .card-reason {
    font-size: 0.8125rem;
    color: #64748b;
    margin-top: 0.125rem;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  /* ── Meta row ── */
  .card-meta {
    display: flex;
    align-items: center;
    gap: 0.25rem;
    font-size: 0.6875rem;
    margin-top: 0.125rem;
  }

  .relevance {
    font-family: monospace;
    color: #60a5fa;
  }

  /* ── Dismiss button ── */
  .dismiss-btn {
    position: absolute;
    top: 0.375rem;
    right: 0.375rem;
    width: 20px;
    height: 20px;
    background: transparent;
    border: none;
    color: #475569;
    font-size: 0.75rem;
    display: flex;
    align-items: center;
    justify-content: center;
    cursor: pointer;
    border-radius: 0.25rem;
    opacity: 0;
    transition: opacity 0.1s, color 0.1s, background 0.1s;
    padding: 0;
  }

  .dismiss-btn:hover {
    color: #f87171;
    background: rgba(239, 68, 68, 0.1);
  }
</style>

```
