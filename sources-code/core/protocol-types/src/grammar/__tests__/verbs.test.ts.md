---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/grammar/__tests__/verbs.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.923911+00:00
---

# core/protocol-types/src/grammar/__tests__/verbs.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import { ValidationErrorCollector } from '../error-collector';
import { validateVerbsSection } from '../validators/verbs';

function run(g: Record<string, unknown>) {
  const errors = ValidationErrorCollector.create();
  const collected = validateVerbsSection(g, errors);
  return { result: errors.toResult(), collected };
}

function minimalSource(overrides: Record<string, unknown> = {}) {
  return {
    source: {
      protocol: 'rest',
      baseUrlTemplate: 'https://api.example.com/v1',
      auth: { type: 'api-key', requiredCredentials: ['key'] },
      entities: [
        {
          entityId: 'item',
          displayName: 'Item',
          endpoint: { list: '/items', get: '/items/{id}' },
          responseShape: { dataPath: '$.data', idField: 'id' },
          fields: [
            { sourceFieldName: 'id', sourceType: 'string', required: true },
            { sourceFieldName: 'name', sourceType: 'string', required: false },
          ],
        },
      ],
      ...overrides,
    },
  };
}

describe('validators/verbs (source declaration)', () => {
  test('minimal source passes and exposes entityIds + fields', () => {
    const { result, collected } = run(minimalSource());
    expect(result.valid).toBe(true);
    expect(collected.declaredEntityIds.has('item')).toBe(true);
    expect(collected.declaredSourceFields.get('item')?.has('name')).toBe(true);
  });

  test('missing source fails', () => {
    const { result } = run({});
    expect(result.valid).toBe(false);
    expect(result.errors[0].path).toBe('source');
  });

  test('invalid protocol fails', () => {
    const { result } = run(minimalSource({ protocol: 'ftp' }));
    expect(result.valid).toBe(false);
    expect(result.errors.some(e => e.path === 'source.protocol')).toBe(true);
  });

  test('invalid auth type fails', () => {
    const { result } = run(
      minimalSource({ auth: { type: 'magic', requiredCredentials: [] } }),
    );
    expect(result.valid).toBe(false);
    expect(result.errors.some(e => e.path === 'source.auth.type')).toBe(true);
  });

  test('non-array requiredCredentials fails', () => {
    const { result } = run(
      minimalSource({ auth: { type: 'api-key', requiredCredentials: 'k' } }),
    );
    expect(result.valid).toBe(false);
    expect(
      result.errors.some(e => e.path === 'source.auth.requiredCredentials'),
    ).toBe(true);
  });

  test('valid pagination passes', () => {
    const { result } = run(
      minimalSource({ pagination: { type: 'cursor', pageSize: 50 } }),
    );
    expect(result.valid).toBe(true);
  });

  test('invalid pagination type fails', () => {
    const { result } = run(
      minimalSource({ pagination: { type: 'shrugs', pageSize: 50 } }),
    );
    expect(result.valid).toBe(false);
    expect(result.errors.some(e => e.path === 'source.pagination.type')).toBe(true);
  });

  test('non-positive pageSize fails', () => {
    const { result } = run(
      minimalSource({ pagination: { type: 'cursor', pageSize: 0 } }),
    );
    expect(result.valid).toBe(false);
    expect(
      result.errors.some(e => e.path === 'source.pagination.pageSize'),
    ).toBe(true);
  });

  test('empty entities fails', () => {
    const { result } = run(minimalSource({ entities: [] }));
    expect(result.valid).toBe(false);
    expect(result.errors.some(e => e.path === 'source.entities')).toBe(true);
  });

  test('source field with invalid sourceType fails', () => {
    const g = minimalSource();
    (g.source.entities[0] as any).fields[0].sourceType = 'blob';
    const { result } = run(g);
    expect(result.valid).toBe(false);
    expect(
      result.errors.some(e => e.path.endsWith('.sourceType')),
    ).toBe(true);
  });

  test('enum field without enumValues fails', () => {
    const g = minimalSource();
    (g.source.entities[0] as any).fields[0] = {
      sourceFieldName: 'kind',
      sourceType: 'enum',
      required: true,
    };
    const { result } = run(g);
    expect(result.valid).toBe(false);
    expect(
      result.errors.some(e => e.path.endsWith('.enumValues')),
    ).toBe(true);
  });

  test('valid relationship passes', () => {
    const g = minimalSource();
    (g.source.entities[0] as any).relationships = [
      {
        targetEntityId: 'other',
        type: 'has_many',
        foreignKey: 'item_id',
        foreignKeyLocation: 'target',
      },
    ];
    expect(run(g).result.valid).toBe(true);
  });

  test('relationship with bad type fails', () => {
    const g = minimalSource();
    (g.source.entities[0] as any).relationships = [
      {
        targetEntityId: 'other',
        type: 'foo',
        foreignKey: 'k',
        foreignKeyLocation: 'source',
      },
    ];
    expect(run(g).result.valid).toBe(false);
  });

  test('relationship with bad foreignKeyLocation fails', () => {
    const g = minimalSource();
    (g.source.entities[0] as any).relationships = [
      {
        targetEntityId: 'other',
        type: 'has_one',
        foreignKey: 'k',
        foreignKeyLocation: 'middle',
      },
    ];
    expect(run(g).result.valid).toBe(false);
  });
});

```
