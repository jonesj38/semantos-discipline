---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/routes/customers/[id]/+page.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.089283+00:00
---

# apps/loom-svelte/src/routes/customers/[id]/+page.svelte

```svelte
<script lang="ts">
  // D-DOG.1.0c Phase 3 E.3 — helm customer-pivot route.
  //
  // The first deep-link route on the helm SPA: when the operator
  // clicks the customer-name cell in the JobList row, the browser
  // navigates to `/helm/customers/<customerCellId>` and this view
  // hydrates.  It shows the customer's contact card (name + role +
  // phone + email) and every job they're listed against (regardless
  // of whether they're primary).
  //
  // Wire pattern — two parallel JSON-RPC calls on the same WSS:
  //   1. `oddjobz.get_customer(customerRef)`         → header card
  //   2. `oddjobz.find_jobs_for_customer(customerRef)` → job list
  //
  // The helm SPA is currently vite-only (no SvelteKit router), so
  // wave-2 sibling sub-PRs introduce the `routes/<verb>/[id]/+page.svelte`
  // file convention together — the App.svelte shell will pick this
  // file up via a thin path-matcher in a follow-up.  In the meantime
  // the component is self-contained: it parses the cellId off
  // `window.location.pathname` so deep-links from the JobList anchor
  // load correctly even before the shell-side router lands.
  //
  // Test surface lives in `lib/customer-pivot.ts` — pure projections
  // exercised by `tests/customer-pivot.test.ts`.

  import { onMount } from "svelte";
  import {
    OddjobzQueryClient,
    WssJsonRpcTransport,
    type OddjobzQueryTransport,
  } from "../../../lib/oddjobz-query";
  import {
    parseCustomerIdFromPath,
    projectHeader,
    projectJobs,
    type CustomerPivotHeader,
    type CustomerPivotJobRow,
  } from "../../../lib/customer-pivot";
  import { formatDueDate } from "../../../lib/joblist-graph";

  /// Tests + storybook stubs pass an explicit [queryClient] +
  /// [pathname]; production derives both from `window`.
  let {
    queryClient,
    pathname,
  }: {
    queryClient?: OddjobzQueryClient;
    pathname?: string;
  } = $props();

  let header = $state<CustomerPivotHeader | null>(null);
  let jobs = $state<CustomerPivotJobRow[]>([]);
  let loading = $state(true);
  let error = $state<string | null>(null);
  let notFound = $state(false);
  let unauthenticated = $state(false);

  function resolveQueryClient(): OddjobzQueryClient | null {
    if (queryClient !== undefined) return queryClient;
    if (typeof window === "undefined") return null;
    const bearer =
      typeof localStorage !== "undefined"
        ? (localStorage.getItem("helm.bearer") ?? "")
        : "";
    if (bearer.length === 0) {
      unauthenticated = true;
      return null;
    }
    const proto = window.location.protocol === "https:" ? "wss:" : "ws:";
    const wssUrl = `${proto}//${window.location.host}/api/v1/rpc`;
    const transport: OddjobzQueryTransport = new WssJsonRpcTransport({
      wssUrl,
      bearer,
    });
    return new OddjobzQueryClient(transport);
  }

  function resolvePathname(): string {
    if (pathname !== undefined) return pathname;
    if (typeof window === "undefined") return "";
    return window.location.pathname;
  }

  async function load() {
    loading = true;
    error = null;
    notFound = false;
    const id = parseCustomerIdFromPath(resolvePathname());
    if (id === null) {
      error = "no customer id in URL";
      loading = false;
      return;
    }
    const qc = resolveQueryClient();
    if (qc === null) {
      // Either unauthenticated (handled by the auth-stub branch) or
      // running outside a browser (SSR / test stub without an
      // explicit client).  Bail without rendering an error spike.
      loading = false;
      return;
    }
    try {
      const [customer, jobRows] = await Promise.all([
        qc.getCustomer(id),
        qc.findJobsForCustomer(id),
      ]);
      const projected = projectHeader(customer);
      if (projected === null) {
        notFound = true;
      } else {
        header = projected;
        jobs = projectJobs(jobRows, id);
      }
    } catch (e: unknown) {
      error = e instanceof Error ? e.message : String(e);
    } finally {
      loading = false;
    }
  }

  onMount(() => {
    load();
  });
</script>

<section class="customer-pivot">
  <header>
    <a class="back-link" href="/helm/" title="Back to jobs">← jobs</a>
    <h2>Customer</h2>
    <button onclick={() => load()} disabled={loading}>
      {loading ? "Loading…" : "Refresh"}
    </button>
  </header>

  {#if unauthenticated}
    <p class="auth-needed">
      Session expired. <a href="/helm/">Sign in</a> to load this customer.
    </p>
  {:else if loading}
    <p class="loading">Loading customer…</p>
  {:else if error !== null}
    <p class="error">Failed to load customer: <code>{error}</code></p>
  {:else if notFound || header === null}
    <p class="empty">
      No customer with that id. The pivot route looks up by 64-hex cellId —
      v1 carry-over rows aren't reachable here yet.
    </p>
  {:else}
    <div class="card">
      <div class="card-row">
        <span class="label">name</span>
        <span class="value">{header.displayName}</span>
      </div>
      {#if header.role !== null}
        <div class="card-row">
          <span class="label">role</span>
          <span class="value role-chip">{header.role}</span>
        </div>
      {/if}
      <div class="card-row">
        <span class="label">phone</span>
        {#if header.phone.length > 0}
          <a class="value" href={`tel:${header.phone}`}>{header.phone}</a>
        {:else}
          <span class="value placeholder">—</span>
        {/if}
      </div>
      <div class="card-row">
        <span class="label">email</span>
        {#if header.email.length > 0}
          <a class="value" href={`mailto:${header.email}`}>{header.email}</a>
        {:else}
          <span class="value placeholder">—</span>
        {/if}
      </div>
      {#if header.address.length > 0}
        <div class="card-row">
          <span class="label">address</span>
          <span class="value">{header.address}</span>
        </div>
      {/if}
      <div class="card-row">
        <span class="label">cellId</span>
        <code class="value cell-id">{header.cellId}</code>
      </div>
    </div>

    <h3>Jobs ({jobs.length})</h3>
    {#if jobs.length === 0}
      <p class="empty">
        This customer isn't on any current job. They'll appear here as
        soon as a v2 job links them in <code>customerRefs</code>.
      </p>
    {:else}
      <table>
        <thead>
          <tr>
            <th>id</th>
            <th>WO#</th>
            <th>role</th>
            <th>state</th>
            <th>due</th>
            <th>scheduled</th>
          </tr>
        </thead>
        <tbody>
          {#each jobs as job (job.id)}
            <tr class:legacy={job.cellId === null}>
              <td><code>{job.id}</code></td>
              <td>
                {#if job.workOrderNumber !== null}
                  {job.workOrderNumber}
                {:else}
                  <span class="placeholder">—</span>
                {/if}
              </td>
              <td>
                {#if job.role !== null}
                  <span class="role-chip">{job.role}</span>
                  {#if job.primary}
                    <span class="primary-badge" title="Primary contact">★</span>
                  {/if}
                {:else}
                  <span class="placeholder">—</span>
                {/if}
              </td>
              <td>{job.state}</td>
              <td>{formatDueDate(job.dueDate)}</td>
              <td>{job.scheduled_at}</td>
            </tr>
          {/each}
        </tbody>
      </table>
    {/if}
  {/if}
</section>

<style>
  .customer-pivot {
    background: var(--shell);
    border: 1px solid var(--rule);
    border-radius: 6px;
    padding: 16px;
    margin: 16px 0;
  }

  header {
    display: flex;
    align-items: baseline;
    gap: 12px;
    margin-bottom: 12px;
  }

  header h2 {
    margin: 0;
    flex: 1;
  }

  .back-link {
    color: var(--ink-soft);
    text-decoration: none;
    font-family: var(--mono);
    font-size: 11px;
    letter-spacing: 0.06em;
    text-transform: uppercase;
  }

  .back-link:hover {
    color: var(--ink);
  }

  header button {
    background: none;
    border: 1px solid var(--rule);
    border-radius: 4px;
    padding: 4px 10px;
    color: var(--ink-soft);
    font: inherit;
    font-size: 11px;
    font-family: var(--mono);
    letter-spacing: 0.06em;
    text-transform: uppercase;
    cursor: pointer;
    transition: border-color 0.15s, color 0.15s;
  }

  header button:hover:not([disabled]) {
    border-color: var(--rule-bright);
    color: var(--ink);
  }

  header button[disabled] {
    opacity: 0.4;
    cursor: not-allowed;
  }

  .card {
    border: 1px solid var(--rule);
    border-radius: 4px;
    padding: 12px 14px;
    margin-bottom: 16px;
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .card-row {
    display: grid;
    grid-template-columns: 90px 1fr;
    align-items: baseline;
    gap: 12px;
  }

  .label {
    font-family: var(--mono);
    font-size: 10px;
    color: var(--ink-faint);
    text-transform: uppercase;
    letter-spacing: 0.08em;
  }

  .value {
    color: var(--ink);
  }

  a.value {
    color: var(--ink);
    text-decoration: none;
    border-bottom: 1px dotted var(--rule);
  }

  a.value:hover {
    border-bottom-color: var(--rule-bright, currentColor);
  }

  .cell-id {
    font-family: var(--mono);
    font-size: 11px;
    color: var(--ink-soft);
    word-break: break-all;
  }

  h3 {
    margin: 12px 0 8px;
    font-family: var(--mono);
    font-size: 12px;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--ink-soft);
  }

  table {
    width: 100%;
    border-collapse: collapse;
  }

  th,
  td {
    text-align: left;
    padding: 6px 8px;
    border-bottom: 1px solid var(--rule);
  }

  th {
    font-size: 10px;
    color: var(--ink-faint);
    text-transform: uppercase;
    letter-spacing: 0.06em;
  }

  .role-chip {
    display: inline-block;
    font-family: var(--mono);
    font-size: 10px;
    border: 1px solid var(--rule);
    border-radius: 3px;
    padding: 1px 6px;
    color: var(--ink-soft);
    letter-spacing: 0.04em;
  }

  .primary-badge {
    margin-left: 4px;
    color: var(--accent, var(--ink));
    font-size: 12px;
  }

  .placeholder {
    color: var(--ink-faint);
  }

  .legacy {
    opacity: 0.92;
  }

  .auth-needed,
  .loading,
  .empty {
    font-style: italic;
    color: var(--ink-faint);
    font-size: 12px;
    font-family: var(--mono);
  }

  .error {
    color: var(--linear);
    font-size: 12px;
    font-family: var(--mono);
  }
</style>

```
