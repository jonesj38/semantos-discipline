---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/config-store/__tests__/config-store-integration.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.125940+00:00
---

# runtime/services/src/services/config-store/__tests__/config-store-integration.test.ts

```ts
/**
 * ConfigStore integration test — drives the facade through ports
 * stubs end-to-end. Pins:
 *   - switchExtension loads core + domain via the bundled port
 *   - merge → seed → overlays pipeline produces the expected taxonomy
 *   - applyOverlay persists via the overlay port
 *   - resolveProposalBallot turns a finalized motion into an overlay
 *   - intent-taxonomy registrar sees the expected register/unregister
 *     sequence on switch
 */

import { afterEach, describe, expect, test } from 'bun:test';
import { get, set } from '@semantos/state';
import { ConfigStore } from '../config-store-facade';
import {
  bundledExtensionsPort,
  intentTaxonomyRegistrarPort,
  overlayPersistencePort,
  type BundledExtensions,
  type IntentTaxonomyRegistrar,
  type OverlayPersistence,
} from '../ports';
import {
  activeExtensionIdAtom,
  configAtom,
  coreConfigAtom,
  coreTaxonomyLoadedAtom,
  errorAtom,
  loadingAtom,
  overlaysAtom,
  taxonomySeedAtom,
} from '../atoms';
import type { ConfigOverlay, ExtensionConfig } from '../../../config/extensionConfig';
import { sampleSeed } from './fixtures';

function resetAtoms(): void {
  set(configAtom, null);
  set(coreConfigAtom, null);
  set(activeExtensionIdAtom, 'trades-services');
  set(overlaysAtom, []);
  set(taxonomySeedAtom, null);
  set(coreTaxonomyLoadedAtom, false);
  set(loadingAtom, false);
  set(errorAtom, null);
}

afterEach(() => {
  bundledExtensionsPort.unbind();
  intentTaxonomyRegistrarPort.unbind();
  overlayPersistencePort.unbind();
  resetAtoms();
});

const validTypeHash = '00'.repeat(32);
const noteType = {
  name: 'Note',
  linearity: 'LINEAR',
  fields: [],
  typeHash: validTypeHash,
};
const jobType = {
  name: 'Job',
  linearity: 'LINEAR',
  fields: [],
  typeHash: validTypeHash,
};
const phase = { id: 'p1', name: 'phase-1' };
const coreConfig: ExtensionConfig = {
  id: 'core',
  name: 'core',
  objectTypes: [noteType] as never,
  capabilities: [{ id: 1, name: 'core-cap' } as never],
  scripts: [],
  commercePhases: [phase] as never,
  flows: [],
};
const tradesConfig: ExtensionConfig = {
  id: 'trades-services',
  name: 'trades',
  objectTypes: [jobType] as never,
  capabilities: [{ id: 2, name: 'trades-cap' } as never],
  scripts: [],
  commercePhases: [phase] as never,
  flows: [],
};

function makeBundled(over: Partial<BundledExtensions> = {}): BundledExtensions {
  return {
    hasExtension: (id) => id === 'core' || id === 'trades-services',
    loadExtension: async (id) => ({
      default: id === 'core' ? coreConfig : tradesConfig,
    }),
    hasTaxonomy: () => false,
    loadTaxonomy: async () => ({}),
    loadTaxonomySeed: async () => ({ default: { axes: sampleSeed } }),
    ...over,
  };
}

function makeRegistrar(): IntentTaxonomyRegistrar & { calls: string[] } {
  const calls: string[] = [];
  return {
    calls,
    loadCoreTaxonomy: () => calls.push('loadCore'),
    registerTaxonomy: () => calls.push('register'),
    unregisterTaxonomy: (id) => calls.push(`unregister:${id}`),
  };
}

function makePersistence(initial: ConfigOverlay[] = []): OverlayPersistence & {
  saved: ConfigOverlay[][];
} {
  const saved: ConfigOverlay[][] = [];
  return {
    saved,
    load: async () => [...initial],
    save: async (overlays) => {
      saved.push([...overlays]);
    },
  };
}

describe('ConfigStore integration', () => {
  test('1. switchExtension wires core + trades + seed and produces a merged taxonomy', async () => {
    bundledExtensionsPort.bind(makeBundled());
    intentTaxonomyRegistrarPort.bind(makeRegistrar());
    overlayPersistencePort.bind(makePersistence());
    const store = new ConfigStore();
    await store.switchExtension('trades-services');
    const cfg = store.getConfig()!;
    expect(cfg.id).toBe('trades-services');
    const dim = cfg.taxonomy!.dimensions[0]!;
    expect(dim.id).toBe('what');
  });

  test('2. switching to "core" returns the core config un-merged', async () => {
    bundledExtensionsPort.bind(makeBundled());
    intentTaxonomyRegistrarPort.bind(makeRegistrar());
    overlayPersistencePort.bind(makePersistence());
    const store = new ConfigStore();
    await store.switchExtension('core');
    const cfg = store.getConfig()!;
    expect(cfg.id).toBe('core');
    expect(cfg.objectTypes.map((t) => (t as { name: string }).name)).toEqual(['Note']);
  });

  test('3. surfaces loader errors via getError + emits a snapshot', async () => {
    bundledExtensionsPort.bind(
      makeBundled({
        loadExtension: async () => {
          throw new Error('boom');
        },
      }),
    );
    intentTaxonomyRegistrarPort.bind(makeRegistrar());
    overlayPersistencePort.bind(makePersistence());
    const store = new ConfigStore();
    await store.switchExtension('trades-services');
    expect(store.getConfig()).toBeNull();
    expect(store.getError()).toBe('boom');
  });

  test('4. initFromAdapter hydrates overlaysAtom from the persistence port', async () => {
    bundledExtensionsPort.bind(makeBundled());
    intentTaxonomyRegistrarPort.bind(makeRegistrar());
    overlayPersistencePort.bind(makePersistence([
      { id: 'o', source: 'ballot', appliedAt: 0, taxonomyNodes: [] },
    ]));
    const store = new ConfigStore();
    await store.initFromAdapter();
    expect(get(overlaysAtom)).toHaveLength(1);
  });

  test('5. applyOverlay persists overlays and re-derives the config', async () => {
    bundledExtensionsPort.bind(makeBundled());
    intentTaxonomyRegistrarPort.bind(makeRegistrar());
    const persistence = makePersistence();
    overlayPersistencePort.bind(persistence);

    const store = new ConfigStore();
    await store.switchExtension('trades-services');

    store.applyOverlay({
      id: 'o-1',
      source: 'ballot',
      appliedAt: 1,
      taxonomyNodes: [{ path: 'what.thing.box', name: 'box', axis: 'what' }],
    });
    // applyOverlay persists asynchronously — let it flush.
    await new Promise((r) => setTimeout(r, 5));
    expect(persistence.saved).toHaveLength(1);
    expect(get(overlaysAtom)).toHaveLength(1);
  });

  test('6. resolveProposalBallot returns true and creates an overlay on a finalized win', async () => {
    bundledExtensionsPort.bind(makeBundled());
    intentTaxonomyRegistrarPort.bind(makeRegistrar());
    overlayPersistencePort.bind(makePersistence());
    const store = new ConfigStore();
    await store.switchExtension('trades-services');
    const ok = store.resolveProposalBallot(
      {
        status: 'finalized',
        votesFor: 5,
        votesAgainst: 1,
        motion: JSON.stringify({
          axis: 'what',
          parentPath: 'what.thing',
          nodeName: 'Box',
        }),
      },
      'b-1',
    );
    expect(ok).toBe(true);
    expect(get(overlaysAtom)).toHaveLength(1);
  });

  test('7. failed-eligibility ballots return false and leave overlays untouched', async () => {
    bundledExtensionsPort.bind(makeBundled());
    intentTaxonomyRegistrarPort.bind(makeRegistrar());
    overlayPersistencePort.bind(makePersistence());
    const store = new ConfigStore();
    await store.switchExtension('trades-services');
    expect(store.resolveProposalBallot({ status: 'open' }, 'b-1')).toBe(false);
    expect(get(overlaysAtom)).toHaveLength(0);
  });

  test('8. initialize() loads the default extension', async () => {
    bundledExtensionsPort.bind(makeBundled());
    intentTaxonomyRegistrarPort.bind(makeRegistrar());
    overlayPersistencePort.bind(makePersistence());
    const store = new ConfigStore();
    await store.initialize();
    expect(store.getActiveExtensionId()).toBe('trades-services');
  });

  test('9. core taxonomy is loaded via the registrar at most once', async () => {
    bundledExtensionsPort.bind(
      makeBundled({
        hasTaxonomy: (id) => id === 'core' || id === 'generic',
        loadTaxonomy: async (id) => {
          if (id === 'core') return { default: { nodes: [] } };
          return { default: { extensionId: id, inject: [] } };
        },
      }),
    );
    const registrar = makeRegistrar();
    intentTaxonomyRegistrarPort.bind(registrar);
    overlayPersistencePort.bind(makePersistence());
    const store = new ConfigStore();
    await store.switchExtension('trades-services');
    await store.switchExtension('trades-services');
    expect(registrar.calls.filter((c) => c === 'loadCore')).toHaveLength(1);
  });

  test('10. registrar.unregister is called when switching away from a previously active taxonomy', async () => {
    bundledExtensionsPort.bind(
      makeBundled({
        hasTaxonomy: (id) =>
          id === 'core' || id === 'generic' || id === 'trades-services' || id === 'consciousness',
        loadTaxonomy: async (id) => {
          if (id === 'core') return { default: { nodes: [] } };
          return { default: { extensionId: id, inject: [] } };
        },
      }),
    );
    const registrar = makeRegistrar();
    intentTaxonomyRegistrarPort.bind(registrar);
    overlayPersistencePort.bind(makePersistence());

    const store = new ConfigStore();
    await store.switchExtension('trades-services');
    await store.switchExtension('core');
    expect(registrar.calls.some((c) => c === 'unregister:trades-services')).toBe(true);
  });
});

```
