---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/views/CustomerList.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.070176+00:00
---

# apps/loom-svelte/src/views/CustomerList.svelte

```svelte
<script lang="ts">
  // D-O5.followup-3 — Customer list view.
  //
  // Mirrors `JobList.svelte`'s shape exactly.  Fetches the operator's
  // customers by sending `find customers` over the bearer-gated REPL
  // HTTP endpoint and renders the result as a simple table.  Backed
  // by the brain dispatcher's typed `customers` resource (runtime/semantos-brain/
  // src/resources/customers_handler.zig); the JSON-array branch is
  // hot.  TSV / fallback-empty branches stay in place for backwards-
  // compat with any operator wiring a different upstream.

  import { onMount } from "svelte";
  import { ReplClient, ReplUnauthorizedError } from "../lib/repl-client";
  import { clearAuth } from "../lib/auth";
  import { customersTick } from "../lib/customers-store";

  /// Allow tests + storybook stubs to pass an explicit client.
  let { client = new ReplClient() }: { client?: ReplClient } = $props();

  type Customer = {
    id: string;
    display_name: string;
    phone: string;
    email: string;
    address: string;
    created_at: string;
  };

  let customers = $state<Customer[]>([]);
  let loading = $state(true);
  let error = $state<string | null>(null);
  let unauthenticated = $state(false);

  async function load() {
    loading = true;
    error = null;
    try {
      const resp = await client.send("find customers");
      if ("error" in resp) {
        error = resp.error;
        return;
      }
      customers = parseCustomers(resp.result);
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

  /// Parse the REPL's `find customers` output into Customer rows.
  ///
  /// Mirrors `JobList.svelte`'s parseJobs exactly:
  ///   1. JSON if the trimmed result starts with `[` or `{` — return
  ///      typed rows (the dispatcher path);
  ///   2. otherwise, tab-separated lines (legacy fallback);
  ///   3. otherwise, the empty list.
  ///
  /// Notes are deliberately omitted from the list payload (only
  /// surfaced via `customers.find_by_id`).
  export function parseCustomers(text: string): Customer[] {
    const trimmed = text.trim();
    if (trimmed.length === 0) return [];
    if (trimmed.startsWith("[") || trimmed.startsWith("{")) {
      try {
        const parsed = JSON.parse(trimmed);
        if (Array.isArray(parsed)) {
          return parsed.map((row): Customer => ({
            id: String(row.id ?? ""),
            display_name: String(row.display_name ?? row.name ?? ""),
            phone: String(row.phone ?? ""),
            email: String(row.email ?? ""),
            address: String(row.address ?? ""),
            created_at: String(row.created_at ?? ""),
          }));
        }
      } catch {
        // fall through
      }
    }
    // TSV / line fallback.
    const lines = trimmed.split("\n").filter((l) => l.length > 0 && !l.startsWith("#"));
    return lines.flatMap((line): Customer[] => {
      const cols = line.split("\t");
      if (cols.length < 2) return [];
      return [{
        id: cols[0]!,
        display_name: cols[1]!,
        phone: cols[2] ?? "",
        email: cols[3] ?? "",
        address: cols[4] ?? "",
        created_at: cols[5] ?? "",
      }];
    });
  }

  onMount(() => {
    load();
    // D-O5.followup-4 — re-fetch on live `customer.created` events
    // emitted by the brain's helm event broker (delivered via the
    // WSS subscriber wired in App.svelte → wireCustomersTick).
    // Mirrors JobList.svelte's posture exactly: ignore the very
    // first emission (the store's initial value) and re-issue
    // `find customers` on every subsequent change.
    let firstSeen: number | null = null;
    const unsub = customersTick.subscribe((n) => {
      if (firstSeen === null) {
        firstSeen = n;
        return;
      }
      load();
    });
    return unsub;
  });
</script>

<section class="customer-list">
  <header>
    <h2>Customers</h2>
    <button onclick={() => load()} disabled={loading}>
      {loading ? "Loading…" : "Refresh"}
    </button>
  </header>

  {#if unauthenticated}
    <p class="auth-needed">
      Session expired. <a href="/helm/">Sign in</a> to reload your customers.
    </p>
  {:else if error}
    <p class="error">Failed to load customers: <code>{error}</code></p>
  {:else if loading}
    <p class="loading">Loading customers…</p>
  {:else if customers.length === 0}
    <p class="empty">
      No customers yet. Use <code>add customer &lt;name&gt;</code> in the brain REPL
      to create your first customer record, or wait for the helm-side
      "Add customer" affordance shipping in a follow-up.
    </p>
  {:else}
    <table>
      <thead>
        <tr>
          <th>id</th>
          <th>name</th>
          <th>phone</th>
          <th>email</th>
          <th>address</th>
        </tr>
      </thead>
      <tbody>
        {#each customers as customer (customer.id)}
          <tr>
            <td><code>{customer.id}</code></td>
            <td>{customer.display_name}</td>
            <td>{customer.phone}</td>
            <td>{customer.email}</td>
            <td>{customer.address}</td>
          </tr>
        {/each}
      </tbody>
    </table>
  {/if}
</section>

<style>
  .customer-list {
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
  .auth-needed, .error, .loading, .empty {
    font-style: italic;
    color: #555;
  }
  .error {
    color: #a00;
  }
</style>

```
