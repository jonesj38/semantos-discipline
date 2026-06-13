---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/views/InvoiceEditorInline.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.071943+00:00
---

# apps/loom-svelte/src/views/InvoiceEditorInline.svelte

```svelte
<script lang="ts">
  /**
   * InvoiceEditorInline — per-job invoice builder for the desktop helm.
   *
   * Mirrors QuoteEditorInline adapted for invoices:
   *   • Lists existing invoices for the job (find invoices --job-id <id>)
   *   • Inline FSM action buttons (Send / Mark Paid / Mark Partial /
   *     Mark Viewed / Mark Overdue / Cancel)
   *   • New-invoice editor: line items, NL parser, conversation context
   *   • Auto-populates from accepted quote draft in localStorage
   *     (helm.quotedoc.<jobId>) so the WO → invoice or quote → invoice
   *     transition pre-fills everything the operator built in the quote
   *   • Single `amount` field (not min/max range like quotes)
   *   • TAX INVOICE header in save output; source label in notes
   *
   * REPL verbs:
   *   find invoices --job-id <id>  → list
   *   add invoice --job <id> --amount <N> --notes "<text>"
   *   send invoice <id>
   *   mark invoice paid <id>
   *   mark invoice partial <id>
   *   mark invoice viewed <id>
   *   mark invoice overdue <id>
   *   cancel invoice <id>
   */
  import { getActiveSession } from '../lib/hat-sessions';
  import { ReplClient, ReplUnauthorizedError } from '../lib/repl-client';
  import { fetchTurns, type ConversationTurn } from '../lib/conversation-turns-api';
  import { invoicesTick } from '../lib/invoices-store';
  import { onMount } from 'svelte';

  let { jobId }: { jobId: string } = $props();

  // ── Types ─────────────────────────────────────────────────────────────────

  interface LineItem {
    description: string;
    quantity: number;
    unitCents: number;
    source: 'quote' | 'manual' | 'receipt';  // mirrors InvoiceDocument variance tracking
  }

  interface InvoiceRow {
    id: string;
    job_id: string;
    status: string;
    amount: number;
    amount_paid: number;
    notes: string;
    sent_at: string;
    paid_at: string;
    created_at: string;
    updated_at: string;
  }

  // ── Constants ─────────────────────────────────────────────────────────────

  const DEFAULT_PAYMENT_TERMS = 'Payment due within 14 days of invoice.';
  const QUOTE_DRAFT_KEY = `helm.quotedoc.${jobId}`;
  const INVOICE_DRAFT_KEY = `helm.invoicedoc.${jobId}`;

  // ── Client ────────────────────────────────────────────────────────────────

  const client = new ReplClient();

  function resolveBearer(): string {
    const session = getActiveSession();
    return session?.bearer ??
      (typeof localStorage !== 'undefined'
        ? (localStorage.getItem('helm.bearer') ?? '')
        : '');
  }

  // ── Invoice list state ────────────────────────────────────────────────────

  let invoices = $state<InvoiceRow[]>([]);
  let invoicesLoading = $state(false);
  let invoicesError = $state<string | null>(null);

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
  let seededFromQuote = $state(false);

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

  function sourceLabel(source: LineItem['source']): string {
    switch (source) {
      case 'quote':   return '📋';
      case 'receipt': return '🧾';
      default:        return '';
    }
  }

  // ── Draft persistence ─────────────────────────────────────────────────────

  function loadDraft() {
    if (typeof localStorage === 'undefined') return;
    // Prefer existing invoice draft; fall back to seeding from quote draft.
    try {
      const raw = localStorage.getItem(INVOICE_DRAFT_KEY);
      if (raw) {
        const d = JSON.parse(raw) as { items?: unknown; paymentTerms?: unknown; notes?: unknown };
        if (Array.isArray(d.items)) items = d.items as LineItem[];
        if (typeof d.paymentTerms === 'string') paymentTerms = d.paymentTerms;
        if (typeof d.notes === 'string') notes = d.notes;
        return;
      }
    } catch { /* ignore */ }

    // No invoice draft — try to seed from accepted quote draft.
    try {
      const qRaw = localStorage.getItem(QUOTE_DRAFT_KEY);
      if (qRaw) {
        const qd = JSON.parse(qRaw) as { items?: unknown; paymentTerms?: unknown; notes?: unknown };
        if (Array.isArray(qd.items) && (qd.items as unknown[]).length > 0) {
          // Mark all quote-seeded items with source='quote'.
          items = (qd.items as Array<{description?: string; quantity?: number; unitCents?: number}>).map(
            (i) => ({
              description: String(i.description ?? ''),
              quantity:    Number(i.quantity ?? 1),
              unitCents:   Number(i.unitCents ?? 0),
              source:      'quote' as const,
            }),
          );
          if (typeof qd.paymentTerms === 'string') paymentTerms = qd.paymentTerms;
          if (typeof qd.notes === 'string') notes = qd.notes;
          seededFromQuote = true;
        }
      }
    } catch { /* ignore */ }
    // Last resort: fetch accepted quote from brain and parse notes as line items.
    // This handles the case where the quote was built on the phone (no localStorage draft).
    if (!seededFromQuote) {
      void seedFromBrainQuote();
    }
  }

  /**
   * Fallback: query the brain for accepted quotes for this job, parse the
   * first one's notes text using the NL parser to extract line items.
   * Only runs when no localStorage draft exists (phone-to-helm handoff).
   */
  async function seedFromBrainQuote() {
    try {
      const resp = await client.send(`find quotes --job-id ${jobId}`);
      if ('error' in resp) return;
      const text = resp.result.trim();
      if (!text.startsWith('[') && !text.startsWith('{')) return;
      const parsed = JSON.parse(text);
      if (!Array.isArray(parsed)) return;
      const accepted = parsed.find(
        (r: Record<string, unknown>) => String(r.status ?? '') === 'accepted',
      );
      if (!accepted || !accepted.notes) return;
      const notesText = String(accepted.notes);
      // First line may be a semicolon-joined items line — parse it.
      const firstLine = notesText.split('\n')[0];
      const parsed_items = parseNl(firstLine).filter((i) => i.unitCents > 0);
      if (parsed_items.length === 0) return;
      items = parsed_items.map((i) => ({ ...i, source: 'quote' as const }));
      // Remaining lines after the items line may be payment terms.
      const remainder = notesText.split('\n').slice(1).join('\n').trim();
      if (remainder && !remainder.toLowerCase().startsWith('tax invoice')) {
        paymentTerms = remainder.split('\n')[0] ?? DEFAULT_PAYMENT_TERMS;
      }
      seededFromQuote = true;
      persistDraft();
    } catch { /* ignore — brain may be slow or quote format may differ */ }
  }

  function persistDraft() {
    if (typeof localStorage === 'undefined') return;
    localStorage.setItem(
      INVOICE_DRAFT_KEY,
      JSON.stringify({ items, paymentTerms, notes }),
    );
  }

  function clearDraft() {
    if (typeof localStorage !== 'undefined') localStorage.removeItem(INVOICE_DRAFT_KEY);
  }

  // ── NL parser (same as QuoteEditorInline) ─────────────────────────────────

  function parseNl(text: string): LineItem[] {
    return text
      .split(/[\n,;]+/)
      .map((s) => s.trim())
      .filter(Boolean)
      .map(parseOneLine)
      .filter((i) => i.description.length > 0 || i.unitCents > 0);
  }

  function parseOneLine(line: string): LineItem {
    const priceM = line.match(/\$(\d+(?:\.\d{1,2})?)/);
    const unitCents = priceM ? Math.round(parseFloat(priceM[1]) * 100) : 0;
    let rest = line.replace(/\$\d+(?:\.\d{1,2})?/, '').trim();
    const qtyM = rest.match(/^(\d+(?:\.\d+)?)\s*[xX×h]\s*/);
    const quantity = qtyM ? parseFloat(qtyM[1]) : 1;
    if (qtyM) rest = rest.slice(qtyM[0].length).trim();
    const description = rest.replace(/[,;.]+$/, '').trim();
    return { description, quantity, unitCents, source: 'manual' };
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
    items = [...items, { description: '', quantity: 1, unitCents: 0, source: 'manual' }];
    persistDraft();
  }

  function removeItem(idx: number) {
    items = items.filter((_, i) => i !== idx);
    persistDraft();
  }

  function updateItem(idx: number, field: 'description' | 'quantity' | 'unitCents', raw: string) {
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
    if (contextOpen) { contextOpen = false; return; }
    contextOpen = true;
    if (contextTurns.length > 0) return;
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
      case 'gmail': case 'email': return '📧';
      case 'sms':         return '💬';
      case 'voice_note':  return '🎤';
      case 'widget':      return '🖥';
      case 'repl':        return '⌨';
      default:            return '·';
    }
  }

  // ── Build notes text ──────────────────────────────────────────────────────

  function buildNotesText(): string {
    const parts: string[] = ['TAX INVOICE'];
    if (seededFromQuote) parts.push('(from accepted quote)');
    if (items.length > 0) {
      parts.push(
        items
          .map((i) => `${sourceLabel(i.source)}${qtyDisplay(i)}${i.description} ${formatCents(lineTotal(i))}`)
          .join('; '),
      );
    }
    if (paymentTerms.trim()) parts.push(paymentTerms.trim());
    if (notes.trim()) parts.push(notes.trim());
    return parts.join('\n');
  }

  // ── Save invoice ──────────────────────────────────────────────────────────

  async function saveInvoice() {
    saving = true;
    saveBanner = null;
    const total = totalCents();
    const notesText = buildNotesText();
    const escaped = notesText.replaceAll('"', '\\"').replaceAll('\n', '\\n');
    const cmd = `add invoice --job ${jobId} --amount ${total} --notes "${escaped}"`;
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
          saveBanner = { kind: 'ok', text: `Invoice ${parsed.id} saved (${parsed.status}).` };
          clearDraft();
          items = [];
          notes = '';
          paymentTerms = DEFAULT_PAYMENT_TERMS;
          seededFromQuote = false;
          editorOpen = false;
          await loadInvoices();
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

  // ── Invoice list ──────────────────────────────────────────────────────────

  async function loadInvoices() {
    invoicesLoading = true;
    invoicesError = null;
    try {
      const resp = await client.send(`find invoices --job-id ${jobId}`);
      if ('error' in resp) {
        invoicesError = resp.error;
        return;
      }
      const text = resp.result.trim();
      if (!text) { invoices = []; return; }
      if (text.startsWith('[') || text.startsWith('{')) {
        const parsed = JSON.parse(text);
        if (Array.isArray(parsed)) {
          invoices = parsed.map((r) => ({
            id:               String(r.id ?? ''),
            job_id:           String(r.job_id ?? ''),
            status:           String(r.status ?? ''),
            amount:           Number(r.amount ?? 0),
            amount_paid:      Number(r.amount_paid ?? 0),
            notes:            String(r.notes ?? ''),
            sent_at:          String(r.sent_at ?? ''),
            paid_at:          String(r.paid_at ?? ''),
            created_at:       String(r.created_at ?? ''),
            updated_at:       String(r.updated_at ?? ''),
          }));
        }
      }
    } catch (e: unknown) {
      invoicesError = e instanceof Error ? e.message : String(e);
    } finally {
      invoicesLoading = false;
    }
  }

  // ── FSM actions ───────────────────────────────────────────────────────────

  const FSM_ACTIONS: Record<string, Array<{ label: string; verb: string; confirm?: string }>> = {
    draft: [
      { label: 'Send', verb: 'send invoice' },
      { label: 'Cancel', verb: 'cancel invoice', confirm: 'Cancel this invoice?' },
    ],
    sent: [
      { label: 'Mark Paid', verb: 'mark invoice paid' },
      { label: 'Mark Partial', verb: 'mark invoice partial' },
      { label: 'Mark Viewed', verb: 'mark invoice viewed' },
      { label: 'Mark Overdue', verb: 'mark invoice overdue', confirm: 'Mark as overdue?' },
      { label: 'Cancel', verb: 'cancel invoice', confirm: 'Cancel this invoice?' },
    ],
    viewed: [
      { label: 'Mark Paid', verb: 'mark invoice paid' },
      { label: 'Mark Partial', verb: 'mark invoice partial' },
      { label: 'Mark Overdue', verb: 'mark invoice overdue', confirm: 'Mark as overdue?' },
      { label: 'Cancel', verb: 'cancel invoice', confirm: 'Cancel this invoice?' },
    ],
    partial: [
      { label: 'Mark Paid', verb: 'mark invoice paid' },
      { label: 'Mark Overdue', verb: 'mark invoice overdue', confirm: 'Mark as overdue?' },
    ],
    overdue: [
      { label: 'Mark Paid', verb: 'mark invoice paid' },
      { label: 'Mark Partial', verb: 'mark invoice partial' },
    ],
  };

  async function runFsmAction(invoiceId: string, verb: string, label: string, confirm?: string) {
    if (confirm && !window.confirm(confirm)) return;
    actionBusy = { ...actionBusy, [invoiceId]: true };
    actionBanner = { ...actionBanner };
    delete actionBanner[invoiceId];
    try {
      const resp = await client.send(`${verb} ${invoiceId}`);
      if ('error' in resp) {
        actionBanner = { ...actionBanner, [invoiceId]: { kind: 'err', text: resp.error } };
        return;
      }
      const text = resp.result.trim();
      if (text.startsWith('{')) {
        const parsed = JSON.parse(text);
        if (parsed.error) {
          actionBanner = { ...actionBanner, [invoiceId]: { kind: 'err', text: `${label}: ${parsed.error}` } };
          return;
        }
        if (parsed.status === 'already_in_state') {
          actionBanner = { ...actionBanner, [invoiceId]: { kind: 'warn', text: `Already ${parsed.invoice?.status ?? 'in state'}` } };
        } else if (parsed.id) {
          actionBanner = { ...actionBanner, [invoiceId]: { kind: 'ok', text: `${label} → ${parsed.status}` } };
        }
      }
      await loadInvoices();
    } catch (e: unknown) {
      actionBanner = {
        ...actionBanner,
        [invoiceId]: { kind: 'err', text: e instanceof Error ? e.message : String(e) },
      };
    } finally {
      actionBusy = { ...actionBusy, [invoiceId]: false };
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
    void loadInvoices();
    let first: number | null = null;
    const unsub = invoicesTick.subscribe((n) => {
      if (first === null) { first = n; return; }
      void loadInvoices();
    });
    return unsub;
  });
</script>

<!-- ── Invoice list ────────────────────────────────────────────────────────── -->
<div class="ie-wrap">
  <div class="ie-header">
    {#if invoicesLoading}
      <span class="ie-loading">⏳ loading invoices…</span>
    {:else if invoicesError}
      <span class="ie-err">{invoicesError}</span>
    {:else if invoices.length === 0}
      <span class="ie-empty">No invoices yet.</span>
    {:else}
      <ul class="ie-list">
        {#each invoices as inv (inv.id)}
          <li class="ie-row">
            <div class="ie-row-top">
              <code class="ie-id">{inv.id.slice(0, 8)}…</code>
              <span class="ie-status ie-status-{inv.status}">{inv.status}</span>
              <span class="ie-amount">{formatCents(inv.amount)}</span>
              {#if inv.amount_paid > 0 && inv.amount_paid < inv.amount}
                <span class="ie-paid">paid {formatCents(inv.amount_paid)}</span>
              {/if}
              <span class="ie-date">{inv.updated_at.slice(0, 10)}</span>
            </div>
            {#if inv.notes}
              <p class="ie-notes">{inv.notes}</p>
            {/if}
            {#if FSM_ACTIONS[inv.status]}
              <div class="ie-actions">
                {#each FSM_ACTIONS[inv.status] as a}
                  <button
                    class="ie-action-btn ie-action-{a.verb.split(' ').at(-1)}"
                    onclick={() => runFsmAction(inv.id, a.verb, a.label, a.confirm)}
                    disabled={actionBusy[inv.id] ?? false}
                  >
                    {a.label}
                  </button>
                {/each}
              </div>
            {/if}
            {#if actionBanner[inv.id]}
              <p class="ie-action-banner ie-action-banner-{actionBanner[inv.id].kind}">
                {actionBanner[inv.id].text}
              </p>
            {/if}
          </li>
        {/each}
      </ul>
    {/if}

    {#if !editorOpen}
      <button class="ie-new-btn" onclick={openEditor}>+ New Invoice</button>
    {/if}
  </div>

  <!-- ── Inline editor ──────────────────────────────────────────────────── -->
  {#if editorOpen}
    <div class="ie-editor">
      <div class="ie-editor-header">
        <span class="ie-editor-title">
          Draft TAX INVOICE
          {#if seededFromQuote}
            <span class="ie-quote-seed">— seeded from accepted quote</span>
          {/if}
        </span>
        <button class="ie-cancel" onclick={cancelEditor}>✕ Cancel</button>
      </div>

      <!-- NL input bar -->
      <div class="ie-nl-row">
        <textarea
          class="ie-nl-input"
          placeholder={`Describe work or materials, e.g. "Service call $90, labour 3h $95, silicone tube $12"`}
          rows="2"
          bind:value={nlInput}
          onkeydown={(e) => { if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) handleParseNl(); }}
        ></textarea>
        <button
          class="ie-nl-btn"
          onclick={handleParseNl}
          disabled={!nlInput.trim()}
          title="Parse into line items (Ctrl+Enter)"
        >Parse</button>
      </div>
      <p class="ie-nl-hint">Separate items with commas or newlines. Ctrl+Enter to parse.</p>

      <!-- Conversation context toggle -->
      <div class="ie-ctx-row">
        <button class="ie-ctx-btn" onclick={toggleContext}>
          {contextOpen ? '▲ Hide context' : '▼ Show conversation context'}
        </button>
      </div>
      {#if contextOpen}
        <div class="ie-ctx-panel">
          {#if contextLoading}
            <p class="ie-ctx-loading">Loading conversation…</p>
          {:else if contextTurns.length === 0}
            <p class="ie-ctx-empty">No conversation turns on record for this job.</p>
          {:else}
            {#each contextTurns as t (t.turnId)}
              <div class="ie-ctx-turn ie-ctx-turn-{t.direction}">
                <span class="ie-ctx-meta">
                  {surfaceLabel(t.surface)} {t.identityValue ?? t.participantRole} · {formatTs(t.timestamp)}
                </span>
                <p class="ie-ctx-body">{t.bodyText}</p>
              </div>
            {/each}
          {/if}
        </div>
      {/if}

      <!-- Line items table -->
      <div class="ie-items-header">
        <span class="ie-items-label">Line items</span>
        <button class="ie-add-item" onclick={addBlankItem}>+ Add row</button>
      </div>

      {#if items.length === 0}
        <p class="ie-items-empty">
          No items yet. Describe the work above or click "Add row".
        </p>
      {:else}
        <div class="ie-items-table">
          <div class="ie-items-thead">
            <span class="ie-col-desc">Description</span>
            <span class="ie-col-qty">Qty</span>
            <span class="ie-col-unit">Unit $</span>
            <span class="ie-col-total">Total</span>
            <span class="ie-col-src">Src</span>
            <span class="ie-col-del"></span>
          </div>
          {#each items as item, idx (idx)}
            <div class="ie-items-row">
              <input
                class="ie-col-desc ie-cell"
                type="text"
                value={item.description}
                placeholder="Description"
                oninput={(e) => updateItem(idx, 'description', (e.target as HTMLInputElement).value)}
              />
              <input
                class="ie-col-qty ie-cell ie-cell-num"
                type="number"
                step="0.5"
                min="0"
                value={item.quantity}
                oninput={(e) => updateItem(idx, 'quantity', (e.target as HTMLInputElement).value)}
              />
              <input
                class="ie-col-unit ie-cell ie-cell-num"
                type="number"
                step="0.01"
                min="0"
                value={(item.unitCents / 100).toFixed(2)}
                oninput={(e) => updateItem(idx, 'unitCents', (e.target as HTMLInputElement).value)}
              />
              <span class="ie-col-total ie-cell-total">{formatCents(lineTotal(item))}</span>
              <span class="ie-col-src ie-cell-src" title={item.source}>{sourceLabel(item.source)}</span>
              <button class="ie-del" onclick={() => removeItem(idx)} title="Remove">✕</button>
            </div>
          {/each}
        </div>
        <div class="ie-total-row">
          <span class="ie-total-label">Total due</span>
          <span class="ie-total-value">{formatCents(totalCents())}</span>
        </div>
      {/if}

      <!-- Payment terms -->
      <label class="ie-field-label" for="ie-pt">Payment terms</label>
      <textarea
        id="ie-pt"
        class="ie-textarea"
        rows="2"
        bind:value={paymentTerms}
        onchange={persistDraft}
      ></textarea>

      <!-- Scope notes -->
      <label class="ie-field-label" for="ie-notes">Notes</label>
      <textarea
        id="ie-notes"
        class="ie-textarea"
        rows="3"
        placeholder="Additional notes, inclusions, exclusions, WO reference…"
        bind:value={notes}
        onchange={persistDraft}
      ></textarea>

      <!-- Save row -->
      <div class="ie-save-row">
        <button
          class="ie-save-btn"
          onclick={saveInvoice}
          disabled={saving || items.length === 0}
        >
          {saving ? 'Saving…' : `Save Invoice (${formatCents(totalCents())})`}
        </button>
        <button class="ie-cancel-sm" onclick={cancelEditor} disabled={saving}>Cancel</button>
      </div>

      {#if saveBanner}
        <p class="ie-save-banner ie-save-banner-{saveBanner.kind}">{saveBanner.text}</p>
      {/if}
    </div>
  {/if}
</div>

<style>
  .ie-wrap {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
    font-family: var(--mono, ui-monospace, monospace);
    font-size: 0.8125rem;
  }

  .ie-header { display: flex; flex-direction: column; gap: 0.5rem; }

  .ie-loading, .ie-empty { color: #4b5563; font-style: italic; font-size: 0.8125rem; }
  .ie-err { color: #f87171; font-size: 0.8125rem; }

  .ie-list { list-style: none; padding: 0; margin: 0; display: flex; flex-direction: column; gap: 0.5rem; }

  .ie-row {
    background: #1a1a1a;
    border: 1px solid #2a2a2a;
    border-radius: 0.375rem;
    padding: 0.5rem 0.625rem;
    display: flex;
    flex-direction: column;
    gap: 0.25rem;
  }

  .ie-row-top { display: flex; align-items: baseline; gap: 0.5rem; flex-wrap: wrap; }

  .ie-id { color: #6b7280; font-size: 0.75rem; }

  .ie-status {
    font-size: 0.6875rem;
    padding: 0.0625rem 0.375rem;
    border-radius: 0.25rem;
    background: #2a2a2a;
    color: #9ca3af;
  }
  .ie-status-draft    { background: rgba(59,130,246,0.15); color: #93c5fd; }
  .ie-status-sent     { background: rgba(245,158,11,0.15); color: #fcd34d; }
  .ie-status-viewed   { background: rgba(167,139,250,0.15); color: #c4b5fd; }
  .ie-status-partial  { background: rgba(245,158,11,0.15); color: #fcd34d; }
  .ie-status-paid     { background: rgba(34,197,94,0.15); color: #86efac; }
  .ie-status-overdue  { background: rgba(239,68,68,0.15); color: #fca5a5; }
  .ie-status-cancelled { background: rgba(107,114,128,0.15); color: #6b7280; }

  .ie-amount { color: #e5e7eb; font-weight: 600; }
  .ie-paid { color: #86efac; font-size: 0.75rem; }
  .ie-date { color: #4b5563; font-size: 0.6875rem; margin-left: auto; }

  .ie-notes {
    color: #6b7280;
    font-size: 0.75rem;
    margin: 0;
    white-space: pre-wrap;
    word-break: break-word;
    border-left: 2px solid #2a2a2a;
    padding-left: 0.5rem;
  }

  .ie-actions { display: flex; gap: 0.375rem; flex-wrap: wrap; margin-top: 0.25rem; }

  .ie-action-btn {
    background: #1e293b;
    border: 1px solid #334155;
    border-radius: 0.25rem;
    color: #93c5fd;
    cursor: pointer;
    font-family: inherit;
    font-size: 0.6875rem;
    padding: 0.1875rem 0.5rem;
  }
  .ie-action-btn:hover:not(:disabled) { background: #263045; border-color: #60a5fa; }
  .ie-action-btn:disabled { opacity: 0.4; cursor: default; }
  .ie-action-btn.ie-action-paid   { background: rgba(34,197,94,0.1); border-color: rgba(34,197,94,0.3); color: #86efac; }
  .ie-action-btn.ie-action-cancel { background: rgba(239,68,68,0.1); border-color: rgba(239,68,68,0.3); color: #fca5a5; }
  .ie-action-btn.ie-action-overdue { background: rgba(239,68,68,0.1); border-color: rgba(239,68,68,0.3); color: #fca5a5; }
  .ie-action-btn.ie-action-partial { background: rgba(245,158,11,0.1); border-color: rgba(245,158,11,0.3); color: #fcd34d; }

  .ie-action-banner { font-size: 0.6875rem; padding: 0.1875rem 0.5rem; border-radius: 0.25rem; margin: 0; }
  .ie-action-banner-ok   { background: rgba(34,197,94,0.1);  color: #86efac; }
  .ie-action-banner-warn { background: rgba(245,158,11,0.1); color: #fcd34d; }
  .ie-action-banner-err  { background: rgba(239,68,68,0.1);  color: #fca5a5; }

  .ie-new-btn {
    align-self: flex-start;
    background: #064e3b;
    border: 1px solid #065f46;
    border-radius: 0.375rem;
    color: #6ee7b7;
    cursor: pointer;
    font-family: inherit;
    font-size: 0.8125rem;
    padding: 0.375rem 0.75rem;
  }
  .ie-new-btn:hover { background: #065f46; }

  /* ── Editor ── */
  .ie-editor {
    background: #0b1e15;
    border: 1px solid #064e3b;
    border-radius: 0.5rem;
    padding: 0.75rem;
    display: flex;
    flex-direction: column;
    gap: 0.625rem;
  }

  .ie-editor-header { display: flex; align-items: center; justify-content: space-between; }

  .ie-editor-title { font-weight: 600; color: #6ee7b7; font-size: 0.875rem; }
  .ie-quote-seed { font-weight: 400; color: #34d399; font-size: 0.75rem; }

  .ie-cancel {
    background: transparent;
    border: 1px solid #064e3b;
    border-radius: 0.25rem;
    color: #4b5563;
    cursor: pointer;
    font: inherit;
    font-size: 0.75rem;
    padding: 0.1875rem 0.5rem;
  }
  .ie-cancel:hover { color: #6b7280; border-color: #065f46; }

  .ie-nl-row { display: flex; gap: 0.5rem; align-items: flex-end; }

  .ie-nl-input {
    flex: 1;
    background: #071a10;
    border: 1px solid #064e3b;
    border-radius: 0.375rem;
    color: #e5e7eb;
    font: inherit;
    font-size: 0.8125rem;
    padding: 0.375rem 0.5rem;
    resize: none;
    line-height: 1.4;
    outline: none;
  }
  .ie-nl-input:focus { border-color: #34d399; }

  .ie-nl-btn {
    background: #065f46;
    border: none;
    border-radius: 0.375rem;
    color: #6ee7b7;
    cursor: pointer;
    font: inherit;
    font-size: 0.8125rem;
    padding: 0.375rem 0.75rem;
    white-space: nowrap;
    align-self: flex-end;
  }
  .ie-nl-btn:hover:not(:disabled) { background: #047857; }
  .ie-nl-btn:disabled { opacity: 0.4; cursor: default; }

  .ie-nl-hint { color: #374151; font-size: 0.6875rem; margin: -0.25rem 0 0; }

  .ie-ctx-row { display: flex; }
  .ie-ctx-btn {
    background: transparent;
    border: 1px solid #064e3b;
    border-radius: 0.25rem;
    color: #4b5563;
    cursor: pointer;
    font: inherit;
    font-size: 0.75rem;
    padding: 0.25rem 0.625rem;
  }
  .ie-ctx-btn:hover { color: #6b7280; border-color: #065f46; }

  .ie-ctx-panel {
    background: #061210;
    border: 1px solid #064e3b;
    border-radius: 0.375rem;
    max-height: 200px;
    overflow-y: auto;
    padding: 0.5rem;
    display: flex;
    flex-direction: column;
    gap: 0.375rem;
  }

  .ie-ctx-loading, .ie-ctx-empty { color: #4b5563; font-style: italic; font-size: 0.75rem; margin: 0; }

  .ie-ctx-turn { display: flex; flex-direction: column; gap: 0.125rem; padding: 0.25rem 0.375rem; border-radius: 0.25rem; }
  .ie-ctx-turn-inbound  { background: rgba(30,41,59,0.4); }
  .ie-ctx-turn-outbound { background: rgba(4,78,46,0.3); }

  .ie-ctx-meta { font-size: 0.625rem; color: #374151; }
  .ie-ctx-body { color: #6b7280; font-size: 0.75rem; margin: 0; white-space: pre-wrap; word-break: break-word; }

  .ie-items-header { display: flex; align-items: center; justify-content: space-between; }

  .ie-items-label {
    font-weight: 600;
    color: #6ee7b7;
    font-size: 0.6875rem;
    text-transform: uppercase;
    letter-spacing: 0.06em;
  }

  .ie-add-item {
    background: transparent;
    border: 1px solid #064e3b;
    border-radius: 0.25rem;
    color: #34d399;
    cursor: pointer;
    font: inherit;
    font-size: 0.75rem;
    padding: 0.1875rem 0.5rem;
  }
  .ie-add-item:hover { background: rgba(52,211,153,0.08); }

  .ie-items-empty { color: #374151; font-style: italic; font-size: 0.75rem; margin: 0; }

  .ie-items-table { display: flex; flex-direction: column; gap: 0.25rem; }

  .ie-items-thead,
  .ie-items-row {
    display: grid;
    grid-template-columns: 1fr 4rem 5rem 4.5rem 1.5rem 1.5rem;
    gap: 0.375rem;
    align-items: center;
  }

  .ie-items-thead { padding: 0 0.25rem; margin-bottom: 0.125rem; }
  .ie-items-thead > * { font-size: 0.625rem; color: #374151; text-transform: uppercase; letter-spacing: 0.08em; }

  .ie-cell {
    background: #071a10;
    border: 1px solid #064e3b;
    border-radius: 0.25rem;
    color: #e5e7eb;
    font: inherit;
    font-size: 0.8125rem;
    padding: 0.25rem 0.375rem;
    outline: none;
    width: 100%;
    box-sizing: border-box;
  }
  .ie-cell:focus { border-color: #34d399; }
  .ie-cell-num { text-align: right; }
  .ie-cell-total { text-align: right; color: #e5e7eb; font-size: 0.8125rem; }
  .ie-cell-src { text-align: center; font-size: 0.875rem; }

  .ie-del { background: transparent; border: none; color: #374151; cursor: pointer; font-size: 0.75rem; padding: 0; line-height: 1; }
  .ie-del:hover { color: #f87171; }

  .ie-total-row {
    display: flex;
    justify-content: flex-end;
    gap: 1rem;
    padding: 0.375rem 0.25rem;
    border-top: 1px solid #064e3b;
  }

  .ie-total-label { color: #4b5563; font-size: 0.8125rem; text-transform: uppercase; letter-spacing: 0.06em; }
  .ie-total-value { color: #6ee7b7; font-weight: 700; font-size: 0.9375rem; }

  .ie-field-label { font-size: 0.6875rem; color: #374151; text-transform: uppercase; letter-spacing: 0.08em; display: block; }

  .ie-textarea {
    background: #071a10;
    border: 1px solid #064e3b;
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
  .ie-textarea:focus { border-color: #34d399; }

  .ie-save-row { display: flex; gap: 0.5rem; align-items: center; padding-top: 0.25rem; }

  .ie-save-btn {
    background: #065f46;
    border: none;
    border-radius: 0.375rem;
    color: #6ee7b7;
    cursor: pointer;
    font: inherit;
    font-size: 0.875rem;
    font-weight: 600;
    padding: 0.5rem 1.25rem;
  }
  .ie-save-btn:hover:not(:disabled) { background: #047857; }
  .ie-save-btn:disabled { opacity: 0.4; cursor: default; }

  .ie-cancel-sm {
    background: transparent;
    border: 1px solid #374151;
    border-radius: 0.375rem;
    color: #4b5563;
    cursor: pointer;
    font: inherit;
    font-size: 0.8125rem;
    padding: 0.375rem 0.75rem;
  }
  .ie-cancel-sm:hover { color: #6b7280; }

  .ie-save-banner { font-size: 0.75rem; padding: 0.375rem 0.5rem; border-radius: 0.25rem; margin: 0; }
  .ie-save-banner-ok   { background: rgba(34,197,94,0.12);  color: #86efac; }
  .ie-save-banner-warn { background: rgba(245,158,11,0.12); color: #fcd34d; }
  .ie-save-banner-err  { background: rgba(239,68,68,0.12);  color: #fca5a5; }
</style>

```
