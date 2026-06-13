---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/views/QuoteDetail.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.070461+00:00
---

# apps/loom-svelte/src/views/QuoteDetail.svelte

```svelte
<script lang="ts" module>
  // D-O4.followup-3 — Quote detail view with FSM action buttons.
  //
  // Mirrors `VisitDetail.svelte`'s shape exactly for the §O4 Quote FSM.
  // Action buttons key off the current status:
  //   draft      → Present (operator) | Supersede (operator)
  //   presented  → Accept (service)   | Decline (service)
  //                                   | Expire (service)
  //                                   | Supersede (operator)
  //   accepted   → (no actions — terminal)
  //   rejected   → (no actions — terminal)
  //   expired    → (no actions — terminal)
  //   superseded → (no actions — terminal)
  //
  // The brain REPL `present quote <id>` / `accept quote <id>` / `decline
  // quote <id>` / `expire quote <id>` / `supersede quote <id>` verbs
  // (runtime/semantos-brain/src/repl.zig) plumb through to the dispatcher's
  // `quotes.transition` cmd, which returns one of three JSON shapes
  // (mirror of jobs.transition / visits.transition):
  //   • Bare Quote   — transition applied
  //   • {status: "already_in_state", quote: {...}}  — idempotent retry
  //   • {error, from, to, cap_required}             — typed FSM rejection

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

  export type QuoteTransitionResult =
    | { kind: "success"; quote: Quote }
    | { kind: "already_in_state"; quote: Quote }
    | { kind: "error"; error: string; from: string; to: string; cap_required: string | null };

  export function parseQuoteTransitionResult(text: string): QuoteTransitionResult {
    const trimmed = text.trim();
    if (trimmed.length === 0 || !trimmed.startsWith("{")) {
      return { kind: "error", error: "parse_error", from: "", to: "", cap_required: null };
    }
    try {
      const parsed = JSON.parse(trimmed);
      if (parsed && typeof parsed === "object") {
        if (parsed.status === "already_in_state" && parsed.quote) {
          return { kind: "already_in_state", quote: quoteFromBody(parsed.quote) };
        }
        if (typeof parsed.error === "string") {
          return {
            kind: "error",
            error: parsed.error,
            from: String(parsed.from ?? ""),
            to: String(parsed.to ?? ""),
            cap_required: typeof parsed.cap_required === "string"
              ? parsed.cap_required
              : null,
          };
        }
        if (parsed.id && parsed.status) {
          return { kind: "success", quote: quoteFromBody(parsed) };
        }
      }
    } catch {
      // fall through to parse_error.
    }
    return { kind: "error", error: "parse_error", from: "", to: "", cap_required: null };
  }

  function quoteFromBody(row: Record<string, unknown>): Quote {
    return {
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
    };
  }

  /// State → operator-readable REPL verb map.  Multiple verbs per
  /// state surface (presented has Accept / Decline / Expire / Supersede).
  /// Empty list means no transitions are offered for that state.
  export type QuoteAction = {
    label: string;
    verb: string;
  };

  export function actionsForStatus(status: string): readonly QuoteAction[] {
    switch (status) {
      case "draft":
        return [
          { label: "Present", verb: "present quote" },
          { label: "Supersede", verb: "supersede quote" },
        ];
      case "presented":
        return [
          { label: "Accept", verb: "accept quote" },
          { label: "Decline", verb: "decline quote" },
          { label: "Expire", verb: "expire quote" },
          { label: "Supersede", verb: "supersede quote" },
        ];
      case "accepted":
      case "rejected":
      case "expired":
      case "superseded":
        return [];
      default:
        return [];
    }
  }

  /// Format a cost amount in cents into a `$X.YY` display string.
  export function formatCents(cents: number): string {
    return `$${(cents / 100).toFixed(2)}`;
  }
</script>

<script lang="ts">
  import { onMount } from "svelte";
  import { ReplClient, ReplUnauthorizedError } from "../lib/repl-client";
  import { clearAuth } from "../lib/auth";
  import { quotesTick } from "../lib/quotes-store";

  let {
    client = new ReplClient(),
    quote: initialQuote,
  }: {
    client?: ReplClient;
    quote: Quote;
  } = $props();

  let quote = $state<Quote>(initialQuote);
  let busy = $state(false);
  let banner = $state<{ kind: "ok" | "warn" | "err"; text: string } | null>(null);
  let unauthenticated = $state(false);

  /// D-O5.followup-4 — re-fetch the displayed quote on a `quote.*`
  /// event tick.  Mirrors JobList.svelte's posture: ignore the very
  /// first emission and re-issue `find quote <id>` on every
  /// subsequent change.  Failures are silently swallowed; the next
  /// manual interaction surfaces persistent errors via runAction.
  async function refetch() {
    try {
      const resp = await client.send(`find quote ${quote.id}`);
      if ("error" in resp) return;
      const trimmed = resp.result.trim();
      if (!trimmed.startsWith("{")) return;
      const parsed = JSON.parse(trimmed);
      if (parsed && typeof parsed === "object" && parsed.id) {
        quote = quoteFromBody(parsed as Record<string, unknown>);
      }
    } catch (e: unknown) {
      if (e instanceof ReplUnauthorizedError) {
        unauthenticated = true;
        clearAuth();
      }
      // Non-fatal otherwise.
    }
  }

  onMount(() => {
    let firstSeen: number | null = null;
    const unsub = quotesTick.subscribe((n) => {
      if (firstSeen === null) {
        firstSeen = n;
        return;
      }
      void refetch();
    });
    return unsub;
  });

  async function runAction(action: QuoteAction) {
    busy = true;
    banner = null;
    try {
      const resp = await client.send(`${action.verb} ${quote.id}`);
      if ("error" in resp) {
        banner = { kind: "err", text: `${action.label} failed: ${resp.error}` };
        return;
      }
      const r = parseQuoteTransitionResult(resp.result);
      if (r.kind === "success") {
        quote = r.quote;
        banner = { kind: "ok", text: `${action.label}: ${quote.status}` };
      } else if (r.kind === "already_in_state") {
        quote = r.quote;
        banner = { kind: "warn", text: `${action.label}: already ${quote.status}` };
      } else {
        const detail = r.error === "wrong_cap" && r.cap_required
          ? `requires ${r.cap_required}`
          : r.error;
        banner = { kind: "err", text: `${action.label} failed: ${detail}` };
      }
    } catch (e: unknown) {
      if (e instanceof ReplUnauthorizedError) {
        unauthenticated = true;
        clearAuth();
        return;
      }
      banner = { kind: "err", text: e instanceof Error ? e.message : String(e) };
    } finally {
      busy = false;
    }
  }

  let actions = $derived(actionsForStatus(quote.status));
</script>

<section class="quote-detail">
  <header>
    <h2>Quote <code>{quote.id}</code></h2>
    <span class="status status-{quote.status}">{quote.status}</span>
  </header>

  {#if unauthenticated}
    <p class="auth-needed">
      Session expired. <a href="/helm/">Sign in</a> to continue.
    </p>
  {:else}
    <dl>
      <dt>Quote ID</dt><dd><code>{quote.id}</code></dd>
      <dt>Job</dt><dd><code>{quote.job_id}</code></dd>
      <dt>Status</dt><dd>{quote.status}</dd>
      <dt>Cost min</dt><dd>{formatCents(quote.cost_min)}</dd>
      <dt>Cost max</dt><dd>{formatCents(quote.cost_max)}</dd>
      {#if quote.accepted_at}
        <dt>Accepted</dt><dd>{quote.accepted_at}</dd>
      {/if}
      {#if quote.rejected_at}
        <dt>Rejected</dt><dd>{quote.rejected_at}</dd>
      {/if}
      {#if quote.notes}
        <dt>Notes</dt><dd>{quote.notes}</dd>
      {/if}
      <dt>Created</dt><dd>{quote.created_at}</dd>
      <dt>Updated</dt><dd>{quote.updated_at}</dd>
    </dl>

    {#if actions.length > 0}
      <div class="actions">
        {#each actions as a (a.verb)}
          <button onclick={() => runAction(a)} disabled={busy}>
            {busy ? "Working…" : a.label}
          </button>
        {/each}
      </div>
    {:else}
      <p class="terminal">Quote is {quote.status}; no further actions.</p>
    {/if}

    {#if banner}
      <p class="banner banner-{banner.kind}">{banner.text}</p>
    {/if}
  {/if}
</section>

<style>
  .quote-detail {
    border: 1px solid #ddd;
    border-radius: 4px;
    padding: 1rem;
    margin: 1rem 0;
  }
  header {
    display: flex;
    justify-content: space-between;
    align-items: baseline;
    gap: 1rem;
  }
  dl {
    display: grid;
    grid-template-columns: max-content 1fr;
    gap: 0.4rem 1rem;
  }
  dt { font-weight: 600; color: #555; }
  dd { margin: 0; }
  .actions {
    display: flex;
    gap: 0.5rem;
    margin-top: 1rem;
    flex-wrap: wrap;
  }
  button {
    padding: 0.5rem 1rem;
    cursor: pointer;
  }
  button[disabled] { cursor: not-allowed; opacity: 0.6; }
  .status {
    font-family: ui-monospace, monospace;
    font-size: 0.85em;
    background: #f3f3f3;
    padding: 0.1em 0.4em;
    border-radius: 3px;
  }
  .terminal { font-style: italic; color: #555; }
  .banner {
    margin-top: 1rem;
    padding: 0.5rem 0.8rem;
    border-radius: 3px;
  }
  .banner-ok   { background: #e8f3e8; color: #244; }
  .banner-warn { background: #fff7e0; color: #644; }
  .banner-err  { background: #fde8e8; color: #a00; }
  .auth-needed { font-style: italic; color: #555; }
</style>

```
