---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/views/ConversationThread.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.070757+00:00
---

# apps/loom-svelte/src/views/ConversationThread.svelte

```svelte
<script lang="ts">
  /**
   * ConversationThread — per-job conversation turn reader + operator note sender.
   *
   * Shows all ConversationTurns for a job's entityRef, fetched via
   * GET /api/v1/conversation/turns?entityRef=<jobId>.  Surfaces emails,
   * SMS, voice notes, widget chats, and REPL notes in a single chronological
   * feed.
   *
   * Also allows the operator to add typed notes via POST /api/v1/voice-note
   * (entity_cell_hash = jobId).  These land as operator-role turns and show
   * up immediately after the refresh.
   *
   * Auto-refreshes every 30 s.  The Flutter field app's Thread tab uses the
   * same endpoint — turns added on either surface appear here without any
   * extra wiring.
   */
  import { getActiveSession } from '../lib/hat-sessions';
  import { fetchTurns, sendOperatorNote, type ConversationTurn } from '../lib/conversation-turns-api';

  let { jobId }: { jobId: string } = $props();

  // ── State ─────────────────────────────────────────────────────────────────

  let turns = $state<ConversationTurn[]>([]);
  let loading = $state(false);
  let loadError = $state(false);
  let noteText = $state('');
  let sending = $state(false);
  let sendError = $state<string | null>(null);

  // ── Helpers ───────────────────────────────────────────────────────────────

  function resolveBearer(): string {
    const session = getActiveSession();
    return session?.bearer ??
      (typeof localStorage !== 'undefined'
        ? (localStorage.getItem('helm.bearer') ?? '')
        : '');
  }

  function surfaceLabel(surface: string): string {
    switch (surface) {
      case 'gmail':
      case 'email':       return '📧';
      case 'sms':         return '💬';
      case 'voice_note':  return '🎤';
      case 'widget':      return '🖥';
      case 'repl':        return '⌨';
      default:            return '·';
    }
  }

  function formatTime(epochMs: number): string {
    const d = new Date(epochMs);
    const hh = String(d.getHours()).padStart(2, '0');
    const mm = String(d.getMinutes()).padStart(2, '0');
    const dd = String(d.getDate()).padStart(2, '0');
    const mo = String(d.getMonth() + 1).padStart(2, '0');
    return `${dd}/${mo} ${hh}:${mm}`;
  }

  function senderLabel(turn: ConversationTurn): string {
    if (turn.identityValue) return turn.identityValue;
    return turn.participantRole;
  }

  // ── Load ──────────────────────────────────────────────────────────────────

  async function load() {
    loading = true;
    loadError = false;
    const bearer = resolveBearer();
    const result = await fetchTurns(jobId, bearer);
    loading = false;
    if (result.length === 0 && !bearer) {
      loadError = true;
      return;
    }
    // Sort ascending by timestamp — endpoint may return any order.
    turns = result.sort((a, b) => a.timestamp - b.timestamp);
  }

  // ── Send note ─────────────────────────────────────────────────────────────

  async function handleSend() {
    const text = noteText.trim();
    if (!text) return;
    sending = true;
    sendError = null;
    const bearer = resolveBearer();
    const ok = await sendOperatorNote(jobId, text, bearer);
    sending = false;
    if (ok) {
      noteText = '';
      await load(); // refresh to show the new turn
    } else {
      sendError = 'Failed to save note — check bearer + brain connection.';
    }
  }

  // ── Auto-refresh ──────────────────────────────────────────────────────────

  $effect(() => {
    void load();
    const interval = setInterval(() => { void load(); }, 30_000);
    return () => clearInterval(interval);
  });
</script>

<div class="thread">
  <div class="thread-header">
    <span class="thread-title">Conversation</span>
    {#if loading}
      <span class="thread-loading">⏳</span>
    {:else}
      <button class="refresh-btn" onclick={() => load()} title="Refresh">↻</button>
    {/if}
  </div>

  <div class="thread-body">
    {#if loadError}
      <p class="thread-empty">No session — sign in to view conversation.</p>
    {:else if turns.length === 0 && !loading}
      <p class="thread-empty">
        No turns yet. Emails, SMS replies, voice notes, and widget messages
        will appear here as they're recorded.
      </p>
    {:else}
      {#each turns as turn (turn.turnId)}
        <div class="bubble-row {turn.direction === 'outbound' ? 'outbound' : 'inbound'}">
          <div class="bubble">
            <div class="bubble-meta">
              <span class="surface-icon" title={turn.surface}>{surfaceLabel(turn.surface)}</span>
              <span class="sender">{senderLabel(turn)}</span>
              {#if turn.outboundState && turn.outboundState !== 'sent' && turn.outboundState !== 'delivered'}
                <span class="outbound-state {turn.outboundState}">{turn.outboundState}</span>
              {/if}
              <span class="ts">{formatTime(turn.timestamp)}</span>
            </div>
            <p class="bubble-body">{turn.bodyText}</p>
          </div>
        </div>
      {/each}
    {/if}
  </div>

  <!-- Operator note input -->
  <div class="thread-compose">
    <textarea
      class="compose-input"
      placeholder="Add a note about this job…"
      rows="2"
      bind:value={noteText}
      disabled={sending}
      onkeydown={(e) => {
        if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) handleSend();
      }}
    ></textarea>
    <button
      class="send-btn"
      onclick={handleSend}
      disabled={sending || !noteText.trim()}
    >
      {sending ? '…' : 'Add note'}
    </button>
  </div>
  {#if sendError}
    <p class="send-error">{sendError}</p>
  {/if}
</div>

<style>
  .thread {
    display: flex;
    flex-direction: column;
    gap: 0;
    border: 1px solid var(--rule, #2a2a2a);
    border-radius: 0.5rem;
    overflow: hidden;
    background: var(--color-bg, #0f0f0f);
  }

  /* ── Header ── */
  .thread-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0.5rem 0.75rem;
    background: var(--color-surface, #1a1a1a);
    border-bottom: 1px solid var(--rule, #2a2a2a);
  }

  .thread-title {
    font-size: 0.8125rem;
    font-weight: 600;
    color: #e5e7eb;
  }

  .thread-loading {
    font-size: 0.75rem;
    color: #6b7280;
  }

  .refresh-btn {
    background: transparent;
    border: none;
    color: #6b7280;
    cursor: pointer;
    font-size: 0.875rem;
    padding: 0;
    line-height: 1;
  }

  .refresh-btn:hover { color: #9ca3af; }

  /* ── Body ── */
  .thread-body {
    flex: 1;
    overflow-y: auto;
    padding: 0.75rem;
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
    min-height: 80px;
    max-height: 320px;
  }

  .thread-empty {
    color: #4b5563;
    font-size: 0.8125rem;
    font-style: italic;
    margin: 0;
    text-align: center;
    padding: 1rem 0;
  }

  /* ── Bubbles ── */
  .bubble-row {
    display: flex;
  }

  .bubble-row.inbound  { justify-content: flex-start; }
  .bubble-row.outbound { justify-content: flex-end; }

  .bubble {
    max-width: 80%;
    padding: 0.5rem 0.625rem;
    border-radius: 0.5rem;
    font-size: 0.8125rem;
    line-height: 1.45;
  }

  .bubble-row.inbound  .bubble {
    background: #1e293b;
    border: 1px solid #334155;
    border-bottom-left-radius: 0.125rem;
  }

  .bubble-row.outbound .bubble {
    background: #1d4ed8;
    border: 1px solid #2563eb;
    border-bottom-right-radius: 0.125rem;
  }

  .bubble-meta {
    display: flex;
    align-items: baseline;
    gap: 0.375rem;
    margin-bottom: 0.25rem;
    flex-wrap: wrap;
  }

  .surface-icon { font-size: 0.75rem; }

  .sender {
    font-size: 0.6875rem;
    font-weight: 600;
    color: #93c5fd;
  }

  .bubble-row.outbound .sender { color: #bfdbfe; }

  .ts {
    font-size: 0.625rem;
    color: #6b7280;
    margin-left: auto;
  }

  .bubble-row.outbound .ts { color: #93c5fd; opacity: 0.75; }

  .outbound-state {
    font-size: 0.625rem;
    padding: 0.0625rem 0.375rem;
    border-radius: 0.25rem;
    background: rgba(255,255,255,0.1);
    color: #bfdbfe;
  }

  .outbound-state.proposed { background: rgba(245,158,11,0.2); color: #fcd34d; }
  .outbound-state.failed   { background: rgba(239,68,68,0.2);  color: #fca5a5; }

  .bubble-body {
    color: #e2e8f0;
    margin: 0;
    white-space: pre-wrap;
    word-break: break-word;
  }

  .bubble-row.outbound .bubble-body { color: #fff; }

  /* ── Compose ── */
  .thread-compose {
    display: flex;
    gap: 0.5rem;
    padding: 0.5rem 0.75rem;
    background: var(--color-surface, #1a1a1a);
    border-top: 1px solid var(--rule, #2a2a2a);
    align-items: flex-end;
  }

  .compose-input {
    flex: 1;
    background: #111;
    border: 1px solid #333;
    border-radius: 0.375rem;
    color: #e5e7eb;
    font: inherit;
    font-size: 0.8125rem;
    padding: 0.375rem 0.5rem;
    resize: none;
    line-height: 1.4;
    outline: none;
  }

  .compose-input:focus { border-color: #60a5fa; }
  .compose-input:disabled { opacity: 0.5; }

  .send-btn {
    background: #1d4ed8;
    border: none;
    border-radius: 0.375rem;
    color: #fff;
    cursor: pointer;
    font-size: 0.8125rem;
    padding: 0.375rem 0.75rem;
    white-space: nowrap;
    align-self: flex-end;
  }

  .send-btn:hover:not(:disabled) { background: #2563eb; }
  .send-btn:disabled { opacity: 0.4; cursor: default; }

  .send-error {
    color: #f87171;
    font-size: 0.75rem;
    margin: 0.25rem 0.75rem;
  }
</style>

```
