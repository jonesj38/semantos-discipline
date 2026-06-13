---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/views/InvoiceList.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.074554+00:00
---

# apps/loom-svelte/src/views/InvoiceList.svelte

```svelte
<script lang="ts" module>
  // D-O4.followup-4 — Invoice list view.
  //
  // Mirrors `QuoteList.svelte`'s shape exactly.  Fetches invoices via
  // `find invoices` (optionally filtered by `--job-id <id>`) over the
  // bearer-gated REPL HTTP endpoint and renders the result as a table.
  // Backed by the brain dispatcher's typed `invoices` resource (runtime/
  // brain/src/resources/invoices_handler.zig).  Closes the brain-side
  // cutover of all 4 oddjobz FSMs.

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

  /// Parse the REPL's `find invoices` output into Invoice rows.
  /// JSON-only — invoices have no TSV legacy.  Mirrors `parseQuotes`'s
  /// posture for empty / malformed inputs.
  export function parseInvoices(text: string): Invoice[] {
    const trimmed = text.trim();
    if (trimmed.length === 0) return [];
    if (!(trimmed.startsWith("[") || trimmed.startsWith("{"))) return [];
    try {
      const parsed = JSON.parse(trimmed);
      if (Array.isArray(parsed)) {
        return parsed.map((row): Invoice => ({
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
        }));
      }
    } catch {
      // fall through to empty.
    }
    return [];
  }

  /// Format a cost amount in cents into a `$X.YY` display string.
  export function formatCents(cents: number): string {
    const dollars = cents / 100;
    return `$${dollars.toFixed(2)}`;
  }
</script>

<script lang="ts">
  import { onMount } from "svelte";
  import { ReplClient, ReplUnauthorizedError } from "../lib/repl-client";
  import { clearAuth } from "../lib/auth";
  import { invoicesTick } from "../lib/invoices-store";

  let {
    client = new ReplClient(),
    jobIdFilter,
  }: {
    client?: ReplClient;
    jobIdFilter?: string;
  } = $props();

  let invoices = $state<Invoice[]>([]);
  let loading = $state(true);
  let error = $state<string | null>(null);
  let unauthenticated = $state(false);

  async function load() {
    loading = true;
    error = null;
    try {
      const cmd = jobIdFilter
        ? `find invoices --job-id ${jobIdFilter}`
        : "find invoices";
      const resp = await client.send(cmd);
      if ("error" in resp) {
        error = resp.error;
        return;
      }
      invoices = parseInvoices(resp.result);
    } catch (e: unknown) {
      if (e instanceof ReplUnauthorizedError) {
        unauthenticated = true;
        clearAuth();
        return;
      }
      error = e instanceof Error ? e.message : String(e);
    } finally {
      loading = false;
    }
  }

  onMount(() => {
    load();
    // D-O5.followup-4 — re-fetch on live `invoice.created` /
    // `invoice.transitioned` events.  Mirrors JobList.svelte.
    let firstSeen: number | null = null;
    const unsub = invoicesTick.subscribe((n) => {
      if (firstSeen === null) {
        firstSeen = n;
        return;
      }
      load();
    });
    return unsub;
  });
</script>

<section class="invoice-list">
  <header>
    <h2>Invoices{jobIdFilter ? ` for job ${jobIdFilter}` : ""}</h2>
    <button onclick={() => load()} disabled={loading}>
      {loading ? "Loading…" : "Refresh"}
    </button>
  </header>

  {#if unauthenticated}
    <p class="auth-needed">
      Session expired. <a href="/helm/">Sign in</a> to reload your invoices.
    </p>
  {:else if error}
    <p class="error">Failed to load invoices: <code>{error}</code></p>
  {:else if loading}
    <p class="loading">Loading invoices…</p>
  {:else if invoices.length === 0}
    <p class="empty">
      No invoices drafted. Use <code>add invoice --job &lt;id&gt; [--amount N]</code>
      in the brain REPL to draft one.
    </p>
  {:else}
    <table>
      <thead>
        <tr>
          <th>id</th>
          <th>job</th>
          <th>status</th>
          <th>amount</th>
          <th>paid</th>
          <th>updated</th>
        </tr>
      </thead>
      <tbody>
        {#each invoices as invoice (invoice.id)}
          <tr>
            <td><code>{invoice.id}</code></td>
            <td><code>{invoice.job_id}</code></td>
            <td><span class="status status-{invoice.status}">{invoice.status}</span></td>
            <td>{formatCents(invoice.amount)}</td>
            <td>{formatCents(invoice.amount_paid)}</td>
            <td>{invoice.updated_at}</td>
          </tr>
        {/each}
      </tbody>
    </table>
  {/if}
</section>

<style>
  .invoice-list {
    border: 1px solid #ddd;
    border-radius: 4px;
    padding: 1rem;
    margin: 1rem 0;
  }
  header {
    display: flex;
    justify-content: space-between;
    align-items: baseline;
  }
  table {
    width: 100%;
    border-collapse: collapse;
    margin-top: 0.5rem;
  }
  th, td {
    text-align: left;
    padding: 0.4rem 0.6rem;
    border-bottom: 1px solid #eee;
  }
  th {
    font-size: 0.85em;
    color: #666;
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }
  .status {
    font-family: ui-monospace, monospace;
    font-size: 0.85em;
    background: #f3f3f3;
    padding: 0.1em 0.4em;
    border-radius: 3px;
  }
  .auth-needed, .error, .loading, .empty {
    font-style: italic;
    color: #555;
  }
  .error {
    color: #a00;
  }
</style>

```
