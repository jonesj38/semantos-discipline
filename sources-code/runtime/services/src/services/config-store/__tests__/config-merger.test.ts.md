---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/config-store/__tests__/config-merger.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.124957+00:00
---

# runtime/services/src/services/config-store/__tests__/config-merger.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import { mergeExtensions } from '../config-merger';
import { makeConfig } from './fixtures';

describe('mergeExtensions', () => {
  test('1. domain wins on object-type name conflicts', () => {
    const core = makeConfig({
      objectTypes: [{ name: 'Job', typeHash: 'core' } as never],
    });
    const domain = makeConfig({
      objectTypes: [{ name: 'Job', typeHash: 'domain' } as never],
    });
    const merged = mergeExtensions(core, domain);
    expect(merged.objectTypes).toHaveLength(1);
    expect((merged.objectTypes[0] as { typeHash: string }).typeHash).toBe('domain');
  });

  test('2. core types without conflicts pass through', () => {
    const core = makeConfig({
      objectTypes: [{ name: 'Note' } as never, { name: 'Task' } as never],
    });
    const domain = makeConfig({
      objectTypes: [{ name: 'Job' } as never],
    });
    const merged = mergeExtensions(core, domain);
    expect(merged.objectTypes.map((t) => (t as { name: string }).name).sort()).toEqual([
      'Job',
      'Note',
      'Task',
    ]);
  });

  test('3. capabilities dedupe by id (domain wins)', () => {
    const core = makeConfig({
      capabilities: [{ id: 1, name: 'core-cap' } as never],
    });
    const domain = makeConfig({
      capabilities: [{ id: 1, name: 'domain-cap' } as never, { id: 2, name: 'extra' } as never],
    });
    const merged = mergeExtensions(core, domain);
    expect(merged.capabilities).toHaveLength(2);
    const cap1 = merged.capabilities.find((c) => c.id === 1) as { name: string };
    expect(cap1.name).toBe('domain-cap');
  });

  test('4. scripts concatenate (core first, then domain)', () => {
    const core = makeConfig({ scripts: [{ id: 'a' } as never] });
    const domain = makeConfig({ scripts: [{ id: 'b' } as never] });
    const merged = mergeExtensions(core, domain);
    expect(merged.scripts.map((s) => (s as { id: string }).id)).toEqual(['a', 'b']);
  });

  test('5. flows concatenate', () => {
    const core = makeConfig({ flows: [{ id: 'a' } as never] });
    const domain = makeConfig({ flows: [{ id: 'b' } as never] });
    const merged = mergeExtensions(core, domain);
    expect(merged.flows!.map((f) => (f as { id: string }).id)).toEqual(['a', 'b']);
  });

  test('6. taxonomy/policies/theme prefer domain when set', () => {
    const core = makeConfig({ taxonomy: { dimensions: [{ id: 'core-dim' } as never] } });
    const domain = makeConfig({ taxonomy: { dimensions: [{ id: 'domain-dim' } as never] } });
    expect(mergeExtensions(core, domain).taxonomy?.dimensions).toEqual([
      { id: 'domain-dim' } as never,
    ]);
  });

  test('7. taxonomy falls back to core when domain has none', () => {
    const core = makeConfig({ taxonomy: { dimensions: [{ id: 'c' } as never] } });
    const domain = makeConfig();
    expect(mergeExtensions(core, domain).taxonomy?.dimensions).toEqual([
      { id: 'c' } as never,
    ]);
  });

  test('8. commercePhases come from domain', () => {
    const core = makeConfig({ commercePhases: [{ id: 'core' } as never] });
    const domain = makeConfig({ commercePhases: [{ id: 'domain' } as never] });
    expect(mergeExtensions(core, domain).commercePhases).toEqual([{ id: 'domain' } as never]);
  });
});

```
