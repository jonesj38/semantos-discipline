---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/semantos-ir/src/lower.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.004789+00:00
---

# core/semantos-ir/src/lower.ts

```ts
/**
 * Nanopass 1: Lower — ConstraintExpr AST → IRProgram (ANF)
 *
 * Recursively walks the ConstraintExpr tree and flattens it into
 * a sequence of named bindings. Each AST node becomes exactly one
 * IRBinding. Logical nodes reference their operand bindings by name.
 *
 * Pure function — no I/O, no side effects.
 */

import type { ConstraintExpr } from './expr';
import type { IRBinding, IRProgram, IRKind } from './types';

// ── Counter-based name generation ─────────────────────────────

class NameGen {
  private counter = 0;
  next(): string {
    return `$${this.counter++}`;
  }
}

// ── Lower ─────────────────────────────────────────────────────

function lowerExpr(
  expr: ConstraintExpr,
  names: NameGen,
  bindings: IRBinding[],
): string {
  switch (expr.kind) {
    case 'comparison': {
      const name = names.next();
      bindings.push({
        name,
        kind: 'comparison',
        op: expr.op,
        field: expr.field,
        value: expr.value,
      });
      return name;
    }

    case 'logical': {
      // Lower all operands first (ANF: sub-expressions before combinators)
      const operandNames = expr.operands.map(op => lowerExpr(op, names, bindings));

      if (expr.op === 'not') {
        const name = names.next();
        bindings.push({
          name,
          kind: 'logical_not',
          operands: operandNames,
        });
        return name;
      }

      const irKind: IRKind = expr.op === 'and' ? 'logical_and' : 'logical_or';
      const name = names.next();
      bindings.push({
        name,
        kind: irKind,
        operands: operandNames,
      });
      return name;
    }

    case 'capability': {
      const name = names.next();
      bindings.push({
        name,
        kind: 'capability',
        capabilityNumber: expr.capabilityNumber,
      });
      return name;
    }

    case 'domainCheck': {
      const name = names.next();
      bindings.push({
        name,
        kind: 'domainCheck',
        domainFlag: expr.domainFlag,
      });
      return name;
    }

    case 'timeConstraint': {
      const unix = Math.floor(new Date(expr.isoTimestamp).getTime() / 1000);
      const name = names.next();
      bindings.push({
        name,
        kind: 'timeConstraint',
        timeOp: expr.op,
        timestamp: unix,
      });
      return name;
    }

    case 'hostCall': {
      const name = names.next();
      bindings.push({
        name,
        kind: 'hostCall',
        functionName: expr.functionName,
      });
      return name;
    }

    case 'typeHashCheck': {
      const name = names.next();
      bindings.push({
        name,
        kind: 'typeHashCheck',
        expectedHash: expr.expectedHash,
      });
      return name;
    }

    case 'deref': {
      const name = names.next();
      bindings.push({
        name,
        kind: 'deref',
      });
      return name;
    }
  }
}

/**
 * Lower a ConstraintExpr AST into an ANF IRProgram.
 *
 * The returned program's bindings are in topological order —
 * each binding only references earlier bindings by name.
 */
export function lower(expr: ConstraintExpr): IRProgram {
  const names = new NameGen();
  const bindings: IRBinding[] = [];
  const result = lowerExpr(expr, names, bindings);
  return { bindings, result };
}

```
