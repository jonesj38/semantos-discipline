---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/tests/hostcall_compiler.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.362149+00:00
---

# runtime/shell/tests/hostcall_compiler.test.ts

```ts
// Phase 25.5 Gate Tests: Lisp Compiler OP_CALLHOST (D25.5.3)

import { describe, test, expect } from 'bun:test';
import { LispCompiler } from '../src/lisp/compiler';
import { parseExpression } from '../src/lisp/parser';

const OP_CALLHOST = 0xD0;

const compiler = new LispCompiler({ compiledAt: '2026-03-31T00:00:00Z' });

describe('D25.5.3 — Lisp compiler OP_CALLHOST', () => {
  test('(call-host "diagonal-path?") compiles to push + 0xD0', () => {
    const expr = parseExpression('(call-host "diagonal-path?")');
    const result = compiler.compile(expr);
    expect(result.scriptWords).toContain('"diagonal-path?" OP_CALLHOST');
    // Last byte should be OP_CALLHOST
    expect(result.scriptBytes[result.scriptBytes.length - 1]).toBe(OP_CALLHOST);
  });

  test('(diagonal-path?) sugar compiles same as explicit form', () => {
    const explicit = parseExpression('(call-host "diagonal-path?")');
    const sugar = parseExpression('(diagonal-path?)');
    const explicitResult = compiler.compile(explicit);
    const sugarResult = compiler.compile(sugar);
    expect(sugarResult.scriptWords).toContain('"diagonal-path?" OP_CALLHOST');
    // Both should produce identical bytes
    expect(Array.from(sugarResult.scriptBytes)).toEqual(
      Array.from(explicitResult.scriptBytes),
    );
  });

  test('bare predicate in (and ...) compiles correctly', () => {
    const expr = parseExpression('(and (= amount 500) (is-boss?))');
    const result = compiler.compile(expr);
    expect(result.scriptWords).toContain('"is-boss?" OP_CALLHOST');
    expect(result.scriptWords).toContain('BOOLAND');
    // Bytes should contain OP_CALLHOST
    expect(Array.from(result.scriptBytes)).toContain(OP_CALLHOST);
  });

  test('compilation is deterministic (same input = same bytes)', () => {
    const expr1 = parseExpression('(call-host "test-fn?")');
    const expr2 = parseExpression('(call-host "test-fn?")');
    const r1 = compiler.compile(expr1);
    const r2 = compiler.compile(expr2);
    expect(Array.from(r1.scriptBytes)).toEqual(Array.from(r2.scriptBytes));
    expect(r1.scriptWords).toBe(r2.scriptWords);
  });

  test('existing expressions compile unchanged — (> amount 500)', () => {
    const expr = parseExpression('(> amount 500)');
    const result = compiler.compile(expr);
    // Should NOT contain OP_CALLHOST
    expect(Array.from(result.scriptBytes)).not.toContain(OP_CALLHOST);
    expect(result.scriptWords).toContain('AMOUNT-GT');
  });

  test('(= status "active") still produces same bytes as before', () => {
    const expr = parseExpression('(= status "active")');
    const result = compiler.compile(expr);
    expect(result.scriptWords).toContain('STATUS-EQ');
    expect(Array.from(result.scriptBytes)).not.toContain(OP_CALLHOST);
  });

  test('(has-capability 3) still produces old opcode, not host call', () => {
    const expr = parseExpression('(has-capability 3)');
    const result = compiler.compile(expr);
    expect(result.scriptWords).toContain('CHECK-CAP');
    expect(Array.from(result.scriptBytes)).not.toContain(OP_CALLHOST);
  });
});

```
