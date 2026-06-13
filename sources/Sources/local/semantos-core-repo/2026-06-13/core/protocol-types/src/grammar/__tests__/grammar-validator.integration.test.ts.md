---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/grammar/__tests__/grammar-validator.integration.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.924211+00:00
---

# core/protocol-types/src/grammar/__tests__/grammar-validator.integration.test.ts

```ts
/**
 * Integration test for the composed orchestrator.
 *
 * Verifies that running all DEFAULT_SECTIONS through the
 * `validateExtensionGrammar` facade produces the same pass/fail
 * outcome as the legacy single-file validator. The legacy file is
 * now a re-export shim, so importing from either path should yield
 * identical results.
 */

import { describe, expect, test } from 'bun:test';
import { validateExtensionGrammar as legacyEntry } from '../../extension-grammar-validator';
import { validateExtensionGrammar } from '../grammar-validator';

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

describe('grammar-validator orchestrator (integration)', () => {
  test('valid composite grammar passes', () => {
    const r = validateExtensionGrammar(minimalGrammar());
    expect(r.valid).toBe(true);
    expect(r.errors).toHaveLength(0);
  });

  test('legacy shim re-exports the same function', () => {
    expect(legacyEntry).toBe(validateExtensionGrammar);
  });

  test('null input collects a top-level error', () => {
    const r = validateExtensionGrammar(null);
    expect(r.valid).toBe(false);
    expect(r.errors[0].path).toBe('');
  });

  test('empty object accumulates errors from every section that demands fields', () => {
    const r = validateExtensionGrammar({});
    expect(r.valid).toBe(false);
    expect(r.errors.length).toBeGreaterThan(3);
  });

  test('one bad section does not short-circuit other sections', () => {
    const g = minimalGrammar();
    // Introduce errors across multiple sections simultaneously.
    (g as any).grammarId = 'bad id';
    (g as any).capabilities[0].capability = 'bogus';
    (g as any).source.protocol = 'ftp';
    const r = validateExtensionGrammar(g);
    expect(r.valid).toBe(false);
    const paths = r.errors.map(e => e.path);
    expect(paths.some(p => p === 'grammarId')).toBe(true);
    expect(paths.some(p => p === 'source.protocol')).toBe(true);
    expect(paths.some(p => p.startsWith('capabilities['))).toBe(true);
  });

  test('reference resolution still works across sections', () => {
    const g = minimalGrammar();
    (g.entityMappings as any[])[0].sourceEntityId = 'nope';
    (g.entityMappings as any[])[0].targetObjectType = 'nope.type';
    const r = validateExtensionGrammar(g);
    expect(r.valid).toBe(false);
    expect(r.errors.some(e => e.message.includes('nope'))).toBe(true);
  });

  test('sections are dispatched in deterministic order', () => {
    // Manifest errors should come first; verbs second; bindings later.
    const r = validateExtensionGrammar({});
    const paths = r.errors.map(e => e.path);
    const manifestIdx = paths.findIndex(p => p === 'grammarId');
    const sourceIdx = paths.findIndex(p => p === 'source');
    expect(manifestIdx).toBeLessThan(sourceIdx);
  });
});

```
