---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/phase36a-grammar-bridge.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.583283+00:00
---

# tests/gates/phase36a-grammar-bridge.test.ts

```ts
import { describe, test, expect } from 'bun:test';
import { readFileSync } from 'fs';
import { join } from 'path';
import { grammarToExtensionConfig } from '../../core/protocol-types/src/grammar-config-bridge';
import { validateExtensionGrammar } from '../../core/protocol-types/src/extension-grammar-validator';
import type { ExtensionGrammar } from '../../core/protocol-types/src/extension-grammar';

const ROOT = join(import.meta.dir, '../..');
const PROPERTYME_GRAMMAR: ExtensionGrammar = JSON.parse(
  readFileSync(join(ROOT, 'configs/extensions/propertyme/grammar.json'), 'utf-8'),
);

/** Minimal valid grammar for testing. */
function minimalGrammar(): ExtensionGrammar {
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
  };
}

describe('Grammar-to-ExtensionConfig Bridge', () => {
  test('T1: minimal grammar produces valid ExtensionConfig', () => {
    const config = grammarToExtensionConfig(minimalGrammar());

    expect(config.id).toBe('com.test.minimal');
    expect(config.name).toBe('Minimal Test Grammar');
    expect(Array.isArray(config.objectTypes)).toBe(true);
    expect(config.objectTypes.length).toBe(1);
    expect(Array.isArray(config.capabilities)).toBe(true);
    expect(Array.isArray(config.scripts)).toBe(true);
    expect(Array.isArray(config.commercePhases)).toBe(true);
  });

  test('T2: PropertyMe grammar produces config with all 6 object types', () => {
    const config = grammarToExtensionConfig(PROPERTYME_GRAMMAR);

    expect(config.objectTypes.length).toBe(6);
    const names = config.objectTypes.map(ot => ot.name);
    expect(names).toContain('Property Listing');
    expect(names).toContain('Lease Agreement');
    expect(names).toContain('Tenant');
    expect(names).toContain('Maintenance Request');
    expect(names).toContain('Property Inspection');
    expect(names).toContain('Property Owner');
  });

  test('T3: payloadSchema maps to config fields', () => {
    const config = grammarToExtensionConfig(minimalGrammar());
    const itemType = config.objectTypes[0];

    expect(itemType.fields.length).toBe(2);

    const nameField = itemType.fields.find(f => f.name === 'name');
    expect(nameField).toBeDefined();
    expect(nameField!.type).toBe('string');

    const valueField = itemType.fields.find(f => f.name === 'value');
    expect(valueField).toBeDefined();
    expect(valueField!.type).toBe('number');
  });

  test('T4: taxonomy extensions map to config taxonomy', () => {
    const config = grammarToExtensionConfig(PROPERTYME_GRAMMAR);

    expect(config.taxonomy).toBeDefined();
    expect(config.taxonomy!.dimensions.length).toBeGreaterThan(0);

    const whatDim = config.taxonomy!.dimensions.find(d => d.id === 'what');
    expect(whatDim).toBeDefined();
    expect(whatDim!.nodes.length).toBeGreaterThan(0);
  });

  test('T5: capabilities map to config capability definitions', () => {
    const config = grammarToExtensionConfig(PROPERTYME_GRAMMAR);

    expect(config.capabilities.length).toBe(4);
    const names = config.capabilities.map(c => c.name);
    expect(names).toContain('NETWORK_OUTBOUND');
    expect(names).toContain('STORAGE_WRITE');
    expect(names).toContain('STORAGE_READ');
  });

  test('T6: typeHash is 64-char hex SHA-256', () => {
    const config = grammarToExtensionConfig(minimalGrammar());

    for (const ot of config.objectTypes) {
      expect(typeof ot.typeHash).toBe('string');
      expect(ot.typeHash.length).toBe(64);
      expect(/^[0-9a-f]{64}$/.test(ot.typeHash)).toBe(true);
    }
  });

  test('T7: PropertyMe config has correct linearity values', () => {
    const config = grammarToExtensionConfig(PROPERTYME_GRAMMAR);

    const listing = config.objectTypes.find(ot => ot.name === 'Property Listing');
    expect(listing!.linearity).toBe('AFFINE');

    const lease = config.objectTypes.find(ot => ot.name === 'Lease Agreement');
    expect(lease!.linearity).toBe('LINEAR');

    const inspection = config.objectTypes.find(ot => ot.name === 'Property Inspection');
    expect(inspection!.linearity).toBe('LINEAR');
  });

  test('T8: enum fields include values array', () => {
    const config = grammarToExtensionConfig(PROPERTYME_GRAMMAR);
    const listing = config.objectTypes.find(ot => ot.name === 'Property Listing')!;

    const propType = listing.fields.find(f => f.name === 'propertyType');
    expect(propType).toBeDefined();
    expect(propType!.type).toBe('enum');
    expect(propType!.values).toBeDefined();
    expect(propType!.values!.length).toBeGreaterThan(0);
    expect(propType!.values).toContain('house');
  });

  test('T9: commerce phases collected from all object types', () => {
    const config = grammarToExtensionConfig(PROPERTYME_GRAMMAR);

    expect(config.commercePhases.length).toBeGreaterThan(0);
    expect(config.commercePhases).toContain('draft');
    expect(config.commercePhases).toContain('active');
  });

  test('T10: date/datetime fields map to datetime type', () => {
    const config = grammarToExtensionConfig(PROPERTYME_GRAMMAR);
    const lease = config.objectTypes.find(ot => ot.name === 'Lease Agreement')!;

    const startDate = lease.fields.find(f => f.name === 'startDate');
    expect(startDate).toBeDefined();
    expect(startDate!.type).toBe('datetime');
  });

  test('T11: object types from transitions produce flows', () => {
    const config = grammarToExtensionConfig(PROPERTYME_GRAMMAR);

    // PropertyMe has several object types with transitions
    expect(config.flows).toBeDefined();
    expect(config.flows!.length).toBeGreaterThan(0);
  });

  test('T12: config has category field from typePath', () => {
    const config = grammarToExtensionConfig(PROPERTYME_GRAMMAR);

    const listing = config.objectTypes.find(ot => ot.name === 'Property Listing')!;
    expect(listing.category).toBe('property.listing');
  });
});

```
