---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/views/SiteDetail.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.075417+00:00
---

# apps/loom-svelte/src/views/SiteDetail.svelte

```svelte
<script lang="ts">
  // D-DOG.1.0c Phase 3 E.2 — site-pivot view.
  //
  // Reference: docs/prd/D-DOG-1.0c-LAYER-1-PROMOTION-MATRIX.md §4 Phase 3
  //   E.2 — "all jobs at this address".  Reached from JobList by
  //   clicking the address cell, which sets `window.location.hash` to
  //   `#/sites/<cellId>`.  App.svelte parses the hash and mounts this
  //   view with [siteRef] as a prop.
  //
  // IO surface: two same-bearer JSON-RPC calls over the existing WSS
  // transport (lib/oddjobz-query.ts):
  //
  //   - `oddjobz.get_site(siteRef)`              → header
  //   - `oddjobz.find_jobs_at_site(siteRef)`     → row list
  //   - `oddjobz.list_customers()`               → customer-name resolution
  //
  // Pure joining + formatting lives in lib/site-pivot.ts so the parser
  // / renderer invariants are tested under `node --test` without
  // instantiating a Svelte component.

  import { onMount } from "svelte";
  import StageTrail from "../components/StageTrail.svelte";
  import {
    OddjobzQueryClient,
    WssJsonRpcTransport,
    type OddjobzCustomerRow,
    type OddjobzJobRow,
    type OddjobzQueryTransport,
    type OddjobzSiteRow,
  } from "../lib/oddjobz-query";
  import { customerMap } from "../lib/joblist-graph";
  import {
    buildSiteAddressHeader,
    buildSiteJobRows,
    formatDueDate,
    formatPrimaryCustomer,
    type SiteAddressHeader,
    type SiteJobRow,
  } from "../lib/site-pivot";
  import { jobsTick } from "../lib/jobs-store";

  // ── Props ──────────────────────────────────────────────────────────
  //
  // [siteRef] is the 64-hex cellID parsed from the hash router.
  // [queryClient] mirrors JobList's seam: tests + storybook stubs pass
  // an explicit client, production constructs a one-shot WSS transport
  // against the same-origin brain.
  let {
    siteRef,
    queryClient,
  }: {
    siteRef: string;
    queryClient?: OddjobzQueryClient;
  } = $props();

  // ── Component state ────────────────────────────────────────────────

  let header = $state<SiteAddressHeader | null>(null);
  let rows = $state<SiteJobRow[]>([]);
  let loading = $state(true);
  let error = $state<string | null>(null);
  /// True when `oddjobz.get_site` returned null — the operator deep-
  /// linked to a site that doesn't (any longer?) exist.  Distinct from
  /// `error` so we can render a non-error empty-state.
  let notFound = $state(false);

  // ── Query-client resolution ────────────────────────────────────────

  /// Mirrors JobList.svelte::resolveQueryClient — production derives
  /// the same-origin WSS URL from `window.location` and reads the
  /// active hat's bearer out of localStorage.  When no bearer is
  /// present we render an "auth needed" state instead of trying to
  /// open an unauthenticated socket.
  function resolveQueryClient(): OddjobzQueryClient | null {
    if (queryClient !== undefined) return queryClient;
    if (typeof window === "undefined") return null;
    const bearer =
      typeof localStorage !== "undefined"
        ? (localStorage.getItem("helm.bearer") ?? "")
        : "";
    if (bearer.length === 0) return null;
    const proto = window.location.protocol === "https:" ? "wss:" : "ws:";
    const wssUrl = `${proto}//${window.location.host}/api/v1/rpc`;
    const transport: OddjobzQueryTransport = new WssJsonRpcTransport({
      wssUrl,
      bearer,
    });
    return new OddjobzQueryClient(transport);
  }

  async function load() {
    loading = true;
    error = null;
    notFound = false;
    header = null;
    rows = [];
    const qc = resolveQueryClient();
    if (qc === null) {
      // No bearer — App.svelte will render the auth stub on its next
      // mount.  Render a minimal placeholder rather than tearing down.
      loading = false;
      error = "Sign in to load this site.";
      return;
    }
    try {
      // Three calls in parallel: header + jobs + customers.  None of
      // them depend on each other's results.
      const [siteRow, jobs, customers] = await Promise.all([
        qc.getSite(siteRef),
        qc.findJobsAtSite(siteRef),
        qc.listCustomers(),
      ]);
      if (siteRow === null) {
        notFound = true;
        return;
      }
      header = buildSiteAddressHeader(siteRow);
      rows = buildSiteJobRows(
        jobs as readonly OddjobzJobRow[],
        customerMap(customers as readonly OddjobzCustomerRow[]),
      );
    } catch (e: unknown) {
      error = e instanceof Error ? e.message : String(e);
    } finally {
      loading = false;
    }
  }

  onMount(() => {
    load();
    // Mirror JobList: re-fetch on live `job.transitioned` ticks so the
    // operator's view stays in sync without a manual refresh.  The
    // ticks fire for any job in the tenant; we re-run our scoped fetch
    // (cheap — three calls, all bounded by site count).
    let firstSeen: number | null = null;
    const unsub = jobsTick.subscribe((n) => {
      if (firstSeen === null) {
        firstSeen = n;
        return;
      }
      load();
    });
    return unsub;
  });

  // ── Navigation back to JobList ─────────────────────────────────────
  //
  // SvelteKit-shaped fallback: if the user got here by typing the URL
  // directly, the back link sends them to `#/jobs` (which App.svelte
  // resolves to the Jobs tab).  Plain `<a>` rather than a button so
  // ctrl-click etc. work.
</script>

<section class="site-detail">
  <header class="page-header">
    <a class="back-link" href="#/jobs">← All jobs</a>
    {#if loading && header === null}
      <h2 class="loading">Loading site…</h2>
    {:else if notFound}
      <h2>Site not found</h2>
      <p class="empty">
        No site cell with that id exists for this hat. The link may be
        stale, or you may need to switch to the hat that owns it.
      </p>
    {:else if header !== null}
      <h2 class="address">
        {header.fullAddress}
        {#if header.keyChip !== null}
          <span class="key-chip" title="Tradesperson access key">
            {header.keyChip}
          </span>
        {/if}
      </h2>
      {#if header.localityLine.length > 0}
        <p class="locality">{header.localityLine}</p>
      {/if}
    {/if}
    <button class="refresh" onclick={() => load()} disabled={loading}>
      {loading ? "Loading…" : "Refresh"}
    </button>
  </header>

  {#if error !== null && !notFound}
    <p class="error">Failed to load site: <code>{error}</code></p>
  {:else if !loading && !notFound && rows.length === 0}
    <p class="empty">
      No jobs at this address yet. Once the brain registers a v2 job
      with this site as its <code>siteRef</code>, it'll appear here.
    </p>
  {:else if rows.length > 0}
    <table>
      <thead>
        <tr>
          <th>id</th>
          <th>customer</th>
          <th>state</th>
          <th>due</th>
          <th>scheduled</th>
        </tr>
      </thead>
      <tbody>
        {#each rows as row (row.id)}
          {@const customerLabel = formatPrimaryCustomer(row.primaryCustomer)}
          <tr class:legacy={!row.hasV2}>
            <td><code>{row.id}</code></td>
            <td>{customerLabel ?? row.customer_name}</td>
            <td class="state-col">
              <StageTrail state={row.state} compact={true} />
              <span class="state-chip {row.state}">{row.state}</span>
              {#if row.hasPhotos}
                <span
                  class="photos-badge"
                  title={row.photoCount !== null && row.photoCount > 0
                    ? `${row.photoCount} photo${row.photoCount === 1 ? "" : "s"} in source`
                    : "Source has photos"}
                >
                  <span aria-hidden="true">📷</span>
                  {#if row.photoCount !== null && row.photoCount > 0}
                    <span class="photos-count">{row.photoCount}</span>
                  {/if}
                </span>
              {/if}
            </td>
            <td>{formatDueDate(row.dueDate)}</td>
            <td>{row.scheduled_at}</td>
          </tr>
        {/each}
      </tbody>
    </table>
  {/if}
</section>

<style>
  .site-detail {
    background: var(--shell);
    border: 1px solid var(--rule);
    border-radius: 6px;
    padding: 16px;
    margin: 16px 0;
  }

  .page-header {
    display: grid;
    grid-template-columns: 1fr auto;
    grid-template-areas:
      "back     refresh"
      "address  refresh"
      "locality refresh";
    align-items: center;
    gap: 4px 12px;
    margin-bottom: 16px;
  }

  .back-link {
    grid-area: back;
    color: var(--ink-soft);
    font-family: var(--mono);
    font-size: 11px;
    text-decoration: none;
    text-transform: uppercase;
    letter-spacing: 0.06em;
  }

  .back-link:hover {
    color: var(--ink);
  }

  .page-header h2 {
    grid-area: address;
    margin: 0;
    display: flex;
    align-items: center;
    gap: 10px;
  }

  .page-header .loading {
    color: var(--ink-faint);
    font-style: italic;
  }

  .key-chip {
    font-size: 11px;
    font-family: var(--mono);
    color: var(--ink-soft);
    background: var(--shell-raised, transparent);
    border: 1px solid var(--rule);
    border-radius: 3px;
    padding: 2px 7px;
    letter-spacing: 0.04em;
    font-weight: normal;
  }

  .locality {
    grid-area: locality;
    margin: 0;
    color: var(--ink-soft);
    font-size: 13px;
  }

  .refresh {
    grid-area: refresh;
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
    transition:
      border-color 0.15s,
      color 0.15s;
  }

  .refresh:hover:not([disabled]) {
    border-color: var(--rule-bright);
    color: var(--ink);
  }

  .refresh[disabled] {
    opacity: 0.4;
    cursor: not-allowed;
  }

  .state-col {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .photos-badge {
    display: inline-flex;
    align-items: center;
    gap: 2px;
    font-size: 11px;
    font-family: var(--mono);
    color: var(--ink-soft);
    background: var(--shell-raised, transparent);
    border: 1px solid var(--rule);
    border-radius: 3px;
    padding: 1px 5px;
  }

  .photos-count {
    font-weight: 600;
  }

  .legacy {
    opacity: 0.92;
  }

  .empty,
  .error {
    color: var(--ink-faint);
    font-size: 12px;
    font-family: var(--mono);
    font-style: italic;
  }

  .error {
    color: var(--linear);
  }
</style>

```
