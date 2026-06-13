---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/grammar/__tests__/schemas.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.925620+00:00
---

# core/protocol-types/src/grammar/__tests__/schemas.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import { ValidationErrorCollector } from '../error-collector';
import { validateSchemasSection } from '../validators/schemas';

function run(g: Record<string, unknown>) {
  const errors = ValidationErrorCollector.create();
  const types = validateSchemasSection(g, errors);
  return { result: errors.toResult(), types };
}

function minimalObjectType(overrides: Record<string, unknown> = {}) {
  return {
    typePath: 'test.thing',
    displayName: 'Thing',
    description: 'A thing',
    linearity: 'AFFINE',
    phases: ['draft', 'active'],
    initialPhase: 'draft',
    payloadSchema: {
      name: { type: 'string' },
    },
    capabilities: { read: [1] },
    ...overrides,
  };
}

describe('validators/schemas (objectTypes)', () => {
  test('valid objectType passes and returns declared typePaths', () => {
    const { result, types } = run({ objectTypes: [minimalObjectType()] });
    expect(result.valid).toBe(true);
    expect(types.has('test.thing')).toBe(true);
  });

  test('non-array fails', () => {
    expect(run({ objectTypes: 'no' }).result.valid).toBe(false);
  });

  test('empty array fails', () => {
    expect(run({ objectTypes: [] }).result.valid).toBe(false);
  });

  test('invalid linearity fails', () => {
    const { result } = run({
      objectTypes: [minimalObjectType({ linearity: 'WAT' })],
    });
    expect(result.valid).toBe(false);
    expect(result.errors.some(e => e.path.endsWith('.linearity'))).toBe(true);
  });

  test('initialPhase missing from phases fails', () => {
    const { result } = run({
      objectTypes: [minimalObjectType({ initialPhase: 'ghost' })],
    });
    expect(result.valid).toBe(false);
    expect(result.errors.some(e => e.message.includes('ghost'))).toBe(true);
  });

  test('invalid payload type fails with deep path', () => {
    const { result } = run({
      objectTypes: [
        minimalObjectType({ payloadSchema: { x: { type: 'invalid' } } }),
      ],
    });
    expect(result.valid).toBe(false);
    expect(
      result.errors.some(e => e.path.endsWith('payloadSchema.x.type')),
    ).toBe(true);
  });

  test('enum without enumValues fails', () => {
    const { result } = run({
      objectTypes: [
        minimalObjectType({ payloadSchema: { e: { type: 'enum' } } }),
      ],
    });
    expect(result.valid).toBe(false);
    expect(result.errors.some(e => e.path.endsWith('.enum'))).toBe(true);
  });

  test('missing capabilities object fails', () => {
    const { result } = run({
      objectTypes: [minimalObjectType({ capabilities: undefined })],
    });
    expect(result.valid).toBe(false);
    expect(result.errors.some(e => e.path.endsWith('.capabilities'))).toBe(true);
  });

  test('transitions reference undeclared phase fails', () => {
    const { result } = run({
      objectTypes: [
        minimalObjectType({
          transitions: [{ fromPhase: 'draft', toPhase: 'ghost' }],
        }),
      ],
    });
    expect(result.valid).toBe(false);
    expect(result.errors.some(e => e.message.includes('toPhase "ghost"'))).toBe(true);
  });

  test('valid transitions pass', () => {
    const { result } = run({
      objectTypes: [
        minimalObjectType({
          transitions: [{ fromPhase: 'draft', toPhase: 'active' }],
        }),
      ],
    });
    expect(result.valid).toBe(true);
  });

  // ── CC5: tier / carrier (additive, optional) ──────────────────────
  test('CC5: tier/carrier absent ⇒ still valid (byte-identical back-compat)', () => {
    const { result } = run({ objectTypes: [minimalObjectType()] });
    expect(result.valid).toBe(true);
  });

  test('CC5: valid tier + carrier pass', () => {
    const { result } = run({
      objectTypes: [
        minimalObjectType({
          payloadSchema: {
            name: { type: 'string', tier: 'core' },
            workOrderNumber: { type: 'string', tier: 'operator-extensible' },
            jobSheet: { type: 'string', carrier: { octave: 1 } },
          },
        }),
      ],
    });
    expect(result.valid).toBe(true);
  });

  test('CC5: invalid tier fails', () => {
    const { result } = run({
      objectTypes: [
        minimalObjectType({
          payloadSchema: { name: { type: 'string', tier: 'bogus' } },
        }),
      ],
    });
    expect(result.valid).toBe(false);
  });

  test('CC5: invalid carrier (octave≠1) fails', () => {
    const { result } = run({
      objectTypes: [
        minimalObjectType({
          payloadSchema: { name: { type: 'string', carrier: { octave: 2 } } },
        }),
      ],
    });
    expect(result.valid).toBe(false);
  });
});

```
