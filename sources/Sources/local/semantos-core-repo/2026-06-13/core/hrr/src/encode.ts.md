---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/hrr/src/encode.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.021823+00:00
---

# core/hrr/src/encode.ts

```ts
/**
 * HRR encoder for Semantos intent programs.
 *
 * Public API:
 *   encodeSIRProgram(program, domainFlag) → Float64Array  (D=1024 unit vector)
 *   bind(role, filler)                   → Float64Array  (circular convolution)
 *   unbind(bound, role)                  → Float64Array  (circular correlation)
 *   cosine(a, b)                         → number        (similarity ∈ [-1, 1])
 *
 * Encoding scheme (Plate 1995, §WI-B1):
 *   Each IRBinding maps to one (role ⊛ filler) term.
 *   The role vector is seeded by (domainFlag, binding.kind).
 *   The filler vector is seeded by (domainFlag, canonical slot value).
 *   The program vector is the L2-normalised superposition of all terms.
 *
 * Structural slot → filler seed mapping:
 *   kind         → binding.kind
 *   op           → binding.op         (comparison bindings)
 *   field        → binding.field      (comparison bindings)
 *   value_class  → quantise(value)    (buckets: <0, 0, 0-1k, 1k-100k, >100k)
 *   capability   → String(cap number)
 *   domain       → String(domainFlag)
 *   time_op      → binding.timeOp
 *
 * The domain slot is present in every program, encoding the domain flag
 * as a filler so cross-domain cosines converge to ≈ 0 via orthogonal
 * role-vector bases (confirmed empirically in WI-A4).
 */

import type { IRBinding, IRProgram } from '@semantos/semantos-ir';
import {
  D,
  roleVec,
  fillerVec,
  circConv,
  circCorr,
  l2normalize,
  dot,
} from './role-vectors';

export { D } from './role-vectors';

// ── Public primitives ─────────────────────────────────────────────────────────

/**
 * Bind role to filler via circular convolution.
 * Result is approximately a unit vector for unit-norm inputs.
 */
export function bind(role: Float64Array, filler: Float64Array): Float64Array {
  return circConv(role, filler);
}

/**
 * Approximate inverse of bind: unbind(bind(r, f), r) ≈ f.
 * Noise increases as superposition grows (standard HRR limit).
 */
export function unbind(bound: Float64Array, role: Float64Array): Float64Array {
  return circCorr(role, bound);
}

/**
 * Cosine similarity ∈ [-1, 1]. Both vectors should be L2-normalised.
 */
export function cosine(a: Float64Array, b: Float64Array): number {
  return Math.max(-1, Math.min(1, dot(a, b)));
}

// ── IRProgram encoder ─────────────────────────────────────────────────────────

/**
 * Encode an IRProgram as a D=1024 unit vector.
 * Deterministic: same (program, domainFlag) always produces the same vector.
 */
export function encodeSIRProgram(
  program: IRProgram,
  domainFlag: number,
): Float64Array {
  const sum = new Float64Array(D);

  // Domain anchor — present in every program.
  addBinding(sum, domainFlag, 'domain', String(domainFlag));

  for (const b of program.bindings) {
    addBinding(sum, domainFlag, 'kind', b.kind);

    if (b.op != null)    addBinding(sum, domainFlag, 'op', b.op);
    if (b.field != null) addBinding(sum, domainFlag, 'field', b.field);
    if (b.value != null) addBinding(sum, domainFlag, 'value_class', quantiseValue(b.value));

    if (b.capabilityNumber != null)
      addBinding(sum, domainFlag, 'capability', String(b.capabilityNumber));

    if (b.domainFlag != null)
      addBinding(sum, domainFlag, 'domain_check', String(b.domainFlag));

    if (b.timeOp != null) addBinding(sum, domainFlag, 'time_op', b.timeOp);

    if (b.functionName != null)
      addBinding(sum, domainFlag, 'host_fn', b.functionName);
  }

  return l2normalize(sum);
}

// ── Structural metadata encoder ───────────────────────────────────────────────

/**
 * Encode a partial intent's structural metadata as a D=1024 unit vector.
 *
 * Uses the same role/filler basis as `encodeSIRProgram` but with
 * high-level structural slots (category, lexicon, action, etc.) rather than
 * IRBinding kinds. This is the encoding used by:
 *   - `HrrLibrary.onIntentOutcome` for storing per-cell vectors
 *   - WI-B3 analogical-prefilter-pass for building query vectors
 *
 * Because both the stored vectors and the query vectors use this function,
 * the cosine similarity is well-defined and domain-appropriate.
 */
export function encodePartialIntent(opts: {
  domainFlag: number;
  juralCategory: string;
  lexicon: string;
  action?: string;
  objectType?: string;
  trustClass?: string;
  /** WI-B4: taxonomy.how from the logic pass — adds signal for rank re-scoring. */
  howTaxonomy?: string;
}): Float64Array {
  const { domainFlag: d } = opts;
  const sum = new Float64Array(D);
  addBinding(sum, d, 'domain',   String(d));
  addBinding(sum, d, 'category', opts.juralCategory);
  addBinding(sum, d, 'lexicon',  opts.lexicon);
  if (opts.action)      addBinding(sum, d, 'action',      opts.action);
  if (opts.objectType)  addBinding(sum, d, 'object_type', opts.objectType);
  if (opts.trustClass)  addBinding(sum, d, 'trust_class', opts.trustClass);
  if (opts.howTaxonomy) addBinding(sum, d, 'how_taxonomy', opts.howTaxonomy);
  return l2normalize(sum);
}

// ── Internal helpers ──────────────────────────────────────────────────────────

function addBinding(
  sum: Float64Array,
  domainFlag: number,
  role: string,
  filler: string,
): void {
  const rv = roleVec(domainFlag, role);
  const fv = fillerVec(domainFlag, filler);
  const bnd = circConv(rv, fv);
  for (let i = 0; i < D; i++) sum[i] += bnd[i];
}

/**
 * Bucket a numeric or string value into a coarse semantic class.
 * This prevents two programs with slightly different raw values (e.g., $850
 * vs $851) from producing orthogonal HRRs while still distinguishing
 * qualitatively different magnitudes.
 */
function quantiseValue(v: number | string): string {
  if (typeof v === 'string') return `str:${v}`;
  if (v < 0)        return 'neg';
  if (v === 0)      return 'zero';
  if (v < 1_000)    return 'small';
  if (v < 100_000)  return 'medium';
  return 'large';
}

```
