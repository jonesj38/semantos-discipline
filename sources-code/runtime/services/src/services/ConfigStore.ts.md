---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/ConfigStore.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.098194+00:00
---

# runtime/services/src/services/ConfigStore.ts

```ts
/**
 * @deprecated Use `./config-store` (the split) instead. This module
 * is a one-release re-export shim for the new home of the config
 * store under `config-store/`. It will be removed once all consumers
 * have migrated.
 *
 * The split lives in `runtime/services/src/services/config-store/`:
 *   - `ports.ts`                  bundledExtensionsPort,
 *                                 overlayPersistencePort,
 *                                 intentTaxonomyRegistrarPort
 *   - `atoms.ts`                  configAtom, activeExtensionIdAtom,
 *                                 overlaysAtom, taxonomySeedAtom,
 *                                 coreTaxonomyLoadedAtom, …
 *   - `config-loader.ts`          async loadConfig via bundled port
 *   - `config-merger.ts`          pure mergeExtensions
 *   - `taxonomy-seed-applicator.ts` pure applyTaxonomySeed
 *   - `overlay-appliance.ts`      pure applyAllOverlays + helpers
 *   - `intent-taxonomy-manager.ts` loadIntentTaxonomy
 *   - `ballot-resolver.ts`        pure resolveTaxonomyBallot
 *   - `default-boot.ts`           bindDefaultConfigStorePorts (live impls)
 *   - `config-store-facade.ts`    public ConfigStore class
 *
 * The legacy constructor signature (`new ConfigStore(adapter?)`) is
 * preserved by auto-binding the default ports on first instantiation
 * — the dual `localStorage` / `StorageAdapter` write path collapses
 * to a single port impl chosen at boot.
 */

import type { StorageAdapter } from '../../../../core/protocol-types/src/storage';
import { ConfigStore as ConfigStoreFacade } from './config-store/config-store-facade';
import { bindDefaultConfigStorePorts } from './config-store/default-boot';

export class ConfigStore extends ConfigStoreFacade {
  constructor(adapter?: StorageAdapter) {
    super();
    bindDefaultConfigStorePorts(adapter ? { adapter } : {});
  }
}

export { DEFAULT_EXTENSION } from './config-store/atoms';

```
