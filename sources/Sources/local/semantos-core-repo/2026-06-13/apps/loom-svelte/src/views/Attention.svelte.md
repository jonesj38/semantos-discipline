---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/views/Attention.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.075987+00:00
---

# apps/loom-svelte/src/views/Attention.svelte

```svelte
<script lang="ts">
  // D-O5.followup-3 — Attention feed view.
  //
  // Three operator-action buckets surfaced by the typed `jobs.find_
  // attention` dispatcher resource (runtime/semantos-brain/src/resources/jobs_
  // handler.zig::find_attention): pending_quote (state=lead), pending_
  // schedule (state=quoted), pending_invoice (state=completed).  Jobs
  // in non-action states (scheduled, in_progress, invoiced, paid,
  // closed) are deliberately excluded.  Mirrors `JobList.svelte`'s
  // shape.

  import { onMount } from "svelte";
  import { ReplClient, ReplUnauthorizedError } from "../lib/repl-client";
  import { clearAuth } from "../lib/auth";

  /// Allow tests + storybook stubs to pass an explicit client.
  let { client = new ReplClient() }: { client?: ReplClient } = $props();

  type Job = {
    id: string;
    customer_name: string;
    state: string;
    scheduled_at: string;
  };
  type AttentionFeed = {
    pending_quote: Job[];
    pending_schedule: Job[];
    pending_invoice: Job[];
    total: number;
  };

  let feed = $state<AttentionFeed>({
    pending_quote: [],
    pending_schedule: [],
    pending_invoice: [],
    total: 0,
  });
  let loading = $state(true);
  let error = $state<string | null>(null);
  let unauthenticated = $state(false);

  async function load() {
    loading = true;
    error = null;
    try {
      const resp = await client.send("find attention");
      if ("error" in resp) {
        error = resp.error;
        return;
      }
      feed = parseAttention(resp.result);
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

  /// Parse the REPL's `find attention` output into an AttentionFeed.
  ///
  /// Mirrors `JobList.svelte`'s parseJobs but for an object-shaped
  /// payload:
  ///   1. JSON object if the trimmed result starts with `{` — return
  ///      typed buckets (the dispatcher path);
  ///   2. otherwise the empty feed (`total = 0`).
  export function parseAttention(text: string): AttentionFeed {
    const empty: AttentionFeed = {
      pending_quote: [],
      pending_schedule: [],
      pending_invoice: [],
      total: 0,
    };
    const trimmed = text.trim();
    if (trimmed.length === 0) return empty;
    if (!trimmed.startsWith("{")) return empty;
    try {
      const parsed = JSON.parse(trimmed);
      if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
        const pq = extractJobs(parsed.pending_quote);
        const ps = extractJobs(parsed.pending_schedule);
        const pi = extractJobs(parsed.pending_invoice);
        const totalRaw = parsed.total;
        const total = typeof totalRaw === "number"
          ? totalRaw
          : pq.length + ps.length + pi.length;
        return {
          pending_quote: pq,
          pending_schedule: ps,
          pending_invoice: pi,
          total,
        };
      }
    } catch {
      // fall through
    }
    return empty;
  }

  function extractJobs(raw: unknown): Job[] {
    if (!Array.isArray(raw)) return [];
    return raw.map((j: any): Job => ({
      id: String(j.id ?? ""),
      customer_name: String(j.customer_name ?? j.customer ?? ""),
      state: String(j.state ?? ""),
      scheduled_at: String(j.scheduled_at ?? ""),
    }));
  }

  onMount(() => {
    load();
  });
</script>

<section class="attention">
  <header>
    <h2>Attention ({feed.total})</h2>
    <button onclick={() => load()} disabled={loading}>
      {loading ? "Loading…" : "Refresh"}
    </button>
  </header>

  {#if unauthenticated}
    <p class="auth-needed">
      Session expired. <a href="/helm/">Sign in</a> to reload your attention feed.
    </p>
  {:else if error}
    <p class="error">Failed to load attention feed: <code>{error}</code></p>
  {:else if loading}
    <p class="loading">Loading attention feed…</p>
  {:else if feed.total === 0}
    <p class="empty">
      Nothing needs your attention right now.  The feed surfaces
      jobs in <code>lead</code> / <code>quoted</code> /
      <code>completed</code> states.
    </p>
  {:else}
    {#if feed.pending_quote.length > 0}
      <div class="bucket">
        <h3>Pending Quote ({feed.pending_quote.length})</h3>
        <p class="hint">Send a quote to the customer.</p>
        <table>
          <tbody>
            {#each feed.pending_quote as job (job.id)}
              <tr>
                <td><code>{job.id}</code></td>
                <td>{job.customer_name}</td>
                <td><span class="state state-{job.state}">{job.state}</span></td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
    {/if}
    {#if feed.pending_schedule.length > 0}
      <div class="bucket">
        <h3>Pending Schedule ({feed.pending_schedule.length})</h3>
        <p class="hint">Customer accepted — schedule the visit.</p>
        <table>
          <tbody>
            {#each feed.pending_schedule as job (job.id)}
              <tr>
                <td><code>{job.id}</code></td>
                <td>{job.customer_name}</td>
                <td><span class="state state-{job.state}">{job.state}</span></td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
    {/if}
    {#if feed.pending_invoice.length > 0}
      <div class="bucket">
        <h3>Pending Invoice ({feed.pending_invoice.length})</h3>
        <p class="hint">Work complete — issue the invoice.</p>
        <table>
          <tbody>
            {#each feed.pending_invoice as job (job.id)}
              <tr>
                <td><code>{job.id}</code></td>
                <td>{job.customer_name}</td>
                <td><span class="state state-{job.state}">{job.state}</span></td>
                <td>{job.scheduled_at}</td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
    {/if}
  {/if}
</section>

<style>
  .attention {
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
  .bucket {
    margin-top: 0.75rem;
    padding: 0.5rem 0.75rem;
    border: 1px solid #eee;
    border-radius: 4px;
  }
  .bucket h3 {
    margin: 0 0 0.2rem 0;
    font-size: 1em;
  }
  .hint {
    margin: 0 0 0.4rem 0;
    font-size: 0.8em;
    color: #777;
    font-style: italic;
  }
  table {
    width: 100%;
    border-collapse: collapse;
  }
  td {
    padding: 0.3rem 0.5rem;
    border-bottom: 1px solid #f3f3f3;
  }
  .state {
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
