---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/tests/route-helpers.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.362675+00:00
---

# runtime/shell/tests/route-helpers.test.ts

```ts
import { describe, test, expect } from 'bun:test';
import { requireObject, requireType, isShellError } from '../src/route-helpers';
import type { ShellError } from '../src/route-helpers';

// ── Minimal context factory ──────────────────────────────────

function makeCtx(objects?: Map<string, any>, objectTypes?: any[]) {
  return {
    store: {
      getState: () => ({
        objects: objects ?? new Map(),
      }),
    },
    config: {
      getConfig: () =>
        objectTypes
          ? { objectTypes }
          : null,
    },
  } as any;
}

// ── isShellError ─────────────────────────────────────────────

describe('isShellError', () => {
  test('returns true for ShellError objects', () => {
    expect(isShellError({ error: 'fail', code: 'ERR' })).toBe(true);
  });

  test('returns false for plain objects', () => {
    expect(isShellError({ id: 'obj-1', name: 'test' })).toBe(false);
  });

  test('returns false for null', () => {
    expect(isShellError(null)).toBe(false);
  });

  test('returns false for primitives', () => {
    expect(isShellError('string')).toBe(false);
    expect(isShellError(42)).toBe(false);
  });

  test('returns false for object with error but no code', () => {
    expect(isShellError({ error: 'fail' })).toBe(false);
  });
});

// ── requireObject ────────────────────────────────────────────

describe('requireObject', () => {
  test('returns MISSING_OBJECT_ID when objectId is undefined', () => {
    const ctx = makeCtx();
    const result = requireObject(ctx, undefined, 'inspect');
    expect(isShellError(result)).toBe(true);
    expect((result as ShellError).code).toBe('MISSING_OBJECT_ID');
  });

  test('returns OBJECT_NOT_FOUND when object does not exist', () => {
    const ctx = makeCtx(new Map());
    const result = requireObject(ctx, 'nonexistent', 'inspect');
    expect(isShellError(result)).toBe(true);
    expect((result as ShellError).code).toBe('OBJECT_NOT_FOUND');
  });

  test('returns object when it exists', () => {
    const obj = { id: 'obj-1', name: 'Test' };
    const objects = new Map([['obj-1', obj]]);
    const ctx = makeCtx(objects);
    const result = requireObject(ctx, 'obj-1', 'inspect');
    expect(isShellError(result)).toBe(false);
    expect((result as any).id).toBe('obj-1');
  });

  test('error message includes verb name', () => {
    const ctx = makeCtx();
    const result = requireObject(ctx, undefined, 'patch') as ShellError;
    expect(result.error).toContain("'patch'");
  });
});

// ── requireType ──────────────────────────────────────────────

describe('requireType', () => {
  test('returns MISSING_TYPE_PATH when typePath is undefined', () => {
    const ctx = makeCtx(new Map(), []);
    const result = requireType(ctx, undefined, 'new');
    expect(isShellError(result)).toBe(true);
    expect((result as ShellError).code).toBe('MISSING_TYPE_PATH');
  });

  test('returns NO_CONFIG when no config loaded', () => {
    const ctx = makeCtx();
    // config.getConfig() returns null
    const result = requireType(ctx, 'Job', 'new');
    expect(isShellError(result)).toBe(true);
    expect((result as ShellError).code).toBe('NO_CONFIG');
  });

  test('returns UNKNOWN_TYPE for nonexistent type', () => {
    const types = [{ name: 'Job', category: 'trades' }];
    const ctx = makeCtx(new Map(), types);
    const result = requireType(ctx, 'Nonexistent', 'new');
    expect(isShellError(result)).toBe(true);
    expect((result as ShellError).code).toBe('UNKNOWN_TYPE');
  });

  test('resolves type by short name', () => {
    const types = [{ name: 'Job', category: 'trades' }];
    const ctx = makeCtx(new Map(), types);
    const result = requireType(ctx, 'Job', 'new');
    expect(isShellError(result)).toBe(false);
    expect((result as any).name).toBe('Job');
  });

  test('resolves type by full category.name path', () => {
    const types = [{ name: 'Job', category: 'trades' }];
    const ctx = makeCtx(new Map(), types);
    const result = requireType(ctx, 'trades.Job', 'new');
    expect(isShellError(result)).toBe(false);
    expect((result as any).name).toBe('Job');
  });

  test('case-insensitive matching', () => {
    const types = [{ name: 'Job', category: 'trades' }];
    const ctx = makeCtx(new Map(), types);
    const result = requireType(ctx, 'TRADES.JOB', 'new');
    expect(isShellError(result)).toBe(false);
    expect((result as any).name).toBe('Job');
  });

  test('error includes available types', () => {
    const types = [{ name: 'Job' }, { name: 'Quote' }];
    const ctx = makeCtx(new Map(), types);
    const result = requireType(ctx, 'Nonexistent', 'new') as ShellError;
    expect(result.error).toContain('Job');
    expect(result.error).toContain('Quote');
  });
});

```
