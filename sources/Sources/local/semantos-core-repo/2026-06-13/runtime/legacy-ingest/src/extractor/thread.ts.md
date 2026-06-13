---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/extractor/thread.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.160507+00:00
---

# runtime/legacy-ingest/src/extractor/thread.ts

```ts
/**
 * Thread-collapsing pass — LI3 deliverable 4.
 *
 * Reference: docs/design/WALLET-LEGACY-INGEST.md §3 LI3 deliverable 4.
 *
 * After per-item extraction, fold proposals that share a thread key
 * (Gmail In-Reply-To / References, WhatsApp conversation id, etc.)
 * into a single thread-level proposal. The operator ratifies the
 * thread, not each message.
 *
 * Strategy: bucket pending proposals by thread key; for each bucket
 * with > 1 member, mark the highest-confidence proposal as the
 * primary and link the rest as siblings. The primary's summary is
 * promoted to a thread-level summary.
 *
 * Cross-content-type clustering (a Gmail thread + a WhatsApp follow-up
 * for the same job) is LI5's job — this pass operates within a single
 * provider and content type.
 */

import type { Proposal } from './types';

export interface ThreadCollapseResult {
  /** The same proposals, with thread keys + sibling links updated. */
  readonly proposals: Proposal[];
  /** ids of proposals that were *folded* into a primary. */
  readonly foldedProposalIds: string[];
}

/**
 * Pure function over a flat array of proposals. Returns a new array
 * with thread metadata populated; original input is not mutated.
 */
export function collapseThreads(input: Proposal[]): ThreadCollapseResult {
  const buckets = new Map<string, Proposal[]>();
  const standalone: Proposal[] = [];

  for (const p of input) {
    if (!p.threadKey) {
      standalone.push(p);
      continue;
    }
    const bucket = buckets.get(p.threadKey) ?? [];
    bucket.push(p);
    buckets.set(p.threadKey, bucket);
  }

  const out: Proposal[] = [...standalone];
  const folded: string[] = [];

  for (const [, bucket] of buckets) {
    if (bucket.length === 1) {
      out.push(bucket[0]);
      continue;
    }
    bucket.sort((a, b) => b.confidence - a.confidence);
    const [primary, ...rest] = bucket;
    const siblingIds = rest.map(p => p.proposalId);
    folded.push(...siblingIds);
    out.push({
      ...primary,
      siblingProposalIds: siblingIds,
      summary: threadSummary(primary, rest),
    });
  }

  return { proposals: out, foldedProposalIds: folded };
}

function threadSummary(primary: Proposal, rest: Proposal[]): string {
  if (rest.length === 0) return primary.summary;
  return `${primary.summary} (+${rest.length} message${rest.length === 1 ? '' : 's'} in thread)`;
}

// ── Reference-number dedup pass ───────────────────────────────────────────────

export interface ReferenceDedupeResult {
  readonly proposals: Proposal[];
  /** proposalIds that were merged into a primary and should be skipped. */
  readonly mergedProposalIds: string[];
}

/**
 * Fold proposals that share the same extracted referenceNumber (work-order
 * number, PO, PropertyMe/BricksAndAgent reference) into a single primary.
 * The highest-confidence proposal wins; the rest become siblings.
 *
 * Run this AFTER collapseThreads — it operates on the already-collapsed set
 * so that separate emails about the same job (not reply chains) are caught.
 */
export function deduplicateByReferenceNumber(input: Proposal[]): ReferenceDedupeResult {
  const buckets = new Map<string, Proposal[]>();
  const standalone: Proposal[] = [];

  for (const p of input) {
    if (!p.referenceNumber) {
      standalone.push(p);
      continue;
    }
    const bucket = buckets.get(p.referenceNumber) ?? [];
    bucket.push(p);
    buckets.set(p.referenceNumber, bucket);
  }

  const out: Proposal[] = [...standalone];
  const merged: string[] = [];

  for (const [, bucket] of buckets) {
    if (bucket.length === 1) {
      out.push(bucket[0]);
      continue;
    }
    bucket.sort((a, b) => b.confidence - a.confidence);
    const [primary, ...rest] = bucket;
    const mergedIds = rest.map(p => p.proposalId);
    merged.push(...mergedIds);
    const existingSiblings = primary.siblingProposalIds ?? [];
    out.push({
      ...primary,
      siblingProposalIds: [...existingSiblings, ...mergedIds],
      summary: refSummary(primary, rest),
    });
  }

  return { proposals: out, mergedProposalIds: merged };
}

function refSummary(primary: Proposal, rest: Proposal[]): string {
  if (rest.length === 0) return primary.summary;
  return `${primary.summary} (+${rest.length} scope update${rest.length === 1 ? '' : 's'} for same reference)`;
}

```
