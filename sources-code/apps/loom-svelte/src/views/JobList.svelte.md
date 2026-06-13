---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/views/JobList.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.073389+00:00
---

# apps/loom-svelte/src/views/JobList.svelte

```svelte
<script lang="ts">
  // D-O5 / D-DOG.1.0c Phase 3 E.1 — JobList view.
  //
  // The MVP first view (D-O5) listed jobs by parsing the REPL's
  // `find jobs` text response, with four flat columns: id / customer /
  // state / scheduled.  D-DOG.1.0c Phase 3 E.1 layers v2 graph fields
  // on top:
  //
  //   - property address (from the linked v2 site cell)
  //   - primary customer + role (from v2 customerRefs.find(primary))
  //   - due date (from v2 dueDate, formatted relative to today)
  //   - has-photos badge (from v2 hasPhotos / photoCount)
  //
  // The REPL `find jobs` path stays the source-of-truth for the row
  // list (it covers BOTH v1 carry-over jobs and v2 graph-aware jobs).
  // The v2 fields come over a separate JSON-RPC channel
  // (lib/oddjobz-query.ts) — one bulk fetch per render: one
  // list_sites + one list_customers + per-site find_jobs_at_site
  // (bounded by site count, not job count).  See lib/joblist-fetch.ts
  // for the N+1 prevention contract and lib/joblist-graph.ts for the
  // pure join.
  //
  // v1 carry-over rows render gracefully — propertyAddress + dueDate
  // → "—", primaryCustomer falls back to the flat `customer_name`
  // string the REPL emits, photos badge is hidden.  The operator's
  // existing 72 first-dogfood v1 cells stay visible.

  import { onMount } from "svelte";
  import { ReplClient, ReplUnauthorizedError } from "../lib/repl-client";
  import { clearAuth } from "../lib/auth";
  import { jobsTick } from "../lib/jobs-store";
  import StageTrail from "../components/StageTrail.svelte";
  import {
    OddjobzQueryClient,
    WssJsonRpcTransport,
    type OddjobzQueryTransport,
  } from "../lib/oddjobz-query";
  import { fetchGraphSnapshot } from "../lib/joblist-fetch";
  import { jobSourceFromProvider } from "../lib/job-source";
  import {
    customerMap,
    enrichJobs,
    formatDueDate,
    formatPrimaryCustomer,
    jobV2Map,
    siteMap,
    type JobListRow,
    type ReplJobRow,
  } from "../lib/joblist-graph";
  // D-DOG.1.0c Phase 3 E.2 — address-cell deep-link target.
  // siteHashRoute('<cellId>') -> '#/sites/<cellId>'; the App.svelte
  // hash router parses that and mounts SiteDetail.  Imported here
  // (not inlined) so the URL shape lives in one place — the future
  // SvelteKit migration only updates that helper.
  import { siteHashRoute } from "../lib/site-pivot";

  /// Allow tests + storybook stubs to pass an explicit client.  When
  /// [queryClient] is supplied, JobList uses it directly; otherwise it
  /// constructs a [WssJsonRpcTransport] against the same-origin brain.
  ///
  /// D-DOG.1.0c Phase 3 E.4 — `onSelectJob` is the row-click escape
  /// hatch.  App.svelte sets a `selectedJobId` from this and swaps in
  /// JobDetailV2.  When the callback isn't supplied (e.g. in unit
  /// tests) the row click is a no-op so the existing parser tests keep
  /// passing.
  let {
    client = new ReplClient(),
    queryClient,
    onSelectJob,
    onSelectSite,
    onSelectCustomer,
  }: {
    client?: ReplClient;
    queryClient?: OddjobzQueryClient;
    onSelectJob?: (jobId: string) => void;
    onSelectSite?: (siteRef: string) => void;
    onSelectCustomer?: (customerRef: string) => void;
  } = $props();

  let rows = $state<JobListRow[]>([]);
  let loading = $state(true);
  let error = $state<string | null>(null);
  let graphError = $state<string | null>(null);
  let unauthenticated = $state(false);

  /// Resolve the typed graph-query client.  Production builds derive a
  /// same-origin WSS URL from `window.location` (matches App.svelte's
  /// helm-event-stream pattern); tests pass [queryClient] explicitly so
  /// no real socket is opened.  Returns null when there's no bearer in
  /// localStorage (the SPA renders the auth-challenge stub instead).
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
    graphError = null;
    try {
      const resp = await client.send("find jobs");
      if ("error" in resp) {
        error = resp.error;
        return;
      }
      const baseRows = parseJobs(resp.result);

      // v2 enrichment — best-effort.  When the brain side hasn't wired
      // the oddjobz query handler (no --enable-repl), we fall through
      // to v1-only rendering with a banner instead of erroring out.
      const qc = resolveQueryClient();
      if (qc === null) {
        rows = enrichJobs(baseRows, new Map(), new Map(), new Map());
      } else {
        const fetched = await fetchGraphSnapshot(qc);
        graphError = fetched.error;
        // The REPL `find jobs` verb isn't wired on the brain yet (it routes
        // through the dispatcher in a follow-up), so when it returns no rows
        // source them from the canonical cell.query v2 jobs instead of showing
        // an empty list. The v2 rows already carry customer_name/state, and
        // enrichJobs joins them to the graph by id.
        const effectiveBase =
          baseRows.length > 0
            ? baseRows
            : fetched.snapshot.v2Jobs.map((j) => ({
                id: j.id,
                customer_name: j.customer_name,
                state: j.state,
                scheduled_at: j.scheduled_at,
              }));
        rows = enrichJobs(
          effectiveBase,
          jobV2Map(fetched.snapshot.v2Jobs),
          siteMap(fetched.snapshot.sites),
          customerMap(fetched.snapshot.customers),
        );
      }
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

  /// Parse the REPL's free-text `find jobs` output into row records.
  ///
  /// Today the REPL has no canonical `find` verb (D-O5.followup-1),
  /// so this falls back to (a) JSON if the result looks like JSON,
  /// (b) a `# id\tcustomer\tstate\tscheduled_at`-style TSV with the
  /// header line skipped, or (c) the empty list.  Surface a clear
  /// "no parser match — raw output" path so the operator sees
  /// something rather than a silent empty grid.
  ///
  /// Output shape is the [ReplJobRow] (v1 carry-over fields only) the
  /// graph-aware joiner consumes; v2 enrichment is layered on
  /// elsewhere.
  export function parseJobs(text: string): ReplJobRow[] {
    const trimmed = text.trim();
    if (trimmed.length === 0) return [];
    if (trimmed.startsWith("[") || trimmed.startsWith("{")) {
      try {
        const parsed = JSON.parse(trimmed);
        if (Array.isArray(parsed)) {
          return parsed.map((row): ReplJobRow => ({
            id: String(row.id ?? ""),
            customer_name: String(row.customer_name ?? row.customer ?? ""),
            state: String(row.state ?? ""),
            scheduled_at: String(row.scheduled_at ?? ""),
          }));
        }
      } catch {
        // fall through
      }
    }
    // TSV / line fallback — REPL's text emit is line-based.
    const lines = trimmed.split("\n").filter((l) => l.length > 0 && !l.startsWith("#"));
    return lines.flatMap((line): ReplJobRow[] => {
      const cols = line.split("\t");
      if (cols.length < 4) return [];
      return [{
        id: cols[0]!,
        customer_name: cols[1]!,
        state: cols[2]!,
        scheduled_at: cols[3]!,
      }];
    });
  }

  onMount(() => {
    load();
    // D-O5.followup-4 — re-fetch on live `job.transitioned` events
    // emitted by the brain's helm event broker (delivered via the
    // WSS subscriber wired in App.svelte → wireJobsTick).  The
    // `jobsTick` store is a monotonic counter; we ignore the value
    // itself, treating each change as a "something changed, refresh
    // now" signal.  Unsubscribe on view teardown.
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
</script>

<section class="job-list">
  <header>
    <h2>Jobs</h2>
    <button onclick={() => load()} disabled={loading}>
      {loading ? "Loading…" : "Refresh"}
    </button>
  </header>

  {#if unauthenticated}
    <p class="auth-needed">
      Session expired. <a href="/helm/">Sign in</a> to reload your jobs.
    </p>
  {:else if error}
    <p class="error">Failed to load jobs: <code>{error}</code></p>
  {:else if loading}
    <p class="loading">Loading jobs…</p>
  {:else if rows.length === 0}
    <p class="empty">
      No jobs yet. The brain REPL's <code>find</code> verb is wired through
      the dispatcher in a follow-up — the helm SPA renders whatever
      <code>find jobs</code> returns.
    </p>
  {:else}
    {#if graphError !== null}
      <p class="graph-warn">
        Graph enrichment unavailable — rendering legacy fields only:
        <code>{graphError}</code>
      </p>
    {/if}
    <table>
      <thead>
        <tr>
          <th>id</th>
          <th>property</th>
          <th>customer</th>
          <th>state</th>
          <th>due</th>
          <th>scheduled</th>
        </tr>
      </thead>
      <tbody>
        {#each rows as row (row.id)}
          {@const customerLabel = formatPrimaryCustomer(row.primaryCustomer)}
          {@const source = jobSourceFromProvider(row.primaryCustomer?.providerId)}
          <!--
            D-DOG.1.0c Phase 3 E.4 — row body click → navigate to the
            job-detail surface.  The address cell + customer cell stop
            propagation so each navigates elsewhere (site / customer
            pivot routes) instead of dragging the operator into the
            job-detail surface they didn't want.  The `onclick` is only
            wired when [onSelectJob] is supplied so unit tests that
            only render the table without a router stay click-inert.
          -->
          <tr
            class:legacy={!row.hasV2}
            class:clickable={onSelectJob !== undefined}
            onclick={() => onSelectJob?.(row.id)}
          >
            <td><code>{row.id}</code></td>
            <td
              class="address-col"
              onclick={(e) => {
                if (row.siteRef !== null && onSelectSite !== undefined) {
                  e.stopPropagation();
                  onSelectSite(row.siteRef);
                }
              }}
            >
              {#if row.propertyAddress !== null}
                <!-- D-DOG.1.0c Phase 3 E.2 — clicking the address
                     cell pivots into the site-detail view (all jobs at
                     this address).  We render an anchor only when
                     `siteRef` is present (every v2 row carries it; v1
                     carry-over rows render the address-less "—"
                     placeholder branch and never reach this code). -->
                {#if row.siteRef !== null}
                  <a
                    class="address site-link"
                    href={siteHashRoute(row.siteRef)}
                    title="See all jobs at this address"
                  >{row.propertyAddress}</a>
                {:else}
                  <span class="address">{row.propertyAddress}</span>
                {/if}
                {#if row.propertyKey !== null}
                  <span class="key-badge" title="Tradesperson access key">
                    {row.propertyKey}
                  </span>
                {/if}
              {:else}
                <span class="placeholder" title="Legacy job — no graph data">—</span>
              {/if}
            </td>
            <td>
              {#if row.primaryCustomer !== null}
                <!-- D-DOG.1.0c Phase 3 E.3 — customer-name cell pivots
                     to the customer-pivot route via anchor + hash router.
                     E.4's row-body click for job-detail uses
                     stopPropagation here so the customer anchor wins. -->
                <a
                  class="customer-link"
                  href={`/helm/customers/${row.primaryCustomer.customerCellId}`}
                  title="Open customer pivot"
                  onclick={(e) => e.stopPropagation()}
                >{customerLabel ?? row.customer_name}</a>
              {:else}
                {customerLabel ?? row.customer_name}
              {/if}
              {#if source !== null}
                <!-- Source pill — provenance of the lead, read off the
                     primary customer's sourceProvenance.providerId
                     (legacy Gmail leads → "email", widget funnel →
                     "widget").  See lib/job-source.ts. -->
                <span
                  class="source-pill source-{source.kind}"
                  title={`Lead source: ${source.label}`}
                >{source.label}</span>
              {/if}
            </td>
            <td class="state-col">
              <StageTrail state={row.state} compact={true} />
              <span class="state-chip {row.state}">{row.state}</span>
              {#if row.legacyUnsigned}
                <!-- D-DOG.1.0c Phase 5 G.2 — pre-Layer-1 v1 cell that
                     `legacy migrate-to-graph` couldn't promote.  The
                     pill flags it as unsigned (per Phase 4 BKDS) so the
                     operator knows it's not a graph cell yet. -->
                <span
                  class="legacy-pill"
                  title="Pre-Layer-1 cell — not yet promoted to a signed graph row"
                >legacy</span>
              {/if}
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
  .job-list {
    background: var(--shell);
    border: 1px solid var(--rule);
    border-radius: 6px;
    padding: 16px;
    margin: 16px 0;
  }

  header {
    display: flex;
    justify-content: space-between;
    align-items: baseline;
    margin-bottom: 12px;
  }

  header h2 {
    margin: 0;
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

  .state-col {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .address-col {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .address {
    color: var(--ink);
  }

  /* D-DOG.1.0c Phase 3 E.2 — address-cell deep-link.  We keep the
     visual identical to the plain `.address` span by default and
     surface a subtle dotted underline on hover so the operator knows
     the cell is interactive without losing the dense table look. */
  a.address.site-link {
    color: inherit;
    text-decoration: none;
    border-bottom: 1px dotted transparent;
    cursor: pointer;
    transition: border-color 0.15s, color 0.15s;
  }

  a.address.site-link:hover,
  a.address.site-link:focus-visible {
    color: var(--ink-bright, var(--ink));
    border-bottom-color: var(--rule-bright, var(--rule));
    outline: none;
  }

  .key-badge {
    font-size: 10px;
    font-family: var(--mono);
    color: var(--ink-soft);
    background: var(--shell-raised, transparent);
    border: 1px solid var(--rule);
    border-radius: 3px;
    padding: 1px 6px;
    letter-spacing: 0.04em;
  }

  .placeholder {
    color: var(--ink-faint);
  }

  .customer-link {
    color: inherit;
    text-decoration: none;
    border-bottom: 1px dotted var(--rule);
    cursor: pointer;
  }

  .customer-link:hover {
    border-bottom-color: var(--rule-bright, currentColor);
    color: var(--ink, currentColor);
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

  /* D-DOG.1.0c Phase 5 G.2 — pre-Layer-1 v1 row marker.  Same visual
     family as the photos-badge but tagged with the warning tone so
     the operator can scan a list and pick out unmigrated rows. */
  .legacy-pill {
    display: inline-flex;
    align-items: center;
    font-size: 10px;
    font-family: var(--mono);
    color: var(--linear, var(--ink-soft));
    background: var(--shell-raised, transparent);
    border: 1px dashed var(--rule);
    border-radius: 3px;
    padding: 1px 5px;
    text-transform: uppercase;
    letter-spacing: 0.06em;
  }

  .photos-count {
    font-weight: 600;
  }

  /* Source pill — lead provenance (email / widget / other).  Same chip
     family as legacy-pill but solid-bordered + tinted per kind so the
     operator can scan intake origin at a glance. */
  .source-pill {
    display: inline-flex;
    align-items: center;
    margin-left: 6px;
    font-size: 10px;
    font-family: var(--mono);
    border: 1px solid var(--rule);
    border-radius: 3px;
    padding: 1px 5px;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: var(--ink-soft);
    background: var(--shell-raised, transparent);
  }
  .source-pill.source-email {
    color: var(--accent, #2563eb);
    border-color: var(--accent, #2563eb);
  }
  .source-pill.source-widget {
    color: var(--ok, #15803d);
    border-color: var(--ok, #15803d);
  }

  .legacy {
    /* Subtle visual cue that this row didn't come with v2 enrichment.
       Kept extremely subtle so the operator's 72 first-dogfood rows
       don't look broken — just a touch faded compared to v2 rows. */
    opacity: 0.92;
  }

  /* D-DOG.1.0c Phase 3 E.4 — row body is the click target for
     navigation to /jobs/<id>.  The address + customer cells nest
     stop-propagation handlers so they navigate elsewhere instead. */
  tr.clickable {
    cursor: pointer;
  }
  tr.clickable:hover {
    background: var(--shell-raised, transparent);
  }
  tr.clickable .address-col,
  tr.clickable td:nth-child(3) {
    cursor: pointer;
  }

  .auth-needed, .loading {
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

  .graph-warn {
    color: var(--ink-soft);
    font-size: 11px;
    font-family: var(--mono);
    background: var(--shell-raised, transparent);
    border: 1px dashed var(--rule);
    border-radius: 4px;
    padding: 6px 10px;
    margin-bottom: 8px;
  }
</style>

```
