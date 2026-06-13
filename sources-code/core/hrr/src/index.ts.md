---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/hrr/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.020974+00:00
---

# core/hrr/src/index.ts

```ts
/**
 * @semantos/hrr — Plate (1995) circular-convolution HRR for Semantos intent programs.
 *
 * Entry points:
 *   encodeSIRProgram(program, domainFlag) → Float64Array
 *   bind(role, filler)                   → Float64Array
 *   unbind(bound, role)                  → Float64Array
 *   cosine(a, b)                         → number
 *
 * Low-level primitives (for WI-B5 hierarchical encoding and tests):
 *   roleVec(domainFlag, roleName)        → Float64Array
 *   fillerVec(domainFlag, fillerValue)   → Float64Array
 *   seedVec(seed)                        → Float64Array
 *   D                                    → 1024
 */

export { encodeSIRProgram, encodePartialIntent, bind, unbind, cosine, D } from './encode';
export { roleVec, fillerVec, seedVec } from './role-vectors';
export { encodeHierarchical, detailSimilarity } from './hierarchical';
export type { HierarchicalVector, ClauseBinding } from './hierarchical';

```
