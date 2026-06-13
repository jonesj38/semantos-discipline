---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests-bun/hostcall_registry.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.986995+00:00
---

# core/cell-engine/tests-bun/hostcall_registry.test.ts

```ts
// Phase 25.5 Gate Tests: HostFunctionRegistry (D25.5.2)
// Pure TypeScript tests — no WASM needed.

import { describe, test, expect } from 'bun:test';
import { HostFunctionRegistry } from '../bindings/host-functions';
import { registerBuiltinHostFunctions } from '../bindings/builtin-host-functions';

describe('D25.5.2 — HostFunctionRegistry', () => {
  test('register and call a named function', () => {
    const registry = new HostFunctionRegistry();
    registry.register('is-boss?', () => 1);
    registry.setContext({});
    expect(registry.call('is-boss?')).toBe(1);
  });

  test('setContext freezes the context object', () => {
    const registry = new HostFunctionRegistry();
    let capturedCtx: Record<string, unknown> = {};
    registry.register('capture', (ctx) => {
      capturedCtx = ctx as Record<string, unknown>;
      return 1;
    });
    registry.setContext({ name: 'alice' });
    registry.call('capture');
    expect(capturedCtx.name).toBe('alice');
    // Context should be frozen
    expect(() => {
      (capturedCtx as Record<string, unknown>).name = 'bob';
    }).toThrow();
  });

  test('clearContext removes all context fields', () => {
    const registry = new HostFunctionRegistry();
    let ctxKeys: string[] = [];
    registry.register('check', (ctx) => {
      ctxKeys = Object.keys(ctx);
      return 0;
    });
    registry.setContext({ a: 1, b: 2 });
    registry.clearContext();
    registry.call('check');
    expect(ctxKeys.length).toBe(0);
  });

  test('call with unknown name returns sentinel 0xFFFFFFFF', () => {
    const registry = new HostFunctionRegistry();
    expect(registry.call('nonexistent')).toBe(0xFFFFFFFF);
  });

  test('list() returns all registered function names', () => {
    const registry = new HostFunctionRegistry();
    registry.register('a', () => 0);
    registry.register('b', () => 1);
    registry.register('c', () => 2);
    expect(registry.list().sort()).toEqual(['a', 'b', 'c']);
  });

  test('has() returns true for registered, false for unknown', () => {
    const registry = new HostFunctionRegistry();
    registry.register('exists', () => 1);
    expect(registry.has('exists')).toBe(true);
    expect(registry.has('missing')).toBe(false);
  });

  test('multiple functions can be registered and dispatched', () => {
    const registry = new HostFunctionRegistry();
    registry.register('fn-a', () => 10);
    registry.register('fn-b', () => 20);
    registry.register('fn-c', () => 30);
    registry.setContext({});
    expect(registry.call('fn-a')).toBe(10);
    expect(registry.call('fn-b')).toBe(20);
    expect(registry.call('fn-c')).toBe(30);
  });

  test('host function receives correct context values', () => {
    const registry = new HostFunctionRegistry();
    registry.register('check-value', (ctx) => {
      return ctx.amount === 500 ? 1 : 0;
    });
    registry.setContext({ amount: 500 });
    expect(registry.call('check-value')).toBe(1);
    registry.setContext({ amount: 100 });
    expect(registry.call('check-value')).toBe(0);
  });
});

describe('D25.5.5 — Built-in host functions', () => {
  test('field-eq? returns 1 when field matches', () => {
    const registry = new HostFunctionRegistry();
    registerBuiltinHostFunctions(registry);
    registry.setContext({
      fields: { color: 'red' },
      _currentField: 'color',
      _currentValue: 'red',
    });
    expect(registry.call('field-eq?')).toBe(1);
  });

  test('field-eq? returns 0 when field does not match', () => {
    const registry = new HostFunctionRegistry();
    registerBuiltinHostFunctions(registry);
    registry.setContext({
      fields: { color: 'blue' },
      _currentField: 'color',
      _currentValue: 'red',
    });
    expect(registry.call('field-eq?')).toBe(0);
  });

  test('field-gt? returns 1 when field > value', () => {
    const registry = new HostFunctionRegistry();
    registerBuiltinHostFunctions(registry);
    registry.setContext({
      fields: { amount: 1000 },
      _currentField: 'amount',
      _currentValue: 500,
    });
    expect(registry.call('field-gt?')).toBe(1);
  });

  test('field-lt? returns 1 when field < value', () => {
    const registry = new HostFunctionRegistry();
    registerBuiltinHostFunctions(registry);
    registry.setContext({
      fields: { pressure: 100 },
      _currentField: 'pressure',
      _currentValue: 150,
    });
    expect(registry.call('field-lt?')).toBe(1);
  });

  test('has-capability? returns 1 when capability present', () => {
    const registry = new HostFunctionRegistry();
    registerBuiltinHostFunctions(registry);
    registry.setContext({
      capabilities: [1, 3, 5],
      _currentValue: 3,
    });
    expect(registry.call('has-capability?')).toBe(1);
  });

  test('has-capability? returns 0 when capability missing', () => {
    const registry = new HostFunctionRegistry();
    registerBuiltinHostFunctions(registry);
    registry.setContext({
      capabilities: [1, 3, 5],
      _currentValue: 7,
    });
    expect(registry.call('has-capability?')).toBe(0);
  });

  test('all four built-in functions are registered', () => {
    const registry = new HostFunctionRegistry();
    registerBuiltinHostFunctions(registry);
    expect(registry.has('field-eq?')).toBe(true);
    expect(registry.has('field-gt?')).toBe(true);
    expect(registry.has('field-lt?')).toBe(true);
    expect(registry.has('has-capability?')).toBe(true);
  });
});

```
