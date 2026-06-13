---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/views/QuoteEditorInline.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.071377+00:00
---

# apps/loom-svelte/src/views/QuoteEditorInline.svelte

```svelte
<script lang="ts">
  /**
   * QuoteEditorInline — per-job quote builder for the desktop helm.
   *
   * Shows existing quotes for the job + an inline new-quote editor.
   * Mirrors the Flutter QuoteEditorSheet feature-set adapted for
   * desktop real-estate:
   *   • line items table (description / qty / unit $ / total / delete)
   *   • "Describe the work" NL input → simple in-browser parser
   *   • "Show conversation context" toggle → read-only turns panel
   *   • payment terms + notes fields
   *   • running total footer
   *   • Save → REPL `add quote --job <id> --cost-min N --cost-max N --notes "..."`
   *
   * Draft line items are kept in localStorage (helm.quotedoc.<jobId>)
   * so a reload doesn't wipe work-in-progress.  The brain Quote stores
   * only FSM state + cost range + a human-readable notes text — not raw
   * JSON.
   *
   * FSM action buttons (Present / Accept / Decline / Expire / Supersede)
   * are shown inline for each existing quote row.
   */
  import { getActiveSession } from '../lib/hat-sessions';
  import { ReplClient, ReplUnauthorizedError } from '../lib/repl-client';
  import { fetchTurns, type ConversationTurn } from '../lib/conversation-turns-api';
  import { quotesTick } from '../lib/quotes-store';
  import { onMount } from 'svelte';

  let { jobId }: { jobId: string } = $props();

  // ── Types ─────────────────────────────────────────────────────────────────

  interface LineItem {
    description: string;
    quantity: number;     // float
    unitCents: number;    // integer cents
  }

  interface QuoteRow {
    id: string;
    job_id: string;
    status: string;
    cost_min: number;
    cost_max: number;
    notes: string;
    created_at: string;
    updated_at: string;
  }

  // ── Constants ─────────────────────────────────────────────────────────────

  const DEFAULT_PAYMENT_TERMS = 'Payment due within 14 days of invoice.';
  const DRAFT_KEY = `helm.quotedoc.${jobId}`;

  // ── Client ────────────────────────────────────────────────────────────────

  const client = new ReplClient();

  function resolveBearer(): string {
    const session = getActiveSession();
    return session?.bearer ??
      (typeof localStorage !== 'undefined'
        ? (localStorage.getItem('helm.bearer') ?? '')
        : '');
  }

  // ── Quote list state ──────────────────────────────────────────────────────

  let quotes = $state<QuoteRow[]>([]);
  let quotesLoading = $state(false);
  let quotesError = $state<string | null>(null);

  // Per-quote: busy flag and banner for FSM actions.
  let actionBusy = $state<Record<string, boolean>>({});
  let actionBanner = $state<Record<string, { kind: 'ok' | 'warn' | 'err'; text: string }>>({});

  // ── Editor state ──────────────────────────────────────────────────────────

  let editorOpen = $state(false);
  let items = $state<LineItem[]>([]);
  let paymentTerms = $state(DEFAULT_PAYMENT_TERMS);
  let notes = $state('');
  let nlInput = $state('');
  let saving = $state(false);
  let saveBanner = $state<{ kind: 'ok' | 'warn' | 'err'; text: string } | null>(null);

  // ── Conversation context ──────────────────────────────────────────────────

  let contextOpen = $state(false);
  let contextTurns = $state<ConversationTurn[]>([]);
  let contextLoading = $state(false);

  // ── Helpers ───────────────────────────────────────────────────────────────

  function formatCents(cents: number): string {
    return `$${(cents / 100).toFixed(2)}`;
  }

  function totalCents(): number {
    return items.reduce((s, i) => s + Math.round(i.quantity * i.unitCents), 0);
  }

  function lineTotal(item: LineItem): number {
    return Math.round(item.quantity * item.unitCents);
  }

  function formatQty(qty: number): string {
    return qty === Math.round(qty) ? String(qty) : qty.toFixed(2);
  }

  function qtyDisplay(item: LineItem): string {
    return item.quantity === 1 ? '' : `${formatQty(item.quantity)}× `;
  }

  // ── Draft persistence ─────────────────────────────────────────────────────

  function loadDraft() {
    if (typeof localStorage === 'undefined') return;
    try {
      const raw = localStorage.getItem(DRAFT_KEY);
      if (!raw) return;
      const d = JSON.parse(raw) as { items?: unknown; paymentTerms?: unknown; notes?: unknown };
      if (Array.isArray(d.items)) {
        items = (d.items as LineItem[]).filter(
          (i) => typeof i.description === 'string',
        );
      }
      if (typeof d.paymentTerms === 'string') paymentTerms = d.paymentTerms;
      if (typeof d.notes === 'string') notes = d.notes;
    } catch {
      // malformed draft — ignore.
    }
  }

  function persistDraft() {
    if (typeof localStorage === 'undefined') return;
    localStorage.setItem(
      DRAFT_KEY,
      JSON.stringify({ items, paymentTerms, notes }),
    );
  }

  function clearDraft() {
    if (typeof localStorage !== 'undefined') localStorage.removeItem(DRAFT_KEY);
  }

  // ── NL parser ─────────────────────────────────────────────────────────────

  /**
   * Parse freehand text into line items.  Splits on newlines + commas,
   * then for each token:
   *   • `$X.XX` anywhere → unit price in cents
   *   • leading `Nx` or `N ×` → quantity
   *   • remainder → description
   *
   * Examples (all parse correctly):
   *   "Fix leaking tap $150"
   *   "3x washers $5, Labour 2h $90"
   *   "Service call $0 (included)"
   */
  function parseNl(text: string): LineItem[] {
    return text
      .split(/[\n,;]+/)
      .map((s) => s.trim())
      .filter(Boolean)
      .map(parseOneLine)
      .filter((i) => i.description.length > 0 || i.unitCents > 0);
  }

  function parseOneLine(line: string): LineItem {
    // Price: first `$X` or `$X.XX` occurrence.
    const priceM = line.match(/\$(\d+(?:\.\d{1,2})?)/);
    const unitCents = priceM ? Math.round(parseFloat(priceM[1]) * 100) : 0;
    let rest = line.replace(/\$\d+(?:\.\d{1,2})?/, '').trim();

    // Quantity: leading `Nx`, `N×`, `N x`, `Nh` (hours).
    const qtyM = rest.match(/^(\d+(?:\.\d+)?)\s*[xX×h]\s*/);
    const quantity = qtyM ? parseFloat(qtyM[1]) : 1;
    if (qtyM) rest = rest.slice(qtyM[0].length).trim();

    const description = rest.replace(/[,;.]+$/, '').trim();
    return { description, quantity, unitCents };
  }

  function handleParseNl() {
    const parsed = parseNl(nlInput);
    if (parsed.length === 0) return;
    items = [...items, ...parsed];
    nlInput = '';
    persistDraft();
  }

  // ── Line item CRUD ────────────────────────────────────────────────────────

  function addBlankItem() {
    items = [...items, { description: '', quantity: 1, unitCents: 0 }];
    persistDraft();
  }

  function removeItem(idx: number) {
    items = items.filter((_, i) => i !== idx);
    persistDraft();
  }

  function updateItem(idx: number, field: keyof LineItem, raw: string) {
    items = items.map((item, i) => {
      if (i !== idx) return item;
      if (field === 'description') return { ...item, description: raw };
      if (field === 'quantity') return { ...item, quantity: parseFloat(raw) || 0 };
      if (field === 'unitCents') return { ...item, unitCents: Math.round((parseFloat(raw) || 0) * 100) };
      return item;
    });
    persistDraft();
  }

  // ── Conversation context ──────────────────────────────────────────────────

  async function toggleContext() {
    if (contextOpen) {
      contextOpen = false;
      return;
    }
    contextOpen = true;
    if (contextTurns.length > 0) return; // already loaded
    contextLoading = true;
    const bearer = resolveBearer();
    const result = await fetchTurns(jobId, bearer);
    contextTurns = result.sort((a, b) => a.timestamp - b.timestamp);
    contextLoading = false;
  }

  function formatTs(epochMs: number): string {
    const d = new Date(epochMs);
    return `${String(d.getDate()).padStart(2,'0')}/${String(d.getMonth()+1).padStart(2,'0')} ${String(d.getHours()).padStart(2,'0')}:${String(d.getMinutes()).padStart(2,'0')}`;
  }

  function surfaceLabel(surface: string): string {
    switch (surface) {
      case 'gmail':
      case 'email':      return '📧';
      case 'sms':        return '💬';
      case 'voice_note': return '🎤';
      case 'widget':     return '🖥';
      case 'repl':       return '⌨';
      default:           return '·';
    }
  }

  // ── Build notes text ──────────────────────────────────────────────────────

  function buildNotesText(): string {
    const parts: string[] = [];
    if (items.length > 0) {
      parts.push(
        items
          .map((i) => `${qtyDisplay(i)}${i.description} ${formatCents(lineTotal(i))}`)
          .join('; '),
      );
    }
    if (paymentTerms.trim()) parts.push(paymentTerms.trim());
    if (notes.trim()) parts.push(notes.trim());
    return parts.join('\n');
  }

  // ── Save quote ────────────────────────────────────────────────────────────

  async function saveQuote() {
    saving = true;
    saveBanner = null;
    const total = totalCents();
    const notesText = buildNotesText();
    const escaped = notesText.replaceAll('"', '\\"').replaceAll('\n', '\\n');
    const cmd = `add quote --job ${jobId} --cost-min ${total} --cost-max ${total} --notes "${escaped}"`;
    try {
      const resp = await client.send(cmd);
      if ('error' in resp) {
        saveBanner = { kind: 'err', text: `Failed: ${resp.error}` };
        return;
      }
      const text = resp.result.trim();
      if (text.startsWith('{')) {
        const parsed = JSON.parse(text);
        if (parsed.error) {
          saveBanner = { kind: 'err', text: `${parsed.error}: ${parsed.job_id ?? ''}` };
          return;
        }
        if (parsed.id) {
          saveBanner = { kind: 'ok', text: `Quote ${parsed.id} saved (${parsed.status}).` };
          clearDraft();
          items = [];
          notes = '';
          paymentTerms = DEFAULT_PAYMENT_TERMS;
          editorOpen = false;
          await loadQuotes(); // refresh list
          return;
        }
      }
      saveBanner = { kind: 'warn', text: `Unexpected response: ${text.slice(0, 80)}` };
    } catch (e: unknown) {
      if (e instanceof ReplUnauthorizedError) {
        saveBanner = { kind: 'err', text: 'Session expired — sign in again.' };
        return;
      }
      saveBanner = { kind: 'err', text: e instanceof Error ? e.message : String(e) };
    } finally {
      saving = false;
    }
  }

  // ── Quote list ────────────────────────────────────────────────────────────

  async function loadQuotes() {
    quotesLoading = true;
    quotesError = null;
    try {
      const resp = await client.send(`find quotes --job-id ${jobId}`);
      if ('error' in resp) {
        quotesError = resp.error;
        return;
      }
      const text = resp.result.trim();
      if (!text || text.length === 0) {
        quotes = [];
        return;
      }
      if (text.startsWith('[') || text.startsWith('{')) {
        const parsed = JSON.parse(text);
        if (Array.isArray(parsed)) {
          quotes = parsed.map((r) => ({
            id: String(r.id ?? ''),
            job_id: String(r.job_id ?? ''),
            status: String(r.status ?? ''),
            cost_min: Number(r.cost_min ?? 0),
            cost_max: Number(r.cost_max ?? 0),
            notes: String(r.notes ?? ''),
            created_at: String(r.created_at ?? ''),
            updated_at: String(r.updated_at ?? ''),
          }));
        }
      }
    } catch (e: unknown) {
      quotesError = e instanceof Error ? e.message : String(e);
    } finally {
      quotesLoading = false;
    }
  }

  // ── FSM actions on existing quotes ────────────────────────────────────────

  const FSM_ACTIONS: Record<string, Array<{ label: string; verb: string; confirm?: string }>> = {
    draft: [
      { label: 'Present', verb: 'present quote' },
      { label: 'Supersede', verb: 'supersede quote', confirm: 'Supersede this quote?' },
    ],
    presented: [
      { label: 'Accept', verb: 'accept quote' },
      { label: 'Decline', verb: 'decline quote', confirm: 'Decline this quote?' },
      { label: 'Expire', verb: 'expire quote', confirm: 'Mark as expired?' },
      { label: 'Supersede', verb: 'supersede quote', confirm: 'Supersede this quote?' },
    ],
  };

  async function runFsmAction(quoteId: string, verb: string, label: string, confirm?: string) {
    if (confirm && !window.confirm(confirm)) return;
    actionBusy = { ...actionBusy, [quoteId]: true };
    actionBanner = { ...actionBanner };
    delete actionBanner[quoteId];
    try {
      const resp = await client.send(`${verb} ${quoteId}`);
      if ('error' in resp) {
        actionBanner = { ...actionBanner, [quoteId]: { kind: 'err', text: resp.error } };
        return;
      }
      const text = resp.result.trim();
      if (text.startsWith('{')) {
        const parsed = JSON.parse(text);
        if (parsed.error) {
          actionBanner = { ...actionBanner, [quoteId]: { kind: 'err', text: `${label}: ${parsed.error}` } };
          return;
        }
        if (parsed.status === 'already_in_state') {
          actionBanner = { ...actionBanner, [quoteId]: { kind: 'warn', text: `Already ${parsed.quote?.status ?? 'in state'}` } };
        } else if (parsed.id) {
          actionBanner = { ...actionBanner, [quoteId]: { kind: 'ok', text: `${label} → ${parsed.status}` } };
        }
      }
      await loadQuotes();
    } catch (e: unknown) {
      actionBanner = {
        ...actionBanner,
        [quoteId]: { kind: 'err', text: e instanceof Error ? e.message : String(e) },
      };
    } finally {
      actionBusy = { ...actionBusy, [quoteId]: false };
    }
  }

  // ── Open / close editor ───────────────────────────────────────────────────

  function openEditor() {
    loadDraft();
    editorOpen = true;
    saveBanner = null;
  }

  function cancelEditor() {
    editorOpen = false;
    saveBanner = null;
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  onMount(() => {
    void loadQuotes();
    // Re-fetch list when quote events arrive.
    let first: number | null = null;
    const unsub = quotesTick.subscribe((n) => {
      if (first === null) { first = n; return; }
      void loadQuotes();
    });
    return unsub;
  });
</script>

<!-- ── Quote list ──────────────────────────────────────────────────────────── -->
<div class="qe-wrap">
  <div class="qe-header">
    {#if quotesLoading}
      <span class="qe-loading">⏳ loading quotes…</span>
    {:else if quotesError}
      <span class="qe-err">{quotesError}</span>
    {:else if quotes.length === 0}
      <span class="qe-empty">No quotes drafted yet.</span>
    {:else}
      <ul class="qe-list">
        {#each quotes as q (q.id)}
          <li class="qe-row">
            <div class="qe-row-top">
              <code class="qe-id">{q.id.slice(0, 8)}…</code>
              <span class="qe-status qe-status-{q.status}">{q.status}</span>
              <span class="qe-cost">
                {formatCents(q.cost_min)}
                {#if q.cost_max !== q.cost_min} – {formatCents(q.cost_max)}{/if}
              </span>
              <span class="qe-date">{q.updated_at.slice(0, 10)}</span>
            </div>
            {#if q.notes}
              <p class="qe-notes">{q.notes}</p>
            {/if}
            {#if FSM_ACTIONS[q.status]}
              <div class="qe-actions">
                {#each FSM_ACTIONS[q.status] as a}
                  <button
                    class="qe-action-btn qe-action-{a.verb.split(' ')[0]}"
                    onclick={() => runFsmAction(q.id, a.verb, a.label, a.confirm)}
                    disabled={actionBusy[q.id] ?? false}
                  >
                    {a.label}
                  </button>
                {/each}
              </div>
            {/if}
            {#if actionBanner[q.id]}
              <p class="qe-action-banner qe-action-banner-{actionBanner[q.id].kind}">
                {actionBanner[q.id].text}
              </p>
            {/if}
          </li>
        {/each}
      </ul>
    {/if}

    {#if !editorOpen}
      <button class="qe-new-btn" onclick={openEditor}>+ New Quote</button>
    {/if}
  </div>

  <!-- ── Inline editor ──────────────────────────────────────────────────── -->
  {#if editorOpen}
    <div class="qe-editor">
      <div class="qe-editor-header">
        <span class="qe-editor-title">Draft Quote</span>
        <button class="qe-cancel" onclick={cancelEditor}>✕ Cancel</button>
      </div>

      <!-- NL input bar -->
      <div class="qe-nl-row">
        <textarea
          class="qe-nl-input"
          placeholder={`Describe the work, e.g. "Fix leaking tap $150, washers x3 $5, 2h labour $90"`}
          rows="2"
          bind:value={nlInput}
          onkeydown={(e) => { if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) handleParseNl(); }}
        ></textarea>
        <button
          class="qe-nl-btn"
          onclick={handleParseNl}
          disabled={!nlInput.trim()}
          title="Parse into line items (Ctrl+Enter)"
        >Parse</button>
      </div>
      <p class="qe-nl-hint">Separate items with commas or newlines. Ctrl+Enter to parse.</p>

      <!-- Conversation context toggle -->
      <div class="qe-ctx-row">
        <button class="qe-ctx-btn" onclick={toggleContext}>
          {contextOpen ? '▲ Hide context' : '▼ Show conversation context'}
        </button>
      </div>
      {#if contextOpen}
        <div class="qe-ctx-panel">
          {#if contextLoading}
            <p class="qe-ctx-loading">Loading conversation…</p>
          {:else if contextTurns.length === 0}
            <p class="qe-ctx-empty">No conversation turns on record for this job.</p>
          {:else}
            {#each contextTurns as t (t.turnId)}
              <div class="qe-ctx-turn qe-ctx-turn-{t.direction}">
                <span class="qe-ctx-meta">
                  {surfaceLabel(t.surface)} {t.identityValue ?? t.participantRole} · {formatTs(t.timestamp)}
                </span>
                <p class="qe-ctx-body">{t.bodyText}</p>
              </div>
            {/each}
          {/if}
        </div>
      {/if}

      <!-- Line items table -->
      <div class="qe-items-header">
        <span class="qe-items-label">Line items</span>
        <button class="qe-add-item" onclick={addBlankItem}>+ Add row</button>
      </div>

      {#if items.length === 0}
        <p class="qe-items-empty">
          No items yet. Describe the work above or click "Add row".
        </p>
      {:else}
        <div class="qe-items-table">
          <div class="qe-items-thead">
            <span class="qe-col-desc">Description</span>
            <span class="qe-col-qty">Qty</span>
            <span class="qe-col-unit">Unit $</span>
            <span class="qe-col-total">Total</span>
            <span class="qe-col-del"></span>
          </div>
          {#each items as item, idx (idx)}
            <div class="qe-items-row">
              <input
                class="qe-col-desc qe-cell"
                type="text"
                value={item.description}
                placeholder="Description"
                oninput={(e) => updateItem(idx, 'description', (e.target as HTMLInputElement).value)}
              />
              <input
                class="qe-col-qty qe-cell qe-cell-num"
                type="number"
                step="0.5"
                min="0"
                value={item.quantity}
                oninput={(e) => updateItem(idx, 'quantity', (e.target as HTMLInputElement).value)}
              />
              <input
                class="qe-col-unit qe-cell qe-cell-num"
                type="number"
                step="0.01"
                min="0"
                value={(item.unitCents / 100).toFixed(2)}
                oninput={(e) => updateItem(idx, 'unitCents', (e.target as HTMLInputElement).value)}
              />
              <span class="qe-col-total qe-cell-total">{formatCents(lineTotal(item))}</span>
              <button class="qe-del" onclick={() => removeItem(idx)} title="Remove">✕</button>
            </div>
          {/each}
        </div>
        <div class="qe-total-row">
          <span class="qe-total-label">Total</span>
          <span class="qe-total-value">{formatCents(totalCents())}</span>
        </div>
      {/if}

      <!-- Payment terms -->
      <label class="qe-field-label" for="qe-pt">Payment terms</label>
      <textarea
        id="qe-pt"
        class="qe-textarea"
        rows="2"
        bind:value={paymentTerms}
        onchange={persistDraft}
      ></textarea>

      <!-- Scope notes -->
      <label class="qe-field-label" for="qe-notes">Notes / scope</label>
      <textarea
        id="qe-notes"
        class="qe-textarea"
        rows="3"
        placeholder="Scope of work, inclusions, exclusions…"
        bind:value={notes}
        onchange={persistDraft}
      ></textarea>

      <!-- Save row -->
      <div class="qe-save-row">
        <button
          class="qe-save-btn"
          onclick={saveQuote}
          disabled={saving || items.length === 0}
        >
          {saving ? 'Saving…' : `Save Quote (${formatCents(totalCents())})`}
        </button>
        <button class="qe-cancel-sm" onclick={cancelEditor} disabled={saving}>Cancel</button>
      </div>

      {#if saveBanner}
        <p class="qe-save-banner qe-save-banner-{saveBanner.kind}">{saveBanner.text}</p>
      {/if}
    </div>
  {/if}
</div>

<style>
  .qe-wrap {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
    font-family: var(--mono, ui-monospace, monospace);
    font-size: 0.8125rem;
  }

  /* ── Header / list ── */
  .qe-header {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
  }

  .qe-loading,
  .qe-empty {
    color: #4b5563;
    font-style: italic;
    font-size: 0.8125rem;
  }

  .qe-err { color: #f87171; font-size: 0.8125rem; }

  .qe-list {
    list-style: none;
    padding: 0;
    margin: 0;
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
  }

  .qe-row {
    background: #1a1a1a;
    border: 1px solid #2a2a2a;
    border-radius: 0.375rem;
    padding: 0.5rem 0.625rem;
    display: flex;
    flex-direction: column;
    gap: 0.25rem;
  }

  .qe-row-top {
    display: flex;
    align-items: baseline;
    gap: 0.5rem;
    flex-wrap: wrap;
  }

  .qe-id { color: #6b7280; font-size: 0.75rem; }

  .qe-status {
    font-size: 0.6875rem;
    padding: 0.0625rem 0.375rem;
    border-radius: 0.25rem;
    background: #2a2a2a;
    color: #9ca3af;
  }
  .qe-status-draft     { background: rgba(59,130,246,0.15); color: #93c5fd; }
  .qe-status-presented { background: rgba(245,158,11,0.15); color: #fcd34d; }
  .qe-status-accepted  { background: rgba(34,197,94,0.15);  color: #86efac; }
  .qe-status-rejected  { background: rgba(239,68,68,0.15);  color: #fca5a5; }
  .qe-status-expired,
  .qe-status-superseded { background: rgba(107,114,128,0.15); color: #6b7280; }

  .qe-cost { color: #e5e7eb; font-weight: 600; }
  .qe-date { color: #4b5563; font-size: 0.6875rem; margin-left: auto; }

  .qe-notes {
    color: #6b7280;
    font-size: 0.75rem;
    margin: 0;
    white-space: pre-wrap;
    word-break: break-word;
    border-left: 2px solid #2a2a2a;
    padding-left: 0.5rem;
  }

  .qe-actions {
    display: flex;
    gap: 0.375rem;
    flex-wrap: wrap;
    margin-top: 0.25rem;
  }

  .qe-action-btn {
    background: #1e293b;
    border: 1px solid #334155;
    border-radius: 0.25rem;
    color: #93c5fd;
    cursor: pointer;
    font-family: inherit;
    font-size: 0.6875rem;
    padding: 0.1875rem 0.5rem;
  }
  .qe-action-btn:hover:not(:disabled) { background: #263045; border-color: #60a5fa; }
  .qe-action-btn:disabled { opacity: 0.4; cursor: default; }
  .qe-action-btn.qe-action-accept { background: rgba(34,197,94,0.1); border-color: rgba(34,197,94,0.3); color: #86efac; }
  .qe-action-btn.qe-action-decline { background: rgba(239,68,68,0.1); border-color: rgba(239,68,68,0.3); color: #fca5a5; }
  .qe-action-btn.qe-action-expire { background: rgba(107,114,128,0.1); border-color: rgba(107,114,128,0.3); color: #9ca3af; }
  .qe-action-btn.qe-action-supersede { background: rgba(245,158,11,0.1); border-color: rgba(245,158,11,0.3); color: #fcd34d; }

  .qe-action-banner {
    font-size: 0.6875rem;
    padding: 0.1875rem 0.5rem;
    border-radius: 0.25rem;
    margin: 0;
  }
  .qe-action-banner-ok   { background: rgba(34,197,94,0.1);  color: #86efac; }
  .qe-action-banner-warn { background: rgba(245,158,11,0.1); color: #fcd34d; }
  .qe-action-banner-err  { background: rgba(239,68,68,0.1);  color: #fca5a5; }

  .qe-new-btn {
    align-self: flex-start;
    background: #1d4ed8;
    border: none;
    border-radius: 0.375rem;
    color: #fff;
    cursor: pointer;
    font-family: inherit;
    font-size: 0.8125rem;
    padding: 0.375rem 0.75rem;
  }
  .qe-new-btn:hover { background: #2563eb; }

  /* ── Editor ── */
  .qe-editor {
    background: #111;
    border: 1px solid #2a2a2a;
    border-radius: 0.5rem;
    padding: 0.75rem;
    display: flex;
    flex-direction: column;
    gap: 0.625rem;
  }

  .qe-editor-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
  }

  .qe-editor-title {
    font-weight: 600;
    color: #e5e7eb;
    font-size: 0.875rem;
  }

  .qe-cancel {
    background: transparent;
    border: 1px solid #374151;
    border-radius: 0.25rem;
    color: #6b7280;
    cursor: pointer;
    font: inherit;
    font-size: 0.75rem;
    padding: 0.1875rem 0.5rem;
  }
  .qe-cancel:hover { color: #9ca3af; border-color: #4b5563; }

  /* NL input */
  .qe-nl-row {
    display: flex;
    gap: 0.5rem;
    align-items: flex-end;
  }

  .qe-nl-input {
    flex: 1;
    background: #0f0f0f;
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
  .qe-nl-input:focus { border-color: #60a5fa; }

  .qe-nl-btn {
    background: #1d4ed8;
    border: none;
    border-radius: 0.375rem;
    color: #fff;
    cursor: pointer;
    font: inherit;
    font-size: 0.8125rem;
    padding: 0.375rem 0.75rem;
    white-space: nowrap;
    align-self: flex-end;
  }
  .qe-nl-btn:hover:not(:disabled) { background: #2563eb; }
  .qe-nl-btn:disabled { opacity: 0.4; cursor: default; }

  .qe-nl-hint {
    color: #4b5563;
    font-size: 0.6875rem;
    margin: -0.25rem 0 0;
  }

  /* Context panel */
  .qe-ctx-row { display: flex; }

  .qe-ctx-btn {
    background: transparent;
    border: 1px solid #2a2a2a;
    border-radius: 0.25rem;
    color: #6b7280;
    cursor: pointer;
    font: inherit;
    font-size: 0.75rem;
    padding: 0.25rem 0.625rem;
  }
  .qe-ctx-btn:hover { color: #9ca3af; border-color: #374151; }

  .qe-ctx-panel {
    background: #0a0a0a;
    border: 1px solid #1f2937;
    border-radius: 0.375rem;
    max-height: 200px;
    overflow-y: auto;
    padding: 0.5rem;
    display: flex;
    flex-direction: column;
    gap: 0.375rem;
  }

  .qe-ctx-loading,
  .qe-ctx-empty {
    color: #4b5563;
    font-style: italic;
    font-size: 0.75rem;
    margin: 0;
  }

  .qe-ctx-turn {
    display: flex;
    flex-direction: column;
    gap: 0.125rem;
    padding: 0.25rem 0.375rem;
    border-radius: 0.25rem;
  }
  .qe-ctx-turn-inbound  { background: rgba(30,41,59,0.6); }
  .qe-ctx-turn-outbound { background: rgba(29,78,216,0.2); }

  .qe-ctx-meta {
    font-size: 0.625rem;
    color: #4b5563;
  }

  .qe-ctx-body {
    color: #9ca3af;
    font-size: 0.75rem;
    margin: 0;
    white-space: pre-wrap;
    word-break: break-word;
  }

  /* Line items */
  .qe-items-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
  }

  .qe-items-label {
    font-weight: 600;
    color: #e5e7eb;
    font-size: 0.8125rem;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    font-size: 0.6875rem;
  }

  .qe-add-item {
    background: transparent;
    border: 1px solid #374151;
    border-radius: 0.25rem;
    color: #60a5fa;
    cursor: pointer;
    font: inherit;
    font-size: 0.75rem;
    padding: 0.1875rem 0.5rem;
  }
  .qe-add-item:hover { background: rgba(96,165,250,0.08); }

  .qe-items-empty {
    color: #4b5563;
    font-style: italic;
    font-size: 0.75rem;
    margin: 0;
  }

  .qe-items-table {
    display: flex;
    flex-direction: column;
    gap: 0.25rem;
  }

  .qe-items-thead,
  .qe-items-row {
    display: grid;
    grid-template-columns: 1fr 4rem 5rem 4.5rem 1.5rem;
    gap: 0.375rem;
    align-items: center;
  }

  .qe-items-thead {
    padding: 0 0.25rem;
    margin-bottom: 0.125rem;
  }

  .qe-items-thead > * {
    font-size: 0.625rem;
    color: #4b5563;
    text-transform: uppercase;
    letter-spacing: 0.08em;
  }

  .qe-cell {
    background: #0f0f0f;
    border: 1px solid #2a2a2a;
    border-radius: 0.25rem;
    color: #e5e7eb;
    font: inherit;
    font-size: 0.8125rem;
    padding: 0.25rem 0.375rem;
    outline: none;
    width: 100%;
    box-sizing: border-box;
  }
  .qe-cell:focus { border-color: #60a5fa; }

  .qe-cell-num { text-align: right; }

  .qe-cell-total {
    text-align: right;
    color: #e5e7eb;
    font-size: 0.8125rem;
  }

  .qe-del {
    background: transparent;
    border: none;
    color: #4b5563;
    cursor: pointer;
    font-size: 0.75rem;
    padding: 0;
    line-height: 1;
  }
  .qe-del:hover { color: #f87171; }

  .qe-total-row {
    display: flex;
    justify-content: flex-end;
    gap: 1rem;
    padding: 0.375rem 0.25rem;
    border-top: 1px solid #2a2a2a;
  }

  .qe-total-label {
    color: #6b7280;
    font-size: 0.8125rem;
    text-transform: uppercase;
    letter-spacing: 0.06em;
  }

  .qe-total-value {
    color: #e5e7eb;
    font-weight: 700;
    font-size: 0.9375rem;
  }

  /* Payment terms / notes */
  .qe-field-label {
    font-size: 0.6875rem;
    color: #4b5563;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    display: block;
  }

  .qe-textarea {
    background: #0f0f0f;
    border: 1px solid #2a2a2a;
    border-radius: 0.375rem;
    color: #e5e7eb;
    font: inherit;
    font-size: 0.8125rem;
    padding: 0.375rem 0.5rem;
    resize: vertical;
    line-height: 1.4;
    outline: none;
    width: 100%;
    box-sizing: border-box;
  }
  .qe-textarea:focus { border-color: #60a5fa; }

  /* Save row */
  .qe-save-row {
    display: flex;
    gap: 0.5rem;
    align-items: center;
    padding-top: 0.25rem;
  }

  .qe-save-btn {
    background: #1d4ed8;
    border: none;
    border-radius: 0.375rem;
    color: #fff;
    cursor: pointer;
    font: inherit;
    font-size: 0.875rem;
    font-weight: 600;
    padding: 0.5rem 1.25rem;
  }
  .qe-save-btn:hover:not(:disabled) { background: #2563eb; }
  .qe-save-btn:disabled { opacity: 0.4; cursor: default; }

  .qe-cancel-sm {
    background: transparent;
    border: 1px solid #374151;
    border-radius: 0.375rem;
    color: #6b7280;
    cursor: pointer;
    font: inherit;
    font-size: 0.8125rem;
    padding: 0.375rem 0.75rem;
  }
  .qe-cancel-sm:hover { color: #9ca3af; }

  .qe-save-banner {
    font-size: 0.75rem;
    padding: 0.375rem 0.5rem;
    border-radius: 0.25rem;
    margin: 0;
  }
  .qe-save-banner-ok   { background: rgba(34,197,94,0.12);  color: #86efac; }
  .qe-save-banner-warn { background: rgba(245,158,11,0.12); color: #fcd34d; }
  .qe-save-banner-err  { background: rgba(239,68,68,0.12);  color: #fca5a5; }
</style>

```
