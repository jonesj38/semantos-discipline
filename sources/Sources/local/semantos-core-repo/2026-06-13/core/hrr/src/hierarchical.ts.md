---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/hrr/src/hierarchical.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.021260+00:00
---

# core/hrr/src/hierarchical.ts

```ts
/**
 * WI-B5 — Hierarchical HRR for octave-1+ structures.
 *
 * An octave-0 structure has a fixed number of structural metadata slots
 * (category, lexicon, action, etc.) — its HRR noise budget is bounded.
 *
 * An octave-1 structure is a multi-clause entity (e.g., a real-estate lease
 * with 8 obligation clauses, 3 condition clauses, 2 power clauses). Encoding
 * all clauses into a single vector degrades retrieval: with 20+ bindings the
 * superposition noise exceeds the 0.7 cosine threshold from WI-A4.
 *
 * Solution: two-level representation mirroring OP_DEREF_POINTER at the
 * cell-engine level.
 *   summary  — octave-0 encoding from structural metadata only.
 *              Used for fast library retrieval. Noise-bounded.
 *   detail   — octave-1 encoding from all clause bindings.
 *              Used for second-pass re-scoring after summary retrieval.
 *
 * The library stores the summary vector; after nearest() returns candidates,
 * a caller with the detail vectors can do a high-fidelity re-rank.
 *
 * See research/cognition-implementation-plan.md §WI-B5.
 */

import {
  D,
  roleVec,
  fillerVec,
  circConv,
  l2normalize,
  dot,
} from './role-vectors';
import { encodePartialIntent } from './encode';

// ── Public types ──────────────────────────────────────────────────────────────

export interface ClauseBinding {
  /** Role name within the grammar (e.g., 'obligation_clause', 'condition_clause'). */
  role: string;
  /** Filler value (e.g., 'payment_due', 'no_smoking', 'entry_allowed'). */
  filler: string;
}

export interface HierarchicalVector {
  /** Octave-0 summary — noise-bounded, used for fast retrieval. */
  summary: Float64Array;
  /** Octave-1 detail — encodes all clause bindings, used for re-ranking. */
  detail: Float64Array;
  /** Number of clauses encoded in the detail vector. */
  clauseCount: number;
}

// ── Encoder ───────────────────────────────────────────────────────────────────

/**
 * Encode a multi-clause structure as a hierarchical (summary + detail) HRR pair.
 *
 * The summary is identical to `encodePartialIntent` and does NOT change as
 * more clauses are added — retrieval noise stays within the octave-0 budget.
 *
 * The detail encodes every clause binding so that two contracts with more
 * shared clauses produce higher cosine similarity on the detail vector.
 */
export function encodeHierarchical(opts: {
  domainFlag: number;
  juralCategory: string;
  lexicon: string;
  action?: string;
  objectType?: string;
  trustClass?: string;
  howTaxonomy?: string;
  clauses: ClauseBinding[];
}): HierarchicalVector {
  const { domainFlag: d } = opts;

  const summary = encodePartialIntent({
    domainFlag: d,
    juralCategory: opts.juralCategory,
    lexicon: opts.lexicon,
    action: opts.action,
    objectType: opts.objectType,
    trustClass: opts.trustClass,
    howTaxonomy: opts.howTaxonomy,
  });

  const detailSum = new Float64Array(D);

  // Domain anchor
  addClause(detailSum, d, 'domain', String(d));
  // Structural metadata slots (same as summary but contribute to detail too)
  addClause(detailSum, d, 'category', opts.juralCategory);
  addClause(detailSum, d, 'lexicon',  opts.lexicon);
  if (opts.action)     addClause(detailSum, d, 'action',      opts.action);
  if (opts.objectType) addClause(detailSum, d, 'object_type', opts.objectType);
  if (opts.trustClass) addClause(detailSum, d, 'trust_class', opts.trustClass);

  // Clause bindings
  for (const c of opts.clauses) {
    addClause(detailSum, d, c.role, c.filler);
  }

  return {
    summary,
    detail: l2normalize(detailSum),
    clauseCount: opts.clauses.length,
  };
}

/**
 * Cosine similarity between two detail vectors.
 * Measures how many clause bindings are shared.
 */
export function detailSimilarity(a: HierarchicalVector, b: HierarchicalVector): number {
  return Math.max(-1, Math.min(1, dot(a.detail, b.detail)));
}

// ── Internal ──────────────────────────────────────────────────────────────────

function addClause(sum: Float64Array, domainFlag: number, role: string, filler: string): void {
  const rv = roleVec(domainFlag, role);
  const fv = fillerVec(domainFlag, filler);
  const bnd = circConv(rv, fv);
  for (let i = 0; i < D; i++) sum[i] += bnd[i];
}

```
