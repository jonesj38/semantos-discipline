---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/semantos-ir/src/expr.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.004527+00:00
---

# core/semantos-ir/src/expr.ts

```ts
/**
 * Surface-grammar primitives — the AST types the IRs consume.
 *
 * Hoisted from runtime/shell/src/lisp/types.ts to remove the core/→runtime/
 * import-boundary violation. ConstraintExpr is the surface-grammar primitive
 * that the OIR (semantos-ir) and SIR (semantos-sir) lower; it logically
 * belongs in core/ alongside the IRs that consume it, not under shell.
 *
 * Lisp-specific types (PolicyForm, ScriptOutput, the interpretConstraint /
 * validateConstraintFields helpers) stay in runtime/shell/src/lisp/types.ts.
 * That file re-exports ConstraintExpr & friends from here so existing shell
 * code keeps working unchanged.
 */

// ── Identity References ────────────────────────────────────────

export type IdentityRef =
  | { type: 'role'; name: string }
  | { type: 'domainFlag'; flag: number }
  | { type: 'certPattern'; pattern: string };

// ── Constraint Expressions ─────────────────────────────────────

export type ComparisonOp = '>' | '<' | '>=' | '<=' | '=' | '!=';

export interface ComparisonExpr {
  kind: 'comparison';
  op: ComparisonOp;
  field: string;
  value: number | string;
}

export interface LogicalExpr {
  kind: 'logical';
  op: 'and' | 'or' | 'not';
  operands: ConstraintExpr[];
}

export interface CapabilityExpr {
  kind: 'capability';
  capabilityNumber: number;
}

export interface DomainCheckExpr {
  kind: 'domainCheck';
  domainFlag: number | string;
}

export interface TimeConstraintExpr {
  kind: 'timeConstraint';
  op: 'timeAfter' | 'timeBefore';
  isoTimestamp: string;
}

export interface HostCallExpr {
  kind: 'hostCall';
  functionName: string;
}

export interface TypeHashCheckExpr {
  kind: 'typeHashCheck';
  expectedHash: string;  // hex-encoded SHA-256 (64 hex chars = 32 bytes)
}

export interface DerefExpr {
  kind: 'deref';
}

export type ConstraintExpr =
  | ComparisonExpr
  | LogicalExpr
  | CapabilityExpr
  | DomainCheckExpr
  | TimeConstraintExpr
  | HostCallExpr
  | TypeHashCheckExpr
  | DerefExpr;

// ── Linearity Mode ─────────────────────────────────────────────

export type LinearityMode = 'LINEAR' | 'AFFINE' | 'RELEVANT' | 'FUNGIBLE';

```
