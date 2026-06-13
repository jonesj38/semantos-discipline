---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/semantos-ir/src/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.004264+00:00
---

# core/semantos-ir/src/types.ts

```ts
/**
 * ANF (Administrative Normal Form) intermediate representation.
 *
 * Every sub-expression in a ConstraintExpr tree becomes a named binding.
 * This eliminates evaluation-order ambiguity and makes the IR
 * serializable to canonical JSON for golden-file differential testing.
 *
 * The IR sits between the AST (ConstraintExpr) and opcode bytes:
 *   ConstraintExpr  ──lower()──►  IRProgram  ──emit()──►  Uint8Array
 */

// Re-export the source AST type so consumers don't need a shell dependency
export type { ConstraintExpr } from './expr';

// ── IR Node Kinds ─────────────────────────────────────────────
// Mirror the 8 ConstraintExpr kinds (logical is split into and/or/not)

export type IRKind =
  | 'comparison'
  | 'logical_and'
  | 'logical_or'
  | 'logical_not'
  | 'capability'
  | 'domainCheck'
  | 'timeConstraint'
  | 'hostCall'
  | 'typeHashCheck'
  | 'deref';

// ── IR Binding ────────────────────────────────────────────────

export interface IRBinding {
  /** Unique binding name (counter-based: "$0", "$1", ...) */
  name: string;
  /** Which constraint kind produced this binding */
  kind: IRKind;

  // ── Kind-specific payload (only relevant fields are set) ────

  /** Comparison operator (>, <, >=, <=, =, !=) */
  op?: string;
  /** Field name for comparison */
  field?: string;
  /** Literal value for comparison */
  value?: number | string;

  /** References to operand bindings (for logical combinators) */
  operands?: string[];

  /** Capability number */
  capabilityNumber?: number;
  /** Domain flag (numeric or string) */
  domainFlag?: number | string;

  /** Time constraint operator (timeAfter / timeBefore) */
  timeOp?: 'timeAfter' | 'timeBefore';
  /** Unix timestamp (seconds since epoch) */
  timestamp?: number;

  /** Host function name */
  functionName?: string;
  /** Expected type hash (64-char hex) */
  expectedHash?: string;
}

// ── IR Program ────────────────────────────────────────────────

export interface IRProgram {
  /** Ordered sequence of bindings (topological order — each binding
   *  only references earlier bindings) */
  bindings: IRBinding[];
  /** Name of the final binding whose value is the program result */
  result: string;
}

```
