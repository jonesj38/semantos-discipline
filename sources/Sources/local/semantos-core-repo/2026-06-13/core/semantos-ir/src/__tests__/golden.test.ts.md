---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/semantos-ir/src/__tests__/golden.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.005999+00:00
---

# core/semantos-ir/src/__tests__/golden.test.ts

```ts
/**
 * Golden-file test suite for the Semantos IR nanopass pipeline.
 *
 * Each test case:
 *   1. Constructs a ConstraintExpr (typed AST node)
 *   2. Lowers it to an IRProgram via lower()
 *   3. Verifies the canonical IR JSON matches the golden snapshot
 *   4. Emits opcodes via emit()
 *   5. Compiles the same expr via LispCompiler.compileConstraint()
 *   6. Asserts byte-for-byte equivalence (the differential test)
 *
 * If a second frontend (e.g. Runar) produces the same IR for the
 * same semantics, the golden files prove equivalence.
 */

import { describe, test, expect } from 'bun:test';
import { lower } from '../lower';
import { emit } from '../emit';
import { canonicalize } from '../canonical';
import type { ConstraintExpr } from '../expr';

// ── Reference compiler for differential testing ───────────────
// We import the compileConstraint function indirectly by accessing
// the LispCompiler's internal pipeline. Since compileConstraint is
// not exported, we replicate the same flow: build a ConstraintExpr
// and use the compiler's public API via a minimal SExpression.

import { LispCompiler } from '../../../../runtime/shell/src/lisp/compiler';
import type { SExpression } from '../../../../runtime/shell/src/lisp/parser';

// Helper: create a frozen-time compiler for deterministic output
const compiler = new LispCompiler({ compiledAt: '2026-01-01T00:00:00.000Z' });

// Helper: build an SExpression atom
function atom(value: string | number, kind: 'symbol' | 'number' | 'string' = 'symbol'): SExpression {
  return { type: 'atom', value, kind, line: 1 };
}

// Helper: build an SExpression list
function list(...elements: SExpression[]): SExpression {
  return { type: 'list', elements, line: 1 };
}

// ── Test Cases ────────────────────────────────────────────────

describe('Semantos IR — Golden-File Tests', () => {

  test('G1: simple comparison (> amount 500)', () => {
    const expr: ConstraintExpr = {
      kind: 'comparison',
      op: '>',
      field: 'amount',
      value: 500,
    };

    const ir = lower(expr);
    expect(ir.bindings).toHaveLength(1);
    expect(ir.bindings[0].kind).toBe('comparison');
    expect(ir.bindings[0].op).toBe('>');
    expect(ir.bindings[0].field).toBe('amount');
    expect(ir.bindings[0].value).toBe(500);
    expect(ir.result).toBe('$0');

    // Golden IR snapshot
    const goldenIR = '{"bindings":[{"field":"amount","kind":"comparison","name":"$0","op":">","value":500}],"result":"$0"}';
    expect(canonicalize(ir)).toBe(goldenIR);

    // Differential: IR path vs direct compiler
    const irBytes = emit(ir);
    const refOutput = compiler.compile(list(atom('>'), atom('amount'), atom(500, 'number')));
    expect(Array.from(irBytes)).toEqual(Array.from(refOutput.scriptBytes));
  });

  test('G2: string comparison (= status "active")', () => {
    const expr: ConstraintExpr = {
      kind: 'comparison',
      op: '=',
      field: 'status',
      value: 'active',
    };

    const ir = lower(expr);
    expect(ir.bindings).toHaveLength(1);

    const irBytes = emit(ir);
    const refOutput = compiler.compile(list(atom('='), atom('status'), atom('active', 'string')));
    expect(Array.from(irBytes)).toEqual(Array.from(refOutput.scriptBytes));
  });

  test('G3: capability check (has-capability 3)', () => {
    const expr: ConstraintExpr = {
      kind: 'capability',
      capabilityNumber: 3,
    };

    const ir = lower(expr);
    expect(ir.bindings).toHaveLength(1);
    expect(ir.bindings[0].kind).toBe('capability');
    expect(ir.bindings[0].capabilityNumber).toBe(3);

    const irBytes = emit(ir);
    const refOutput = compiler.compile(list(atom('has-capability'), atom(3, 'number')));
    expect(Array.from(irBytes)).toEqual(Array.from(refOutput.scriptBytes));
  });

  test('G4: logical AND (and (> amount 500) (has-capability 3))', () => {
    const expr: ConstraintExpr = {
      kind: 'logical',
      op: 'and',
      operands: [
        { kind: 'comparison', op: '>', field: 'amount', value: 500 },
        { kind: 'capability', capabilityNumber: 3 },
      ],
    };

    const ir = lower(expr);
    // 2 leaf bindings + 1 logical_and = 3 bindings
    expect(ir.bindings).toHaveLength(3);
    expect(ir.bindings[2].kind).toBe('logical_and');
    expect(ir.bindings[2].operands).toEqual(['$0', '$1']);

    const irBytes = emit(ir);
    const refOutput = compiler.compile(
      list(
        atom('and'),
        list(atom('>'), atom('amount'), atom(500, 'number')),
        list(atom('has-capability'), atom(3, 'number')),
      ),
    );
    expect(Array.from(irBytes)).toEqual(Array.from(refOutput.scriptBytes));
  });

  test('G5: time constraint (time-after "2026-06-01T00:00:00Z")', () => {
    const expr: ConstraintExpr = {
      kind: 'timeConstraint',
      op: 'timeAfter',
      isoTimestamp: '2026-06-01T00:00:00Z',
    };

    const ir = lower(expr);
    expect(ir.bindings).toHaveLength(1);
    expect(ir.bindings[0].kind).toBe('timeConstraint');
    expect(ir.bindings[0].timeOp).toBe('timeAfter');
    // Unix timestamp for 2026-06-01T00:00:00Z
    expect(ir.bindings[0].timestamp).toBe(Math.floor(new Date('2026-06-01T00:00:00Z').getTime() / 1000));

    const irBytes = emit(ir);
    const refOutput = compiler.compile(
      list(atom('time-after'), atom('2026-06-01T00:00:00Z', 'string')),
    );
    expect(Array.from(irBytes)).toEqual(Array.from(refOutput.scriptBytes));
  });

  test('G6: host call (call-host "killPort")', () => {
    const expr: ConstraintExpr = {
      kind: 'hostCall',
      functionName: 'killPort',
    };

    const ir = lower(expr);
    expect(ir.bindings).toHaveLength(1);
    expect(ir.bindings[0].kind).toBe('hostCall');
    expect(ir.bindings[0].functionName).toBe('killPort');

    const irBytes = emit(ir);
    const refOutput = compiler.compile(
      list(atom('call-host'), atom('killPort', 'string')),
    );
    expect(Array.from(irBytes)).toEqual(Array.from(refOutput.scriptBytes));
  });

  test('G7: type hash check', () => {
    const hash = 'a'.repeat(64); // 64 hex chars = 32 bytes
    const expr: ConstraintExpr = {
      kind: 'typeHashCheck',
      expectedHash: hash,
    };

    const ir = lower(expr);
    expect(ir.bindings).toHaveLength(1);
    expect(ir.bindings[0].expectedHash).toBe(hash);

    const irBytes = emit(ir);
    const refOutput = compiler.compile(
      list(atom('check-type-hash'), atom(hash, 'string')),
    );
    expect(Array.from(irBytes)).toEqual(Array.from(refOutput.scriptBytes));
  });

  test('G8: deref', () => {
    const expr: ConstraintExpr = {
      kind: 'deref',
    };

    const ir = lower(expr);
    expect(ir.bindings).toHaveLength(1);
    expect(ir.bindings[0].kind).toBe('deref');

    const irBytes = emit(ir);
    const refOutput = compiler.compile(list(atom('deref')));
    expect(Array.from(irBytes)).toEqual(Array.from(refOutput.scriptBytes));
  });

  test('G9: domain check (check-domain 5)', () => {
    const expr: ConstraintExpr = {
      kind: 'domainCheck',
      domainFlag: 5,
    };

    const ir = lower(expr);
    expect(ir.bindings).toHaveLength(1);
    expect(ir.bindings[0].kind).toBe('domainCheck');

    const irBytes = emit(ir);
    const refOutput = compiler.compile(
      list(atom('check-domain'), atom(5, 'number')),
    );
    expect(Array.from(irBytes)).toEqual(Array.from(refOutput.scriptBytes));
  });

  test('G10: nested logical (or (and (> x 1) (< y 10)) (has-capability 7))', () => {
    const expr: ConstraintExpr = {
      kind: 'logical',
      op: 'or',
      operands: [
        {
          kind: 'logical',
          op: 'and',
          operands: [
            { kind: 'comparison', op: '>', field: 'x', value: 1 },
            { kind: 'comparison', op: '<', field: 'y', value: 10 },
          ],
        },
        { kind: 'capability', capabilityNumber: 7 },
      ],
    };

    const ir = lower(expr);
    // $0: comparison x>1, $1: comparison y<10, $2: and($0,$1), $3: cap(7), $4: or($2,$3)
    expect(ir.bindings).toHaveLength(5);
    expect(ir.bindings[4].kind).toBe('logical_or');
    expect(ir.bindings[4].operands).toEqual(['$2', '$3']);

    const irBytes = emit(ir);
    const refOutput = compiler.compile(
      list(
        atom('or'),
        list(
          atom('and'),
          list(atom('>'), atom('x'), atom(1, 'number')),
          list(atom('<'), atom('y'), atom(10, 'number')),
        ),
        list(atom('has-capability'), atom(7, 'number')),
      ),
    );
    expect(Array.from(irBytes)).toEqual(Array.from(refOutput.scriptBytes));
  });

  test('G11: logical NOT (not (> amount 100))', () => {
    const expr: ConstraintExpr = {
      kind: 'logical',
      op: 'not',
      operands: [
        { kind: 'comparison', op: '>', field: 'amount', value: 100 },
      ],
    };

    const ir = lower(expr);
    expect(ir.bindings).toHaveLength(2);
    expect(ir.bindings[1].kind).toBe('logical_not');

    const irBytes = emit(ir);
    const refOutput = compiler.compile(
      list(atom('not'), list(atom('>'), atom('amount'), atom(100, 'number'))),
    );
    expect(Array.from(irBytes)).toEqual(Array.from(refOutput.scriptBytes));
  });

  // ── Canonical serializer sanity check ─────────────────────

  test('G12: canonical JSON is deterministic (key order)', () => {
    const a = { z: 1, a: 2, m: 3 };
    const b = { m: 3, z: 1, a: 2 };
    expect(canonicalize(a)).toBe(canonicalize(b));
    expect(canonicalize(a)).toBe('{"a":2,"m":3,"z":1}');
  });

  test('G13: canonical JSON handles nested structures', () => {
    const ir = lower({ kind: 'capability', capabilityNumber: 42 });
    const json1 = canonicalize(ir);
    const json2 = canonicalize(ir);
    expect(json1).toBe(json2);
    expect(json1).toContain('"capabilityNumber":42');
  });
});

```
