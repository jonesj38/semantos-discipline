---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/grammar/__tests__/capabilities.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.924494+00:00
---

# core/protocol-types/src/grammar/__tests__/capabilities.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import { ValidationErrorCollector } from '../error-collector';
import { validateCapabilitiesSection } from '../validators/capabilities';

function run(g: Record<string, unknown>) {
  const errors = ValidationErrorCollector.create();
  validateCapabilitiesSection(g, errors);
  return errors.toResult();
}

describe('validators/capabilities', () => {
  test('valid capability passes', () => {
    const r = run({
      capabilities: [
        { capability: 'network.outbound', reason: 'Fetch data', required: true },
      ],
    });
    expect(r.valid).toBe(true);
  });

  test('non-array fails', () => {
    const r = run({ capabilities: 'oops' });
    expect(r.valid).toBe(false);
    expect(r.errors[0].path).toBe('capabilities');
  });

  test('invalid capability id fails', () => {
    const r = run({
      capabilities: [{ capability: 'bogus.id', reason: 'x', required: true }],
    });
    expect(r.valid).toBe(false);
    expect(r.errors.some(e => e.path.endsWith('.capability'))).toBe(true);
  });

  test('missing reason fails', () => {
    const r = run({
      capabilities: [{ capability: 'storage.read', required: true }],
    });
    expect(r.valid).toBe(false);
    expect(r.errors.some(e => e.path.endsWith('.reason'))).toBe(true);
  });

  test('non-boolean required fails', () => {
    const r = run({
      capabilities: [
        { capability: 'storage.read', reason: 'x', required: 'yes' },
      ],
    });
    expect(r.valid).toBe(false);
    expect(r.errors.some(e => e.path.endsWith('.required'))).toBe(true);
  });

  test('non-object entry fails with stable path', () => {
    const r = run({ capabilities: [null] });
    expect(r.valid).toBe(false);
    expect(r.errors[0].path).toBe('capabilities[0]');
  });
});

```
