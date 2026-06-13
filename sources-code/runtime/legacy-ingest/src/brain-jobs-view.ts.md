---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/brain-jobs-view.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.131869+00:00
---

# runtime/legacy-ingest/src/brain-jobs-view.ts

```ts
/**
 * T9 follow-up — production wiring of the chat resolver's `JobsView`
 * seam against the brain's job-cell index.
 *
 * Reference: docs/prd/D-Reingest-Typed-Cells.md §TDD Gate / T9.
 *
 * The chat resolver (`chat-resolver.ts`) takes any `JobsView`
 * implementation; tests inject in-memory stubs. Production wires a
 * `BrainJobsView` that pulls open jobs from the brain's view of
 * TAG_JOB cells via an injected fetcher callback. The fetcher is the
 * RPC-transport seam — it doesn't know about chat resolution, just
 * how to enumerate the operator's open jobs.
 *
 * Separation of concerns:
 *   • `BrainJobsView` — caches the fetcher result for the chat-session
 *     lifetime + does the service-tag + active-state filter
 *   • `JobsFetcher` (caller-supplied) — WSS dispatch to `oddjobz.list_*`
 *     verbs (or the cached projection a PWA already keeps for the
 *     JobList view); plain async function so tests pass an array
 *
 * Why a cached snapshot rather than per-query fetches:
 *   The operator's open-job count is single-thousands at most (per
 *   memory `v1_production_is_test_data`); fetching once per chat
 *   session is fine, refresh on TTL or explicit invalidate. The
 *   resolver is bursty (often several queries per utterance — intent
 *   detection might propose multiple service tags) so the local cache
 *   matters more than the freshness lag.
 */

import type { JobsView, JobSummary } from './chat-resolver';

/* ──────────────────────────────────────────────────────────────────────
 * Public types
 * ────────────────────────────────────────────────────────────────────── */

/** Async callback the BrainJobsView uses to populate its cache. */
export type JobsFetcher = () => Promise<readonly JobSummary[]>;

export interface BrainJobsViewOpts {
  /** Fetcher seam — WSS dispatch / local LMDB / cached PWA projection. */
  readonly fetcher: JobsFetcher;
  /**
   * How long the snapshot stays cached, in ms. After the TTL the next
   * `findActiveByServices` triggers a fresh fetch. Default 30s — small
   * enough that an operator who just minted a cell sees it on the
   * next utterance, big enough to coalesce typical resolver bursts.
   */
  readonly cacheTtlMs?: number;
  /**
   * Clock function for deterministic tests. Defaults to Date.now.
   */
  readonly clockFn?: () => number;
  /**
   * States considered "active" for chat resolution — only jobs in
   * one of these states are candidates. Default covers the typical
   * open-job lifecycle: lead → quoted → scheduled → in_progress →
   * invoiced. `completed` / `closed` / `paid` are excluded so chat
   * resolution doesn't accidentally reopen finalised work.
   */
  readonly activeStates?: ReadonlySet<string>;
}

const DEFAULT_ACTIVE_STATES = new Set<string>([
  'lead',
  'quoted',
  'scheduled',
  'in_progress',
  'invoiced',
]);

const DEFAULT_TTL_MS = 30_000;

/* ──────────────────────────────────────────────────────────────────────
 * Public class
 * ────────────────────────────────────────────────────────────────────── */

export class BrainJobsView implements JobsView {
  private readonly fetcher: JobsFetcher;
  private readonly cacheTtlMs: number;
  private readonly clockFn: () => number;
  private readonly activeStates: ReadonlySet<string>;

  private cachedJobs: readonly JobSummary[] | null = null;
  private cachedAt: number = 0;
  /** Coalesce concurrent fetches so a burst doesn't issue N RPCs. */
  private inflight: Promise<readonly JobSummary[]> | null = null;

  constructor(opts: BrainJobsViewOpts) {
    this.fetcher = opts.fetcher;
    this.cacheTtlMs = opts.cacheTtlMs ?? DEFAULT_TTL_MS;
    this.clockFn = opts.clockFn ?? (() => Date.now());
    this.activeStates = opts.activeStates ?? DEFAULT_ACTIVE_STATES;
  }

  async findActiveByServices(services: readonly string[]): Promise<readonly JobSummary[]> {
    const jobs = await this.snapshot();
    const active = jobs.filter(j => this.activeStates.has(j.state));
    if (services.length === 0) return active;
    const wanted = new Set(services);
    return active.filter(j => j.services.some(s => wanted.has(s)));
  }

  /** Force the next call to fetch fresh — e.g. after a cell mint. */
  invalidate(): void {
    this.cachedJobs = null;
    this.cachedAt = 0;
    this.inflight = null;
  }

  /** Expose the current cached size — useful for telemetry / debugging. */
  cachedCount(): number {
    return this.cachedJobs?.length ?? 0;
  }

  /* ── Internal ──────────────────────────────────────────────────── */

  private async snapshot(): Promise<readonly JobSummary[]> {
    const now = this.clockFn();
    if (this.cachedJobs && now - this.cachedAt < this.cacheTtlMs) {
      return this.cachedJobs;
    }
    if (this.inflight) return this.inflight;
    this.inflight = this.fetcher()
      .then(jobs => {
        this.cachedJobs = jobs;
        this.cachedAt = now;
        this.inflight = null;
        return jobs;
      })
      .catch(err => {
        this.inflight = null;
        // On error: if we have a stale cache, return it (graceful
        // degradation — the chat resolver still works against the
        // previously-known state). If no cache yet, propagate.
        if (this.cachedJobs) return this.cachedJobs;
        throw err;
      });
    return this.inflight;
  }
}

```
