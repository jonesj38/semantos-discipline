---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/config-store/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.112491+00:00
---

# runtime/services/src/services/config-store/index.ts

```ts
/**
 * ConfigStore barrel — public surface for the split.
 */

export { ConfigStore, DEFAULT_EXTENSION } from './config-store-facade';
export {
  bundledExtensionsPort,
  overlayPersistencePort,
  intentTaxonomyRegistrarPort,
  getBundledExtensions,
  getOverlayPersistence,
  getIntentTaxonomyRegistrar,
  type BundledExtensions,
  type OverlayPersistence,
  type IntentTaxonomyRegistrar,
} from './ports';
export {
  configAtom,
  coreConfigAtom,
  activeExtensionIdAtom,
  overlaysAtom,
  taxonomySeedAtom,
  coreTaxonomyLoadedAtom,
  activeIntentTaxonomyExtensionAtom,
  loadingAtom,
  errorAtom,
  type SeedAxis,
  type SeedNode,
} from './atoms';
export { mergeExtensions } from './config-merger';
export { loadConfig } from './config-loader';
export {
  applyTaxonomySeed,
  seedToTaxonomyNodes,
  flattenNodePaths,
} from './taxonomy-seed-applicator';
export { applyAllOverlays, insertNodeAtParent } from './overlay-appliance';
export { loadIntentTaxonomy } from './intent-taxonomy-manager';
export { resolveTaxonomyBallot } from './ballot-resolver';
export {
  defaultBundledExtensions,
  defaultRegistrar,
  localStorageOverlayPersistence,
  makeAdapterOverlayPersistence,
  bindDefaultConfigStorePorts,
} from './default-boot';

```
