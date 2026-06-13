---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/grammar/__tests__/bindings.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.925060+00:00
---

# core/protocol-types/src/grammar/__tests__/bindings.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import { ValidationErrorCollector } from '../error-collector';
import {
  validateBindingsSection,
  type BindingRefs,
} from '../validators/bindings';

const REFS: BindingRefs = {
  declaredEntityIds: new Set(['item']),
  declaredObjectTypes: new Set(['test.item']),
  declaredSourceFields: new Map([
    ['item', new Set(['id', 'name', 'value'])],
  ]),
};

function run(g: Record<string, unknown>) {
  const errors = ValidationErrorCollector.create();
  validateBindingsSection(g, REFS, errors);
  return errors.toResult();
}

function minimalMapping(overrides: Record<string, unknown> = {}) {
  return {
    sourceEntityId: 'item',
    targetObjectType: 'test.item',
    fieldMappings: [
      { sourceField: 'name', targetField: 'name', required: true },
    ],
    taxonomy: {
      what: 'what.thing',
      how: 'how.api',
      why: 'why.sync',
    },
    ...overrides,
  };
}

describe('validators/bindings (entityMappings)', () => {
  test('valid mapping passes', () => {
    expect(run({ entityMappings: [minimalMapping()] }).valid).toBe(true);
  });

  test('non-array fails', () => {
    expect(run({ entityMappings: 42 }).valid).toBe(false);
  });

  test('unresolved sourceEntityId fails', () => {
    const r = run({
      entityMappings: [minimalMapping({ sourceEntityId: 'ghost' })],
    });
    expect(r.valid).toBe(false);
    expect(r.errors.some(e => e.message.includes('ghost'))).toBe(true);
  });

  test('unresolved targetObjectType fails', () => {
    const r = run({
      entityMappings: [minimalMapping({ targetObjectType: 'no.such.type' })],
    });
    expect(r.valid).toBe(false);
    expect(r.errors.some(e => e.message.includes('no.such.type'))).toBe(true);
  });

  test('unresolved sourceField fails', () => {
    const r = run({
      entityMappings: [
        minimalMapping({
          fieldMappings: [
            { sourceField: 'phantom', targetField: 'p', required: false },
          ],
        }),
      ],
    });
    expect(r.valid).toBe(false);
    expect(r.errors.some(e => e.message.includes('phantom'))).toBe(true);
  });

  test('dotted sourceField resolved by root', () => {
    const r = run({
      entityMappings: [
        minimalMapping({
          fieldMappings: [
            { sourceField: 'name.first', targetField: 'first', required: false },
          ],
        }),
      ],
    });
    expect(r.valid).toBe(true);
  });

  test('missing taxonomy fails', () => {
    const r = run({
      entityMappings: [minimalMapping({ taxonomy: undefined })],
    });
    expect(r.valid).toBe(false);
    expect(r.errors.some(e => e.path.endsWith('.taxonomy'))).toBe(true);
  });

  test('partial taxonomy fails', () => {
    const r = run({
      entityMappings: [minimalMapping({ taxonomy: { what: 'x' } })],
    });
    expect(r.valid).toBe(false);
    expect(r.errors.some(e => e.message.includes('how'))).toBe(true);
  });

  test('invalid linearityOverride fails', () => {
    const r = run({
      entityMappings: [minimalMapping({ linearityOverride: 'WAT' })],
    });
    expect(r.valid).toBe(false);
  });

  test('valid condition passes', () => {
    const r = run({
      entityMappings: [
        minimalMapping({
          condition: { field: 'status', operator: 'eq', value: 'on' },
        }),
      ],
    });
    expect(r.valid).toBe(true);
  });

  test('bad condition operator fails', () => {
    const r = run({
      entityMappings: [
        minimalMapping({
          condition: { field: 'status', operator: 'xx', value: 'on' },
        }),
      ],
    });
    expect(r.valid).toBe(false);
  });

  test('invalid visibility fails', () => {
    const r = run({
      entityMappings: [
        minimalMapping({
          fieldMappings: [
            {
              sourceField: 'name',
              targetField: 'name',
              required: true,
              visibility: 'invisible',
            },
          ],
        }),
      ],
    });
    expect(r.valid).toBe(false);
  });

  test('safe compute transform passes', () => {
    const r = run({
      entityMappings: [
        minimalMapping({
          fieldMappings: [
            {
              sourceField: 'value',
              targetField: 'computed',
              required: false,
              transform: { type: 'compute', expression: 'source.value * 2' },
            },
          ],
        }),
      ],
    });
    expect(r.valid).toBe(true);
  });

  test('unsafe compute transform fails', () => {
    const r = run({
      entityMappings: [
        minimalMapping({
          fieldMappings: [
            {
              sourceField: 'value',
              targetField: 'computed',
              required: false,
              transform: { type: 'compute', expression: 'eval("nope")' },
            },
          ],
        }),
      ],
    });
    expect(r.valid).toBe(false);
    expect(r.errors.some(e => e.message.includes('not safe'))).toBe(true);
  });

  test('invalid transform type fails', () => {
    const r = run({
      entityMappings: [
        minimalMapping({
          fieldMappings: [
            {
              sourceField: 'name',
              targetField: 'foo',
              required: false,
              transform: { type: 'execute' },
            },
          ],
        }),
      ],
    });
    expect(r.valid).toBe(false);
    expect(r.errors.some(e => e.message.includes('transform type'))).toBe(true);
  });
});

```
