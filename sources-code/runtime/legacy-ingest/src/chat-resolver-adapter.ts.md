---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/chat-resolver-adapter.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.128117+00:00
---

# runtime/legacy-ingest/src/chat-resolver-adapter.ts

```ts
/**
 * T9 follow-up — production chat-resolver adapter for the PWA / TUI.
 *
 * Reference: docs/prd/D-Reingest-Typed-Cells.md §TDD Gate / T9.
 *
 * The chat-resolver itself (`chat-resolver.ts::resolveJobReference`)
 * is transport-agnostic — it takes a `JobsView`. This adapter wires
 * three pieces operators see end-to-end:
 *
 *   1. `BrainJobsView` (cached) — populated by a JobsFetcher the
 *      caller injects (typically a WSS dispatch to the brain's
 *      job-index verbs, or a PWA-side cached projection).
 *   2. `resolveJobReference` — service-tag / intent matching.
 *   3. A single `resolveChatUtterance` entry point — what the PWA
 *      calls per utterance.
 *
 * The adapter also exposes `onCellMinted` — call this after a fresh
 * cell mint (e.g. after `legacy reingest` adds a job) so the cached
 * JobsView snapshot refreshes on the next utterance.
 */

import { resolveJobReference, type ResolverResult } from './chat-resolver';
import { BrainJobsView, type JobsFetcher } from './brain-jobs-view';

/* ──────────────────────────────────────────────────────────────────────
 * Public types
 * ────────────────────────────────────────────────────────────────────── */

export interface ChatResolverAdapterOpts {
  /** RPC seam — fetches the operator's open jobs. */
  readonly jobsFetcher: JobsFetcher;
  /** Optional cache TTL (default 30s). */
  readonly cacheTtlMs?: number;
  /** Optional clock for tests. */
  readonly clockFn?: () => number;
  /** Optional override of which states count as "active". */
  readonly activeStates?: ReadonlySet<string>;
}

/** The adapter wraps a long-lived JobsView so cache state persists. */
export class ChatResolverAdapter {
  private readonly view: BrainJobsView;

  constructor(opts: ChatResolverAdapterOpts) {
    this.view = new BrainJobsView({
      fetcher: opts.jobsFetcher,
      cacheTtlMs: opts.cacheTtlMs,
      clockFn: opts.clockFn,
      activeStates: opts.activeStates,
    });
  }

  /**
   * Resolve an operator utterance to one of:
   *   • match — a single job_cell_id (with confidence + intent)
   *   • ambiguous — candidate list for the PWA to render a picker
   *   • none — no open jobs satisfy the utterance
   *
   * Optional `siteHint`: when the PWA knows the operator is currently
   * looking at a specific site, pass the site_cell_id to disambiguate
   * multi-match cases.
   */
  async resolve(args: {
    readonly utterance: string;
    readonly siteHint?: string | null;
  }): Promise<ResolverResult> {
    return resolveJobReference({
      utterance: args.utterance,
      siteHint: args.siteHint ?? null,
      jobsView: this.view,
    });
  }

  /**
   * Notify the adapter that the underlying job graph changed —
   * forces the next utterance to fetch a fresh snapshot. Call this
   * after `legacy reingest` finishes, or after the PWA writes a
   * fresh proposal through ratification.
   */
  onCellMinted(): void {
    this.view.invalidate();
  }

  /** Telemetry — how many open jobs the view has cached right now. */
  cachedCount(): number {
    return this.view.cachedCount();
  }
}

```
