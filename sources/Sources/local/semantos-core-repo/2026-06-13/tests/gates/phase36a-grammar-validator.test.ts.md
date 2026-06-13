---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/phase36a-grammar-validator.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.581796+00:00
---

# tests/gates/phase36a-grammar-validator.test.ts

```ts
import { describe, test, expect } from 'bun:test';
import { readFileSync } from 'fs';
import { join } from 'path';
import { validateExtensionGrammar } from '../../core/protocol-types/src/extension-grammar-validator';

const ROOT = join(import.meta.dir, '../..');
const PROPERTYME_GRAMMAR = JSON.parse(
  readFileSync(join(ROOT, 'configs/extensions/propertyme/grammar.json'), 'utf-8'),
);

/** Build a minimal valid grammar for testing. */
function minimalGrammar(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    metaSchemaVersion: '1.0.0',
    grammarId: 'com.test.minimal',
    grammarVersion: '1.0.0',
    displayName: 'Minimal Test Grammar',
    description: 'A minimal grammar for testing',
    author: { certId: 'test-cert', name: 'Test Author' },
    source: {
      protocol: 'rest',
      baseUrlTemplate: 'https://api.example.com/v1',
      auth: { type: 'api-key', requiredCredentials: ['api_key'] },
      entities: [
        {
          entityId: 'item',
          displayName: 'Item',
          endpoint: { list: '/items', get: '/items/{id}' },
          responseShape: { dataPath: '$.data.items', idField: 'id' },
          fields: [
            { sourceFieldName: 'id', sourceType: 'string', required: true },
            { sourceFieldName: 'name', sourceType: 'string', required: true },
            { sourceFieldName: 'value', sourceType: 'number', required: false },
          ],
        },
      ],
    },
    objectTypes: [
      {
        typePath: 'test.item',
        displayName: 'Test Item',
        description: 'A test item',
        linearity: 'AFFINE',
        phases: ['draft', 'active'],
        initialPhase: 'draft',
        payloadSchema: {
          name: { type: 'string', description: 'Item name' },
          value: { type: 'number', description: 'Item value' },
        },
        capabilities: { read: [1] },
      },
    ],
    entityMappings: [
      {
        sourceEntityId: 'item',
        targetObjectType: 'test.item',
        fieldMappings: [
          { sourceField: 'name', targetField: 'name', required: true },
          { sourceField: 'value', targetField: 'value', required: false },
        ],
        taxonomy: {
          what: 'what.thing.item',
          how: 'how.technical.api.rest',
          why: 'why.integration.data-sync',
        },
      },
    ],
    capabilities: [
      { capability: 'network.outbound', reason: 'Fetch data from API', required: true },
    ],
    taxonomyNamespace: 'test',
    ...overrides,
  };
}

describe('Extension Grammar Validator', () => {
  test('T1: valid minimal grammar passes', () => {
    const result = validateExtensionGrammar(minimalGrammar());
    expect(result.valid).toBe(true);
    expect(result.errors.filter(e => e.severity === 'error')).toHaveLength(0);
  });

  test('T2: valid PropertyMe grammar passes', () => {
    const result = validateExtensionGrammar(PROPERTYME_GRAMMAR);
    expect(result.valid).toBe(true);
    expect(result.errors.filter(e => e.severity === 'error')).toHaveLength(0);
  });

  test('T3: missing grammarId fails', () => {
    const g = minimalGrammar();
    delete g.grammarId;
    const result = validateExtensionGrammar(g);
    expect(result.valid).toBe(false);
    expect(result.errors.some(e => e.path === 'grammarId')).toBe(true);
  });

  test('T4: invalid grammarVersion (not semver) fails', () => {
    const result = validateExtensionGrammar(minimalGrammar({ grammarVersion: 'abc' }));
    expect(result.valid).toBe(false);
    expect(result.errors.some(e => e.path === 'grammarVersion')).toBe(true);
  });

  test('T5: invalid grammarId format fails', () => {
    const result = validateExtensionGrammar(minimalGrammar({ grammarId: 'bad id' }));
    expect(result.valid).toBe(false);
    expect(result.errors.some(e => e.path === 'grammarId')).toBe(true);
  });

  test('T6: objectType with invalid payload type fails', () => {
    const g = minimalGrammar();
    (g.objectTypes as any[])[0].payloadSchema = { bad: { type: 'invalid' } };
    const result = validateExtensionGrammar(g);
    expect(result.valid).toBe(false);
    expect(result.errors.some(e => e.path.includes('payloadSchema.bad.type'))).toBe(true);
  });

  test('T7: entityMapping with unresolved sourceEntityId fails', () => {
    const g = minimalGrammar();
    (g.entityMappings as any[])[0].sourceEntityId = 'nonexistent';
    const result = validateExtensionGrammar(g);
    expect(result.valid).toBe(false);
    expect(result.errors.some(e => e.message.includes('nonexistent'))).toBe(true);
  });

  test('T8: entityMapping with unresolved targetObjectType fails', () => {
    const g = minimalGrammar();
    (g.entityMappings as any[])[0].targetObjectType = 'nonexistent.type';
    const result = validateExtensionGrammar(g);
    expect(result.valid).toBe(false);
    expect(result.errors.some(e => e.message.includes('nonexistent.type'))).toBe(true);
  });

  test('T9: fieldMapping with unresolved sourceField fails', () => {
    const g = minimalGrammar();
    (g.entityMappings as any[])[0].fieldMappings.push({
      sourceField: 'does_not_exist',
      targetField: 'foo',
      required: false,
    });
    const result = validateExtensionGrammar(g);
    expect(result.valid).toBe(false);
    expect(result.errors.some(e => e.message.includes('does_not_exist'))).toBe(true);
  });

  test('T10: invalid source protocol fails', () => {
    const g = minimalGrammar();
    (g.source as any).protocol = 'ftp';
    const result = validateExtensionGrammar(g);
    expect(result.valid).toBe(false);
    expect(result.errors.some(e => e.path === 'source.protocol')).toBe(true);
  });

  test('T11: invalid capability identifier fails', () => {
    const g = minimalGrammar();
    (g.capabilities as any[])[0].capability = 'network.invalid';
    const result = validateExtensionGrammar(g);
    expect(result.valid).toBe(false);
    expect(result.errors.some(e => e.path.includes('capability'))).toBe(true);
  });

  test('T12: valid taxonomy extension passes', () => {
    const g = minimalGrammar({
      taxonomyExtensions: [
        {
          axis: 'what',
          parentPath: 'what.thing',
          nodes: [{ segment: 'widget', displayName: 'Widget', description: 'A widget' }],
        },
      ],
    });
    const result = validateExtensionGrammar(g);
    expect(result.valid).toBe(true);
  });

  test('T13: invalid taxonomy axis fails', () => {
    const g = minimalGrammar({
      taxonomyExtensions: [
        { axis: 'invalid', parentPath: 'foo', nodes: [{ segment: 'x', displayName: 'X', description: 'X' }] },
      ],
    });
    const result = validateExtensionGrammar(g);
    expect(result.valid).toBe(false);
    expect(result.errors.some(e => e.path.includes('axis'))).toBe(true);
  });

  test('T14: unsafe compute expression fails', () => {
    const g = minimalGrammar();
    (g.entityMappings as any[])[0].fieldMappings.push({
      sourceField: 'value',
      targetField: 'computed',
      required: false,
      transform: { type: 'compute', expression: 'eval("malicious")' },
    });
    const result = validateExtensionGrammar(g);
    expect(result.valid).toBe(false);
    expect(result.errors.some(e => e.message.includes('not safe'))).toBe(true);
  });

  test('T15: safe compute expression passes', () => {
    const g = minimalGrammar();
    (g.entityMappings as any[])[0].fieldMappings.push({
      sourceField: 'value',
      targetField: 'computed',
      required: false,
      transform: { type: 'compute', expression: 'source.value * 2' },
    });
    const result = validateExtensionGrammar(g);
    expect(result.valid).toBe(true);
  });

  test('T16: null input fails gracefully', () => {
    const result = validateExtensionGrammar(null);
    expect(result.valid).toBe(false);
  });

  test('T17: empty object collects multiple errors', () => {
    const result = validateExtensionGrammar({});
    expect(result.valid).toBe(false);
    expect(result.errors.length).toBeGreaterThan(3);
  });

  test('T18: initialPhase not in phases array fails', () => {
    const g = minimalGrammar();
    (g.objectTypes as any[])[0].initialPhase = 'nonexistent';
    const result = validateExtensionGrammar(g);
    expect(result.valid).toBe(false);
    expect(result.errors.some(e => e.message.includes('nonexistent'))).toBe(true);
  });

  test('T19: valid migration rule passes', () => {
    const g = minimalGrammar({
      migrations: [
        { fromVersion: '1.0.0', toVersion: '2.0.0', fieldRenames: { old: 'new' } },
      ],
    });
    const result = validateExtensionGrammar(g);
    expect(result.valid).toBe(true);
  });

  test('T20: invalid transform type fails', () => {
    const g = minimalGrammar();
    (g.entityMappings as any[])[0].fieldMappings.push({
      sourceField: 'name',
      targetField: 'foo',
      required: false,
      transform: { type: 'execute' },
    });
    const result = validateExtensionGrammar(g);
    expect(result.valid).toBe(false);
    expect(result.errors.some(e => e.message.includes('transform type'))).toBe(true);
  });
});

```
