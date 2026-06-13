---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/shell/OddjobzCartridge.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.085587+00:00
---

# apps/loom-svelte/src/shell/OddjobzCartridge.svelte

```svelte
<script lang="ts">
  import JobList from '../views/JobList.svelte';
  import JobDetailV2 from '../views/JobDetailV2.svelte';
  import CustomerList from '../views/CustomerList.svelte';
  import Calendar from '../views/Calendar.svelte';
  import Attention from '../views/Attention.svelte';
  import VisitList from '../views/VisitList.svelte';
  import QuoteList from '../views/QuoteList.svelte';
  import InvoiceList from '../views/InvoiceList.svelte';
  import Transcript from '../views/Transcript.svelte';
  import SiteConfigEditor from '../views/SiteConfigEditor.svelte';
  import SiteDetail from '../views/SiteDetail.svelte';
  import { parseSiteHashRoute } from '../lib/site-pivot';

  type OddjobzTab = 'jobs' | 'calendar' | 'attention' | 'customers' | 'visits' | 'quotes' | 'invoices' | 'transcript' | 'site-config';

  let {
    initialJobId = null,
    // SH2-H / D14 — entry hint from a dispatched verb (e.g. "job", "customer").
    // Mapped to the matching tab so a DO/FIND verb opens the right flow.
    entryEntity = null,
  }: { initialJobId?: string | null; entryEntity?: string | null } = $props();

  let selectedJobId = $state<string | null>(initialJobId);
  let activeTab = $state<OddjobzTab>('jobs');
  let sitePivotRef = $state<string | null>(null);

  // Sync site-pivot hash
  function syncHash() {
    sitePivotRef = parseSiteHashRoute(window.location.hash);
  }
  $effect(() => {
    syncHash();
    window.addEventListener('hashchange', syncHash);
    return () => window.removeEventListener('hashchange', syncHash);
  });

  function selectTab(tab: OddjobzTab) {
    activeTab = tab;
    if (sitePivotRef !== null && typeof window !== 'undefined') {
      const cleanUrl = `${window.location.pathname}${window.location.search}`;
      history.replaceState(null, '', cleanUrl);
      sitePivotRef = null;
    }
  }

  // SH2-H / D14 — map a dispatched verb's entity to this cartridge's tab.
  const ENTITY_TAB: Record<string, OddjobzTab> = {
    job: 'jobs',
    customer: 'customers',
    visit: 'visits',
    quote: 'quotes',
    invoice: 'invoices',
    site: 'site-config',
  };
  $effect(() => {
    if (entryEntity && ENTITY_TAB[entryEntity]) {
      selectTab(ENTITY_TAB[entryEntity]);
    }
  });

  const TABS: { id: OddjobzTab; label: string }[] = [
    { id: 'jobs', label: 'Jobs' },
    { id: 'calendar', label: 'Calendar' },
    { id: 'attention', label: 'Attention' },
    { id: 'customers', label: 'Customers' },
    { id: 'visits', label: 'Visits' },
    { id: 'quotes', label: 'Quotes' },
    { id: 'invoices', label: 'Invoices' },
    { id: 'transcript', label: 'Transcript' },
    { id: 'site-config', label: 'Site Config' },
  ];
</script>

<div class="oddjobz-cartridge">
  <nav class="cartridge-tabs">
    {#each TABS as tab}
      <button
        class:active={activeTab === tab.id && sitePivotRef === null && (tab.id !== 'jobs' || selectedJobId === null)}
        onclick={() => { selectTab(tab.id); if (tab.id === 'jobs') selectedJobId = null; }}
      >{tab.label}</button>
    {/each}
  </nav>
  <div class="cartridge-content">
    {#if sitePivotRef !== null}
      <SiteDetail siteRef={sitePivotRef} />
    {:else if activeTab === 'jobs'}
      {#if selectedJobId !== null}
        <JobDetailV2 jobId={selectedJobId} onBack={() => (selectedJobId = null)} />
      {:else}
        <JobList onSelectJob={(id) => (selectedJobId = id)} />
      {/if}
    {:else if activeTab === 'calendar'}
      <Calendar />
    {:else if activeTab === 'attention'}
      <Attention />
    {:else if activeTab === 'customers'}
      <CustomerList />
    {:else if activeTab === 'visits'}
      <VisitList />
    {:else if activeTab === 'quotes'}
      <QuoteList />
    {:else if activeTab === 'invoices'}
      <InvoiceList />
    {:else if activeTab === 'transcript'}
      <Transcript />
    {:else if activeTab === 'site-config'}
      <SiteConfigEditor />
    {/if}
  </div>
</div>

<style>
  .oddjobz-cartridge {
    display: flex;
    flex-direction: column;
    height: 100%;
  }

  .cartridge-tabs {
    display: flex;
    gap: 0.25rem;
    padding: 0 0.5rem;
    border-bottom: 1px solid #2a2a2a;
    flex-wrap: wrap;
    flex-shrink: 0;
  }

  .cartridge-tabs button {
    background: transparent;
    border: none;
    border-bottom: 2px solid transparent;
    color: #9ca3af;
    cursor: pointer;
    font-size: 0.8125rem;
    font-weight: 500;
    padding: 0.5rem 0.75rem;
    transition: color 0.15s, border-color 0.15s;
    white-space: nowrap;
  }

  .cartridge-tabs button:hover {
    color: #e5e7eb;
  }

  .cartridge-tabs button.active {
    color: #60a5fa;
    border-bottom-color: #60a5fa;
  }

  .cartridge-content {
    flex: 1;
    overflow-y: auto;
    padding: 1rem;
  }
</style>

```
