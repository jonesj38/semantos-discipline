---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/config-store/ports.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.115081+00:00
---

# runtime/services/src/services/config-store/ports.ts

```ts
/**
 * Bindable ports for the ConfigStore split.
 *
 * Replaces the legacy hard-coded module imports
 * (`@configs/extensions/*.json` + `@configs/taxonomy/*.json`) and the
 * dual `localStorage` / `StorageAdapter` overlay-persistence path with
 * `@semantos/state` ports so tests inject deterministic loaders and
 * production code wires the live impls at boot.
 */

import { port, type Port } from '@semantos/state';

import type {
  ConfigOverlay,
  ExtensionConfig,
} from '../../config/extensionConfig';
import type {
  IntentTaxonomyNode,
  TaxonomyConfig,
} from '../IntentTaxonomy';

/** Loads bundled extension configs by id. */
export interface BundledExtensions {
  hasExtension(id: string): boolean;
  loadExtension(id: string): Promise<unknown>;
  hasTaxonomy(id: string): boolean;
  loadTaxonomy(id: string): Promise<unknown>;
  loadTaxonomySeed(): Promise<unknown | null>;
}

/** Persists / loads the user's overlay list. */
export interface OverlayPersistence {
  load(): Promise<ConfigOverlay[]>;
  save(overlays: ConfigOverlay[]): Promise<void>;
}

/**
 * Lazy registrar for the IntentTaxonomy singleton — kept abstract so
 * tests can pass a record/log stub instead of mutating module state.
 */
export interface IntentTaxonomyRegistrar {
  loadCoreTaxonomy(nodes: IntentTaxonomyNode[]): void;
  registerTaxonomy(config: TaxonomyConfig, flows: ExtensionConfig['flows']): void;
  unregisterTaxonomy(extensionId: string): void;
}

export const bundledExtensionsPort: Port<BundledExtensions> = port<BundledExtensions>(
  'config-bundled-extensions',
);
export const overlayPersistencePort: Port<OverlayPersistence> = port<OverlayPersistence>(
  'config-overlay-persistence',
);
export const intentTaxonomyRegistrarPort: Port<IntentTaxonomyRegistrar> =
  port<IntentTaxonomyRegistrar>('config-intent-taxonomy-registrar');

/** Resolve the bound bundled-extensions impl, or throw with a hint. */
export function getBundledExtensions(): BundledExtensions {
  return bundledExtensionsPort.get();
}

/** Resolve the bound overlay persister, or throw with a hint. */
export function getOverlayPersistence(): OverlayPersistence {
  return overlayPersistencePort.get();
}

/** Resolve the bound intent-taxonomy registrar, or throw with a hint. */
export function getIntentTaxonomyRegistrar(): IntentTaxonomyRegistrar {
  return intentTaxonomyRegistrarPort.get();
}

```
