---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/views/JobDetail.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.075122+00:00
---

# apps/loom-svelte/src/views/JobDetail.svelte

```svelte
<script lang="ts" module>
  // D-O5 followup-1 — Job detail view with FSM action buttons.
  //
  // The desktop helm's pre-followup-1 surface stopped at JobList; this
  // PR ships the FSM cutover so an operator can drive a job through
  // the canonical §O4 transitions without leaving the helm.
  //
  // Action buttons key off the current state (mirrors the mobile
  // helm's job_detail_screen.dart — same FSM table, same operator-
  // readable verbs):
  //   lead          → Quote
  //   quoted        → Schedule
  //   scheduled     → Start
  //   in_progress   → Complete
  //   completed     → Invoice
  //   invoiced      → Mark Paid
  //   paid          → Close
  //   closed        → (no actions)
  //
  // The brain REPL `quote job <id>` / `schedule job <id>` / etc. verbs
  // (runtime/semantos-brain/src/repl.zig) plumb through to the dispatcher's
  // `jobs.transition` command, which returns one of three JSON shapes:
  //   • Bare Job     — transition applied
  //   • {status: "already_in_state", job: {...}}  — idempotent retry
  //   • {error, from, to, cap_required}           — typed FSM rejection
  //
  // `parseJobTransitionResult` (exported from this module so the test
  // suite can pin the bytes) decodes all three.

  export type Job = {
    id: string;
    customer_name: string;
    state: string;
    scheduled_at: string;
    created_at?: string;
  };

  /// Result discriminator the helm view consumes.  Mirror of the
  /// mobile helm's `JobTransitionResult` shape.
  export type JobTransitionResult =
    | { kind: "success"; job: Job }
    | { kind: "already_in_state"; job: Job }
    | { kind: "error"; error: string; from: string; to: string; cap_required: string | null };

  export function parseJobTransitionResult(text: string): JobTransitionResult {
    const trimmed = text.trim();
    if (trimmed.length === 0 || !trimmed.startsWith("{")) {
      return { kind: "error", error: "parse_error", from: "", to: "", cap_required: null };
    }
    try {
      const parsed = JSON.parse(trimmed);
      if (parsed && typeof parsed === "object") {
        if (parsed.status === "already_in_state" && parsed.job) {
          return { kind: "already_in_state", job: jobFromBody(parsed.job) };
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
        if (parsed.id && parsed.state) {
          return { kind: "success", job: jobFromBody(parsed) };
        }
      }
    } catch {
      // Fall through to parse_error.
    }
    return { kind: "error", error: "parse_error", from: "", to: "", cap_required: null };
  }

  function jobFromBody(row: Record<string, unknown>): Job {
    return {
      id: String(row.id ?? ""),
      customer_name: String(row.customer_name ?? row.customer ?? ""),
      state: String(row.state ?? ""),
      scheduled_at: String(row.scheduled_at ?? ""),
      created_at: row.created_at ? String(row.created_at) : undefined,
    };
  }

  /// State → operator-readable REPL verb map.  The brain REPL parser
  /// knows these verbatim (runtime/semantos-brain/src/repl.zig::handleLine).
  /// `null` means no transition is offered for that state.
  export type StateAction = {
    label: string;
    verb: string;
  };

  export function actionForState(state: string): StateAction | null {
    switch (state) {
      case "lead":        return { label: "Quote",     verb: "quote job" };
      case "quoted":      return { label: "Schedule",  verb: "schedule job" };
      case "scheduled":   return { label: "Start",     verb: "start job" };
      case "in_progress": return { label: "Complete",  verb: "complete job" };
      case "completed":   return { label: "Invoice",   verb: "invoice job" };
      case "invoiced":    return { label: "Mark Paid", verb: "mark job paid" };
      case "paid":        return { label: "Close",     verb: "close job" };
      case "closed":      return null;
      default:            return null;
    }
  }
</script>

<script lang="ts">
  import { onMount } from "svelte";
  import {
    ReplClient,
    ReplUnauthorizedError,
    ReplValidationError,
    ReplStateMovedOnError,
    ReplFkError,
  } from "../lib/repl-client";
  import { clearAuth } from "../lib/auth";
  import StageTrail from "../components/StageTrail.svelte";
  import { parseVisits, type Visit } from "./VisitList.svelte";
  import { parseQuotes, formatCents, type Quote } from "./QuoteList.svelte";
  import {
    parseInvoices,
    formatCents as formatInvoiceCents,
    type Invoice,
  } from "./InvoiceList.svelte";

  let {
    client = new ReplClient(),
    job: initialJob,
  }: {
    client?: ReplClient;
    job: Job;
  } = $props();

  let job = $state<Job>(initialJob);
  let busy = $state(false);
  let banner = $state<{ kind: "ok" | "warn" | "err"; text: string } | null>(null);
  let unauthenticated = $state(false);

  // D-O5m.followup-5 K1 conflict UI — inline conflict banner state.
  // When a transition produces a typed conflict (state_moved_on /
  // not_found / etc.) we render a structured banner with retry +
  // dismiss actions instead of the bare red error banner.
  let conflict = $state<
    | {
        kind: "state_moved_on";
        wireKind: string;
        message: string;
        brainState: string | null;
        fromState: string | null;
        toState: string | null;
        action: StateAction;
      }
    | {
        kind: "fk_error";
        wireKind: string;
        message: string;
        entity: string;
        id: string | null;
        action: StateAction;
      }
    | { kind: "validation"; wireKind: string; message: string; action: StateAction }
    | null
  >(null);

  function dismissConflict() {
    conflict = null;
  }

  async function retryConflict() {
    if (!conflict) return;
    const action = conflict.action;
    conflict = null;
    await runAction(action);
  }

  // D-O4.followup-2 — visits-for-this-job slice.  Loaded on mount via
  // `find visits --job-id <id>` so the operator sees the visit chain
  // alongside the job FSM action button.
  let visits = $state<Visit[]>([]);
  let visitsLoading = $state(false);
  let visitsError = $state<string | null>(null);

  // D-O4.followup-3 — quotes-for-this-job slice.  Same shape as the
  // visits slice above; loaded on mount via `find quotes --job-id <id>`.
  let quotes = $state<Quote[]>([]);
  let quotesLoading = $state(false);
  let quotesError = $state<string | null>(null);

  // D-O4.followup-4 — invoices-for-this-job slice.  Same shape as the
  // quotes slice above; loaded on mount via `find invoices --job-id <id>`.
  // Closes the brain-side cutover of all 4 oddjobz FSMs.
  let invoices = $state<Invoice[]>([]);
  let invoicesLoading = $state(false);
  let invoicesError = $state<string | null>(null);

  async function loadVisits() {
    visitsLoading = true;
    visitsError = null;
    try {
      const resp = await client.send(`find visits --job-id ${job.id}`);
      if ("error" in resp) {
        visitsError = resp.error;
        return;
      }
      visits = parseVisits(resp.result);
    } catch (e: unknown) {
      if (e instanceof ReplUnauthorizedError) {
        unauthenticated = true;
        clearAuth();
        return;
      }
      visitsError = e instanceof Error ? e.message : String(e);
    } finally {
      visitsLoading = false;
    }
  }

  async function loadQuotes() {
    quotesLoading = true;
    quotesError = null;
    try {
      const resp = await client.send(`find quotes --job-id ${job.id}`);
      if ("error" in resp) {
        quotesError = resp.error;
        return;
      }
      quotes = parseQuotes(resp.result);
    } catch (e: unknown) {
      if (e instanceof ReplUnauthorizedError) {
        unauthenticated = true;
        clearAuth();
        return;
      }
      quotesError = e instanceof Error ? e.message : String(e);
    } finally {
      quotesLoading = false;
    }
  }

  async function loadInvoices() {
    invoicesLoading = true;
    invoicesError = null;
    try {
      const resp = await client.send(`find invoices --job-id ${job.id}`);
      if ("error" in resp) {
        invoicesError = resp.error;
        return;
      }
      invoices = parseInvoices(resp.result);
    } catch (e: unknown) {
      if (e instanceof ReplUnauthorizedError) {
        unauthenticated = true;
        clearAuth();
        return;
      }
      invoicesError = e instanceof Error ? e.message : String(e);
    } finally {
      invoicesLoading = false;
    }
  }

  onMount(() => {
    loadVisits();
    loadQuotes();
    loadInvoices();
  });

  async function runAction(action: StateAction) {
    busy = true;
    banner = null;
    conflict = null;
    try {
      const resp = await client.send(`${action.verb} ${job.id}`);
      if ("error" in resp) {
        banner = { kind: "err", text: `${action.label} failed: ${resp.error}` };
        return;
      }
      const r = parseJobTransitionResult(resp.result);
      if (r.kind === "success") {
        job = r.job;
        banner = { kind: "ok", text: `${action.label}: ${job.state}` };
      } else if (r.kind === "already_in_state") {
        job = r.job;
        banner = { kind: "warn", text: `${action.label}: already ${job.state}` };
      } else {
        // D-O5m.followup-5 — promote typed FSM rejections to the
        // typed conflict banner.  Falls back to the generic err
        // banner for parse_error / unknown shapes.
        const stateMovedKinds = new Set([
          "state_moved_on",
          "not_reachable",
          "wrong_principal",
          "wrong_cap",
        ]);
        const fkKinds = new Set(["not_found", "visit_not_found", "job_not_found"]);
        if (stateMovedKinds.has(r.error)) {
          conflict = {
            kind: "state_moved_on",
            wireKind: r.error,
            message:
              r.error === "wrong_cap" && r.cap_required
                ? `${action.label} requires ${r.cap_required}.`
                : `${action.label} can't be applied — this job moved on.`,
            brainState: r.from || null,
            fromState: r.from || null,
            toState: r.to || null,
            action,
          };
          return;
        }
        if (fkKinds.has(r.error)) {
          conflict = {
            kind: "fk_error",
            wireKind: r.error,
            message: `${action.label} can't be applied — this job no longer exists on the brain.`,
            entity: "job",
            id: job.id,
            action,
          };
          return;
        }
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
      // D-O5m.followup-5 — typed error → structured banner.  These
      // are raised by ReplClient.send for 400-shaped bodies; the
      // 200-with-error path is handled above via parseJobTransitionResult.
      if (e instanceof ReplStateMovedOnError) {
        conflict = {
          kind: "state_moved_on",
          wireKind: e.kind,
          message: `${action.label} can't be applied — this job moved on.`,
          brainState: e.brainState,
          fromState: e.fromState,
          toState: e.toState,
          action,
        };
        return;
      }
      if (e instanceof ReplFkError) {
        conflict = {
          kind: "fk_error",
          wireKind: e.kind,
          message: `${action.label} can't be applied — this ${e.entity} no longer exists.`,
          entity: e.entity,
          id: e.id,
          action,
        };
        return;
      }
      if (e instanceof ReplValidationError) {
        conflict = {
          kind: "validation",
          wireKind: e.kind,
          message: `${action.label} failed validation: ${e.hint ?? e.kind}`,
          action,
        };
        return;
      }
      banner = { kind: "err", text: e instanceof Error ? e.message : String(e) };
    } finally {
      busy = false;
    }
  }

  let action = $derived(actionForState(job.state));
</script>

<section class="job-detail">
  <header>
    <h2>{job.customer_name || job.id}</h2>
    <span class="state-chip {job.state}">{job.state}</span>
  </header>
  <div class="trail-row">
    <StageTrail state={job.state} compact={false} />
  </div>

  {#if unauthenticated}
    <p class="auth-needed">
      Session expired. <a href="/helm/">Sign in</a> to continue.
    </p>
  {:else}
    <dl>
      <dt>Job ID</dt><dd><code>{job.id}</code></dd>
      <dt>Customer</dt><dd>{job.customer_name}</dd>
      <dt>State</dt><dd>{job.state}</dd>
      <dt>Scheduled</dt><dd>{job.scheduled_at || "—"}</dd>
    </dl>

    {#if action}
      <button onclick={() => action && runAction(action)} disabled={busy}>
        {busy ? "Working…" : action.label}
      </button>
    {:else}
      <p class="terminal">Job is closed; no further actions.</p>
    {/if}

    {#if banner}
      <p class="banner banner-{banner.kind}">{banner.text}</p>
    {/if}

    {#if conflict}
      <!-- D-O5m.followup-5 K1 conflict UI — inline conflict banner. -->
      <aside class="conflict conflict-{conflict.kind}" role="alert">
        <header class="conflict-header">
          <strong>Conflict:</strong>
          <code class="conflict-kind">{conflict.wireKind}</code>
        </header>
        <p class="conflict-message">{conflict.message}</p>
        {#if conflict.kind === "state_moved_on" && conflict.brainState}
          <p class="conflict-detail">
            Brain's current state: <code>{conflict.brainState}</code>
            {#if conflict.toState}
              · attempted: <code>{conflict.toState}</code>
            {/if}
          </p>
        {/if}
        {#if conflict.kind === "fk_error" && conflict.id}
          <p class="conflict-detail">
            Missing {conflict.entity} id: <code>{conflict.id}</code>
          </p>
        {/if}
        <div class="conflict-actions">
          <button onclick={retryConflict} disabled={busy}>Retry</button>
          <button onclick={dismissConflict}>Dismiss</button>
        </div>
      </aside>
    {/if}

    <h3>Visits</h3>
    {#if visitsLoading}
      <p class="loading">Loading visits…</p>
    {:else if visitsError}
      <p class="error">Failed to load visits: <code>{visitsError}</code></p>
    {:else if visits.length === 0}
      <p class="empty">No visits scheduled for this job.</p>
    {:else}
      <ul class="visits">
        {#each visits as v (v.id)}
          <li>
            <code>{v.id}</code> — <span class="status status-{v.status}">{v.status}</span>
            <span class="visit-type">{v.visit_type}</span>
            {#if v.actual_start}
              <span class="visit-meta">started {v.actual_start}</span>
            {/if}
          </li>
        {/each}
      </ul>
    {/if}

    <h3>Quotes</h3>
    {#if quotesLoading}
      <p class="loading">Loading quotes…</p>
    {:else if quotesError}
      <p class="error">Failed to load quotes: <code>{quotesError}</code></p>
    {:else if quotes.length === 0}
      <p class="empty">No quotes drafted for this job.</p>
    {:else}
      <ul class="quotes">
        {#each quotes as q (q.id)}
          <li>
            <code>{q.id}</code> — <span class="status status-{q.status}">{q.status}</span>
            <span class="quote-cost">{formatCents(q.cost_min)} – {formatCents(q.cost_max)}</span>
          </li>
        {/each}
      </ul>
    {/if}

    <h3>Invoices</h3>
    {#if invoicesLoading}
      <p class="loading">Loading invoices…</p>
    {:else if invoicesError}
      <p class="error">Failed to load invoices: <code>{invoicesError}</code></p>
    {:else if invoices.length === 0}
      <p class="empty">No invoices drafted for this job.</p>
    {:else}
      <ul class="invoices">
        {#each invoices as inv (inv.id)}
          <li>
            <code>{inv.id}</code> — <span class="status status-{inv.status}">{inv.status}</span>
            <span class="invoice-amount">{formatInvoiceCents(inv.amount)}</span>
          </li>
        {/each}
      </ul>
    {/if}
  {/if}
</section>

<style>
  .job-detail {
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
    gap: 1rem;
    margin-bottom: 4px;
  }

  .trail-row {
    margin: 12px 0 16px;
  }

  button {
    margin-top: 12px;
    padding: 6px 14px;
    background: none;
    border: 1px solid var(--rule-bright);
    border-radius: 4px;
    color: var(--ink-soft);
    font: inherit;
    font-size: 12px;
    font-family: var(--mono);
    letter-spacing: 0.06em;
    text-transform: uppercase;
    cursor: pointer;
    transition: border-color 0.15s, color 0.15s;
  }

  button:hover:not([disabled]) {
    border-color: var(--activation);
    color: var(--activation);
  }

  button[disabled] { cursor: not-allowed; opacity: 0.4; }

  .terminal { font-style: italic; color: var(--ink-faint); font-size: 12px; }

  .banner {
    margin-top: 12px;
    padding: 8px 12px;
    border-radius: 4px;
    font-family: var(--mono);
    font-size: 12px;
    border: 1px solid var(--rule);
  }

  .banner-ok   { border-color: var(--hold); color: var(--hold); background: var(--hold-soft); }
  .banner-warn { border-color: var(--linear); color: var(--linear); background: var(--linear-soft); }
  .banner-err  { border-color: var(--linear); color: var(--linear); background: var(--linear-soft); }

  /* D-O5m.followup-5 K1 conflict UI */
  .conflict {
    margin-top: 12px;
    padding: 12px 14px;
    border-radius: 4px;
    background: var(--shell-2);
    border-left: 3px solid var(--linear);
    border: 1px solid var(--rule);
    border-left-width: 3px;
  }

  .conflict-state_moved_on { border-left-color: var(--linear); }
  .conflict-fk_error      { border-left-color: var(--activation); }
  .conflict-validation    { border-left-color: var(--ink-faint); }

  .conflict-header { display: flex; gap: 8px; align-items: baseline; }

  .conflict-kind {
    font-family: var(--mono);
    font-size: 11px;
    color: var(--ink-faint);
  }

  .conflict-message {
    margin: 6px 0;
    font-size: 12px;
    color: var(--ink-soft);
  }

  .conflict-detail {
    font-size: 11px;
    color: var(--ink-faint);
    font-family: var(--mono);
    margin: 4px 0;
  }

  .conflict-actions {
    display: flex;
    gap: 8px;
    margin-top: 10px;
  }

  .conflict-actions button {
    margin-top: 0;
    padding: 4px 10px;
  }

  .auth-needed { font-style: italic; color: var(--ink-faint); font-size: 12px; }

  h3 {
    margin-top: 24px;
    margin-bottom: 8px;
    font-size: 10px;
    font-weight: 600;
    color: var(--ink-faint);
    font-family: var(--mono);
    text-transform: uppercase;
    letter-spacing: 0.1em;
  }

  .visits, .quotes, .invoices {
    list-style: none;
    padding: 0;
    margin: 0;
  }

  .visits li, .quotes li, .invoices li {
    padding: 8px 0;
    border-bottom: 1px solid var(--rule);
    font-family: var(--mono);
    font-size: 12px;
    color: var(--ink-soft);
  }

  .visits li:last-child, .quotes li:last-child, .invoices li:last-child {
    border-bottom: none;
  }

  .status {
    display: inline-block;
    font-family: var(--mono);
    font-size: 10px;
    letter-spacing: 0.06em;
    text-transform: uppercase;
    padding: 2px 6px;
    border-radius: 3px;
    border: 1px solid var(--rule);
    background: var(--shell-2);
    color: var(--ink-soft);
  }

  .visit-type, .visit-meta {
    margin-left: 8px;
    color: var(--ink-faint);
    font-size: 11px;
    font-family: var(--mono);
  }

  .loading { font-style: italic; color: var(--ink-faint); font-size: 12px; font-family: var(--mono); }
</style>

```
