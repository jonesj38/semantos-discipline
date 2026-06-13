---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/views/JobDetailV2.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.073076+00:00
---

# apps/loom-svelte/src/views/JobDetailV2.svelte

```svelte
<script lang="ts">
  // D-DOG.1.0c Phase 3 E.4 — helm SPA job-detail view (graph-aware).
  //
  // Reference: docs/prd/D-DOG-1.0c-LAYER-1-PROMOTION-MATRIX.md §4 Phase 3
  //   E.4 — render the v2 job's full work-order surface plus linked site
  //   (one link), linked customers (primary + secondaries, each linked)
  //   and the attachments list.
  //
  // The conceptual route is `/jobs/<id>`; this SPA isn't SvelteKit so the
  // view is mounted inline by App.svelte when an operator clicks a row in
  // JobList.  Same posture as the existing tab views — App.svelte holds
  // the selectedJobId state and swaps between JobList and JobDetailV2.
  //
  // IO contract:
  //   1. oddjobz.get_job(jobRef) → full v2 row
  //   2. parallel: list_sites + list_customers (so we can resolve siteRef
  //      and customerRefs into names; same maps the JobList view fetches)
  //   3. oddjobz.find_attachments_for_job(jobRef) → attachment list
  //
  // PDF inline rendering is deferred — each attachment renders as
  //   "Attachment: <sourceBlobKey> (<mimeType>, N pages, M photos)"
  // The deferred `legacy attachment <id>` verb is the surface that will
  // expand a row into the rendered PDF.
  //
  // Falls back gracefully:
  //   - jobRef points at a v1 carry-over (no cellId) → render header + a
  //     "this job has no graph data yet" banner; v2 panels stay empty
  //   - listSites/listCustomers fail → render the job + attachments,
  //     surface a graph-warn banner above the linked-customers section
  //   - find_attachments_for_job returns empty → render "No attachments"

  import { onMount } from "svelte";
  import { jobsTick } from "../lib/jobs-store";
  import { attachmentsTick } from "../lib/attachments-store";
  import {
    OddjobzQueryClient,
    OddjobzQueryError,
    WssJsonRpcTransport,
    type OddjobzAttachmentRow,
    type OddjobzCustomerRow,
    type OddjobzQueryTransport,
    type OddjobzSiteRow,
  } from "../lib/oddjobz-query";
  import { getActiveSession } from "../lib/hat-sessions";
  import {
    customerMap,
    siteMap,
  } from "../lib/joblist-graph";
  import {
    buildJobDetailView,
    formatAttachmentSummary,
    sortAttachments,
    type JobDetailView,
  } from "../lib/job-detail-graph";
  import ConversationThread from "./ConversationThread.svelte";
  import QuoteEditorInline from "./QuoteEditorInline.svelte";
  import InvoiceEditorInline from "./InvoiceEditorInline.svelte";

  let {
    jobId,
    queryClient,
    onBack,
    onNavigateSite,
    onNavigateCustomer,
  }: {
    jobId: string;
    queryClient?: OddjobzQueryClient;
    onBack?: () => void;
    onNavigateSite?: (siteRef: string) => void;
    onNavigateCustomer?: (customerRef: string) => void;
  } = $props();

  let view = $state<JobDetailView | null>(null);
  let attachments = $state<OddjobzAttachmentRow[]>([]);
  let loading = $state(true);
  let error = $state<string | null>(null);
  let graphWarn = $state<string | null>(null);
  let attachError = $state<string | null>(null);

  /// Same resolver shape as JobList — production builds derive a
  /// same-origin WSS URL from `window.location`; tests pass
  /// [queryClient] explicitly so no real socket is opened.  Returns null
  /// when there's no bearer in localStorage so the view renders an
  /// auth-prompt fallback rather than a hung loading spinner.
  function resolveQueryClient(): OddjobzQueryClient | null {
    if (queryClient !== undefined) return queryClient;
    if (typeof window === "undefined") return null;
    // Prefer the active hat session bearer (post-migration path); fall
    // back to legacy helm.bearer in localStorage (pre-migration window).
    const session = getActiveSession();
    const bearer =
      session?.bearer ??
      (typeof localStorage !== "undefined"
        ? (localStorage.getItem("helm.bearer") ?? "")
        : "");
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
    graphWarn = null;
    attachError = null;
    const qc = resolveQueryClient();
    if (qc === null) {
      error = "no-bearer";
      loading = false;
      return;
    }
    try {
      // Three calls in parallel — get_job + the two list views needed
      // to resolve siteRef + customerRefs into names; attachments fan
      // out separately so a slow attachments read doesn't block the
      // header.
      let sites: OddjobzSiteRow[] = [];
      let customers: OddjobzCustomerRow[] = [];
      const [job, sitesResult, customersResult, attResult] =
        await Promise.all([
          qc.getJob(jobId),
          qc.listSites().catch((e) => {
            graphWarn = e instanceof Error ? e.message : String(e);
            return [] as OddjobzSiteRow[];
          }),
          qc.listCustomers().catch((e) => {
            if (graphWarn === null) {
              graphWarn = e instanceof Error ? e.message : String(e);
            }
            return [] as OddjobzCustomerRow[];
          }),
          qc.findAttachmentsForJob(jobId).catch((e) => {
            attachError = e instanceof Error ? e.message : String(e);
            return [] as OddjobzAttachmentRow[];
          }),
        ]);
      sites = sitesResult;
      customers = customersResult;
      if (job === null) {
        error = "not_found";
        view = null;
        attachments = [];
        return;
      }
      view = buildJobDetailView(job, siteMap(sites), customerMap(customers));
      attachments = sortAttachments(attResult);
    } catch (e: unknown) {
      if (e instanceof OddjobzQueryError) {
        error = `${e.code}: ${e.message}`;
      } else {
        error = e instanceof Error ? e.message : String(e);
      }
    } finally {
      loading = false;
    }
  }

  onMount(() => {
    load();
    // Re-fetch on live tick events.  Same posture as JobList — ignore
    // the first emission (the store's initial value) and treat every
    // subsequent change as a "something changed, refresh now" signal.
    let firstJobs: number | null = null;
    let firstAtts: number | null = null;
    const u1 = jobsTick.subscribe((n) => {
      if (firstJobs === null) {
        firstJobs = n;
        return;
      }
      load();
    });
    const u2 = attachmentsTick.subscribe((n) => {
      if (firstAtts === null) {
        firstAtts = n;
        return;
      }
      load();
    });
    return () => {
      u1();
      u2();
    };
  });

  function handleSiteClick(siteRef: string, e: MouseEvent) {
    e.stopPropagation();
    onNavigateSite?.(siteRef);
  }

  function handleCustomerClick(customerRef: string, e: MouseEvent) {
    e.stopPropagation();
    onNavigateCustomer?.(customerRef);
  }
</script>

<section class="job-detail-v2">
  <header>
    <button class="back" onclick={() => onBack?.()} type="button">← Back</button>
    <h2>Job <code>{jobId}</code></h2>
  </header>

  {#if loading}
    <p class="loading">Loading job…</p>
  {:else if error === "no-bearer"}
    <p class="auth-needed">
      Session expired. <a href="/helm/">Sign in</a> to view this job.
    </p>
  {:else if error === "not_found"}
    <p class="error">
      Job <code>{jobId}</code> not found. It may have been deleted, or
      this helm doesn't have access to its tenant.
    </p>
  {:else if error !== null}
    <p class="error">Failed to load job: <code>{error}</code></p>
  {:else if view !== null}
    {#if !view.hasV2}
      <p class="legacy-warn">
        This job is a v1 carry-over — graph-aware fields (work order,
        billing party, linked customers) aren't available.  The
        attachments list still renders any v1 visit-side photos linked
        through the visit graph.
      </p>
    {/if}

    <dl class="job-fields">
      <dt>Customer</dt>
      <dd>{view.customer_name || "—"}</dd>
      <dt>State</dt>
      <dd><span class="state-chip {view.state}">{view.state}</span></dd>
      <dt>Scheduled</dt>
      <dd>{view.scheduled_at || "—"}</dd>
      <dt>Created</dt>
      <dd>{view.created_at || "—"}</dd>

      {#if view.hasV2}
        <dt>Work order</dt>
        <dd>{view.workOrderNumber ?? "—"}</dd>
        <dt>Issued</dt>
        <dd>{view.issuanceDate ?? "—"}</dd>
        <dt>Due</dt>
        <dd>{view.dueDate ?? "—"}</dd>
        <dt>Property key</dt>
        <dd>{view.propertyKey ?? "—"}</dd>
        <dt>Billing party</dt>
        <dd>
          {#if view.billingParty}
            {view.billingParty.name} <span class="muted">({view.billingParty.type})</span>
          {:else}
            —
          {/if}
        </dd>
        <dt>Photos</dt>
        <dd>
          {#if view.hasPhotos}
            <span class="photos-badge">
              <span aria-hidden="true">📷</span>
              {#if view.photoCount !== null && view.photoCount > 0}
                <span class="photos-count">{view.photoCount}</span>
              {/if}
            </span>
          {:else}
            —
          {/if}
        </dd>
      {/if}
    </dl>

    {#if graphWarn !== null}
      <p class="graph-warn">
        Graph enrichment partially failed: <code>{graphWarn}</code>
      </p>
    {/if}

    <h3>Site</h3>
    {@const siteRef = view.siteRef}
    {#if siteRef !== null}
      <p class="link-row">
        <a
          href={"/sites/" + siteRef}
          onclick={(e) => handleSiteClick(siteRef, e)}
        >
          {view.siteAddress ?? siteRef}
        </a>
        {#if view.siteAddress === null}
          <span class="muted">— not in current snapshot</span>
        {/if}
      </p>
    {:else}
      <p class="empty">No linked site (v1 carry-over).</p>
    {/if}

    <h3>Customers</h3>
    {#if view.customers.length === 0}
      <p class="empty">No linked customers (v1 carry-over).</p>
    {:else}
      <ul class="customers">
        {#each view.customers as link (link.cellId)}
          <li class:primary={link.primary}>
            <a
              href={"/customers/" + link.cellId}
              onclick={(e) => handleCustomerClick(link.cellId, e)}
            >
              {link.displayName ?? link.cellId}
            </a>
            <span class="role">{link.role}</span>
            {#if link.primary}
              <span class="primary-badge" title="Primary customer">primary</span>
            {/if}
          </li>
        {/each}
      </ul>
    {/if}

    <h3>Attachments</h3>
    {#if attachError !== null}
      <p class="error">
        Failed to load attachments: <code>{attachError}</code>
      </p>
    {:else if attachments.length === 0}
      <p class="empty">No attachments.</p>
    {:else}
      <ul class="attachments">
        {#each attachments as att (att.id)}
          <li>
            <span class="att-summary">{formatAttachmentSummary(att)}</span>
            {#if att.caption.length > 0}
              <span class="att-caption">— {att.caption}</span>
            {/if}
          </li>
        {/each}
      </ul>
      <p class="att-footnote">
        PDF inline rendering is deferred to the <code>legacy attachment</code>
        verb.
      </p>
    {/if}

    <!-- Quote editor — list existing quotes + draft new ones.
         Line items are persisted locally; the brain stores FSM state
         + cost range + human-readable notes summary. -->
    <h3>Quotes</h3>
    <QuoteEditorInline {jobId} />

    <!-- Invoice editor — list existing invoices + draft new ones.
         Pre-populated from accepted quote draft in localStorage.
         WO jobs that skip quoting can create invoices directly. -->
    <h3>Invoices</h3>
    <InvoiceEditorInline {jobId} />

    <!-- Conversation thread — all turns for this job's entityRef.
         Shows emails, SMS, voice notes, widget chat, and typed notes.
         Operator can add notes directly from this view. -->
    <h3>Conversation</h3>
    <ConversationThread {jobId} />
  {/if}
</section>

<style>
  .job-detail-v2 {
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
    font-size: 14px;
  }

  header h2 code {
    color: var(--ink-soft);
  }

  .back {
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
  }

  .back:hover {
    border-color: var(--rule-bright);
    color: var(--ink);
  }

  dl.job-fields {
    display: grid;
    grid-template-columns: max-content 1fr;
    gap: 4px 16px;
    margin: 0 0 12px;
    font-size: 12px;
    font-family: var(--mono);
  }

  dl.job-fields dt {
    color: var(--ink-faint);
    text-transform: uppercase;
    font-size: 10px;
    letter-spacing: 0.08em;
    align-self: center;
  }

  dl.job-fields dd {
    margin: 0;
    color: var(--ink);
  }

  h3 {
    margin-top: 20px;
    margin-bottom: 6px;
    font-size: 10px;
    font-weight: 600;
    color: var(--ink-faint);
    font-family: var(--mono);
    text-transform: uppercase;
    letter-spacing: 0.1em;
  }

  .empty,
  .loading,
  .auth-needed {
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

  .graph-warn,
  .legacy-warn {
    color: var(--ink-soft);
    font-size: 11px;
    font-family: var(--mono);
    background: var(--shell-raised, transparent);
    border: 1px dashed var(--rule);
    border-radius: 4px;
    padding: 6px 10px;
    margin-bottom: 8px;
  }

  .link-row {
    margin: 4px 0;
    font-size: 12px;
    font-family: var(--mono);
  }

  .link-row a,
  ul.customers a {
    color: var(--activation, var(--ink));
    text-decoration: underline;
  }

  ul.customers,
  ul.attachments {
    list-style: none;
    padding: 0;
    margin: 0;
  }

  ul.customers li,
  ul.attachments li {
    padding: 6px 0;
    border-bottom: 1px solid var(--rule);
    font-family: var(--mono);
    font-size: 12px;
    color: var(--ink-soft);
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    align-items: baseline;
  }

  ul.customers li:last-child,
  ul.attachments li:last-child {
    border-bottom: none;
  }

  ul.customers li.primary {
    background: var(--shell-raised, transparent);
  }

  .role {
    font-size: 10px;
    color: var(--ink-faint);
    text-transform: uppercase;
    letter-spacing: 0.06em;
  }

  .primary-badge {
    font-size: 10px;
    color: var(--activation, var(--ink-soft));
    border: 1px solid var(--rule);
    border-radius: 3px;
    padding: 1px 5px;
    text-transform: uppercase;
    letter-spacing: 0.06em;
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

  .muted {
    color: var(--ink-faint);
  }

  .att-caption {
    color: var(--ink-faint);
  }

  .att-footnote {
    font-size: 10px;
    color: var(--ink-faint);
    font-family: var(--mono);
    margin: 6px 0 0;
  }
</style>

```
