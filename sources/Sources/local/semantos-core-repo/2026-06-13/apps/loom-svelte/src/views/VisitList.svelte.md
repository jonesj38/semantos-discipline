---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/views/VisitList.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.072732+00:00
---

# apps/loom-svelte/src/views/VisitList.svelte

```svelte
<script lang="ts" module>
  // D-O4.followup-2 — Visit list view.
  //
  // Mirrors `CustomerList.svelte`'s shape exactly.  Fetches visits via
  // `find visits` (optionally filtered by `--job-id <id>`) over the
  // bearer-gated REPL HTTP endpoint and renders the result as a table.
  // Backed by the brain dispatcher's typed `visits` resource (runtime/
  // brain/src/resources/visits_handler.zig).

  export type Visit = {
    id: string;
    job_id: string;
    visit_type: string;
    status: string;
    notes: string;
    actual_start: string;
    outcome: string;
    created_at: string;
    updated_at: string;
  };

  /// Parse the REPL's `find visits` output into Visit rows.  JSON-only
  /// — visits have no TSV legacy.  Mirrors `parseCustomers`'s posture
  /// for empty / malformed inputs.
  export function parseVisits(text: string): Visit[] {
    const trimmed = text.trim();
    if (trimmed.length === 0) return [];
    if (!(trimmed.startsWith("[") || trimmed.startsWith("{"))) return [];
    try {
      const parsed = JSON.parse(trimmed);
      if (Array.isArray(parsed)) {
        return parsed.map((row): Visit => ({
          id: String(row.id ?? ""),
          job_id: String(row.job_id ?? ""),
          visit_type: String(row.visit_type ?? ""),
          status: String(row.status ?? ""),
          notes: String(row.notes ?? ""),
          actual_start: String(row.actual_start ?? ""),
          outcome: String(row.outcome ?? ""),
          created_at: String(row.created_at ?? ""),
          updated_at: String(row.updated_at ?? ""),
        }));
      }
    } catch {
      // fall through to empty.
    }
    return [];
  }
</script>

<script lang="ts">
  import { onMount } from "svelte";
  import { ReplClient, ReplUnauthorizedError } from "../lib/repl-client";
  import { clearAuth } from "../lib/auth";
  import { visitsTick } from "../lib/visits-store";

  let {
    client = new ReplClient(),
    jobIdFilter,
  }: {
    client?: ReplClient;
    jobIdFilter?: string;
  } = $props();

  let visits = $state<Visit[]>([]);
  let loading = $state(true);
  let error = $state<string | null>(null);
  let unauthenticated = $state(false);

  async function load() {
    loading = true;
    error = null;
    try {
      const cmd = jobIdFilter
        ? `find visits --job-id ${jobIdFilter}`
        : "find visits";
      const resp = await client.send(cmd);
      if ("error" in resp) {
        error = resp.error;
        return;
      }
      visits = parseVisits(resp.result);
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
    // D-O5.followup-4 — re-fetch on live `visit.created` /
    // `visit.transitioned` events.  Mirrors JobList.svelte.
    let firstSeen: number | null = null;
    const unsub = visitsTick.subscribe((n) => {
      if (firstSeen === null) {
        firstSeen = n;
        return;
      }
      load();
    });
    return unsub;
  });
</script>

<section class="visit-list">
  <header>
    <h2>Visits{jobIdFilter ? ` for job ${jobIdFilter}` : ""}</h2>
    <button onclick={() => load()} disabled={loading}>
      {loading ? "Loading…" : "Refresh"}
    </button>
  </header>

  {#if unauthenticated}
    <p class="auth-needed">
      Session expired. <a href="/helm/">Sign in</a> to reload your visits.
    </p>
  {:else if error}
    <p class="error">Failed to load visits: <code>{error}</code></p>
  {:else if loading}
    <p class="loading">Loading visits…</p>
  {:else if visits.length === 0}
    <p class="empty">
      No visits scheduled. Use <code>add visit --job &lt;id&gt; --type &lt;type&gt;</code>
      in the brain REPL to schedule one.
    </p>
  {:else}
    <table>
      <thead>
        <tr>
          <th>id</th>
          <th>job</th>
          <th>type</th>
          <th>status</th>
          <th>started</th>
          <th>outcome</th>
        </tr>
      </thead>
      <tbody>
        {#each visits as visit (visit.id)}
          <tr>
            <td><code>{visit.id}</code></td>
            <td><code>{visit.job_id}</code></td>
            <td>{visit.visit_type}</td>
            <td><span class="status status-{visit.status}">{visit.status}</span></td>
            <td>{visit.actual_start || "—"}</td>
            <td>{visit.outcome || "—"}</td>
          </tr>
        {/each}
      </tbody>
    </table>
  {/if}
</section>

<style>
  .visit-list {
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
