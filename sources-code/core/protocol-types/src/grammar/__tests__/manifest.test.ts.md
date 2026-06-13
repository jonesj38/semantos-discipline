---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/grammar/__tests__/manifest.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.924773+00:00
---

# core/protocol-types/src/grammar/__tests__/manifest.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import { ValidationErrorCollector } from '../error-collector';
import {
  validateManifest,
  validateMigrations,
} from '../validators/manifest';

function runManifest(g: Record<string, unknown>) {
  const errors = ValidationErrorCollector.create();
  validateManifest(g, errors);
  return errors.toResult();
}

function minimalEnvelope(overrides: Record<string, unknown> = {}) {
  return {
    metaSchemaVersion: '1.0.0',
    grammarId: 'com.test.minimal',
    grammarVersion: '1.0.0',
    displayName: 'M',
    description: 'D',
    author: { certId: 'c', name: 'n' },
    taxonomyNamespace: 'test',
    ...overrides,
  };
}

describe('validators/manifest', () => {
  test('valid envelope passes', () => {
    expect(runManifest(minimalEnvelope()).valid).toBe(true);
  });

  test('missing grammarId fails', () => {
    const g = minimalEnvelope();
    delete (g as any).grammarId;
    const r = runManifest(g);
    expect(r.valid).toBe(false);
    expect(r.errors.some(e => e.path === 'grammarId')).toBe(true);
  });

  test('non-semver grammarVersion fails', () => {
    const r = runManifest(minimalEnvelope({ grammarVersion: 'abc' }));
    expect(r.valid).toBe(false);
  });

  test('bad grammarId format fails', () => {
    const r = runManifest(minimalEnvelope({ grammarId: 'bad id' }));
    expect(r.valid).toBe(false);
  });

  test('missing author fails', () => {
    const r = runManifest(minimalEnvelope({ author: undefined }));
    expect(r.valid).toBe(false);
    expect(r.errors.some(e => e.path === 'author')).toBe(true);
  });

  test('extends with both fields passes', () => {
    const r = runManifest(
      minimalEnvelope({ extends: { grammarId: 'a.b', versionRange: '^1.0.0' } }),
    );
    expect(r.valid).toBe(true);
  });

  test('extends as non-object fails', () => {
    const r = runManifest(minimalEnvelope({ extends: 'oops' }));
    expect(r.valid).toBe(false);
  });
});

function runMigrations(g: Record<string, unknown>) {
  const errors = ValidationErrorCollector.create();
  validateMigrations(g, errors);
  return errors.toResult();
}

describe('validators/manifest — migrations', () => {
  test('absent migrations is OK', () => {
    expect(runMigrations({}).valid).toBe(true);
  });

  test('non-array migrations fails', () => {
    expect(runMigrations({ migrations: 'no' }).valid).toBe(false);
  });

  test('valid migration passes', () => {
    expect(
      runMigrations({
        migrations: [{ fromVersion: '1.0.0', toVersion: '2.0.0' }],
      }).valid,
    ).toBe(true);
  });

  test('migration missing fromVersion fails', () => {
    expect(
      runMigrations({
        migrations: [{ toVersion: '2.0.0' }],
      }).valid,
    ).toBe(false);
  });

  test('non-semver fromVersion fails', () => {
    expect(
      runMigrations({
        migrations: [{ fromVersion: 'one', toVersion: '2.0.0' }],
      }).valid,
    ).toBe(false);
  });
});

```
