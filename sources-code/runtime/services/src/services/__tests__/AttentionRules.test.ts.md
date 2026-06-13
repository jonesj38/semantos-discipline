---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/__tests__/AttentionRules.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.110322+00:00
---

# runtime/services/src/services/__tests__/AttentionRules.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import { AttentionRules, compilePattern } from '../AttentionRules';
import type { LoomObject } from '../../types/loom';
import type { CellHeader } from '@semantos/protocol-types/browser';

function makeObj(over: Partial<LoomObject> = {}): LoomObject {
  const header: CellHeader = {
    version: 1,
    linearity: 3,
    fieldHeader: 0,
    sigSet: 0,
  } as unknown as CellHeader;
  return {
    id: over.id ?? 'obj-1',
    typeDefinition: over.typeDefinition ?? { name: 'TestType', fields: [], category: 'misc' } as any,
    header,
    payload: over.payload ?? {},
    patches: over.patches ?? [],
    visibility: over.visibility ?? 'draft',
    createdAt: over.createdAt ?? 0,
    updatedAt: over.updatedAt ?? 0,
    ...over,
  } as LoomObject;
}

describe('compilePattern', () => {
  test('exact-name match', () => {
    const p = compilePattern('TestType');
    expect(p(makeObj())).toBe(true);
    expect(p(makeObj({ typeDefinition: { name: 'Other', fields: [], category: 'misc' } as any }))).toBe(false);
  });

  test('glob match', () => {
    const p = compilePattern('Test*');
    expect(p(makeObj())).toBe(true);
    expect(p(makeObj({ typeDefinition: { name: 'TestVariant', fields: [], category: 'misc' } as any }))).toBe(true);
    expect(p(makeObj({ typeDefinition: { name: 'OtherType', fields: [], category: 'misc' } as any }))).toBe(false);
  });

  test('structured field filter — from:', () => {
    const p = compilePattern('from:foo@example.com');
    expect(p(makeObj({ payload: { from: 'foo@example.com' } }))).toBe(true);
    expect(p(makeObj({ payload: { from: 'bar@example.com' } }))).toBe(false);
  });
});

describe('AttentionRules', () => {
  test('pin causes evaluate.pinned=true', async () => {
    const r = new AttentionRules();
    await r.pin('TestType');
    const e = r.evaluate(makeObj());
    expect(e.pinned).toBe(true);
    expect(e.suppressed).toBe(false);
  });

  test('suppress prevents pinning siblings but pin overrides for matched object', async () => {
    const r = new AttentionRules();
    await r.suppress('TestType');
    expect(r.evaluate(makeObj()).suppressed).toBe(true);
    await r.pin('obj-1');
    const e = r.evaluate(makeObj({ id: 'obj-1' }));
    expect(e.pinned).toBe(true);
    expect(e.suppressed).toBe(false);
  });

  test('must-show contributes a boost', async () => {
    const r = new AttentionRules();
    await r.mustShow('TestType', 0.30);
    expect(r.evaluate(makeObj()).boost).toBe(0.30);
  });

  test('class-boost is multiplicative', async () => {
    const r = new AttentionRules();
    await r.classBoost('TestType', 1.5);
    expect(r.evaluate(makeObj()).multiplier).toBeCloseTo(1.5);
  });

  test('history records every commit', async () => {
    const r = new AttentionRules();
    await r.pin('a');
    await r.suppress('b');
    await r.unsuppress('b');
    expect(r.getHistory().length).toBe(3);
    expect(r.getHistory()[0].action).toBe('pin');
  });

  test('expired pin is ignored', async () => {
    const r = new AttentionRules();
    const past = new Date(Date.now() - 1000).toISOString();
    await r.pin('TestType', { until: past });
    expect(r.evaluate(makeObj()).pinned).toBe(false);
  });
});

```
