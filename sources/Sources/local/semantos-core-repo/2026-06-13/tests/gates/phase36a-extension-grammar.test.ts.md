---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/phase36a-extension-grammar.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.570658+00:00
---

# tests/gates/phase36a-extension-grammar.test.ts

```ts
/**
 * Phase 36A Gate Tests — Extension Grammar JSON Schema
 *
 * T1–T6:   Schema / type exports
 * T7–T12:  Validator correctness
 * T13–T16: Bridge correctness
 * T17–T18: Shell command integration
 * T19–T22: Reference grammar (PropertyMe)
 */

import { describe, test, expect } from 'bun:test';
import { readFileSync, existsSync } from 'fs';
import { join } from 'path';

const ROOT = join(import.meta.dir, '../..');

// ── Schema Completeness (T1–T6) ─────────────────────────────────

describe('Phase 36A — Schema completeness', () => {
  const indexSource = readFileSync(
    join(ROOT, 'core/protocol-types/src/index.ts'),
    'utf-8',
  );

  test('T1: ExtensionGrammar type is exported from barrel', () => {
    expect(indexSource).toContain('ExtensionGrammar');
  });

  test('T2: validateExtensionGrammar is exported from barrel', () => {
    expect(indexSource).toContain('validateExtensionGrammar');
  });

  test('T3: grammarToExtensionConfig is exported from barrel', () => {
    expect(indexSource).toContain('grammarToExtensionConfig');
  });

  test('T4: loadExtensionGrammar and resolveGrammarExtends exported', () => {
    expect(indexSource).toContain('loadExtensionGrammar');
    expect(indexSource).toContain('resolveGrammarExtends');
  });

  test('T5: grammar verb registered in parser', () => {
    const parserSource = readFileSync(
      join(ROOT, 'runtime/shell/src/parser.ts'),
      'utf-8',
    );
    expect(parserSource).toContain("'grammar'");
  });

  test('T6: grammar command routed in router', () => {
    const routerSource = readFileSync(
      join(ROOT, 'runtime/shell/src/router.ts'),
      'utf-8',
    );
    expect(routerSource).toContain('routeGrammar');
    expect(routerSource).toContain("case 'grammar'");
  });
});

// ── Validator Correctness (T7–T12) ──────────────────────────────

describe('Phase 36A — Validator correctness', () => {
  // Dynamic imports to test real module resolution
  const { validateExtensionGrammar } = require(
    join(ROOT, 'core/protocol-types/src/extension-grammar-validator'),
  );

  const propertymeGrammar = JSON.parse(
    readFileSync(join(ROOT, 'configs/extensions/propertyme/grammar.json'), 'utf-8'),
  );

  test('T7: valid PropertyMe grammar passes validation', () => {
    const result = validateExtensionGrammar(propertymeGrammar);
    expect(result.valid).toBe(true);
  });

  test('T8: missing required fields are detected', () => {
    const result = validateExtensionGrammar({});
    expect(result.valid).toBe(false);
    expect(result.errors.length).toBeGreaterThan(3);
  });

  test('T9: invalid semver grammarVersion is rejected', () => {
    const bad = { ...propertymeGrammar, grammarVersion: 'not-semver' };
    const result = validateExtensionGrammar(bad);
    expect(result.valid).toBe(false);
    expect(result.errors.some((e: any) => e.path === 'grammarVersion')).toBe(true);
  });

  test('T10: unresolved entity references are detected', () => {
    const bad = {
      ...propertymeGrammar,
      entityMappings: [
        {
          ...propertymeGrammar.entityMappings[0],
          sourceEntityId: 'nonexistent_entity',
        },
      ],
    };
    const result = validateExtensionGrammar(bad);
    expect(result.valid).toBe(false);
    expect(result.errors.some((e: any) => e.message.includes('nonexistent_entity'))).toBe(true);
  });

  test('T11: unresolved field references are detected', () => {
    const bad = JSON.parse(JSON.stringify(propertymeGrammar));
    bad.entityMappings[0].fieldMappings.push({
      sourceField: 'totally_fake_field',
      targetField: 'fake',
      required: false,
    });
    const result = validateExtensionGrammar(bad);
    expect(result.valid).toBe(false);
    expect(result.errors.some((e: any) => e.message.includes('totally_fake_field'))).toBe(true);
  });

  test('T12: unsafe compute expression is rejected', () => {
    const bad = JSON.parse(JSON.stringify(propertymeGrammar));
    bad.entityMappings[0].fieldMappings.push({
      sourceField: 'bedrooms',
      targetField: 'exploit',
      required: false,
      transform: { type: 'compute', expression: 'require("child_process").exec("rm -rf /")' },
    });
    const result = validateExtensionGrammar(bad);
    expect(result.valid).toBe(false);
    expect(result.errors.some((e: any) => e.message.includes('not safe'))).toBe(true);
  });
});

// ── Bridge Correctness (T13–T16) ────────────────────────────────

describe('Phase 36A — Bridge correctness', () => {
  const { grammarToExtensionConfig } = require(
    join(ROOT, 'core/protocol-types/src/grammar-config-bridge'),
  );

  const propertymeGrammar = JSON.parse(
    readFileSync(join(ROOT, 'configs/extensions/propertyme/grammar.json'), 'utf-8'),
  );

  test('T13: grammarToExtensionConfig produces valid ExtensionConfig', () => {
    const config = grammarToExtensionConfig(propertymeGrammar);
    expect(config.id).toBe('com.semantos.propertyme');
    expect(config.name).toBe('PropertyMe Property Management');
    expect(Array.isArray(config.objectTypes)).toBe(true);
    expect(config.objectTypes.length).toBe(6);
  });

  test('T14: all object types have 64-char hex typeHash', () => {
    const config = grammarToExtensionConfig(propertymeGrammar);
    for (const ot of config.objectTypes) {
      expect(typeof ot.typeHash).toBe('string');
      expect(ot.typeHash.length).toBe(64);
      expect(/^[0-9a-f]{64}$/.test(ot.typeHash)).toBe(true);
    }
  });

  test('T15: taxonomy extensions appear in config', () => {
    const config = grammarToExtensionConfig(propertymeGrammar);
    expect(config.taxonomy).toBeDefined();
    expect(config.taxonomy.dimensions.length).toBeGreaterThan(0);
  });

  test('T16: FSM transitions produce flow definitions', () => {
    const config = grammarToExtensionConfig(propertymeGrammar);
    expect(config.flows).toBeDefined();
    expect(config.flows.length).toBeGreaterThan(0);
    // Each flow has steps and onComplete
    for (const flow of config.flows) {
      expect(flow.id).toBeDefined();
      expect(flow.name).toBeDefined();
      expect(Array.isArray(flow.steps)).toBe(true);
      expect(flow.onComplete).toBeDefined();
    }
  });
});

// ── Shell Command Integration (T17–T18) ─────────────────────────

describe('Phase 36A — Shell command integration', () => {
  const { parseCommand } = require(join(ROOT, 'runtime/shell/src/parser'));
  const { routeGrammar } = require(join(ROOT, 'runtime/shell/src/commands/grammar'));

  const STUB_CTX = {} as any;

  test('T17: grammar validate works end-to-end', async () => {
    const grammarPath = join(ROOT, 'configs/extensions/propertyme/grammar.json');
    const cmd = parseCommand(['grammar', 'validate', grammarPath]);
    const result = await routeGrammar(cmd, STUB_CTX);
    expect(result.valid).toBe(true);
    expect(result.message).toContain('valid');
  });

  test('T18: grammar test calls both validator and bridge', async () => {
    const grammarPath = join(ROOT, 'configs/extensions/propertyme/grammar.json');
    const cmd = parseCommand(['grammar', 'test', grammarPath]);
    const result = await routeGrammar(cmd, STUB_CTX);
    expect(result.success).toBe(true);
    expect(result.config).toBeDefined();
    expect(result.config.objectTypes).toBe(6);
  });
});

// ── Reference Grammar: PropertyMe (T19–T22) ─────────────────────

describe('Phase 36A — PropertyMe reference grammar', () => {
  const grammarPath = join(ROOT, 'configs/extensions/propertyme/grammar.json');

  test('T19: PropertyMe grammar file exists', () => {
    expect(existsSync(grammarPath)).toBe(true);
  });

  const grammar = JSON.parse(readFileSync(grammarPath, 'utf-8'));

  test('T20: declares at least 6 source entities', () => {
    expect(grammar.source.entities.length).toBeGreaterThanOrEqual(6);
    const entityIds = grammar.source.entities.map((e: any) => e.entityId);
    expect(entityIds).toContain('property');
    expect(entityIds).toContain('lease');
    expect(entityIds).toContain('tenant');
    expect(entityIds).toContain('maintenance_request');
    expect(entityIds).toContain('inspection');
    expect(entityIds).toContain('owner');
  });

  test('T21: declares at least 6 object types', () => {
    expect(grammar.objectTypes.length).toBeGreaterThanOrEqual(6);
    const typePaths = grammar.objectTypes.map((ot: any) => ot.typePath);
    expect(typePaths).toContain('property.listing');
    expect(typePaths).toContain('property.lease');
    expect(typePaths).toContain('property.tenant');
    expect(typePaths).toContain('property.maintenance-request');
    expect(typePaths).toContain('property.inspection');
    expect(typePaths).toContain('property.owner');
  });

  test('T22: every source entity has at least one entity mapping', () => {
    const entityIds = grammar.source.entities.map((e: any) => e.entityId);
    const mappedEntityIds = new Set(grammar.entityMappings.map((em: any) => em.sourceEntityId));
    for (const entityId of entityIds) {
      expect(mappedEntityIds.has(entityId)).toBe(true);
    }
  });
});

// ── Anti-Regression ──────────────────────────────────────────────

describe('Phase 36A — Anti-regression', () => {
  const indexSource = readFileSync(
    join(ROOT, 'core/protocol-types/src/index.ts'),
    'utf-8',
  );

  test('Previous exports still present: StorageAdapter', () => {
    expect(indexSource).toContain('StorageAdapter');
  });

  test('Previous exports still present: ExtensionManifest', () => {
    expect(indexSource).toContain('ExtensionManifest');
  });

  test('Previous exports still present: ExtensionLoader', () => {
    expect(indexSource).toContain('ExtensionLoader');
  });

  test('Previous exports still present: CellStore', () => {
    expect(indexSource).toContain('CellStore');
  });

  test('Extension grammar files exist at correct paths', () => {
    expect(existsSync(join(ROOT, 'core/protocol-types/src/extension-grammar.ts'))).toBe(true);
    expect(existsSync(join(ROOT, 'core/protocol-types/src/extension-grammar-validator.ts'))).toBe(true);
    expect(existsSync(join(ROOT, 'core/protocol-types/src/extension-grammar-loader.ts'))).toBe(true);
    expect(existsSync(join(ROOT, 'core/protocol-types/src/grammar-config-bridge.ts'))).toBe(true);
    expect(existsSync(join(ROOT, 'runtime/shell/src/commands/grammar.ts'))).toBe(true);
  });
});

```
