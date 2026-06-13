---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/views/Calendar.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.073983+00:00
---

# apps/loom-svelte/src/views/Calendar.svelte

```svelte
<script lang="ts">
  // D-O5.followup-3 — Calendar view.
  //
  // Mirrors `JobList.svelte`'s shape exactly.  Fetches the operator's
  // jobs grouped per-day by sending `find calendar` over the bearer-
  // gated REPL HTTP endpoint and renders the result as one card per
  // day in [from, to] inclusive.  Backed by the brain dispatcher's
  // typed `jobs` resource (runtime/semantos-brain/src/resources/jobs_handler.
  // zig::find_calendar); the JSON-array branch is hot.  Empty input
  // / parse-failure degrades to the empty list — same posture as
  // `parseJobs`.

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
  type CalendarDay = {
    date: string;
    jobs: Job[];
  };

  let days = $state<CalendarDay[]>([]);
  let loading = $state(true);
  let error = $state<string | null>(null);
  let unauthenticated = $state(false);

  async function load() {
    loading = true;
    error = null;
    try {
      const resp = await client.send("find calendar");
      if ("error" in resp) {
        error = resp.error;
        return;
      }
      days = parseCalendar(resp.result);
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

  /// Parse the REPL's `find calendar` output into CalendarDay rows.
  ///
  /// Mirrors `JobList.svelte`'s parseJobs:
  ///   1. JSON array if the trimmed result starts with `[` — return
  ///      typed CalendarDay rows (the dispatcher path);
  ///   2. otherwise the empty list (no TSV fallback exists for the
  ///      calendar shape — pre-followup-3 the verb didn't exist at
  ///      all, so a TSV branch would just hit free-text fallthrough
  ///      from a misconfigured upstream and is safer empty).
  ///
  /// Days with no jobs scheduled return `jobs: []` so the helm can
  /// render a calendar grid without missing-key checks.
  export function parseCalendar(text: string): CalendarDay[] {
    const trimmed = text.trim();
    if (trimmed.length === 0) return [];
    if (!(trimmed.startsWith("[") || trimmed.startsWith("{"))) return [];
    try {
      const parsed = JSON.parse(trimmed);
      if (Array.isArray(parsed)) {
        return parsed.map((row): CalendarDay => ({
          date: String(row.date ?? ""),
          jobs: Array.isArray(row.jobs)
            ? row.jobs.map((j: any): Job => ({
                id: String(j.id ?? ""),
                customer_name: String(j.customer_name ?? j.customer ?? ""),
                state: String(j.state ?? ""),
                scheduled_at: String(j.scheduled_at ?? ""),
              }))
            : [],
        }));
      }
    } catch {
      // fall through to empty
    }
    return [];
  }

  onMount(() => {
    load();
  });
</script>

<section class="calendar">
  <header>
    <h2>Calendar</h2>
    <button onclick={() => load()} disabled={loading}>
      {loading ? "Loading…" : "Refresh"}
    </button>
  </header>

  {#if unauthenticated}
    <p class="auth-needed">
      Session expired. <a href="/helm/">Sign in</a> to reload your calendar.
    </p>
  {:else if error}
    <p class="error">Failed to load calendar: <code>{error}</code></p>
  {:else if loading}
    <p class="loading">Loading calendar…</p>
  {:else if days.length === 0}
    <p class="empty">
      No calendar data. The brain-side default range is the current
      week (Monday → Monday + 7).  Add jobs with <code>add job</code>
      via the REPL to populate.
    </p>
  {:else}
    <div class="days">
      {#each days as day (day.date)}
        <div class="day">
          <div class="date">{day.date}</div>
          {#if day.jobs.length === 0}
            <div class="day-empty">No jobs scheduled.</div>
          {:else}
            <table>
              <tbody>
                {#each day.jobs as job (job.id)}
                  <tr>
                    <td><code>{job.id}</code></td>
                    <td>{job.customer_name}</td>
                    <td><span class="state state-{job.state}">{job.state}</span></td>
                    <td>{job.scheduled_at}</td>
                  </tr>
                {/each}
              </tbody>
            </table>
          {/if}
        </div>
      {/each}
    </div>
  {/if}
</section>

<style>
  .calendar {
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
  .days {
    display: flex;
    flex-direction: column;
    gap: 0.6rem;
    margin-top: 0.6rem;
  }
  .day {
    border: 1px solid #eee;
    border-radius: 4px;
    padding: 0.5rem 0.75rem;
  }
  .date {
    font-weight: 600;
    font-size: 0.9em;
    margin-bottom: 0.25rem;
  }
  .day-empty {
    font-style: italic;
    color: #888;
    font-size: 0.85em;
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
