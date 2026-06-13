---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/job-dedupe.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.134802+00:00
---

# runtime/legacy-ingest/src/job-dedupe.ts

```ts
/**
 * D-RTC.6 follow-up — Job dedupe.
 *
 * Companion to `site-dedupe.ts`. The bundle-fanout + re-extract paths
 * legitimately produce more than one Proposal for the SAME physical
 * job (the operator forwards a Clever-Property bundle whose PDFs
 * overlap; a `legacy extract --force` re-runs the LLM and the
 * non-deterministic summary wording differs between runs). Sites
 * already collapse on `lookup_key`; jobs did not — each proposal
 * minted a fresh job_cell, so the OJT corpus showed several
 * work-orders (06763, 07537, 07599, 07617) duplicated 2×.
 *
 * This module derives a stable job identity so duplicate proposals
 * resolve to ONE job_cell:
 *
 *   • Primary key — the verbatim work-order number. Clever Property /
 *     RJR / Bricks issue exactly ONE WO per job; same WO ⇒ same job,
 *     regardless of how the LLM phrased the summary on a given pass.
 *   • Fallback (no WO — e.g. a bare quote request) — site_ref +
 *     issuance_date. A site getting one job per issuance day is the
 *     conservative heuristic; the failure mode is a merge (operator
 *     resolves at ratification) rather than duplicate-spam.
 *
 * Deliberately keyed OFF the LLM summary text — re-extraction wording
 * drift is exactly the noise we are collapsing.
 */

import { createHash } from 'node:crypto';

/* ──────────────────────────────────────────────────────────────────────
 * Public types
 * ────────────────────────────────────────────────────────────────────── */

/**
 * Caller-supplied lookup against the brain's (or receipt-store's)
 * view of already-minted jobs.
 *
 * V1 wirings:
 *   • Receipt-backed — an in-memory index built from
 *     ReingestReceiptStore.list() keyed by jobLookupKey (the
 *     `legacy reingest` verb builds this before the proposal loop).
 *   • Dispatcher-backed — a future `job.lookup` brain verb.
 *   • In-memory — used by job-dedupe.test.ts.
 */
export interface JobsDedupeView {
  /**
   * Returns the existing job_cell_id (lowercase 64-char hex) for the
   * given `lookupKey`, or `null` if no job matches.
   */
  findJobByLookupKey(lookupKey: string): Promise<string | null>;
}

export interface JobProposal {
  kind: 'propose';
  /**
   * Deterministic 64-char hex id. Same job identity → same id every
   * time, independent of summary wording drift. Used so the brain's
   * content-addressed cell store + the worker dedupe collapse dupes.
   */
  proposedCellId: string;
  /** The dedupe index entry. */
  lookupKey: string;
}

export interface JobMatch {
  kind: 'match';
  cellId: string;
  lookupKey: string;
}

export type JobDedupeResult = JobMatch | JobProposal;

export interface JobIdentityArgs {
  /** Verbatim work-order number from the source PDF, or null. */
  readonly workOrderNumber: string | null;
  /**
   * PropertyMe / agency order reference (the ref-dedup anchor — folds
   * the separate emails of one job's thread). Present far more often
   * than workOrderNumber. Null when absent.
   */
  readonly referenceNumber?: string | null;
  /** Full property address line, or null. */
  readonly propertyAddress?: string | null;
  /** Site cell id this job is attached to (D-RTC.1b), or null. */
  readonly siteRef: string | null;
  /** ISO YYYY-MM-DD issuance date, or null. */
  readonly issuanceDate: string | null;
}

/* ──────────────────────────────────────────────────────────────────────
 * Public API
 * ────────────────────────────────────────────────────────────────────── */

/**
 * Derive the stable job dedupe key.
 *
 *   WO present  → `wo:<normalised-wo>`
 *   WO absent   → `site:<site_ref>|<issuance_date>`
 *   neither     → `unkeyed:<site_ref-or-empty>` (best effort — these
 *                 proposals can't be confidently deduped; the worker
 *                 still mints them, just without collapse)
 *
 * WO normalisation: trim, lowercase, strip spaces + a leading "wo"/
 * "job"/"#" prefix the LLM sometimes prepends ("WO 07210", "Job
 * #07210", "#07210" all → "07210").
 */
export function deriveJobLookupKey(args: JobIdentityArgs): string {
  // Priority: WO# → PropertyMe/agency reference# → property address.
  // Each anchors ONE logical job; the thread's follow-up emails all
  // carry the same ref/address and therefore collapse instead of
  // minting a duplicate per email. issuance_date is deliberately NOT
  // part of the key — the same job is re-emailed on different dates and
  // must still fold. `site:`/`unkeyed:` (date-fragmenting, never
  // deduped) are gone; a proposal with none of these anchors is not a
  // job and is filtered upstream in the reingest worker.
  const wo = normaliseWorkOrder(args.workOrderNumber);
  if (wo.length > 0) return `wo:${wo}`;
  const ref = normaliseWorkOrder(args.referenceNumber ?? null);
  if (ref.length > 0) return `ref:${ref}`;
  const addr = normaliseAddress(args.propertyAddress ?? null);
  if (addr.length > 0) return `addr:${addr}`;
  // Defensive only — the worker skips anchorless proposals before they
  // reach here. Collapse any that slip through onto one bucket rather
  // than minting an unbounded fan of duplicates.
  return 'unkeyed:';
}

/** Normalise a property address for keying: lowercase, collapse
 * whitespace + punctuation, drop a trailing state/postcode so
 * "12 Foo St, Tewantin QLD 4565" and "12 Foo St Tewantin" fold. */
export function normaliseAddress(raw: string | null | undefined): string {
  if (raw === null || raw === undefined) return '';
  let s = raw.trim().toLowerCase();
  if (s.length === 0) return '';
  s = s.replace(/\bqld\b|\bnsw\b|\bvic\b|\bact\b|\bsa\b|\bwa\b|\bnt\b|\btas\b/g, ' ');
  s = s.replace(/\b\d{4}\b/g, ' '); // postcode
  s = s.replace(/[^a-z0-9]+/g, ' ').trim();
  return s;
}

/**
 * Pure-function half: derive the lookup key + the deterministic
 * proposed cell id. No storage IO.
 */
export function proposeJobCell(args: JobIdentityArgs): JobProposal {
  const lookupKey = deriveJobLookupKey(args);
  return {
    kind: 'propose',
    proposedCellId: computeJobCellId(lookupKey),
    lookupKey,
  };
}

/**
 * Composed entry point: derive key → query the view → branch.
 * `match` means an existing job_cell already represents this work
 * (reuse its id, don't mint a duplicate); `propose` means this is a
 * net-new job.
 *
 * `unkeyed:` proposals (no WO, no site) are never matched — they
 * always return `propose` because we can't confidently say two of
 * them are the same job.
 */
export async function findOrProposeJob(
  args: JobIdentityArgs,
  view: JobsDedupeView,
): Promise<JobDedupeResult> {
  const proposal = proposeJobCell(args);
  // Every anchored key (wo:/ref:/addr:) dedupes. Only the defensive
  // 'unkeyed:' sentinel (anchorless — should have been filtered) skips
  // the index so a stray doesn't collide everything onto one cell.
  if (proposal.lookupKey === 'unkeyed:') return proposal;
  const existing = await view.findJobByLookupKey(proposal.lookupKey);
  if (existing !== null) {
    return { kind: 'match', cellId: existing, lookupKey: proposal.lookupKey };
  }
  return proposal;
}

/* ──────────────────────────────────────────────────────────────────────
 * Internals (exported for parity-oracle testing)
 * ────────────────────────────────────────────────────────────────────── */

/**
 * Reingest-namespaced job cell id formula. Stable function of the
 * dedupe key only — so two proposals for the same WO produce the
 * same id even when their LLM summaries differ.
 */
export function computeJobCellId(lookupKey: string): string {
  const h = createHash('sha256');
  h.update('reingest.job.v1|', 'utf8');
  h.update(lookupKey, 'utf8');
  return h.digest('hex');
}

/** Trim, lowercase, strip a leading wo/job/# token + inner spaces. */
export function normaliseWorkOrder(raw: string | null | undefined): string {
  if (raw === null || raw === undefined) return '';
  let s = raw.trim().toLowerCase();
  if (s.length === 0) return '';
  // Drop a leading "wo", "work order", "job", "#", "no.", "ref"
  // label the LLM or the source PDF sometimes prepends.
  s = s.replace(/^(?:work\s*order|wo|job|ref(?:erence)?|no\.?|#)\s*[:#]?\s*/i, '');
  // Collapse internal whitespace + drop a trailing "#"-style noise.
  s = s.replace(/\s+/g, '').replace(/[#]+/g, '');
  return s;
}

```
