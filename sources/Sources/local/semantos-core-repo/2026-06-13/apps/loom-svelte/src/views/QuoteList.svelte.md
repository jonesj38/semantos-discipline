---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/views/QuoteList.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.074276+00:00
---

# apps/loom-svelte/src/views/QuoteList.svelte

```svelte
<script lang="ts" module>
  // D-O4.followup-3 — Quote list view.
  //
  // Mirrors `VisitList.svelte`'s shape exactly.  Fetches quotes via
  // `find quotes` (optionally filtered by `--job-id <id>`) over the
  // bearer-gated REPL HTTP endpoint and renders the result as a table.
  // Backed by the brain dispatcher's typed `quotes` resource (runtime/
  // brain/src/resources/quotes_handler.zig).

  export type Quote = {
    id: string;
    job_id: string;
    status: string;
    cost_min: number;
    cost_max: number;
    notes: string;
    accepted_at: string;
    rejected_at: string;
    created_at: string;
    updated_at: string;
  };

  /// Parse the REPL's `find quotes` output into Quote rows.  JSON-only
  /// — quotes have no TSV legacy.  Mirrors `parseVisits`'s posture for
  /// empty / malformed inputs.
  export function parseQuotes(text: string): Quote[] {
    const trimmed = text.trim();
    if (trimmed.length === 0) return [];
    if (!(trimmed.startsWith("[") || trimmed.startsWith("{"))) return [];
    try {
      const parsed = JSON.parse(trimmed);
      if (Array.isArray(parsed)) {
        return parsed.map((row): Quote => ({
          id: String(row.id ?? ""),
          job_id: String(row.job_id ?? ""),
          status: String(row.status ?? ""),
          cost_min: Number(row.cost_min ?? 0),
          cost_max: Number(row.cost_max ?? 0),
          notes: String(row.notes ?? ""),
          accepted_at: String(row.accepted_at ?? ""),
          rejected_at: String(row.rejected_at ?? ""),
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
  import { quotesTick } from "../lib/quotes-store";

  let {
    client = new ReplClient(),
    jobIdFilter,
  }: {
    client?: ReplClient;
    jobIdFilter?: string;
  } = $props();

  let quotes = $state<Quote[]>([]);
  let loading = $state(true);
  let error = $state<string | null>(null);
  let unauthenticated = $state(false);

  async function load() {
    loading = true;
    error = null;
    try {
      const cmd = jobIdFilter
        ? `find quotes --job-id ${jobIdFilter}`
        : "find quotes";
      const resp = await client.send(cmd);
      if ("error" in resp) {
        error = resp.error;
        return;
      }
      quotes = parseQuotes(resp.result);
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
    // D-O5.followup-4 — re-fetch on live `quote.created` /
    // `quote.transitioned` events.  Mirrors JobList.svelte.
    let firstSeen: number | null = null;
    const unsub = quotesTick.subscribe((n) => {
      if (firstSeen === null) {
        firstSeen = n;
        return;
      }
      load();
    });
    return unsub;
  });
</script>

<section class="quote-list">
  <header>
    <h2>Quotes{jobIdFilter ? ` for job ${jobIdFilter}` : ""}</h2>
    <button onclick={() => load()} disabled={loading}>
      {loading ? "Loading…" : "Refresh"}
    </button>
  </header>

  {#if unauthenticated}
    <p class="auth-needed">
      Session expired. <a href="/helm/">Sign in</a> to reload your quotes.
    </p>
  {:else if error}
    <p class="error">Failed to load quotes: <code>{error}</code></p>
  {:else if loading}
    <p class="loading">Loading quotes…</p>
  {:else if quotes.length === 0}
    <p class="empty">
      No quotes drafted. Use <code>add quote --job &lt;id&gt; [--cost-min N] [--cost-max N]</code>
      in the brain REPL to draft one.
    </p>
  {:else}
    <table>
      <thead>
        <tr>
          <th>id</th>
          <th>job</th>
          <th>status</th>
          <th>cost min</th>
          <th>cost max</th>
          <th>updated</th>
        </tr>
      </thead>
      <tbody>
        {#each quotes as quote (quote.id)}
          <tr>
            <td><code>{quote.id}</code></td>
            <td><code>{quote.job_id}</code></td>
            <td><span class="status status-{quote.status}">{quote.status}</span></td>
            <td>{formatCents(quote.cost_min)}</td>
            <td>{formatCents(quote.cost_max)}</td>
            <td>{quote.updated_at}</td>
          </tr>
        {/each}
      </tbody>
    </table>
  {/if}
</section>

<style>
  .quote-list {
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
