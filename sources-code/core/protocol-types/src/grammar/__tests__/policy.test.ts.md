---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/grammar/__tests__/policy.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.925904+00:00
---

# core/protocol-types/src/grammar/__tests__/policy.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import { ValidationErrorCollector } from '../error-collector';
import { validatePolicySection } from '../validators/policy';

function run(g: Record<string, unknown>) {
  const errors = ValidationErrorCollector.create();
  validatePolicySection(g, errors);
  return errors.toResult();
}

describe('validators/policy (taxonomyExtensions)', () => {
  test('absent taxonomyExtensions is OK', () => {
    expect(run({}).valid).toBe(true);
  });

  test('non-array fails', () => {
    const r = run({ taxonomyExtensions: 'no' });
    expect(r.valid).toBe(false);
  });

  test('valid extension passes', () => {
    const r = run({
      taxonomyExtensions: [
        {
          axis: 'what',
          parentPath: 'what.thing',
          nodes: [{ segment: 'x', displayName: 'X', description: 'X' }],
        },
      ],
    });
    expect(r.valid).toBe(true);
  });

  test('invalid axis fails', () => {
    const r = run({
      taxonomyExtensions: [
        { axis: 'whence', parentPath: 'p', nodes: [{ segment: 'x', displayName: 'X', description: 'X' }] },
      ],
    });
    expect(r.valid).toBe(false);
    expect(r.errors.some(e => e.path.endsWith('.axis'))).toBe(true);
  });

  test('empty nodes fails', () => {
    const r = run({
      taxonomyExtensions: [{ axis: 'what', parentPath: 'p', nodes: [] }],
    });
    expect(r.valid).toBe(false);
    expect(r.errors.some(e => e.path.endsWith('.nodes'))).toBe(true);
  });

  test('recurses into children', () => {
    const r = run({
      taxonomyExtensions: [
        {
          axis: 'how',
          parentPath: 'how.api',
          nodes: [
            {
              segment: 'rest',
              displayName: 'REST',
              description: 'REST APIs',
              children: [{ segment: 'v1', displayName: 'V1', description: 'V1' }],
            },
          ],
        },
      ],
    });
    expect(r.valid).toBe(true);
  });

  test('child with bad shape fails with deep path', () => {
    const r = run({
      taxonomyExtensions: [
        {
          axis: 'why',
          parentPath: 'why',
          nodes: [
            {
              segment: 'a',
              displayName: 'A',
              description: 'A',
              children: 'oops',
            },
          ],
        },
      ],
    });
    expect(r.valid).toBe(false);
    expect(
      r.errors.some(e => e.path.endsWith('.children')),
    ).toBe(true);
  });
});

```
