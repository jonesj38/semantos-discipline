---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/views/talk/TalkDirectView.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.087158+00:00
---

# apps/loom-svelte/src/views/talk/TalkDirectView.svelte

```svelte
<script lang="ts">
  /**
   * TalkDirectView — 1:1 direct talk context (D-svelte-talk-direct).
   *
   * Two modes:
   *   picker      — contact list; tap to open a conversation.
   *   conversation — thread with selected peer + compose.
   *
   * V1 transport note:
   *   The brain has no p2p message delivery endpoint in this phase.
   *   Sent messages are held in component-local history and marked "queued"
   *   once the optimistic "sending" pulse completes.  The honest UI label
   *   "Queued — no transport" signals this to the user without hiding it.
   *   When D-network-wss-direct lands the send path wires up here.
   */
  import { listContacts, getContactDetail, type BrainContact, type BrainContactDetail } from '../../lib/contacts-api';
  import CallPanel from './CallPanel.svelte';

  let {
    brainBase,
    bearer,
  }: {
    brainBase: string;
    bearer: string;
  } = $props();

  // ── Contact picker state ──────────────────────────────────────────────────────

  let contacts = $state<BrainContact[]>([]);
  let contactsLoading = $state(true);
  let contactsError = $state('');
  let search = $state('');

  // ── Conversation state ────────────────────────────────────────────────────────

  type MsgStatus = 'sending' | 'queued';

  interface DMessage {
    id: number;
    dir: 'out' | 'in';
    text: string;
    status: MsgStatus;
    ts: Date;
  }

  let activePeer = $state<BrainContact | null>(null);
  let peerDetail = $state<BrainContactDetail | null>(null);
  let peerDetailLoading = $state(false);

  // per-certId message history; survives navigation back/forward within session
  let histories = $state(new Map<string, DMessage[]>());
  let nextId = 0;

  let inputText = $state('');
  let composeBusy = $state(false);

  let textareaEl = $state<HTMLTextAreaElement | null>(null);
  let threadEl = $state<HTMLDivElement | null>(null);

  // ── Derived ───────────────────────────────────────────────────────────────────

  const filtered = $derived(
    search.trim()
      ? contacts.filter(c =>
          c.displayName.toLowerCase().includes(search.toLowerCase()) ||
          c.certId.toLowerCase().includes(search.toLowerCase()) ||
          (c.email ?? '').toLowerCase().includes(search.toLowerCase()),
        )
      : contacts,
  );

  const thread = $derived(activePeer ? (histories.get(activePeer.certId) ?? []) : []);

  const activeEdgeCount = $derived(
    peerDetail?.edges.filter(e => e.revokedAt === null).length ?? 0,
  );

  // ── Lifecycle ─────────────────────────────────────────────────────────────────

  $effect(() => {
    loadContacts();
  });

  $effect(() => {
    // scroll thread to bottom whenever messages change
    if (threadEl && thread.length) {
      // microtask so DOM has painted
      queueMicrotask(() => {
        if (threadEl) threadEl.scrollTop = threadEl.scrollHeight;
      });
    }
  });

  async function loadContacts() {
    contactsLoading = true;
    contactsError = '';
    const list = await listContacts(brainBase, bearer);
    contacts = list;
    contactsLoading = false;
    if (list.length === 0) contactsError = '';
  }

  async function openPeer(contact: BrainContact) {
    activePeer = contact;
    peerDetail = null;
    peerDetailLoading = true;
    // seed empty history if first visit
    if (!histories.has(contact.certId)) {
      histories.set(contact.certId, []);
    }
    peerDetail = await getContactDetail(brainBase, bearer, contact.certId);
    peerDetailLoading = false;
  }

  function closePeer() {
    activePeer = null;
    peerDetail = null;
    inputText = '';
  }

  // ── Compose ───────────────────────────────────────────────────────────────────

  function autoGrow(el: HTMLTextAreaElement) {
    el.style.height = '42px';
    el.style.height = Math.min(el.scrollHeight, 120) + 'px';
  }

  function handleKeyDown(e: KeyboardEvent) {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      send();
    }
  }

  async function send() {
    const text = inputText.trim();
    if (!text || composeBusy || !activePeer) return;

    inputText = '';
    if (textareaEl) textareaEl.style.height = '42px';

    const certId = activePeer.certId;
    const msg: DMessage = {
      id: nextId++,
      dir: 'out',
      text,
      status: 'sending',
      ts: new Date(),
    };

    // append to history
    const prev = histories.get(certId) ?? [];
    histories.set(certId, [...prev, msg]);
    histories = new Map(histories); // trigger reactivity

    composeBusy = true;
    // simulate a brief "sending" pulse then flip to queued
    await new Promise(r => setTimeout(r, 600));

    const updated = (histories.get(certId) ?? []).map(m =>
      m.id === msg.id ? { ...m, status: 'queued' as MsgStatus } : m,
    );
    histories.set(certId, updated);
    histories = new Map(histories);
    composeBusy = false;
  }

  // ── Formatting helpers ────────────────────────────────────────────────────────

  function shortCertId(certId: string): string {
    return certId.length > 16 ? `${certId.slice(0, 8)}…${certId.slice(-4)}` : certId;
  }

  function fmtTime(d: Date): string {
    return d.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' });
  }

  function initials(name: string): string {
    return name
      .split(/\s+/)
      .slice(0, 2)
      .map(w => w[0]?.toUpperCase() ?? '')
      .join('');
  }
</script>

<!-- ── Contact picker ──────────────────────────────────────────────────────── -->
{#if !activePeer}
  <div class="picker">
    <!-- Search bar -->
    <div class="picker-search">
      <input
        class="search-input"
        type="search"
        placeholder="Search contacts…"
        bind:value={search}
        autocomplete="off"
        spellcheck={false}
      />
    </div>

    <!-- List body -->
    <div class="picker-body">
      {#if contactsLoading}
        <div class="picker-notice">Loading contacts…</div>
      {:else if contactsError}
        <div class="picker-notice error">{contactsError}</div>
      {:else if contacts.length === 0}
        <div class="picker-empty">
          <div class="empty-icon">↔</div>
          <div class="empty-title">No contacts yet</div>
          <div class="empty-body">Add a contact in Find → Network to start a direct conversation.</div>
        </div>
      {:else if filtered.length === 0}
        <div class="picker-notice">No matches for "{search}"</div>
      {:else}
        {#each filtered as contact (contact.certId)}
          <button class="contact-row" onclick={() => openPeer(contact)}>
            <div class="avatar">{initials(contact.displayName)}</div>
            <div class="contact-info">
              <div class="contact-name">{contact.displayName}</div>
              {#if contact.email}
                <div class="contact-sub">{contact.email}</div>
              {:else}
                <div class="contact-sub mono">{shortCertId(contact.certId)}</div>
              {/if}
            </div>
            <div class="contact-arrow">›</div>
          </button>
        {/each}
      {/if}
    </div>

    <!-- Footer -->
    {#if !contactsLoading && contacts.length > 0}
      <div class="picker-footer">{contacts.length} contact{contacts.length === 1 ? '' : 's'}</div>
    {/if}
  </div>

<!-- ── Conversation ────────────────────────────────────────────────────────── -->
{:else}
  <div class="convo">
    <!-- Peer header -->
    <div class="peer-header">
      <button class="back-btn" onclick={closePeer} aria-label="Back to contacts">←</button>
      <div class="peer-avatar">{initials(activePeer.displayName)}</div>
      <div class="peer-info">
        <div class="peer-name">{activePeer.displayName}</div>
        <div class="peer-meta">
          {#if peerDetailLoading}
            <span class="meta-dim">Loading…</span>
          {:else if peerDetail}
            <span class="mono meta-dim">{shortCertId(activePeer.certId)}</span>
            {#if activeEdgeCount > 0}
              <span class="edge-dot">·</span>
              <span class="edge-badge">{activeEdgeCount} edge{activeEdgeCount === 1 ? '' : 's'}</span>
            {/if}
          {:else}
            <span class="mono meta-dim">{shortCertId(activePeer.certId)}</span>
          {/if}
        </div>
      </div>
      <CallPanel {brainBase} {bearer} {contacts} {activePeer} />
    </div>

    <!-- Transport notice banner -->
    <div class="transport-notice">
      <span class="notice-icon">⚠</span>
      Direct transport not yet active — messages are queued locally.
    </div>

    <!-- Thread -->
    <div class="thread" bind:this={threadEl}>
      {#if thread.length === 0}
        <div class="thread-empty">
          <div class="thread-empty-title">Start a conversation</div>
          <div class="thread-empty-sub">Messages will be queued until direct transport is live.</div>
        </div>
      {:else}
        {#each thread as msg (msg.id)}
          <div class="msg msg-{msg.dir}">
            <div class="msg-bubble">
              {msg.text}
            </div>
            <div class="msg-footer">
              <span class="msg-time">{fmtTime(msg.ts)}</span>
              {#if msg.dir === 'out'}
                {#if msg.status === 'sending'}
                  <span class="msg-status sending">Sending…</span>
                {:else}
                  <span class="msg-status queued">Queued</span>
                {/if}
              {/if}
            </div>
          </div>
        {/each}
      {/if}
    </div>

    <!-- Compose -->
    <div class="compose">
      <textarea
        bind:this={textareaEl}
        bind:value={inputText}
        rows={1}
        placeholder="Message {activePeer.displayName}…"
        autocomplete="off"
        spellcheck={false}
        disabled={composeBusy}
        onkeydown={handleKeyDown}
        oninput={(e) => autoGrow(e.currentTarget as HTMLTextAreaElement)}
      ></textarea>
      <button
        class="send-btn"
        onclick={send}
        disabled={!inputText.trim() || composeBusy}
        aria-label="Send"
      >
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
          <line x1="22" y1="2" x2="11" y2="13" />
          <polygon points="22 2 15 22 11 13 2 9 22 2" />
        </svg>
      </button>
    </div>
  </div>
{/if}

<style>
  /* ── Shared ── */
  * { box-sizing: border-box; }

  /* ── Picker ── */
  .picker {
    display: flex;
    flex-direction: column;
    height: 100%;
    background: #0f172a;
    color: #e2e8f0;
    overflow: hidden;
  }

  .picker-search {
    padding: 0.625rem 1rem;
    border-bottom: 1px solid #1e293b;
    flex-shrink: 0;
  }

  .search-input {
    width: 100%;
    background: #1e293b;
    border: 1px solid #334155;
    border-radius: 0.5rem;
    color: #e2e8f0;
    font-size: 0.875rem;
    padding: 0.4375rem 0.75rem;
    outline: none;
    transition: border-color 0.15s;
  }

  .search-input::placeholder { color: #475569; }
  .search-input:focus { border-color: #3b82f6; }

  .picker-body {
    flex: 1;
    overflow-y: auto;
  }

  .picker-notice {
    padding: 1.5rem 1rem;
    text-align: center;
    font-size: 0.875rem;
    color: #64748b;
  }

  .picker-notice.error { color: #f87171; }

  .picker-empty {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    height: 100%;
    gap: 0.5rem;
    text-align: center;
    padding: 2rem;
  }

  .empty-icon { font-size: 2.5rem; color: #334155; }
  .empty-title { font-size: 0.9375rem; font-weight: 600; color: #94a3b8; }
  .empty-body { font-size: 0.8125rem; color: #475569; max-width: 240px; }

  .contact-row {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    width: 100%;
    padding: 0.75rem 1rem;
    background: transparent;
    border: none;
    border-bottom: 1px solid #1e293b;
    cursor: pointer;
    color: inherit;
    text-align: left;
    transition: background 0.1s;
  }

  .contact-row:hover { background: #1e293b; }
  .contact-row:last-child { border-bottom: none; }

  .avatar {
    width: 38px;
    height: 38px;
    border-radius: 50%;
    background: #1d4ed8;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 0.8125rem;
    font-weight: 700;
    color: #eff6ff;
    flex-shrink: 0;
  }

  .contact-info { flex: 1; min-width: 0; }

  .contact-name {
    font-size: 0.9375rem;
    font-weight: 500;
    color: #f1f5f9;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .contact-sub {
    font-size: 0.75rem;
    color: #64748b;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .contact-sub.mono { font-family: monospace; }

  .contact-arrow {
    font-size: 1.25rem;
    color: #334155;
    flex-shrink: 0;
  }

  .picker-footer {
    padding: 0.5rem 1rem;
    font-size: 0.75rem;
    color: #475569;
    text-align: center;
    border-top: 1px solid #1e293b;
    flex-shrink: 0;
  }

  /* ── Conversation ── */
  .convo {
    display: flex;
    flex-direction: column;
    height: 100%;
    background: #0f172a;
    color: #e2e8f0;
    overflow: hidden;
  }

  .peer-header {
    display: flex;
    align-items: center;
    gap: 0.625rem;
    padding: 0.625rem 1rem;
    background: #111827;
    border-bottom: 1px solid #1e293b;
    flex-shrink: 0;
  }

  .back-btn {
    background: transparent;
    border: none;
    color: #60a5fa;
    font-size: 1.25rem;
    cursor: pointer;
    padding: 0.25rem 0.375rem;
    border-radius: 0.25rem;
    flex-shrink: 0;
    line-height: 1;
    transition: color 0.1s, background 0.1s;
  }

  .back-btn:hover { color: #93c5fd; background: rgba(96, 165, 250, 0.1); }

  .peer-avatar {
    width: 34px;
    height: 34px;
    border-radius: 50%;
    background: #1d4ed8;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 0.75rem;
    font-weight: 700;
    color: #eff6ff;
    flex-shrink: 0;
  }

  .peer-info { flex: 1; min-width: 0; }

  .peer-name {
    font-size: 0.9375rem;
    font-weight: 600;
    color: #f1f5f9;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .peer-meta {
    display: flex;
    align-items: center;
    gap: 0.25rem;
    font-size: 0.6875rem;
    color: #64748b;
  }

  .meta-dim { color: #475569; }
  .mono { font-family: monospace; }
  .edge-dot { color: #334155; }
  .edge-badge { color: #4ade80; }

  /* Transport notice */
  .transport-notice {
    display: flex;
    align-items: center;
    gap: 0.375rem;
    padding: 0.375rem 1rem;
    background: rgba(234, 179, 8, 0.08);
    border-bottom: 1px solid rgba(234, 179, 8, 0.15);
    font-size: 0.6875rem;
    color: #a16207;
    flex-shrink: 0;
  }

  .notice-icon { color: #eab308; }

  /* Thread */
  .thread {
    flex: 1;
    overflow-y: auto;
    padding: 0.75rem 1rem;
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
  }

  .thread-empty {
    flex: 1;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 0.375rem;
    text-align: center;
    padding: 2rem;
  }

  .thread-empty-title { font-size: 0.9375rem; font-weight: 600; color: #334155; }
  .thread-empty-sub { font-size: 0.8125rem; color: #1e293b; max-width: 220px; }

  .msg {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .msg-out { align-items: flex-end; }
  .msg-in  { align-items: flex-start; }

  .msg-bubble {
    max-width: 80%;
    padding: 0.5rem 0.75rem;
    border-radius: 0.75rem;
    font-size: 0.875rem;
    line-height: 1.4;
    word-break: break-word;
  }

  .msg-out .msg-bubble {
    background: #1d4ed8;
    color: #eff6ff;
    border-bottom-right-radius: 0.25rem;
  }

  .msg-in .msg-bubble {
    background: #1e293b;
    color: #cbd5e1;
    border-bottom-left-radius: 0.25rem;
  }

  .msg-footer {
    display: flex;
    align-items: center;
    gap: 0.375rem;
    padding: 0 0.25rem;
  }

  .msg-time { font-size: 0.6875rem; color: #475569; }

  .msg-status {
    font-size: 0.6875rem;
    font-family: monospace;
  }

  .msg-status.sending { color: #64748b; font-style: italic; }
  .msg-status.queued  { color: #854d0e; }

  /* Compose */
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
