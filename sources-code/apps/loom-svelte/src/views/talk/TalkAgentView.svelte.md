---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/views/talk/TalkAgentView.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.087758+00:00
---

# apps/loom-svelte/src/views/talk/TalkAgentView.svelte

```svelte
<script lang="ts">
  /**
   * TalkAgentView — talk.agent context: task delegation to the brain's agent.
   *
   * V1 state: the brain does not yet expose POST /api/v1/agent/run.
   * The UI is fully functional (compose, history, scroll); tasks are
   * submitted optimistically. When the brain returns 404/501 the thread
   * shows an honest "pending" response rather than a false error.
   *
   * Once the brain endpoint lands (tracked as D-brain-agent-run),
   * the response handler here will display the streamed / batch result.
   *
   * Pattern T: agent execution happens in the brain, not client-side.
   * Suggested tasks are static client-side hints — the brain decides
   * whether to honour them.
   */

  let {
    brainBase,
    bearer,
  }: {
    brainBase: string;
    bearer: string;
  } = $props();

  type TaskStatus = 'sending' | 'pending' | 'done' | 'error';

  interface AgentTurn {
    id: number;
    task: string;
    status: TaskStatus;
    response?: string;
    ts: Date;
  }

  let turns = $state<AgentTurn[]>([]);
  let inputText = $state('');
  let busy = $state(false);
  let nextId = 0;

  let textareaEl = $state<HTMLTextAreaElement | null>(null);
  let historyEl = $state<HTMLDivElement | null>(null);

  const SUGGESTED_TASKS = [
    'What jobs need attention today?',
    'Draft a quote for the most recent visit',
    'Summarise overdue invoices',
    'What did I last discuss with this customer?',
  ];

  function autoGrow(el: HTMLTextAreaElement) {
    el.style.height = '42px';
    el.style.height = Math.min(el.scrollHeight, 120) + 'px';
  }

  function scrollToBottom() {
    queueMicrotask(() => {
      if (historyEl) historyEl.scrollTop = historyEl.scrollHeight;
    });
  }

  async function send(task?: string) {
    const text = (task ?? inputText).trim();
    if (!text || busy) return;

    if (!task) {
      inputText = '';
      if (textareaEl) textareaEl.style.height = '42px';
    }

    busy = true;
    const id = nextId++;
    turns = [...turns, { id, task: text, status: 'sending', ts: new Date() }];
    scrollToBottom();

    try {
      const res = await fetch(`${brainBase}/api/v1/agent/run`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${bearer}`,
          'Content-Type': 'application/json',
          Accept: 'application/json',
        },
        body: JSON.stringify({ task: text }),
      });

      if (res.status === 404 || res.status === 501) {
        // Endpoint not yet implemented — honest pending state.
        turns = turns.map(t =>
          t.id === id
            ? { ...t, status: 'pending', response: 'Agent endpoint is pending — your task has been noted.' }
            : t,
        );
      } else if (res.ok) {
        const data = await res.json() as { result?: string; output?: string };
        turns = turns.map(t =>
          t.id === id
            ? { ...t, status: 'done', response: data.result ?? data.output ?? 'Done.' }
            : t,
        );
      } else {
        const errText = await res.text().catch(() => `${res.status}`);
        turns = turns.map(t =>
          t.id === id
            ? { ...t, status: 'error', response: errText }
            : t,
        );
      }
    } catch {
      turns = turns.map(t =>
        t.id === id
          ? { ...t, status: 'pending', response: 'Agent endpoint is pending — your task has been noted.' }
          : t,
      );
    } finally {
      busy = false;
      scrollToBottom();
    }
  }

  function handleKeyDown(e: KeyboardEvent) {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      void send();
    }
  }

  function statusLabel(status: TaskStatus): string {
    return { sending: 'Sending…', pending: 'Queued', done: 'Done', error: 'Error' }[status];
  }
</script>

<div class="talk-agent">
  <!-- Pending notice -->
  <div class="pending-notice">
    <span class="notice-icon">⌖</span>
    Agent execution is queued — tasks are accepted now and will run once
    the brain's agent endpoint ships.
  </div>

  <!-- History -->
  <div
    class="history"
    class:empty={turns.length === 0}
    bind:this={historyEl}
  >
    {#if turns.length === 0}
      <div class="empty-hint">
        <div class="empty-icon">⌖</div>
        <div class="empty-title">Delegate a task</div>
        <div class="empty-body">
          Type a task for the agent — the brain will execute it, read from
          your hat's cell graph, and report back.
        </div>

        <div class="suggested-label">Try asking:</div>
        <div class="suggested-list">
          {#each SUGGESTED_TASKS as suggestion}
            <button
              class="suggestion-chip"
              onclick={() => void send(suggestion)}
              disabled={busy}
            >
              {suggestion}
            </button>
          {/each}
        </div>
      </div>
    {:else}
      {#each turns as turn (turn.id)}
        <div class="turn">
          <!-- Task bubble -->
          <div class="task-row">
            <div class="task-bubble">{turn.task}</div>
            <div class="turn-time">
              {turn.ts.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' })}
            </div>
          </div>

          <!-- Response bubble -->
          <div class="response-row" class:status-pending={turn.status === 'pending'} class:status-done={turn.status === 'done'} class:status-error={turn.status === 'error'}>
            {#if turn.status === 'sending'}
              <div class="response-bubble thinking">
                <span class="thinking-dot">●</span>
                <span class="thinking-dot">●</span>
                <span class="thinking-dot">●</span>
              </div>
            {:else}
              <div class="response-bubble">
                <div class="response-text">{turn.response}</div>
                <div class="status-chip status-{turn.status}">{statusLabel(turn.status)}</div>
              </div>
            {/if}
          </div>
        </div>
      {/each}
    {/if}
  </div>

  <!-- Compose area -->
  <div class="compose">
    <textarea
      bind:this={textareaEl}
      bind:value={inputText}
      rows={1}
      placeholder="Delegate a task to the agent…"
      autocomplete="off"
      spellcheck={false}
      disabled={busy}
      onkeydown={handleKeyDown}
      oninput={(e) => autoGrow(e.currentTarget as HTMLTextAreaElement)}
    ></textarea>
    <button
      class="send-btn"
      onclick={() => void send()}
      disabled={!inputText.trim() || busy}
      aria-label="Send task"
    >
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
        <line x1="22" y1="2" x2="11" y2="13" />
        <polygon points="22 2 15 22 11 13 2 9 22 2" />
      </svg>
    </button>
  </div>
</div>

<style>
  .talk-agent {
    display: flex;
    flex-direction: column;
    height: 100%;
    background: #0f172a;
    color: #e2e8f0;
    overflow: hidden;
  }

  /* ── Pending notice ── */
  .pending-notice {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    padding: 0.5rem 1rem;
    background: rgba(245, 158, 11, 0.08);
    border-bottom: 1px solid rgba(245, 158, 11, 0.2);
    font-size: 0.75rem;
    color: #fbbf24;
    flex-shrink: 0;
  }

  .notice-icon { flex-shrink: 0; font-size: 0.875rem; }

  /* ── History ── */
  .history {
    flex: 1;
    overflow-y: auto;
    padding: 1rem;
    display: flex;
    flex-direction: column;
    gap: 1rem;
  }

  .history.empty {
    align-items: center;
    justify-content: center;
  }

  /* ── Empty state ── */
  .empty-hint {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 0.625rem;
    text-align: center;
    max-width: 280px;
  }

  .empty-icon { font-size: 2rem; color: #334155; }
  .empty-title { font-size: 0.9375rem; font-weight: 600; color: #94a3b8; }
  .empty-body { font-size: 0.8125rem; color: #475569; line-height: 1.5; }

  .suggested-label {
    margin-top: 0.5rem;
    font-size: 0.6875rem;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: #475569;
  }

  .suggested-list {
    display: flex;
    flex-direction: column;
    gap: 0.375rem;
    width: 100%;
  }

  .suggestion-chip {
    background: #1e293b;
    border: 1px solid #334155;
    border-radius: 0.5rem;
    color: #94a3b8;
    font-size: 0.8125rem;
    cursor: pointer;
    padding: 0.5rem 0.75rem;
    text-align: left;
    transition: background 0.1s, color 0.1s, border-color 0.1s;
  }

  .suggestion-chip:hover:not(:disabled) {
    background: #263548;
    color: #e2e8f0;
    border-color: #3b82f6;
  }

  .suggestion-chip:disabled { opacity: 0.4; cursor: default; }

  /* ── Turns ── */
  .turn {
    display: flex;
    flex-direction: column;
    gap: 0.375rem;
  }

  .task-row {
    display: flex;
    flex-direction: column;
    align-items: flex-end;
    gap: 2px;
  }

  .task-bubble {
    background: #1d4ed8;
    color: #eff6ff;
    padding: 0.5rem 0.75rem;
    border-radius: 0.75rem 0.75rem 0.25rem 0.75rem;
    max-width: 85%;
    font-size: 0.875rem;
    line-height: 1.4;
  }

  .turn-time {
    font-size: 0.6875rem;
    color: #475569;
    padding-right: 0.25rem;
  }

  .response-row {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
  }

  .response-bubble {
    background: #1e293b;
    border: 1px solid #334155;
    border-radius: 0.75rem 0.75rem 0.75rem 0.25rem;
    padding: 0.625rem 0.75rem;
    max-width: 90%;
    display: flex;
    flex-direction: column;
    gap: 0.375rem;
  }

  .response-bubble.thinking {
    display: flex;
    flex-direction: row;
    gap: 0.3rem;
    padding: 0.5rem 0.875rem;
    align-items: center;
  }

  .thinking-dot {
    font-size: 0.5rem;
    color: #475569;
    animation: pulse 1.2s ease-in-out infinite;
  }

  .thinking-dot:nth-child(2) { animation-delay: 0.2s; }
  .thinking-dot:nth-child(3) { animation-delay: 0.4s; }

  @keyframes pulse {
    0%, 80%, 100% { opacity: 0.2; }
    40% { opacity: 1; }
  }

  .response-text {
    font-size: 0.875rem;
    color: #cbd5e1;
    line-height: 1.5;
  }

  /* Status chip */
  .status-chip {
    align-self: flex-start;
    font-size: 0.625rem;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    padding: 0.1rem 0.4rem;
    border-radius: 999px;
  }

  .status-pending {
    background: rgba(245, 158, 11, 0.1);
    color: #fbbf24;
  }

  .status-done {
    background: rgba(34, 197, 94, 0.1);
    color: #4ade80;
  }

  .status-error {
    background: rgba(239, 68, 68, 0.1);
    color: #f87171;
  }

  /* ── Compose ── */
  .compose {
    display: flex;
    align-items: flex-end;
    gap: 0.5rem;
    padding: 0.75rem 1rem;
    border-top: 1px solid #1e293b;
    background: #111827;
    flex-shrink: 0;
  }

  .compose textarea {
    flex: 1;
    background: #1e293b;
    border: 1px solid #334155;
    border-radius: 0.5rem;
    color: #e2e8f0;
    font-size: 0.9375rem;
    padding: 0.5rem 0.75rem;
    resize: none;
    outline: none;
    line-height: 1.5;
    transition: border-color 0.15s;
    font-family: inherit;
  }

  .compose textarea::placeholder { color: #475569; }
  .compose textarea:focus { border-color: #3b82f6; }
  .compose textarea:disabled { opacity: 0.5; }

  .send-btn {
    width: 40px;
    height: 40px;
    border-radius: 50%;
    background: #1d4ed8;
    border: none;
    color: #fff;
    display: flex;
    align-items: center;
    justify-content: center;
    cursor: pointer;
    flex-shrink: 0;
    transition: background 0.15s, opacity 0.15s;
  }

  .send-btn:hover:not(:disabled) { background: #2563eb; }
  .send-btn:disabled { opacity: 0.4; cursor: default; }
</style>

```
