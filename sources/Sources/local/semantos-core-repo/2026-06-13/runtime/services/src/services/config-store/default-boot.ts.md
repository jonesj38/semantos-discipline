---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/config-store/default-boot.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.114511+00:00
---

# runtime/services/src/services/config-store/default-boot.ts

```ts
/**
 * Default boot wiring — binds the three ConfigStore ports to the
 * production implementations (bundled JSON imports, FlowRegistry
 * registrar, and overlay persistence).
 *
 * The dual `localStorage`-vs-`StorageAdapter` write path the
 * pre-split monolith carried collapses to a single port: callers
 * pass `{ adapter }` to use the adapter, or omit it to fall back to
 * `localStorage`. Either way the persister handles its own migration
 * (read-from-localStorage → write-to-adapter on first save) at init
 * time inside the implementations below.
 */

import {
  loadCoreTaxonomy,
  registerTaxonomy,
  unregisterTaxonomy,
} from '../FlowRegistry';
import type { StorageAdapter } from '../../../../../core/protocol-types/src/storage';
import type { ConfigOverlay } from '../../config/extensionConfig';
import {
  bundledExtensionsPort,
  intentTaxonomyRegistrarPort,
  overlayPersistencePort,
  type BundledExtensions,
  type IntentTaxonomyRegistrar,
  type OverlayPersistence,
} from './ports';

const OVERLAYS_LOCAL_STORAGE_KEY = 'semantos-config-overlays';
const ADAPTER_OVERLAYS_KEY = 'config/overlays.json';

/** The bundled-import pairs the pre-split monolith owned.
 *
 * Removed 2026-05-25 (post-T6 cleanup, typehash-canonical):
 *   - `navigator` — pointed at non-existent `@configs/packages/navigator.json`;
 *     dead loader entry.  No callers of `loadExtension('navigator')` found.
 *   - `consciousness` — content cherry-picked into `cartridges/betterment/cartridge.json`
 *     (the T6 `betterment` cartridge owns personal-practice cellTypes + flows +
 *     theme).  Old extension config deleted.
 */
const BUNDLED_EXTENSION_LOADERS: Record<string, () => Promise<unknown>> = {
  core: () => import('@configs/extensions/core.json'),
  'trades-services': () => import('@configs/extensions/trades-services.json'),
  'blockchain-risk': () => import('@configs/extensions/blockchain-risk.json'),
  development: () => import('@configs/extensions/development.json'),
  'host-ops': () => import('@configs/extensions/host-ops.json'),
};

const BUNDLED_TAXONOMY_LOADERS: Record<string, () => Promise<unknown>> = {
  core: () => import('@configs/taxonomy/core.json'),
  'trades-services': () => import('@configs/taxonomy/trades.json'),
  generic: () => import('@configs/taxonomy/generic.json'),
  // `consciousness` taxonomy removed 2026-05-25 (post-T6 cleanup); the
  // `self` cartridge owns its own taxonomy.  configs/taxonomy/consciousness.json
  // kept as reference for the future PWA-wiring PR (T7?) but no longer
  // bundle-loaded.
};

export const defaultBundledExtensions: BundledExtensions = {
  hasExtension: (id) => Object.prototype.hasOwnProperty.call(BUNDLED_EXTENSION_LOADERS, id),
  loadExtension: (id) => {
    const fn = BUNDLED_EXTENSION_LOADERS[id];
    if (!fn) return Promise.reject(new Error(`extension '${id}' is not bundled`));
    return fn();
  },
  hasTaxonomy: (id) => Object.prototype.hasOwnProperty.call(BUNDLED_TAXONOMY_LOADERS, id),
  loadTaxonomy: (id) => {
    const fn = BUNDLED_TAXONOMY_LOADERS[id];
    if (!fn) return Promise.reject(new Error(`taxonomy '${id}' is not bundled`));
    return fn();
  },
  loadTaxonomySeed: async () => {
    try {
      return await import('@configs/taxonomy/seed.json');
    } catch {
      return null;
    }
  },
};

export const defaultRegistrar: IntentTaxonomyRegistrar = {
  loadCoreTaxonomy: (nodes) => loadCoreTaxonomy(nodes),
  registerTaxonomy: (config, flows) => registerTaxonomy(config, flows ?? []),
  unregisterTaxonomy: (extensionId) => unregisterTaxonomy(extensionId),
};

/** localStorage-backed overlay persister. Used when no adapter is supplied. */
export const localStorageOverlayPersistence: OverlayPersistence = {
  async load() {
    try {
      const stored = localStorage.getItem(OVERLAYS_LOCAL_STORAGE_KEY);
      return stored ? (JSON.parse(stored) as ConfigOverlay[]) : [];
    } catch {
      return [];
    }
  },
  async save(overlays) {
    try {
      localStorage.setItem(OVERLAYS_LOCAL_STORAGE_KEY, JSON.stringify(overlays));
    } catch {
      // session-only on storage full / unavailable
    }
  },
};

/** StorageAdapter-backed persister with one-shot localStorage migration. */
export function makeAdapterOverlayPersistence(adapter: StorageAdapter): OverlayPersistence {
  let migrated = false;
  return {
    async load() {
      // First load: prefer the adapter; fall back to localStorage and
      // migrate so the next save writes through the adapter.
      try {
        const bytes = await adapter.read(ADAPTER_OVERLAYS_KEY);
        if (bytes) return JSON.parse(new TextDecoder().decode(bytes)) as ConfigOverlay[];
      } catch {
        // fall through to localStorage
      }
      try {
        const stored =
          typeof localStorage !== 'undefined'
            ? localStorage.getItem(OVERLAYS_LOCAL_STORAGE_KEY)
            : null;
        if (stored) {
          migrated = true; // hint a save will happen soon
          return JSON.parse(stored) as ConfigOverlay[];
        }
      } catch {
        // ignore
      }
      return [];
    },
    async save(overlays) {
      try {
        await adapter.write(
          ADAPTER_OVERLAYS_KEY,
          new TextEncoder().encode(JSON.stringify(overlays)),
        );
        if (migrated) {
          migrated = false;
          try {
            if (typeof localStorage !== 'undefined') {
              localStorage.removeItem(OVERLAYS_LOCAL_STORAGE_KEY);
            }
          } catch {
            // ignore
          }
        }
      } catch {
        // session-only on adapter failure
      }
    },
  };
}

/**
 * Bind all three ConfigStore ports to their default implementations.
 * Pass `adapter` to back overlay persistence with a StorageAdapter;
 * omit to use localStorage. Idempotent.
 */
export function bindDefaultConfigStorePorts(opts?: { adapter?: StorageAdapter }): void {
  if (!bundledExtensionsPort.isBound()) bundledExtensionsPort.bind(defaultBundledExtensions);
  if (!intentTaxonomyRegistrarPort.isBound())
    intentTaxonomyRegistrarPort.bind(defaultRegistrar);
  if (!overlayPersistencePort.isBound()) {
    overlayPersistencePort.bind(
      opts?.adapter ? makeAdapterOverlayPersistence(opts.adapter) : localStorageOverlayPersistence,
    );
  }
}

```
