---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/config-store/__tests__/ports.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.126258+00:00
---

# runtime/services/src/services/config-store/__tests__/ports.test.ts

```ts
import { afterEach, describe, expect, test } from 'bun:test';
import {
  bundledExtensionsPort,
  intentTaxonomyRegistrarPort,
  overlayPersistencePort,
} from '../ports';

afterEach(() => {
  bundledExtensionsPort.unbind();
  intentTaxonomyRegistrarPort.unbind();
  overlayPersistencePort.unbind();
});

describe('config-store ports', () => {
  test('1. bundledExtensionsPort throws when unbound', () => {
    expect(() => bundledExtensionsPort.get()).toThrow();
  });

  test('2. bundledExtensionsPort returns the bound impl', () => {
    const stub = {
      hasExtension: () => false,
      loadExtension: async () => ({ default: {} }),
      hasTaxonomy: () => false,
      loadTaxonomy: async () => ({ default: {} }),
      loadTaxonomySeed: async () => null,
    };
    bundledExtensionsPort.bind(stub);
    expect(bundledExtensionsPort.get()).toBe(stub);
  });

  test('3. overlayPersistencePort returns the bound impl', () => {
    const stub = { load: async () => [], save: async () => {} };
    overlayPersistencePort.bind(stub);
    expect(overlayPersistencePort.get()).toBe(stub);
  });

  test('4. intentTaxonomyRegistrarPort returns the bound impl', () => {
    const stub = {
      loadCoreTaxonomy: () => {},
      registerTaxonomy: () => {},
      unregisterTaxonomy: () => {},
    };
    intentTaxonomyRegistrarPort.bind(stub);
    expect(intentTaxonomyRegistrarPort.get()).toBe(stub);
  });

  test('5. unbind() resets each port', () => {
    bundledExtensionsPort.bind({
      hasExtension: () => false,
      loadExtension: async () => ({}),
      hasTaxonomy: () => false,
      loadTaxonomy: async () => ({}),
      loadTaxonomySeed: async () => null,
    });
    expect(bundledExtensionsPort.isBound()).toBe(true);
    bundledExtensionsPort.unbind();
    expect(bundledExtensionsPort.isBound()).toBe(false);
  });
});

```
