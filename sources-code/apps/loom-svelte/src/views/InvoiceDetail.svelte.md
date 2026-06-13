---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/views/InvoiceDetail.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.073693+00:00
---

# apps/loom-svelte/src/views/InvoiceDetail.svelte

```svelte
<script lang="ts" module>
  // D-O4.followup-4 — Invoice detail view with FSM action buttons.
  //
  // Mirrors `QuoteDetail.svelte`'s shape exactly for the §O4 Invoice
  // FSM.  Action buttons key off the current status:
  //   draft      → Send (operator)        | Cancel (operator)
  //   sent       → Mark Paid (service)    | Mark Viewed (service)
  //                                       | Mark Overdue (service)
  //                                       | Cancel (operator)
  //   viewed     → Mark Paid (service)    | Mark Overdue (service)
  //                                       | Cancel (operator)
  //   partial    → Mark Paid (service)    | Mark Overdue (service)
  //   overdue    → Mark Paid (service)    | Mark Partial (service)
  //   paid       → (no actions — terminal)
  //   cancelled  → (no actions — terminal)
  //
  // The brain REPL `send invoice <id>` / `mark invoice paid <id>` /
  // `mark invoice partial <id>` / `mark invoice viewed <id>` /
  // `mark invoice overdue <id>` / `cancel invoice <id>` verbs (runtime/
  // brain/src/repl.zig) plumb through to the dispatcher's
  // `invoices.transition` cmd, which returns one of three JSON shapes
  // (mirror of jobs.transition / visits.transition / quotes.transition):
  //   • Bare Invoice — transition applied
  //   • {status: "already_in_state", invoice: {...}}  — idempotent retry
  //   • {error, from, to, cap_required}                — typed FSM rejection
  //
  // Closes the brain-side cutover of all 4 oddjobz FSMs.

  export type Invoice = {
    id: string;
    job_id: string;
    status: string;
    amount: number;
    amount_paid: number;
    external_invoice_id: string;
    notes: string;
    sent_at: string;
    viewed_at: string;
    paid_at: string;
    created_at: string;
    updated_at: string;
  };

  export type InvoiceTransitionResult =
    | { kind: "success"; invoice: Invoice }
    | { kind: "already_in_state"; invoice: Invoice }
    | { kind: "error"; error: string; from: string; to: string; cap_required: string | null };

  export function parseInvoiceTransitionResult(text: string): InvoiceTransitionResult {
    const trimmed = text.trim();
    if (trimmed.length === 0 || !trimmed.startsWith("{")) {
      return { kind: "error", error: "parse_error", from: "", to: "", cap_required: null };
    }
    try {
      const parsed = JSON.parse(trimmed);
      if (parsed && typeof parsed === "object") {
        if (parsed.status === "already_in_state" && parsed.invoice) {
          return { kind: "already_in_state", invoice: invoiceFromBody(parsed.invoice) };
        }
        if (typeof parsed.error === "string") {
          return {
            kind: "error",
            error: parsed.error,
            from: String(parsed.from ?? ""),
            to: String(parsed.to ?? ""),
            cap_required: typeof parsed.cap_required === "string"
              ? parsed.cap_required
              : null,
          };
        }
        if (parsed.id && parsed.status) {
          return { kind: "success", invoice: invoiceFromBody(parsed) };
        }
      }
    } catch {
      // fall through to parse_error.
    }
    return { kind: "error", error: "parse_error", from: "", to: "", cap_required: null };
  }

  function invoiceFromBody(row: Record<string, unknown>): Invoice {
    return {
      id: String(row.id ?? ""),
      job_id: String(row.job_id ?? ""),
      status: String(row.status ?? ""),
      amount: Number(row.amount ?? 0),
      amount_paid: Number(row.amount_paid ?? 0),
      external_invoice_id: String(row.external_invoice_id ?? ""),
      notes: String(row.notes ?? ""),
      sent_at: String(row.sent_at ?? ""),
      viewed_at: String(row.viewed_at ?? ""),
      paid_at: String(row.paid_at ?? ""),
      created_at: String(row.created_at ?? ""),
      updated_at: String(row.updated_at ?? ""),
    };
  }

  /// State → operator-readable REPL verb map.
  /// Empty list means no transitions are offered for that state.
  export type InvoiceAction = {
    label: string;
    verb: string;
  };

  export function actionsForStatus(status: string): readonly InvoiceAction[] {
    switch (status) {
      case "draft":
        return [
          { label: "Send", verb: "send invoice" },
          { label: "Cancel", verb: "cancel invoice" },
        ];
      case "sent":
        return [
          { label: "Mark Paid", verb: "mark invoice paid" },
          { label: "Mark Viewed", verb: "mark invoice viewed" },
          { label: "Mark Overdue", verb: "mark invoice overdue" },
          { label: "Cancel", verb: "cancel invoice" },
        ];
      case "viewed":
        return [
          { label: "Mark Paid", verb: "mark invoice paid" },
          { label: "Mark Overdue", verb: "mark invoice overdue" },
          { label: "Cancel", verb: "cancel invoice" },
        ];
      case "partial":
        return [
          { label: "Mark Paid", verb: "mark invoice paid" },
          { label: "Mark Overdue", verb: "mark invoice overdue" },
        ];
      case "overdue":
        return [
          { label: "Mark Paid", verb: "mark invoice paid" },
        ];
      case "paid":
      case "cancelled":
        return [];
      default:
        return [];
    }
  }

  /// Format a cost amount in cents into a `$X.YY` display string.
  export function formatCents(cents: number): string {
    return `$${(cents / 100).toFixed(2)}`;
  }
</script>

<script lang="ts">
  import { onMount } from "svelte";
  import { ReplClient, ReplUnauthorizedError } from "../lib/repl-client";
  import { clearAuth } from "../lib/auth";
  import { invoicesTick } from "../lib/invoices-store";

  let {
    client = new ReplClient(),
    invoice: initialInvoice,
  }: {
    client?: ReplClient;
    invoice: Invoice;
  } = $props();

  let invoice = $state<Invoice>(initialInvoice);
  let busy = $state(false);
  let banner = $state<{ kind: "ok" | "warn" | "err"; text: string } | null>(null);
  let unauthenticated = $state(false);

  /// D-O5.followup-4 — re-fetch the displayed invoice on an
  /// `invoice.*` event tick.  Mirrors QuoteDetail.svelte.
  async function refetch() {
    try {
      const resp = await client.send(`find invoice ${invoice.id}`);
      if ("error" in resp) return;
      const trimmed = resp.result.trim();
      if (!trimmed.startsWith("{")) return;
      const parsed = JSON.parse(trimmed);
      if (parsed && typeof parsed === "object" && parsed.id) {
        invoice = invoiceFromBody(parsed as Record<string, unknown>);
      }
    } catch (e: unknown) {
      if (e instanceof ReplUnauthorizedError) {
        unauthenticated = true;
        clearAuth();
      }
      // Non-fatal otherwise.
    }
  }

  onMount(() => {
    let firstSeen: number | null = null;
    const unsub = invoicesTick.subscribe((n) => {
      if (firstSeen === null) {
        firstSeen = n;
        return;
      }
      void refetch();
    });
    return unsub;
  });

  async function runAction(action: InvoiceAction) {
    busy = true;
    banner = null;
    try {
      const resp = await client.send(`${action.verb} ${invoice.id}`);
      if ("error" in resp) {
        banner = { kind: "err", text: `${action.label} failed: ${resp.error}` };
        return;
      }
      const r = parseInvoiceTransitionResult(resp.result);
      if (r.kind === "success") {
        invoice = r.invoice;
        banner = { kind: "ok", text: `${action.label}: ${invoice.status}` };
      } else if (r.kind === "already_in_state") {
        invoice = r.invoice;
        banner = { kind: "warn", text: `${action.label}: already ${invoice.status}` };
      } else {
        const detail = r.error === "wrong_cap" && r.cap_required
          ? `requires ${r.cap_required}`
          : r.error;
        banner = { kind: "err", text: `${action.label} failed: ${detail}` };
      }
    } catch (e: unknown) {
      if (e instanceof ReplUnauthorizedError) {
        unauthenticated = true;
        clearAuth();
        return;
      }
      banner = { kind: "err", text: e instanceof Error ? e.message : String(e) };
    } finally {
      busy = false;
    }
  }

  let actions = $derived(actionsForStatus(invoice.status));
</script>

<section class="invoice-detail">
  <header>
    <h2>Invoice <code>{invoice.id}</code></h2>
    <span class="status status-{invoice.status}">{invoice.status}</span>
  </header>

  {#if unauthenticated}
    <p class="auth-needed">
      Session expired. <a href="/helm/">Sign in</a> to continue.
    </p>
  {:else}
    <dl>
      <dt>Invoice ID</dt><dd><code>{invoice.id}</code></dd>
      <dt>Job</dt><dd><code>{invoice.job_id}</code></dd>
      <dt>Status</dt><dd>{invoice.status}</dd>
      <dt>Amount</dt><dd>{formatCents(invoice.amount)}</dd>
      {#if invoice.amount_paid > 0}
        <dt>Amount paid</dt><dd>{formatCents(invoice.amount_paid)}</dd>
      {/if}
      {#if invoice.external_invoice_id}
        <dt>External ID</dt><dd>{invoice.external_invoice_id}</dd>
      {/if}
      {#if invoice.sent_at}
        <dt>Sent</dt><dd>{invoice.sent_at}</dd>
      {/if}
      {#if invoice.viewed_at}
        <dt>Viewed</dt><dd>{invoice.viewed_at}</dd>
      {/if}
      {#if invoice.paid_at}
        <dt>Paid</dt><dd>{invoice.paid_at}</dd>
      {/if}
      {#if invoice.notes}
        <dt>Notes</dt><dd>{invoice.notes}</dd>
      {/if}
      <dt>Created</dt><dd>{invoice.created_at}</dd>
      <dt>Updated</dt><dd>{invoice.updated_at}</dd>
    </dl>

    {#if actions.length > 0}
      <div class="actions">
        {#each actions as a (a.verb)}
          <button onclick={() => runAction(a)} disabled={busy}>
            {busy ? "Working…" : a.label}
          </button>
        {/each}
      </div>
    {:else}
      <p class="terminal">Invoice is {invoice.status}; no further actions.</p>
    {/if}

    {#if banner}
      <p class="banner banner-{banner.kind}">{banner.text}</p>
    {/if}
  {/if}
</section>

<style>
  .invoice-detail {
    border: 1px solid #ddd;
    border-radius: 4px;
    padding: 1rem;
    margin: 1rem 0;
  }
  header {
    display: flex;
    justify-content: space-between;
    align-items: baseline;
    gap: 1rem;
  }
  dl {
    display: grid;
    grid-template-columns: max-content 1fr;
    gap: 0.4rem 1rem;
  }
  dt { font-weight: 600; color: #555; }
  dd { margin: 0; }
  .actions {
    display: flex;
    gap: 0.5rem;
    margin-top: 1rem;
    flex-wrap: wrap;
  }
  button {
    padding: 0.5rem 1rem;
    cursor: pointer;
  }
  button[disabled] { cursor: not-allowed; opacity: 0.6; }
  .status {
    font-family: ui-monospace, monospace;
    font-size: 0.85em;
    background: #f3f3f3;
    padding: 0.1em 0.4em;
    border-radius: 3px;
  }
  .terminal { font-style: italic; color: #555; }
  .banner {
    margin-top: 1rem;
    padding: 0.5rem 0.8rem;
    border-radius: 3px;
  }
  .banner-ok   { background: #e8f3e8; color: #244; }
  .banner-warn { background: #fff7e0; color: #644; }
  .banner-err  { background: #fde8e8; color: #a00; }
  .auth-needed { font-style: italic; color: #555; }
</style>

```
